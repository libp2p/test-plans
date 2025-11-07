# Nim Transport Interopability Tests

## Current Status

<!--INTEROP_DASHBOARD_START-->
## Using: tcp, noise, yamux
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | c-v0.0.1 | dotnet-v1.0 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | jvm-v1.2 | nim-v1.14 | python-v0.4 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | -------- | ----------- | -------- | -------- | -------- | -------- | -------- | -------- | -------- | --------- | ----------- | ---------- | ---------- | ---------- | ---------- |
| c-v0.0.1 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| dotnet-v1.0 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| go-v0.40 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| go-v0.41 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| go-v0.42 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| go-v0.43 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| go-v0.44 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| go-v0.45 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| jvm-v1.2 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| nim-v1.14 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| python-v0.4 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :red_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.53 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.54 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.55 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.56 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |

## Using: tcp, noise, mplex
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | c-v0.0.1 | jvm-v1.2 | nim-v1.14 | python-v0.4 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | -------- | -------- | --------- | ----------- | ---------- | ---------- | ---------- | ---------- |
| c-v0.0.1 | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| jvm-v1.2 | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| nim-v1.14 | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| python-v0.4 | :white_circle: | :white_circle: | :red_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.53 | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.54 | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.55 | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.56 | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |

## Using: ws, noise, yamux
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | chromium-rust-v0.53 | chromium-rust-v0.54 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | jvm-v1.2 | nim-v1.14 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | ------------------- | ------------------- | -------- | -------- | -------- | -------- | -------- | -------- | -------- | --------- | ---------- | ---------- | ---------- | ---------- |
| chromium-rust-v0.53 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| chromium-rust-v0.54 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| go-v0.40 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| go-v0.41 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| go-v0.42 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| go-v0.43 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| go-v0.44 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| go-v0.45 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| jvm-v1.2 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| nim-v1.14 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.53 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.54 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.55 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.56 | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |

## Using: ws, noise, mplex
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | chromium-rust-v0.53 | chromium-rust-v0.54 | jvm-v1.2 | nim-v1.14 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | ------------------- | ------------------- | -------- | --------- | ---------- | ---------- | ---------- | ---------- |
| chromium-rust-v0.53 | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| chromium-rust-v0.54 | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| jvm-v1.2 | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| nim-v1.14 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.53 | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.54 | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.55 | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |
| rust-v0.56 | :white_circle: | :white_circle: | :white_circle: | :green_circle: | :white_circle: | :white_circle: | :white_circle: | :white_circle: |


<!--INTEROP_DASHBOARD_END-->

