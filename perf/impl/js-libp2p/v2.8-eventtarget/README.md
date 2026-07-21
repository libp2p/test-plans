Server:

```
./perf --run-server --server-address 127.0.0.1:1234 --transport tcp
```

Client

```
./perf --server-address 127.0.0.1:1234 --transport tcp --upload-bytes 10000000 --download bytes=10000000
```