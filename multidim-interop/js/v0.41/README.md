# Javascript (JS) Multi-dimensional Interoperability tests

This directory contains tests for javascript interoperability with other languages.

## Running the tests

To run the tests, you need to have [node.js](https://nodejs.org/en/) installed, minimum v16.

### Examples

For all examples we assume that a redis server is already running, which you can do yourself
as follows:

```
docker run --rm -it -p 6379:6379 redis/redis-stack
```

#### Node to Node

You can have two nodes run the Ping test directly on your (host) machine as follows:

```
# shell 1
REDIS_ADDR=localhost:6379 transport=ws security=noise muxer=mplex is_dialer="true" npm run ping

# shell 2
REDIS_ADDR=localhost:6379 ip="0.0.0.0" transport=ws security=noise muxer=mplex is_dialer="false" npm run ping
```

You should see in the first shell an output such as `Ping successful: 84`, with `84` being the _RTT_.


#### Browser to Node

This is the same as previous test, except that the dialer node is a browser runtime (chromium, webkit, firefox). 

```
# shell 1
REDIS_ADDR=localhost:6379 transport=ws security=noise muxer=mplex is_dialer="true" npm run ping -- --runtime chromium
# NOTE: you can also pass in TEST_BROWSER_HEADFULL=true if you want to see the browser window

# shell 2
REDIS_ADDR=localhost:6379 ip="0.0.0.0" transport=ws security=noise muxer=mplex is_dialer="false" npm run ping
```

If all goes well you should once again see the _RTT_ log.

#### Node to Browser

This is not yet supported, as it would have to mean you are listening from the browser,
which would effectively be a browser-to-browser setup.

To be added later. (Soon, TM).
