import {lastStdoutLine} from "./compose-runner";

// Docker Compose v2 format uses service names without project prefix
let exampleStdout = `
Attaching to dialer-1, dialer_router-1, listener-1, listener_router-1, redis-1, relay-1
redis-1         | 1:C 19 Sep 2023 05:19:20.620 # WARNING Memory overcommit must be enabled! Without it, a background save or replication may fail under low memory condition. Being disabled, it can also cause failures without low memory condition, see https://github.com/jemalloc/jemalloc/issues/1328. To fix this issue add 'vm.overcommit_memory = 1' to /etc/sysctl.conf and then reboot or run the command 'sysctl vm.overcommit_memory=1' for this to take effect.
redis-1         | 1:C 19 Sep 2023 05:19:20.620 * oO0OoO0OoO0Oo Redis is starting oO0OoO0OoO0Oo
redis-1         | 1:C 19 Sep 2023 05:19:20.620 * Redis version=7.2.1, bits=64, commit=00000000, modified=0, pid=1, just started
redis-1         | 1:C 19 Sep 2023 05:19:20.620 # Warning: no config file specified, using the default config. In order to specify a config file use redis-server /path/to/redis.conf
redis-1         | 1:M 19 Sep 2023 05:19:20.620 * monotonic clock: POSIX clock_gettime
redis-1         | 1:M 19 Sep 2023 05:19:20.621 * Running mode=standalone, port=6379.
redis-1         | 1:M 19 Sep 2023 05:19:20.621 * Server initialized
redis-1         | 1:M 19 Sep 2023 05:19:20.621 * Ready to accept connections tcp
dialer-1         | {"rtt_to_holepunched_peer_millis":201}
dialer-1 exited with code 0
`;

const line = lastStdoutLine(exampleStdout, "dialer", "rust-v0_52_x_rust-v0_52__quic_");

if (line != `{"rtt_to_holepunched_peer_millis":201}`) {
    throw new Error("Unexpected stdout")
}
