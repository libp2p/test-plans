import {lastStdoutLine} from "./compose-runner";

let exampleStdout = `
Attaching to rust-v0_52_x_rust-v0_52__quic_-dialer-1, rust-v0_52_x_rust-v0_52__quic_-dialer_router-1, rust-v0_52_x_rust-v0_52__quic_-listener-1, rust-v0_52_x_rust-v0_52__quic_-listener_router-1, rust-v0_52_x_rust-v0_52__quic_-redis-1, rust-v0_52_x_rust-v0_52__quic_-relay-1
rust-v0_52_x_rust-v0_52__quic_-redis-1         | 1:C 19 Sep 2023 05:19:20.620 # WARNING Memory overcommit must be enabled! Without it, a background save or replication may fail under low memory condition. Being disabled, it can also cause failures without low memory condition, see https://github.com/jemalloc/jemalloc/issues/1328. To fix this issue add 'vm.overcommit_memory = 1' to /etc/sysctl.conf and then reboot or run the command 'sysctl vm.overcommit_memory=1' for this to take effect.
rust-v0_52_x_rust-v0_52__quic_-redis-1         | 1:C 19 Sep 2023 05:19:20.620 * oO0OoO0OoO0Oo Redis is starting oO0OoO0OoO0Oo
rust-v0_52_x_rust-v0_52__quic_-redis-1         | 1:C 19 Sep 2023 05:19:20.620 * Redis version=7.2.1, bits=64, commit=00000000, modified=0, pid=1, just started
rust-v0_52_x_rust-v0_52__quic_-redis-1         | 1:C 19 Sep 2023 05:19:20.620 # Warning: no config file specified, using the default config. In order to specify a config file use redis-server /path/to/redis.conf
rust-v0_52_x_rust-v0_52__quic_-redis-1         | 1:M 19 Sep 2023 05:19:20.620 * monotonic clock: POSIX clock_gettime
rust-v0_52_x_rust-v0_52__quic_-redis-1         | 1:M 19 Sep 2023 05:19:20.621 * Running mode=standalone, port=6379.
rust-v0_52_x_rust-v0_52__quic_-redis-1         | 1:M 19 Sep 2023 05:19:20.621 * Server initialized
rust-v0_52_x_rust-v0_52__quic_-redis-1         | 1:M 19 Sep 2023 05:19:20.621 * Ready to accept connections tcp
rust-v0_52_x_rust-v0_52__quic_-dialer-1         | {"rtt_to_holepunched_peer_millis":201}
rust-v0_52_x_rust-v0_52__quic_-dialer-1 exited with code 0
`;

const line = lastStdoutLine(exampleStdout, "dialer", "rust-v0_52_x_rust-v0_52__quic_");

if (line != `{"rtt_to_holepunched_peer_millis":201}`) {
    throw new Error("Unexpected stdout")
}

// Docker Compose v2 uses the short `<service>-1` prefix and adds ANSI codes to
// the exit notice.
let v2Stdout = `Attaching to dialer-1, dialer_router-1, listener-1, listener_router-1, redis-1, relay-1
redis-1  | 1:M 28 Aug 2026 11:11:18.675 * Ready to accept connections tcp
dialer-1           | {"rtt_to_holepunched_peer_millis":200}
\x1b[Kdialer-1 exited with code 0
`;

const v2Line = lastStdoutLine(v2Stdout, "dialer", "go-v0_49_x_go-v0_49__tcp_");

if (v2Line != `{"rtt_to_holepunched_peer_millis":200}`) {
    throw new Error("Unexpected v2 stdout: " + v2Line)
}
