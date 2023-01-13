import { spawn } from 'child_process'

import {
  chromium,
  firefox,
  webkit
} from 'playwright'

import spawnServer from './server/index.js'

export async function run (runtime, bundledTestFile) {
  const envParameters = process.env

  await spawnServer(8080, bundledTestFile)

  let browser
  try {
    const browserDebugPort = process.env.TEST_BROWSER_DEBUG_PORT || 9222

    const browserHeadfull = process.env.TEST_BROWSER_HEADFULL === 'true'

    switch (runtime) {
      // chromium is the default browser engine,
      // and the only browser for which we currently support
      // remote debugging, meaning attaching a local chrome (on your host)
      // to the chromium version running in docker under a testground plan.
      case 'chromium':
        console.log(`launching chromium browser with exposed debug port: ${browserDebugPort}`)
        browser = await chromium.launch({
          headless: !browserHeadfull,
          devtools: browserHeadfull,
          args: [
            '--remote-debugging-address=0.0.0.0',
                        `--remote-debugging-port=${browserDebugPort}`
          ]
        })
        break

        // NOTE: remote debugging is not supported on webkit,
        // it should in theory be possible, but no working solution
        // has been demonstrated so far. Consider the remote debugging for this
        // browser engine (firefox) as a starting point should you want to contribute
        // such support yourself.
      case 'firefox':
        // eslint-disable-next-line no-case-declarations
        const localBrowserDebugPort = Number(browserDebugPort) + 1
        console.log(`launching firefox browser with exposed debug port: ${browserDebugPort} (local ${localBrowserDebugPort})`)
        browser = await firefox.launch({
          headless: true,
          devtools: true,
          args: [
                        `-start-debugger-server=${localBrowserDebugPort}`
          ]
        })

        console.log('launching tcp proxy to expose firefox debugger for remote access')
        // eslint-disable-next-line no-case-declarations
        const tcpProxy = spawn(
          'socat', [
                        `tcp-listen:${browserDebugPort},bind=0.0.0.0,fork`,
                        `tcp:localhost:${localBrowserDebugPort}`
          ]
        )
        tcpProxy.stdout.on('data', (data) => {
          console.log(`firefox debugger: tcpProxy: stdout: ${data}`)
        })

        tcpProxy.stderr.on('data', (data) => {
          console.error(`firefox debugger: tcpProxy: stderr: ${data}`)
        })

        break

        // NOTE: remote debugging is not supported on webkit,
        // nor do we know of an approach on how we would allow such a thing
      case 'webkit':
        console.log('launching webkit browser (remote debugging not yet supported)')
        browser = await webkit.launch({
          headless: true,
          devtools: true
        })
        break

      default:
        console.error(`unknown browser runtime: ${runtime}`)
        process.exit(1)
    }

    const page = await browser.newPage()

    page.on('console', (message) => {
      const loc = message.location()
      console.log(`[${message.type()}] ${loc.url}@L${loc.lineNumber}:C${loc.columnNumber}: ${message.text()} — ${message.args()}`)
    })

    console.log('prepare page window (global) environment')
    await page.addInitScript((env) => {
      window.testground = {
        env
      }
    }, envParameters)

    console.log('opening up testplan webpage on localhost')
    await page.goto('http://127.0.0.1:8080', {
      timeout: 3000
    })

    console.log('waiting until bundled test is finished...')
    // `window.testground.result` is set by shimmed `markTestAsCompleted` function
    const testgroundResult = await page.waitForFunction(() => {
      return window.testground && window.testground.result
    }, undefined, {
      timeout: 120_000
    })
    console.log(`testground in browser finished with result: ${testgroundResult}`)

    console.log('start browser exit process...')

    if (process.env.TEST_KEEP_OPENED_BROWSERS === 'true') {
      console.log('halting browser until SIGINT is received...')
      await new Promise((resolve) => {
        process.on('SIGINT', resolve)
      })
    }
  } catch (error) {
    console.error(`browser process resulted in exception: ${error}`)
    throw error
  } finally {
    if (browser) {
      try {
        await browser.close()
      } catch (error) {
        console.error(`browser closure resulted in exception: ${error}`)
      }
    }
    console.log('exiting browser test...')
    process.exit(0)
  }
}
