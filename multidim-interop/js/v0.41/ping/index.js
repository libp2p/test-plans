import run from 'wo-testground'

import { fileURLToPath } from 'url';
import path from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

;(async () => {
    const IS_DIALER_STR = process.env.is_dialer
    const isDialer = IS_DIALER_STR === 'true'

    if (isDialer) {
        await run(async (runner) => {
            const otherMa = (await runner.redis().blPop('listenerAddr', 10)).element
            console.log('other multi address', otherMa)
            await runner.createBarrier('otherMultiAddress', otherMa)

            await runner.exec(path.join(__dirname, 'test.js'))

            await runner.redis().rPush('dialerDone', '')
        })
    } else {
        await run(async (runner) => {
            await runner.createBarrier('multiAddress')
            await runner.createBarrier('dialerDone')

            const testPromise = runner.exec(path.join(__dirname, 'test.js'))

            const multiAddress = await runner.waitOnBarrier('multiAddress')
            await runner.redis().rPush('listenerAddr', multiAddress)
            console.log('listener address sent over redis...')

            const dialerDoneResult = await runner.redis().blPop('dialerDone', 4);
            if (!dialerDoneResult || dialerDoneResult.element !== '') {
                throw new Error(`unexpected dialer done result: ${JSON.stringify(dialerDoneResult)}`)
            }
            await runner.resolveBarrier('dialerDone')

            await testPromise
        })
    }
})()
