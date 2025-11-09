# Transport Interoperability Tests

## Current Status

<!--INTEROP_DASHBOARD_START-->
## Using: quic-v1
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | c-v0.0.1 | eth-p2p-z-v0.0.1 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | jvm-v1.2 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | -------- | ---------------- | -------- | -------- | -------- | -------- | -------- | -------- | -------- | ---------- | ---------- | ---------- | ---------- |
| c-v0.0.1 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| eth-p2p-z-v0.0.1 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.40 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.41 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.42 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.43 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.44 | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.45 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| jvm-v1.2 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.53 | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.54 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.55 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.56 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |

## Using: webrtc-direct
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | chromium-rust-v0.53 | chromium-rust-v0.54 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | ------------------- | ------------------- | -------- | -------- | -------- | -------- | -------- | -------- | ---------- | ---------- | ---------- | ---------- |
| chromium-rust-v0.53 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: |
| chromium-rust-v0.54 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.40 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: |
| go-v0.41 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: |
| go-v0.42 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: |
| go-v0.43 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: |
| go-v0.44 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: |
| go-v0.45 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: |
| rust-v0.53 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.54 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.55 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.56 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |

## Using: webtransport
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | chromium-rust-v0.53 | chromium-rust-v0.54 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 |
| ------------------------------ | ------------------- | ------------------- | -------- | -------- | -------- | -------- | -------- | -------- |
| chromium-rust-v0.53 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| chromium-rust-v0.54 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.40 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.41 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.42 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.43 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.44 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.45 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |

## Using: tcp, noise, yamux
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | c-v0.0.1 | dotnet-v1.0 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | jvm-v1.2 | nim-v1.14 | python-v0.4 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | -------- | ----------- | -------- | -------- | -------- | -------- | -------- | -------- | -------- | --------- | ----------- | ---------- | ---------- | ---------- | ---------- |
| c-v0.0.1 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| dotnet-v1.0 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.40 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.41 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.42 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.43 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.44 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.45 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| jvm-v1.2 | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| nim-v1.14 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| python-v0.4 | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: |
| rust-v0.53 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.54 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.55 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.56 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |

## Using: tcp, noise, mplex
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | c-v0.0.1 | jvm-v1.2 | nim-v1.14 | python-v0.4 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | -------- | -------- | --------- | ----------- | ---------- | ---------- | ---------- | ---------- |
| c-v0.0.1 | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| jvm-v1.2 | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| nim-v1.14 | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| python-v0.4 | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: | :red_circle: |
| rust-v0.53 | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.54 | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.55 | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.56 | :green_circle: | :green_circle: | :green_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |

## Using: ws, tls, yamux
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | jvm-v1.2 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | -------- | -------- | -------- | -------- | -------- | -------- | -------- | ---------- | ---------- | ---------- | ---------- |
| go-v0.40 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.41 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.42 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.43 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.44 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.45 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| jvm-v1.2 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.53 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.54 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.55 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.56 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |

## Using: ws, noise, yamux
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | chromium-rust-v0.53 | chromium-rust-v0.54 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | jvm-v1.2 | nim-v1.14 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | ------------------- | ------------------- | -------- | -------- | -------- | -------- | -------- | -------- | -------- | --------- | ---------- | ---------- | ---------- | ---------- |
| chromium-rust-v0.53 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| chromium-rust-v0.54 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.40 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.41 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.42 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.43 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.44 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.45 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| jvm-v1.2 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| nim-v1.14 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.53 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.54 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.55 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.56 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |

## Using: ws, noise, mplex
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | chromium-rust-v0.53 | chromium-rust-v0.54 | jvm-v1.2 | nim-v1.14 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | ------------------- | ------------------- | -------- | --------- | ---------- | ---------- | ---------- | ---------- |
| chromium-rust-v0.53 | :white_circle: | :white_circle: | :red_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| chromium-rust-v0.54 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| jvm-v1.2 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| nim-v1.14 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.53 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.54 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.55 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.56 | :white_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |

## Using: ws, tls, mplex
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | jvm-v1.2 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | -------- | ---------- | ---------- | ---------- | ---------- |
| jvm-v1.2 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.53 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.54 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.55 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.56 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |

## Using: tcp, tls, yamux
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | jvm-v1.2 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | -------- | -------- | -------- | -------- | -------- | -------- | -------- | ---------- | ---------- | ---------- | ---------- |
| go-v0.40 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.41 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.42 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.43 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.44 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.45 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| jvm-v1.2 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.53 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.54 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.55 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.56 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |

## Using: tcp, tls, mplex
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | jvm-v1.2 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
| ------------------------------ | -------- | ---------- | ---------- | ---------- | ---------- |
| jvm-v1.2 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.53 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.54 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.55 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.56 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |

## Using: wss, tls, yamux
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 |
| ------------------------------ | -------- | -------- | -------- | -------- | -------- | -------- |
| go-v0.40 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.41 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.42 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.43 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.44 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.45 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |

