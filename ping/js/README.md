# Compatibility JS: Ping Test

## Run in isolation

You can run the test in isolation by importing and running it manually:

```
testground plan import --from ./ping/js --name compatibility-js
```

In a different shell:

```
testground daemon
```

Back to the original shell:

```
testground run single \
    --plan compatibility-js \
    --testcase ping \
    --instances 2 \
    --builder docker:generic \
    --runner local:docker \
    --wait
```

This will run the ping test between two NodeJS instances.
