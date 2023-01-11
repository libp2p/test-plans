import run from 'wo-testground'

import { fileURLToPath } from 'url';
import path from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

;(async () => {
    const IS_DIALER_STR = process.env.is_dialer
    const isDialer = IS_DIALER_STR === 'true'

    await run(async (runner) => {
        if (isDialer) {
            const otherMa = (await runner.redis().blPop('listenerAddr', 10)).element
            await runner.store('otherMultiAddress', otherMa)
        }

        await runner.exec(path.join(__dirname, 'test.js'))

        if (isDialer) {
            await runner.redis().rPush('dialerDone', '')
        } else {
            const ma = await runner.load('multiAddress')
            await runner.redis().rPush('listenerAddr', ma)
            await runner.redis().blPop('dialerDone', 4)
        }
    })
})()