## Using: wss, noise, yamux
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 |
| ------------------------------ | -------- | -------- | -------- | -------- | -------- | -------- |
| go-v0.40 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.41 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.42 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.43 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.44 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.45 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |

## Using: tcp, plaintext, yamux
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | python-v0.4 |
| ------------------------------ | ----------- |
| python-v0.4 | :red_circle: |

## Using: tcp, plaintext, mplex
| ⬇️ dialer 📞 \  ➡️ listener 🎧 | python-v0.4 |
| ------------------------------ | ----------- |
| python-v0.4 | :red_circle: |


<!--INTEROP_DASHBOARD_END-->

## About

This tests that different libp2p implementations can communicate with each other
on each of their supported (transport) capabilities.

Each version of libp2p is defined in `versions.ts`. There the version defines
its capabilities along with the id of its container image.

This repo and tests adhere to these constraints:
1. Be reproducible for a given commit.
2. Caching is an optimization. Things should be fine without it.
3. If we have a cache hit, be fast.

## Test spec

The implementation is run in a container and is passed parameters via
environment variables. The current parameters are:

| Name                 | Description                                                  | Is Optional                                                     |
| -------------------- | ------------------------------------------------------------ | --------------------------------------------------------------- |
| transport            | The transport to use                                         | no                                                              |
| muxer                | The muxer to use                                             | no, except when transport is one of quic, quic-v1, webtransport |
| security             | The security channel to use                                  | no, except when transport is one of quic, quic-v1, webtransport |
| is_dialer            | Should you dial or listen                                    | no                                                              |
| ip                   | IP address to bind the listener to                           | yes, default to "0.0.0.0"                                       |
| redis_addr           | A different address to connect to redis (default redis:6379) | yes, default to the `redis` host on port 6379                   |
| test_timeout_seconds | Control the timeout of test.                                 | yes, default to 180 seconds.                                    |

The test should do two different things depending on if it's the dialer or
listener.

## Running Locally

In some cases you may want to run locally when debugging, such as modifying internal dependencies.

1. To run the test locally, you'll also need to have docker installed in order to run the redis instance. Once docker is running, you can run the following command to start the redis instance:

```bash
docker run --rm -p 6379:6379 redis:7-alpine
```

This will start a redis instance on port 6379.

2. Next, you'll need to install the dependencies and build the implementation for the test.  In this and the next step we are using a JS implementation as an example, so you would run the following command:

```bash
cd impl/js/v0.xx.xx/ && make
```

3. Then you can run a listener by running the following command in this case we are running a rust listener:

```bash
 RUST_LOG=yamux=trace transport=tcp muxer=yamux security=noise is_dialer=false ip="0.0.0.0" redis_addr=localhost:6379  cargo run --package interop-tests
 ```

3. Finally you can run a dialer by running the following command, ensure that you pass the required environment variables, as well as any that may be of use for debugging:

```bash
DEBUG=*:yamux:trace transport=tcp muxer=yamux security=noise is_dialer=true   npm run test -- -t node
```

For more details on how to run a dialer vs a listener, see the sections below.

### Dialer

The dialer should emit all diagnostic logs to `stderr`. Only the final JSON
string result should be emitted to `stdout`.

1. Connect to the Redis instance.
2. Create a libp2p node as defined by the environment variables.
3. Get the listener's address via Redis' `BLPOP` using the `listenerAddr` key.
4. Record the current instant as `handshakeStartInstant`.
5. Connect to the listener.
6. Ping the listener, and record the round trip duration as `pingRTT`
7. Record the duration since `handshakeStartInstant`. This is `handshakePlusOneRTT`.
8. Print to `stdout` the JSON formatted string: `{"handshakePlusOneRTTMillis":
   handshakePlusOneRTT, "pingRTTMilllis": pingRTT}`. Durations should be printed in
   milliseconds as a float.
9.  Exit with a code zero.

On error, the dialer should return a non-zero exit code.

### Listener

The listener should emit all diagnostic logs to `stderr`.

1. Connect to the Redis instance.
2. Create a libp2p node as defined by the environment variables.
3. Publish the listener's address via Redis' `RPUSH` using the `listenerAddr`
   key.
4. Sleep for the duration of `test_timeout_seconds`. The test runner will kill this
   process when the dialer finishes.
5. If the timeout is hit, exit with a non-zero error code.

On error, the listener should return a non-zero exit code.

## Caching

The caching strategy is opinionated in an attempt to make things simpler and
faster. Here's how it works:

1. We cache the result of image.json in each implementation folder.
2. The cache key is derived from the hashes of the files in the implementation folder.
3. When loading from cache, if we have a cache hit, we load the image into
   docker and create the image.json file. We then call `make -o image.json` to
   allow the implementation to build any extra things from cache (e.g. JS-libp2p
   builds browser images from the same base as node). If we have a cache miss,
   we simply call `make` and build from scratch.
4. When we push the cache we use the cache-key along with the docker platform
   (arm64 vs x86_64).
