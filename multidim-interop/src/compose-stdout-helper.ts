// Helpers for parsing stdout from docker-compose. Includes tests that are run if you run this file directly.

// Given Compose stdout, return Dialer stdout
export function dialerStdout(composeStdout: string): string {
    let dialerLines = composeStdout.split("\n").filter(line => line.includes("dialer"))
    dialerLines = dialerLines.filter(line => !line.includes("exited with code"))
    dialerLines = dialerLines.filter(line => line.includes("|"))
    dialerLines = dialerLines.map(line => {
        const [preLine, ...rest] = line.split("|")
        return rest.join("|")
    })
    return dialerLines.join("\n")
}

// simple test case - avoids bringing in a whole test framework
function test() {
    const assert = (b: boolean) => { if (!b) throw new Error("assertion failed") }

    {

        // This came up in CI, not sure why compose split these lines up. Nothing else was using stdout
        const exampleComposeStdout = `
2023-07-05T20:53:32.7346588Z Attaching to zig-v0_0_1_x_zig-v0_0_1__quic-v1_-dialer-1, zig-v0_0_1_x_zig-v0_0_1__quic-v1_-listener-1, zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1
2023-07-05T20:53:32.7347413Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:C 05 Jul 2023 20:53:31.482 # oO0OoO0OoO0Oo Redis is starting oO0OoO0OoO0Oo
2023-07-05T20:53:32.7348271Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:C 05 Jul 2023 20:53:31.482 # Redis version=7.0.11, bits=64, commit=00000000, modified=0, pid=1, just started
2023-07-05T20:53:32.7349285Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:C 05 Jul 2023 20:53:31.482 # Warning: no config file specified, using the default config. In order to specify a config file use redis-server /path/to/redis.conf
2023-07-05T20:53:32.7350098Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:M 05 Jul 2023 20:53:31.483 * monotonic clock: POSIX clock_gettime
2023-07-05T20:53:32.7350785Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:M 05 Jul 2023 20:53:31.483 * Running mode=standalone, port=6379.
2023-07-05T20:53:32.7351427Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:M 05 Jul 2023 20:53:31.483 # Server initialized
2023-07-05T20:53:32.7353510Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:M 05 Jul 2023 20:53:31.483 # WARNING Memory overcommit must be enabled! Without it, a background save or replication may fail under low memory condition. Being disabled, it can can also cause failures without low memory condition, see https://github.com/jemalloc/jemalloc/issues/1328. To fix this issue add 'vm.overcommit_memory = 1' to /etc/sysctl.conf and then reboot or run the command 'sysctl vm.overcommit_memory=1' for this to take effect.
2023-07-05T20:53:32.7354714Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:M 05 Jul 2023 20:53:31.483 * Ready to accept connections
2023-07-05T20:53:32.7355190Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-dialer-1    | {
2023-07-05T20:53:32.7355819Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-dialer-1    | "handshakePlusOneRTTMillis": 7.342, "pingRTTMilllis": 7.113}
2023-07-05T20:53:32.7356363Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-dialer-1 exited with code 0
`

        const expectedParsed = JSON.stringify({ "handshakePlusOneRTTMillis": 7.342, "pingRTTMilllis": 7.113 })
        assert(JSON.stringify(JSON.parse(dialerStdout(exampleComposeStdout))) === expectedParsed)
    }

    {
        const exampleComposeStdout = `2023-07-05T22:41:18.8080447Z Attaching to zig-v0_0_1_x_zig-v0_0_1__quic-v1_-dialer-1, zig-v0_0_1_x_zig-v0_0_1__quic-v1_-listener-1, zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1
2023-07-05T22:41:18.8081556Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:C 05 Jul 2023 22:41:17.438 # oO0OoO0OoO0Oo Redis is starting oO0OoO0OoO0Oo
2023-07-05T22:41:18.8082800Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:C 05 Jul 2023 22:41:17.438 # Redis version=7.0.11, bits=64, commit=00000000, modified=0, pid=1, just started
2023-07-05T22:41:18.8184401Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:C 05 Jul 2023 22:41:17.438 # Warning: no config file specified, using the default config. In order to specify a config file use redis-server /path/to/redis.conf
2023-07-05T22:41:18.8185351Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:M 05 Jul 2023 22:41:17.439 * monotonic clock: POSIX clock_gettime
2023-07-05T22:41:18.8186133Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:M 05 Jul 2023 22:41:17.439 * Running mode=standalone, port=6379.
2023-07-05T22:41:18.8186846Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:M 05 Jul 2023 22:41:17.439 # Server initialized
2023-07-05T22:41:18.8188914Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:M 05 Jul 2023 22:41:17.439 # WARNING Memory overcommit must be enabled! Without it, a background save or replication may fail under low memory condition. Being disabled, it can can also cause failures without low memory condition, see https://github.com/jemalloc/jemalloc/issues/1328. To fix this issue add 'vm.overcommit_memory = 1' to /etc/sysctl.conf and then reboot or run the command 'sysctl vm.overcommit_memory=1' for this to take effect.
2023-07-05T22:41:18.8190173Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-redis-1     | 1:M 05 Jul 2023 22:41:17.439 * Ready to accept connections
2023-07-05T22:41:18.8190833Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-dialer-1    | {"handshakePlusOneRTTMillis": 
2023-07-05T22:41:18.8191389Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-dialer-1    | 8.849
2023-07-05T22:41:18.8191930Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-dialer-1    | , "pingRTTMilllis": 
2023-07-05T22:41:18.8192455Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-dialer-1    | 7.897}
2023-07-05T22:41:18.8192987Z zig-v0_0_1_x_zig-v0_0_1__quic-v1_-dialer-1 exited with code 0`

        const expectedParsed = JSON.stringify({ "handshakePlusOneRTTMillis": 8.849, "pingRTTMilllis": 7.897 })
        assert(JSON.stringify(JSON.parse(dialerStdout(exampleComposeStdout))) === expectedParsed)

    }
}

if (typeof require !== 'undefined' && require.main === module) {
    // Run the test case if this file is run directly.
    test();
}
