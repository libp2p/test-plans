import sqlite3 from "sqlite3";
import { open } from "sqlite";
import { Version } from "../versions";
import { ComposeSpecification } from "../compose-spec/compose-spec";

function buildExtraEnv(timeoutOverride: { [key: string]: number }, test1ID: string, test2ID: string): { [key: string]: string } {
    const maxTimeout = Math.max(timeoutOverride[test1ID] || 0, timeoutOverride[test2ID] || 0)
    return maxTimeout > 0 ? { "test_timeout_seconds": maxTimeout.toString(10) } : {}
}

export async function buildTestSpecs(versions: Array<Version>, nameFilter: string | null, nameIgnore: string | null): Promise<Array<ComposeSpecification>> {
    const containerImages: { [key: string]: () => string } = {}
    const timeoutOverride: { [key: string]: number } = {}
    versions.forEach(v => containerImages[v.id] = () => {
        if (typeof v.containerImageID === "string") {
            return v.containerImageID
        }

        return v.containerImageID(v.id)
    })
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

    await db.exec(`CREATE TABLE IF NOT EXISTS transports (id string not null, transport string not null, onlyDial boolean not null);`)
    await db.exec(`CREATE TABLE IF NOT EXISTS secureChannels (id string not null, sec string not null);`)
    await db.exec(`CREATE TABLE IF NOT EXISTS muxers (id string not null, muxer string not null);`)

    await Promise.all(
        versions.flatMap(version => {
            return [
                db.exec(`INSERT INTO transports (id, transport, onlyDial)
                VALUES ${version.transports.map(normalizeTransport).map(transport => `("${version.id}", "${transport.name}", ${transport.onlyDial})`).join(", ")};`),
                (version.secureChannels.length > 0 ?
                    db.exec(`INSERT INTO secureChannels (id, sec)
                VALUES ${version.secureChannels.map(sec => `("${version.id}", "${sec}")`).join(", ")};`) : []),
                (version.muxers.length > 0 ?
                    db.exec(`INSERT INTO muxers (id, muxer)
                VALUES ${version.muxers.map(muxer => `("${version.id}", "${muxer}")`).join(", ")};`) : []),
            ]
        })
    )

    // Generate the testing combinations by SELECT'ing from both transports
    // and muxers tables the distinct combinations where the transport and the muxer
    // of the different libp2p implementations match.
    const standaloneTransports = ["quic", "quic-v1", "webtransport", "webrtc", "webrtc-direct"].map(x => `"${x}"`).join(", ")
    const queryResults =
        await db.all(`SELECT DISTINCT a.id as id1, b.id as id2, a.transport, ma.muxer, sa.sec
                     FROM transports a, transports b, muxers ma, muxers mb, secureChannels sa, secureChannels sb
                     WHERE a.id == ma.id
                     AND NOT b.onlyDial
                     AND b.id == mb.id
                     AND a.id == sa.id
                     AND b.id == sb.id
                     AND a.transport == b.transport
                     AND sa.sec == sb.sec
                     AND ma.muxer == mb.muxer
                     -- These transports don't define muxers/securechannels
                     AND a.transport NOT IN (${standaloneTransports});`);
    const standaloneTransportsQueryResults =
        await db.all(`SELECT DISTINCT a.id as id1, b.id as id2, a.transport
                     FROM transports a, transports b
                     WHERE a.transport == b.transport
                     AND NOT b.onlyDial
                     -- These transports don't define muxers/securechannels
                     AND a.transport IN (${standaloneTransports});`);
    await db.close();

    const testSpecs = queryResults.map((test): ComposeSpecification => (
        buildSpec(containerImages, {
            name: `${test.id1} x ${test.id2} (${test.transport}, ${test.sec}, ${test.muxer})`,
            dialerID: test.id1,
            listenerID: test.id2,
            transport: test.transport,
            muxer: test.muxer,
            security: test.sec,
            extraEnv: buildExtraEnv(timeoutOverride, test.id1, test.id2)
        }, nameFilter, nameIgnore)
    )).concat(
        standaloneTransportsQueryResults
            .map((test): ComposeSpecification => buildSpec(containerImages, {
                name: `${test.id1} x ${test.id2} (${test.transport})`,
                dialerID: test.id1,
                listenerID: test.id2,
                transport: test.transport,
                extraEnv: buildExtraEnv(timeoutOverride, test.id1, test.id2)
            }, nameFilter, nameIgnore))).filter((spec): spec is ComposeSpecification => spec !== null)

    return testSpecs
}

function buildSpec(containerImages: { [key: string]: () => string }, { name, dialerID, listenerID, transport, muxer, security, extraEnv }: { name: string, dialerID: string, listenerID: string, transport: string, muxer?: string, security?: string, extraEnv?: { [key: string]: string } }, nameFilter: string | null, nameIgnore: string | null): ComposeSpecification | null {
    if (nameFilter && !name.includes(nameFilter)) {
        return null
    }
    if (nameIgnore && name.includes(nameIgnore)) {
        return null
    }
    return {
        name,
        services: {
            dialer: {
                image: containerImages[dialerID](),
                depends_on: ["redis"],
                environment: {
                    version: dialerID,
                    transport,
                    is_dialer: true,
                    ip: "0.0.0.0",
                    redis_addr: "redis:6379",
                    ...(!!muxer && { muxer }),
                    ...(!!security && { security }),
                    ...extraEnv,
                }
            },
            listener: {
                // Add init process to be PID 1 to proxy signals. Rust doesn't
                // handle SIGINT without this
                init: true,
                image: containerImages[listenerID](),
                depends_on: ["redis"],
                environment: {
                    version: listenerID,
                    transport,
                    is_dialer: false,
                    ip: "0.0.0.0",
                    redis_addr: "redis:6379",
                    ...(!!muxer && { muxer }),
                    ...(!!security && { security }),
                    ...extraEnv,
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

function normalizeTransport(transport: string | { name: string, onlyDial: boolean }): { name: string, onlyDial: boolean } {
    return typeof transport === "string" ? { name: transport, onlyDial: false } : transport
}
