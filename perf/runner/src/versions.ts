import fs from 'fs';
import path from 'path';

export type PLATFORMS = 'chromium' | 'firefox' | 'webkit' | 'electron' | 'node'

export type Version = {
    id: string,
    implementation: "go-libp2p" | "js-libp2p" | "nim-libp2p" | "rust-libp2p" | "zig-libp2p" | "https" | "quic-go",
    transportStacks: string[],

    /**
     * If specified, an invocation of the perf script with `--role=relay` will
     * occur
     */
    relay?: boolean

    /**
     * If specified this will be passed to the client as `--platform=$PLATFORM`
     */
    client?: PLATFORMS

    /**
     * If specified this will be passed to the server as `--platform=$PLATFORM`
     */
    server?: PLATFORMS
}

export const versions: Array<Version> = JSON.parse(fs.readFileSync(path.join(__dirname, '../versionsInput.json'), 'utf8'));
