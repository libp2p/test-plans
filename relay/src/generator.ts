import sqlite3 from "sqlite3";
import { open } from "sqlite";
import { Version } from "../versions";
import { ComposeSpecification } from "../compose-spec/compose-spec";

function buildExtraEnv(timeoutOverride: { [key: string]: number }, test1ID: string, test2ID: string): { [key: string]: string } {
    const maxTimeout = Math.max(timeoutOverride[test1ID] || 0, timeoutOverride[test2ID] || 0)
    return maxTimeout > 0 ? { "test_timeout_seconds": maxTimeout.toString(10) } : {}
}

export async function buildTestSpecs(versions: Array<Version>): Promise<Array<ComposeSpecification>> {
    const containerImages: { [key: string]: string } = {}
    const timeoutOverride: { [key: string]: number } = {}
    versions.forEach(v => containerImages[v.id] = v.containerImageID)
    versions.forEach(v => {
        if (v.timeoutSecs) {
            timeoutOverride[v.id] = v.timeoutSecs
        }
    })

    sqlite3.verbose();

    const db = await open({
        // In memory DB. We don't persist this.
        filename: ":memory:",
        driver: sqlite3.Database,
    });

    await db.exec(`CREATE TABLE IF NOT EXISTS roles (id string not null, role string not null);`)

    await Promise.all(
        versions.flatMap(version => {
            return [
                db.exec(`INSERT INTO roles (id, role)
                VALUES ${version.roles.map(role => `("${version.id}", "${role}")`).join(", ")};`),
            ]
        })
    )

    // Generate the testing combinations by SELECT'ing from both transports
    // and muxers tables the distinct combinations where the transport and the muxer
    // of the different libp2p implementations match.
    const queryResults =
        await db.all(`SELECT DISTINCT src.id as idsrc, relay.id as idrelay, dst.id as iddst
                     FROM roles src, roles relay, roles dst;`);
    await db.close();

    const testSpecs = queryResults.map((test): ComposeSpecification => (
        buildSpec(containerImages, {
            name: `${test.idsrc} <-> ${test.idrelay} <-> ${test.iddst}`,
            sourceID: test.idsrc,
            relayID: test.idrelay,
            destinationID: test.iddst,
        })
    ))

    return testSpecs
}

function buildSpec(containerImages: { [key: string]: string }, { name, sourceID, relayID, destinationID }: { name: string, sourceID: string, relayID: string, destinationID: string }): ComposeSpecification {
    return {
        name,
        services: {
            source: {
                init: true,
                image: containerImages[sourceID],
                depends_on: ["redis"],
                environment: {
                    role: "source",
                    version: sourceID,
                }
            },
            relay: {
                init: true,
                image: containerImages[relayID],
                depends_on: ["redis"],
                environment: {
                    role: "relay",
                    version: relayID,
                }
            },
            destination: {
                init: true,
                image: containerImages[destinationID],
                depends_on: ["redis"],
                environment: {
                    role: "destination",
                    version: destinationID,
                }
            },
            redis: {
                image: "redis:7-alpine",
                environment: {
                    REDIS_ARGS: "--loglevel warning"
                }
            }
        }
    }
}
