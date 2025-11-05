import sqlite3 from "sqlite3";
import {open} from "sqlite";
import {Version} from "../versions";
import {ComposeSpecification} from "../compose-spec/compose-spec";
import {sanitizeComposeName} from "./lib";
import path from "path";
import { matchesFilter, parseFilterArgs } from "./testFilter";

export async function buildTestSpecs(versions: Array<Version>, nameFilter: string | null, nameIgnore: string | null, routerImageId: string, relayImageId: string, routerDelay: number, relayDelay: number, assetDir: string, verbose: boolean = false): Promise<Array<ComposeSpecification>> {
    sqlite3.verbose();

    const db = await open({
        // In memory DB. We don't persist this.
        filename: ":memory:",
        driver: sqlite3.Database,
    });

    await db.exec('CREATE TABLE IF NOT EXISTS transports (id string not null, imageID string not null, transport string not null);');

    await Promise.all(
        versions.flatMap(version => {
            const imageID = typeof version.containerImageID === "function"
                ? version.containerImageID(version.id)
                : version.containerImageID;
            return [
                db.exec(`INSERT INTO transports (id, imageID, transport) VALUES ${version.transports.map(transport => `("${version.id}", "${imageID}", "${transport}")`).join(", ")};`)
            ];
        })
    )

    // Generate the testing combinations by SELECT'ing from transports tables the distinct combinations where the transports of the different libp2p implementations match.
    const queryResults =
        await db.all(`SELECT DISTINCT a.id as dialer, a.imageID as dialerImage, b.id as listener, b.imageID as listenerImage, a.transport
                      FROM transports a,
                           transports b
                      WHERE a.transport == b.transport;`
        );
    await db.close();

    // Convert simple string filters to array format for matchesFilter
    const nameFilterArray = nameFilter ? [nameFilter] : null;
    const nameIgnoreArray = nameIgnore ? [nameIgnore] : null;
    const filterOptions = { nameFilter: nameFilterArray, nameIgnore: nameIgnoreArray, verbose };

    return queryResults
        .map(testCase => {
            let name = `${testCase.dialer} x ${testCase.listener} (${testCase.transport})`;

            // Use matchesFilter with collectMode=true to suppress console output during test generation
            if (!matchesFilter(name, filterOptions, true)) {
                return null;
            }

            return buildSpec(name, testCase.dialerImage, testCase.listenerImage, routerImageId, relayImageId, testCase.transport, routerDelay, relayDelay, assetDir, {})
        })
        .filter(spec => spec !== null)
}

function buildSpec(name: string, dialerImage: string, listenerImage: string, routerImageId: string, relayImageId: string, transport: string, routerDelay: number, relayDelay: number, assetDir: string, extraEnv: { [key: string]: string }): ComposeSpecification {
    let internetNetworkName = `${sanitizeComposeName(name)}_internet`

    let startupScriptFn = (actor: "dialer" | "listener") => (`
        set -ex;

        ROUTER_IP=$$(dig +short ${actor}_router)
        INTERNET_SUBNET=$$(curl --fail --silent --unix-socket /var/run/docker.sock http://localhost/networks/${internetNetworkName} | jq -r '.IPAM.Config[0].Subnet')

        ip route add $$INTERNET_SUBNET via $$ROUTER_IP dev eth0

        tcpdump -i eth0 -w /tmp/${actor}.pcap &

        sleep 2 # Let tcpdump start up

        hole-punch-client
    `);

    let relayStartupScript = `
        set -ex;

        tc qdisc add dev eth0 root netem delay ${relayDelay}ms; # Add a delay to all relayed connections

        /usr/bin/relay
    `;

    const dockerSocketVolume = "/var/run/docker.sock:/var/run/docker.sock";
    const tcpDumpVolume = `${path.join(assetDir, sanitizeComposeName(name))}:/tmp:rw`;

    return {
        name,
        services: {
            relay: {
                depends_on: ["redis"],
                image: relayImageId,
                init: true,
                command: ["/bin/sh", "-c", relayStartupScript],
                networks: {
                    internet: {},
                },
                cap_add: ["NET_ADMIN"]
            },
            dialer_router: {
                depends_on: ["redis"],
                image: routerImageId,
                init: true,
                environment: {
                    DELAY_MS: routerDelay
                },
                networks: {
                    lan_dialer: {},
                    internet: {},
                },
                cap_add: ["NET_ADMIN"],
            },
            dialer: {
                depends_on: ["relay", "dialer_router", "redis"],
                image: dialerImage,
                init: true,
                command: ["/bin/sh", "-c", startupScriptFn("dialer")],
                environment: {
                    TRANSPORT: transport,
                    MODE: "dial",
                },
                networks: {
                    lan_dialer: {},
                },
                cap_add: ["NET_ADMIN"],
                volumes: [dockerSocketVolume, tcpDumpVolume]
            },
            listener_router: {
                depends_on: ["redis"],
                image: routerImageId,
                init: true,
                environment: {
                    DELAY_MS: routerDelay
                },
                networks: {
                    lan_listener: {},
                    internet: {},
                },
                cap_add: ["NET_ADMIN"]
            },
            listener: {
                depends_on: ["relay", "listener_router", "redis"],
                image: listenerImage,
                init: true,
                command: ["/bin/sh", "-c", startupScriptFn("listener")],
                environment: {
                    TRANSPORT: transport,
                    MODE: "listen",
                    SSLKEYLOGFILE: "/tmp/tls.key"
                },
                networks: {
                    lan_listener: {},
                },
                cap_add: ["NET_ADMIN"],
                volumes: [dockerSocketVolume, tcpDumpVolume]
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
                    lan_dialer: {
                        aliases: ["redis"]
                    },
                    lan_listener: {
                        aliases: ["redis"]
                    },
                }
            }
        },
        networks: {
            lan_dialer: {},
            lan_listener: {},
            internet: {},
        }
    }
}
