import {lastStdoutLine} from "./compose-runner";

// Older Docker Compose versions prefix each log line with the full container
// name "<project>-<service>-<index>".
const legacyPrefixStdout = `
Attaching to go-v0_49_x_go-v0_49__quic_-client-1, go-v0_49_x_go-v0_49__quic_-redis-1, go-v0_49_x_go-v0_49__quic_-server-1
go-v0_49_x_go-v0_49__quic_-redis-1         | 1:M 11 Sep 2026 09:45:23.550 * Ready to accept connections tcp
go-v0_49_x_go-v0_49__quic_-client-1         | {"reachable":true,"tested_addr":"/ip4/172.19.0.4/udp/43263/quic-v1"}
go-v0_49_x_go-v0_49__quic_-client-1 exited with code 0
`;

// Docker Compose v2.20+ prefixes each log line with just "<service>-<index>",
// and marks the exit line with a carriage return and an ANSI erase-line escape.
const shortPrefixStdout = [
    "Attaching to client-1, redis-1, server-1",
    "redis-1  | 1:M 11 Sep 2026 09:45:23.550 * Ready to accept connections tcp",
    'client-1  | {"reachable":true,"tested_addr":"/ip4/172.19.0.4/udp/43263/quic-v1"}',
    "\r[Kclient-1 exited with code 0",
].join("\n");

const want = `{"reachable":true,"tested_addr":"/ip4/172.19.0.4/udp/43263/quic-v1"}`;

for (const [label, stdout] of [["legacy prefix", legacyPrefixStdout], ["short prefix", shortPrefixStdout]] as const) {
    const line = lastStdoutLine(stdout, "client", "go-v0_49_x_go-v0_49__quic_");
    if (line !== want) {
        throw new Error(`${label}: expected ${want} but got ${line}`);
    }
}

// A compose with no client output must fail loudly rather than crash on undefined.
let threw = false;
try {
    lastStdoutLine("Attaching to redis-1\nredis-1  | ready\n", "client", "empty");
} catch {
    threw = true;
}
if (!threw) {
    throw new Error("expected lastStdoutLine to throw when the client produced no output");
}

console.log("stdoutParser tests passed");
