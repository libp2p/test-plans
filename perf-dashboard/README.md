# Perf Dashboard [wip]

This is an outline of what I'd like to see our perf dashboard look like.

A lot of this is inspired by the [MsQuic
dashboard](https://microsoft.github.io/msquic/). Please look at that first.

For each combination of libp2p implementation, version, and transport we would
have numbers that outline:
1. Download/Upload throughput
2. Request latency
3. Requests per second (for some request/response protocol)
4. Handshakes per second (useful to identify overhead in connection
   initialization).

The y axis on the graphs is the value for the above tests, the x axis is the
specific version. Different lines represent different implementation+transports.

The dashboards should be selectable and filterable.

# Other transports (iperf/http)

We have to be careful to compare apples to apples. A raw iperf number might be
confusing here because no application will ever hit those numbers since they
will at least want some encryption in their connection. I would suggest not
having this or an HTTP comparison. Having HTTPS might be okay.

# Example dashboard

https://observablehq.com/@realmarcopolo/libp2p-perf

The dashboard automatically pulls data from this repo to display it.

It currently pulls example-data.json. The schema of this data is defined in
`benchmarks.schema.json` and `benchmark-result-type.ts`.