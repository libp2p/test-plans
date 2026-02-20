import fs from 'fs';
import path from 'path';

export type Version = {
    id: string,
    implementation: "go-libp2p" | "js-libp2p" | "nim-libp2p" | "rust-libp2p" | "zig-libp2p" | "https" | "quic-go",
    transportStacks: string[],
}

export const versions: Array<Version> = JSON.parse(fs.readFileSync(path.join(__dirname, '../versionsInput.json'), 'utf8'));
