# JS Ping Testplan

This testplan allows you to test `libp2p-js` both
in a NodeJS environment as well as cross-browser (firefox, chromium and webkit).

This plan is for now a "fork" of
[$testground/plans/example-browser-node](https://github.com/testground/testground/tree/master/plans/example-browser-node),
as there is no `docker:browser` builder yet.

The browser folder serves as a magic layer to allow your testplan to be run in a browser.
You should however not have a reason to touch that, the testplan
itself lives in the `src/` folder, which you do touch if needed.

## Usage

Within the root folder of this repository you can run the
integration test for this plan which will run all its test cases
in node and chromium:

```
<TODO>
```

Or in case you want, and already have a `testground daemon` running,
you can also run a single test case as follows:

```
testground run single \
    --plan compatibility-js \
    --testcase ping \
    --instances 1 \
    --builder docker:generic \
    --runner local:docker \
    --wait
```

TODO: correct this usage!

## Remote Debugging

Using the `chrome://inspect` debugger tool,
as documented in <https://developer.chrome.com/docs/devtools/remote-debugging/local-server/>,
you can remotely debug this testplan.

This allows you to attach to the chrome browser which is running the plan.
Different with the [/plans/<TODO>](../example-browser/) plan
is that we only allow the chrome browser here, as to keep things simple here.

How to do it:

1. start the testplan
2. check what host port is bound to the exposed debug port
3. open `chrome://inspect` in your chrome browser on your host machine
4. configure the network targets to discover: `127.0.0.1:<your port>`
5. attach to the debugger using `inspect`

If you want you can now attach breakpoints to anywhere in the source code,
an a refresh of the page should allow you to break on it.

### Firefox Remote Debugging

Using `about:debugging` you should be able to debug remotely
in a similar fashion. However, for now we had no success
in trying to connect to our firefox instance.

As such you consider Firefox remote debugging a non-supported feature for now,
should you want to remotely debug, please us chromium for now (the default browser).

### WebKit Remote Debugging

No approach for remote debugging a WebKit browser is known by the team.
For now this is not supported.

Please use chromium (the default browser) if you wish to remotely debug.
