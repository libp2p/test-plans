import sqlite3 from "sqlite3";
import {open} from "sqlite";
import {Version} from "../versions";
import {ComposeSpecification} from "../compose-spec/compose-spec";
import {sanitizeComposeName} from "./lib";

export async function buildTestSpecs(versions: Array<Version>, nameFilter: string | null, nameIgnore: string | null): Promise<Array<ComposeSpecification>> {
    sqlite3.verbose();

    const db = await open({
        // In memory DB. We don't persist this.
        filename: ":memory:",
        driver: sqlite3.Database,
    });

    await db.exec('CREATE TABLE IF NOT EXISTS transports (id string not null, imageID string not null, transport string not null);');

    await Promise.all(
        versions.flatMap(version => ([
            db.exec(`INSERT INTO transports (id, imageID, transport) VALUES ${version.transports.map(transport => `("${version.id}", "${version.containerImageID}", "${transport}")`).join(", ")};`)
        ]))
    )

    // Generate the testing combinations by SELECT'ing from the transports table the
    // distinct client/server pairs whose transports match. The client asks the server to
    // verify the reachability of the client's address; the server dials it back.
    const queryResults =
        await db.all(`SELECT DISTINCT a.id as client, a.imageID as clientImage, b.id as server, b.imageID as serverImage, a.transport
                      FROM transports a,
                           transports b
                      WHERE a.transport == b.transport;`
        );
    await db.close();

    return queryResults
        .map((testCase, index) => {
            let name = `${testCase.client} x ${testCase.server} (${testCase.transport})`;

            if (nameFilter && !name.includes(nameFilter)) {
                return null
            }
            if (nameIgnore && name.includes(nameIgnore)) {
                return null
            }

            return buildSpec(name, testCase.clientImage, testCase.serverImage, testCase.transport, index)
        })
        .filter(spec => spec !== null)
}

function networkSubnet(index: number): string {
    if (index >= 256 * 256) {
        throw new Error(`test index ${index} exceeds the 11.0.0.0/8 subnet space`)
    }
    return `11.${Math.floor(index / 256)}.${index % 256}.0/24`
}

function buildSpec(name: string, clientImage: string, serverImage: string, transport: string, index: number): ComposeSpecification {
    return {
        name,
        services: {
            server: {
                depends_on: ["redis"],
                image: serverImage,
                init: true,
                environment: {
                    TRANSPORT: transport,
                    MODE: "server",
                },
                networks: {
                    autonat: {},
                },
            },
            client: {
                depends_on: ["server", "redis"],
                image: clientImage,
                init: true,
                environment: {
                    TRANSPORT: transport,
                    MODE: "client",
                },
                networks: {
                    autonat: {},
                },
            },
            redis: {
                image: "redis:7-alpine",
                healthcheck: {
                    test: ["CMD-SHELL", "redis-cli ping | grep PONG"]
                },
                networks: {
                    autonat: {
                        aliases: ["redis"]
                    },
                }
            }
        },
        networks: {
            autonat: {
                ipam: {
                    config: [{ subnet: networkSubnet(index) }],
                },
            },
        }
    }
}
