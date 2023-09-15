import sqlite3 from "sqlite3";
import {open} from "sqlite";
import {Version} from "../versions";
import {ComposeSpecification} from "../compose-spec/compose-spec";

function buildExtraEnv(timeoutOverride: { [key: string]: number }, test1ID: string, test2ID: string): {
    [key: string]: string
} {
    const maxTimeout = Math.max(timeoutOverride[test1ID] || 0, timeoutOverride[test2ID] || 0)
    return maxTimeout > 0 ? {"test_timeout_seconds": maxTimeout.toString(10)} : {}
}

export async function buildTestSpecs(versions: Array<Version>, nameFilter: string | null, nameIgnore: string | null, routerImageId: string, relayImageId: string): Promise<Array<ComposeSpecification>> {
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

    await db.exec(`CREATE TABLE IF NOT EXISTS transports (id string not null, transport string not null);`)

    await Promise.all(
        versions.flatMap(version => {
            return [
                db.exec(`INSERT INTO transports (id, transport) VALUES ${version.transports.map(transport => `("${version.id}", "${transport}")`).join(", ")};`)
            ]
        })
    )

    // Generate the testing combinations by SELECT'ing from transports tables the distinct combinations where the transports of the different libp2p implementations match.
    const queryResults =
        await db.all(`SELECT DISTINCT a.id as alice, b.id as bob, a.transport
                             FROM transports a, transports b
                             WHERE a.transport == b.transport;`
        );
    await db.close();

    return queryResults.map((test): ComposeSpecification => (
        buildSpec(containerImages, {
            name: `${test.alice} x ${test.bob} (${test.transport})`,
            aliceImage: test.alice,
            bobImage: test.bob,
            transport: test.transport,
            extraEnv: buildExtraEnv(timeoutOverride, test.id1, test.id2)
        }, nameFilter, nameIgnore, routerImageId, relayImageId)
    )).filter((spec): spec is ComposeSpecification => spec !== null)
}

interface TestSpec {
    name: string,
    aliceImage: string,
    bobImage: string,
    transport: string,
    extraEnv?: { [key: string]: string }
}

function buildSpec(containerImages: { [key: string]: () => string }, {
    name,
    aliceImage,
    bobImage,
    transport,
    extraEnv
}: TestSpec, nameFilter: string | null, nameIgnore: string | null, routerImageId: string, relayImageId: string): ComposeSpecification | null {
    if (nameFilter && !name.includes(nameFilter)) {
        return null
    }
    if (nameIgnore && name.includes(nameIgnore)) {
        return null
    }
    const INTERNET_PREFIX = "17.0.0";

    let internetSubnet = `${INTERNET_PREFIX}.0/16`;
    const relayListenAddr = `${INTERNET_PREFIX}.12`;

    return {
        name,
        services: {
            relay: {
                image: relayImageId,
                init: true,
                environment: {
                    LISTEN_ADDR: relayListenAddr,
                    RUST_LOG: "debug"
                },
                networks: {
                    internet: {
                        ipv4_address: relayListenAddr
                    },
                    control: {},
                },
                cap_add: ["NET_ADMIN"]
            },
            alice_router: {
                image: routerImageId,
                init: true,
                networks: {
                    alice_lan: {},
                    internet: {},
                },
                cap_add: ["NET_ADMIN"]
            },
            alice: {
                depends_on: ["relay", "alice_router"],
                image: containerImages[aliceImage](),
                init: true,
                command: ["/bin/sh", "-c", `set -ex; ip route add ${internetSubnet} via $(dig +short alice_router) dev eth0; hole-punch-client`],
                environment: {
                    TRANSPORT: transport,
                    MODE: "dial"
                },
                networks: {
                    alice_lan: {},
                    control: {}
                },
                cap_add: ["NET_ADMIN"]
            },
            bob_router: {
                image: routerImageId,
                init: true,
                networks: {
                    bob_lan: {},
                    internet: {},
                },
                cap_add: ["NET_ADMIN"]
            },
            bob: {
                depends_on: ["relay", "bob_router"],
                image: containerImages[bobImage](),
                init: true,
                command: ["/bin/sh", "-c", `set -ex; ip route add ${internetSubnet} via $(dig +short bob_router) dev eth0; hole-punch-client`],
                environment: {
                    TRANSPORT: transport,
                    MODE: "listen"
                },
                networks: {
                    bob_lan: {},
                    control: {}
                },
                cap_add: ["NET_ADMIN"]
            },
            redis: {
                image: "redis:7-alpine",
                environment: {
                    REDIS_ARGS: "--loglevel warning"
                },
                networks: {
                    control: {}
                }
            }
        },
        networks: {
            alice_lan: {},
            bob_lan: {},
            internet: {
                ipam: {
                    config: [
                        {
                            subnet: internetSubnet
                        }
                    ]
                }
            },
            control: { },
        }
    }
}
