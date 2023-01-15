import sqlite3 from "sqlite3";
import { open } from "sqlite";
import { Version } from "../versions";
import { ComposeSpecification } from "../compose-spec/compose-spec";


export async function buildTestSpecs(versions: Array<Version>): Promise<Array<ComposeSpecification>> {
    const containerImages: { [key: string]: string } = {}
    versions.forEach(v => containerImages[v.id] = v.containerImageID)

    sqlite3.verbose();

    const db = await open({
        // In memory DB. We don't persist this.
        filename: ":memory:",
        driver: sqlite3.Database,
    });

    await db.exec(`CREATE TABLE IF NOT EXISTS transports (id string not null, transport string not null);`)
    await db.exec(`CREATE TABLE IF NOT EXISTS secureChannels (id string not null, sec string not null);`)
    await db.exec(`CREATE TABLE IF NOT EXISTS muxers (id string not null, muxer string not null);`)

    await Promise.all(
        versions.flatMap(version => {
            return [
                db.exec(`INSERT INTO transports (id, transport) 
                VALUES ${version.transports.map(transport => `("${version.id}", "${transport}")`).join(", ")};`),
                db.exec(`INSERT INTO secureChannels (id, sec) 
                VALUES ${version.secureChannels.map(sec => `("${version.id}", "${sec}")`).join(", ")};`),
                db.exec(`INSERT INTO muxers (id, muxer) 
                VALUES ${version.muxers.map(muxer => `("${version.id}", "${muxer}")`).join(", ")};`),
            ]
        })
    )

    // Generate the testing combinations by SELECT'ing from both transports
    // and muxers tables the distinct combinations where the transport and the muxer
    // of the different libp2p implementations match.
    const queryResults =
        await db.all(`SELECT DISTINCT a.id as id1, b.id as id2, a.transport, ma.muxer, sa.sec
                     FROM transports a, transports b, muxers ma, muxers mb, secureChannels sa, secureChannels sb
                     WHERE a.id == ma.id
                     AND b.id == mb.id
                     AND a.id == sa.id
                     AND b.id == sb.id
                     AND a.transport == b.transport
                     AND sa.sec == sb.sec
                     AND ma.muxer == mb.muxer
                     -- quic only uses its own muxer/securechannel
                     AND a.transport != "webtransport"
                     AND a.transport != "webrtc"
                     AND a.transport != "quic"
                     AND a.transport != "quic-v1";`);
    const quicQueryResults =
        await db.all(`SELECT DISTINCT a.id as id1, b.id as id2, a.transport
                     FROM transports a, transports b
                     WHERE a.transport == b.transport
                     -- Only quic transports
                     AND a.transport == "quic";`);
    const quicV1QueryResults =
        await db.all(`SELECT DISTINCT a.id as id1, b.id as id2, a.transport
                     FROM transports a, transports b
                     WHERE a.transport == b.transport
                     -- Only quic transports
                     AND a.transport == "quic-v1";`);
    const webtransportQueryResults =
        await db.all(`SELECT DISTINCT a.id as id1, b.id as id2, a.transport
                     FROM transports a, transports b
                     WHERE a.transport == b.transport
                     -- Only webtransport transports
                     AND a.transport == "webtransport";`);
    const webrtcQueryResults =
        await db.all(`SELECT DISTINCT a.id as id1, b.id as id2, a.transport
                     FROM transports a, transports b
                     WHERE a.transport == b.transport
                     -- Only webtransport transports
                     AND a.transport == "webrtc";`);
    await db.close();

    const testSpecs = queryResults.map((test): ComposeSpecification => (
        buildSpec(containerImages, {
            name: `${test.id1} x ${test.id2} (${test.transport}, ${test.sec}, ${test.muxer})`,
            dialerID: test.id1,
            listenerID: test.id2,
            transport: test.transport,
            muxer: test.muxer,
            security: test.sec,
        })
    )).concat(
        quicQueryResults
        .concat(quicV1QueryResults)
        .concat(webtransportQueryResults)
        .concat(webrtcQueryResults)
        .map((test): ComposeSpecification => buildSpec(containerImages, {
            name: `${test.id1} x ${test.id2} (${test.transport})`,
            dialerID: test.id1,
            listenerID: test.id2,
            transport: test.transport,
            muxer: "quic",
            security: "quic",
        })))

    return testSpecs
}

function buildSpec(containerImages: { [key: string]: string }, { name, dialerID, listenerID, transport, muxer, security }: { name: string, dialerID: string, listenerID: string, transport: string, muxer: string, security: string }): ComposeSpecification {
    return {
        name,
        services: {
            dialer: {
                image: containerImages[dialerID],
                depends_on: ["redis"],
                environment: {
                    version: dialerID,
                    transport,
                    muxer,
                    security,
                    is_dialer: true,
                    ip: "0.0.0.0",
                }
            },
            listener: {
                image: containerImages[listenerID],
                depends_on: ["redis"],
                environment: {
                    version: listenerID,
                    transport,
                    muxer,
                    security,
                    is_dialer: false,
                    ip: "0.0.0.0",
                }
            },
            redis: { image: "redis/redis-stack", }
        }
    }
}