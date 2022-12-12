import sqlite3 from "sqlite3";
import { open } from "sqlite";
import { promisify } from "util";
import { TestPlan, TestPlans } from "dsl/src/dsl";
import { createHmac } from "crypto";
import { Version } from "../versions";


export async function buildTestplans(versions: Array<Version>): Promise<TestPlans> {
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
    await db.exec(`CREATE TABLE IF NOT EXISTS hash (id string not null, hash string not null);`)

    await Promise.all(
        versions.flatMap(version => {
            return [
                db.exec(`INSERT INTO transports (id, transport) 
                VALUES ${version.transports.map(transport => `("${version.id}", "${transport}")`).join(", ")};`),
                db.exec(`INSERT INTO secureChannels (id, sec) 
                VALUES ${version.secureChannels.map(sec => `("${version.id}", "${sec}")`).join(", ")};`),
                db.exec(`INSERT INTO muxers (id, muxer) 
                VALUES ${version.muxers.map(muxer => `("${version.id}", "${muxer}")`).join(", ")};`),

                // To create unique combinations of A x B (but not B x A)
                db.exec(`INSERT INTO hash (id, hash) 
                VALUES ("${version.id}", "${createHmac('sha256', version.id).digest('hex')}")`),
            ]
        })
    )

    // Generate the testing combinations by SELECT'ing from both transports
    // and muxers tables the distinct combinations where the transport and the muxer
    // of the different libp2p implementations match.
    const queryResults =
        await db.all(`SELECT DISTINCT a.id as id1, b.id as id2, a.transport, ma.muxer, sa.sec as sec1, sb.sec as sec2, ha.hash, hb.hash
                     FROM transports a, transports b, muxers ma, muxers mb, secureChannels sa, secureChannels sb, hash ha, hash hb
                     WHERE a.id != b.id
                     AND a.id == ma.id
                     AND b.id == mb.id
                     AND a.id == sa.id
                     AND b.id == sb.id
                     AND a.id == ha.id
                     AND b.id == hb.id
                     AND sa.sec == sb.sec
                     AND a.transport == b.transport
                     AND ma.muxer == mb.muxer
                     AND ha.hash < hb.hash;`);
    const sameSecurityQueryResults =
        await db.all(`SELECT DISTINCT a.id as id1, b.id as id2, a.transport, ma.muxer, sa.sec as sec1, sb.sec as sec2, ha.hash, hb.hash
                     FROM transports a, transports b, muxers ma, muxers mb, secureChannels sa, secureChannels sb, hash ha, hash hb
                     WHERE a.id != b.id
                     AND a.id == ma.id
                     AND b.id == mb.id
                     AND a.id == sa.id
                     AND b.id == sb.id
                     AND a.id == ha.id
                     AND b.id == hb.id
                     AND sa.sec != sb.sec
                     AND a.transport == b.transport
                     AND ma.muxer == mb.muxer
                     AND ha.hash < hb.hash;`);
    const sameVersionQueryResults =
        await db.all(`SELECT DISTINCT a.id as id1, a.transport, ha.hash, sa.sec as sec1, sb.sec as sec2, ma.muxer, COUNT(*)
                     FROM transports a, transports b, hash ha, hash hb,
                     secureChannels sa, secureChannels sb, muxers ma
                     WHERE a.id == b.id
                     AND sa.sec != sb.sec
                     AND ha.hash == hb.hash
                     GROUP BY id1
                     HAVING COUNT(*) >= 1;`);
    const sameVersionAndSecurityQueryResults =
        await db.all(`SELECT DISTINCT a.id as id1, a.transport, ha.hash, sa.sec as sec1, sb.sec as sec2, ma.muxer, COUNT(*)
                     FROM transports a, transports b, hash ha, hash hb,
                     secureChannels sa, secureChannels sb, muxers ma
                     WHERE a.id == b.id
                     AND sa.sec == sb.sec
                     AND ha.hash == hb.hash
                     GROUP BY id1
                     HAVING COUNT(*) >= 1;`);
    await db.close();

    const testPlans = queryResults.map((test): TestPlan => ({
        name: `${test.id1} x ${test.id2} (${test.transport}, ${test.sec1}, ${test.sec2}, ${test.muxer})`,
        instances: [{
            name: test.id1,
            containerImageID: containerImages[test.id1],
            runtimeEnv: {
                transport: test.transport,
                muxer: test.muxer,
                security: test.sec1,
            }
        }, {
            name: test.id2,
            containerImageID: containerImages[test.id2],
            runtimeEnv: {
                transport: test.transport,
                muxer: test.muxer,
                security: test.sec2,
            }
        }]
    })).concat(sameSecurityQueryResults.map((test): TestPlan => ({
        name: `${test.id1} x ${test.id2} (${test.transport}, ${test.sec1}, ${test.sec2}, ${test.muxer})`,
        instances: [{
            name: test.id1,
            containerImageID: containerImages[test.id1],
            runtimeEnv: {
                transport: test.transport,
                muxer: test.muxer,
                security: test.sec1,
            }
        }, {
            name: test.id2,
            containerImageID: containerImages[test.id2],
            runtimeEnv: {
                transport: test.transport,
                muxer: test.muxer,
                security: test.sec2,
            }
        }]
    }))).concat(sameVersionQueryResults.map((test): TestPlan => ({
        name: `${test.id1} x ${test.id1} (${test.transport}, ${test.sec1}, ${test.sec2}, ${test.muxer})`,
        instances: [{
            name: test.id1,
            containerImageID: containerImages[test.id1],
            runtimeEnv: {
                transport: test.transport,
                muxer: test.muxer,
                security: test.sec1,
            }
        }, {
            name: test.id1,
            containerImageID: containerImages[test.id1],
            runtimeEnv: {
                transport: test.transport,
                muxer: test.muxer,
                security: test.sec2,
            }
        }]
    }))).concat(sameVersionAndSecurityQueryResults.map((test): TestPlan => ({
        name: `${test.id1} x ${test.id1} (${test.transport}, ${test.sec1}, ${test.sec2}, ${test.muxer})`,
        instances: [{
            name: test.id1,
            containerImageID: containerImages[test.id1],
            runtimeEnv: {
                transport: test.transport,
                muxer: test.muxer,
                security: test.sec1,
            }
        }, {
            name: test.id1,
            containerImageID: containerImages[test.id1],
            runtimeEnv: {
                transport: test.transport,
                muxer: test.muxer,
                security: test.sec2,
            }
        }]
    })))


    return { testPlans }
}
