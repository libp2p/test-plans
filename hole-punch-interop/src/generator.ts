import sqlite3 from "sqlite3";
import {open} from "sqlite";
import {Version} from "../versions";
import {ComposeSpecification} from "../compose-spec/compose-spec";
import {sanitizeComposeName} from "./lib";

function buildExtraEnv(timeoutOverride: { [key: string]: number }, test1ID: string, test2ID: string): {
    [key: string]: string
} {
    const maxTimeout = Math.max(timeoutOverride[test1ID] || 0, timeoutOverride[test2ID] || 0)
    return maxTimeout > 0 ? {"test_timeout_seconds": maxTimeout.toString(10)} : {}
}

export async function buildTestSpecs(versions: Array<Version>, nameFilter: string | null, nameIgnore: string | null, routerImageId: string, relayImageId: string, routerDelay: number, relayDelay: number): Promise<Array<ComposeSpecification>> {
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
        }, nameFilter, nameIgnore, routerImageId, relayImageId, routerDelay, relayDelay)
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
}: TestSpec, nameFilter: string | null, nameIgnore: string | null, routerImageId: string, relayImageId: string, routerDelay: number, relayDelay: number): ComposeSpecification | null {
    if (nameFilter && !name.includes(nameFilter)) {
        return null
    }
    if (nameIgnore && name.includes(nameIgnore)) {
        return null
    }

    const rustLog = "debug,netlink_proto=warn,rustls=warn,multistream_select=warn";
    let internetNetworkName = `${sanitizeComposeName(name)}_internet`

    let startupScriptFn = (actor: "alice" | "bob") => (`
        set -ex;

        # Wait for router to be online
        while ! nslookup "${actor}_router" >&2; do sleep 1; done

        # Wait for redis to be online
        while ! nslookup "redis" >&2; do sleep 1; done

        ROUTER_IP=$$(dig +short ${actor}_router)
        INTERNET_SUBNET=$$(curl --silent --unix-socket /var/run/docker.sock http://localhost/networks/${internetNetworkName} | jq -r '.IPAM.Config[0].Subnet')

        ip route add $$INTERNET_SUBNET via $$ROUTER_IP dev eth0

        hole-punch-client
    `);

    let relayStartupScript = `
        set -ex;
 
        tc qdisc add dev eth0 root netem delay ${relayDelay}ms; # Add a delay to all relayed connections

        /usr/bin/relay
    `;

    const dockerSocketVolume = "/var/run/docker.sock:/var/run/docker.sock";

    return {
        name,
        services: {
            relay: {
                depends_on: ["redis"],
                image: relayImageId,
                init: true,
                command: ["/bin/sh", "-c", relayStartupScript],
                environment: {
                    RUST_LOG: rustLog,
                },
                networks: {
                    internet: { },
                },
                cap_add: ["NET_ADMIN"]
            },
            alice_router: {
                depends_on: ["redis"],
                image: routerImageId,
                init: true,
                environment: {
                  DELAY_MS: routerDelay
                },
                networks: {
                    alice_lan: {},
                    internet: {},
                },
                cap_add: ["NET_ADMIN"]
            },
            alice: {
                depends_on: ["relay", "alice_router", "redis"],
                image: containerImages[aliceImage](),
                init: true,
                command: ["/bin/sh", "-c", startupScriptFn("alice")],
                environment: {
                    TRANSPORT: transport,
                    MODE: "dial",
                    RUST_LOG: rustLog,
                },
                networks: {
                    alice_lan: {},
                },
                cap_add: ["NET_ADMIN"],
                volumes: [dockerSocketVolume]
            },
            bob_router: {
                depends_on: ["redis"],
                image: routerImageId,
                init: true,
                environment: {
                    DELAY_MS: routerDelay
                },
                networks: {
                    bob_lan: {},
                    internet: {},
                },
                cap_add: ["NET_ADMIN"]
            },
            bob: {
                depends_on: ["relay", "bob_router", "redis"],
                image: containerImages[bobImage](),
                init: true,
                command: ["/bin/sh", "-c", startupScriptFn("bob")],
                environment: {
                    TRANSPORT: transport,
                    MODE: "listen",
                    RUST_LOG: rustLog,
                },
                networks: {
                    bob_lan: {},
                },
                cap_add: ["NET_ADMIN"],
                volumes: [dockerSocketVolume]
            },
            redis: {
                image: "redis:7-alpine",
                healthcheck: {
                    test: ["CMD-SHELL", "redis-cli ping | grep PONG"]
                },
                networks: {
                    internet: {
                        aliases: ["redis"]
                    },
                    alice_lan: {
                        aliases: ["redis"]
                    },
                    bob_lan: {
                        aliases: ["redis"]
                    },
                }
            }
        },
        networks: {
            alice_lan: { },
            bob_lan: { },
            internet: { },
        }
    }
}
