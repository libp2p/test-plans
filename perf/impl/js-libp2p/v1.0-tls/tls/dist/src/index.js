/**
 * @packageDocumentation
 *
 * Implements the spec at https://github.com/libp2p/specs/blob/master/tls/tls.md
 *
 * @example
 *
 * ```typescript
 * import { createLibp2p } from 'libp2p'
 * import { tls } from '@libp2p/tls'
 *
 * const node = await createLibp2p({
 *   // ...other options
 *   connectionEncryption: [
 *     tls()
 *   ]
 * })
 * ```
 */
import { TLSSocket, connect } from 'node:tls';
import { CodeError } from '@libp2p/interface';
import { generateCertificate, verifyPeerCertificate, itToStream, streamToIt } from './utils.js';
const PROTOCOL = '/tls/1.0.0';
class TLS {
    protocol = PROTOCOL;
    log;
    timeout;
    constructor(components, init = {}) {
        this.log = components.logger.forComponent('libp2p:tls');
        this.timeout = init.timeout ?? 1000;
    }
    async secureInbound(localId, conn, remoteId) {
        return this._encrypt(localId, conn, false, remoteId);
    }
    async secureOutbound(localId, conn, remoteId) {
        return this._encrypt(localId, conn, true, remoteId);
    }
    /**
     * Encrypt connection
     */
    async _encrypt(localId, conn, isServer, remoteId) {
        const opts = {
            ...await generateCertificate(localId),
            isServer,
            // require TLS 1.3 or later
            minVersion: 'TLSv1.3',
            // accept self-signed certificates
            rejectUnauthorized: false
        };
        let socket;
        if (isServer) {
            // @ts-expect-error docs say this is fine?
            socket = new TLSSocket(itToStream(conn), {
                ...opts,
                // require clients to send certificates
                requestCert: true
            });
        }
        else {
            socket = connect({
                socket: itToStream(conn),
                ...opts
            });
        }
        // @ts-expect-error no other way to prevent the TLS socket readable throwing on destroy?
        socket._readableState.autoDestroy = false;
        return new Promise((resolve, reject) => {
            const abortTimeout = setTimeout(() => {
                socket.destroy(new CodeError('Handshake timeout', 'ERR_HANDSHAKE_TIMEOUT'));
            }, this.timeout);
            const verifyRemote = () => {
                const remote = socket.getPeerCertificate();
                verifyPeerCertificate(remote.raw, remoteId, this.log)
                    .then(remotePeer => {
                    this.log('remote certificate ok, remote peer %p', remotePeer);
                    resolve({
                        remotePeer,
                        conn: {
                            ...conn,
                            ...streamToIt(socket)
                        }
                    });
                })
                    .catch(err => {
                    reject(err);
                })
                    .finally(() => {
                    clearTimeout(abortTimeout);
                });
            };
            socket.on('error', err => {
                reject(err);
                clearTimeout(abortTimeout);
            });
            socket.on('secure', (evt) => {
                this.log('verifying remote certificate');
                verifyRemote();
            });
        });
    }
}
export function tls(init) {
    return (components) => new TLS(components, init);
}
//# sourceMappingURL=index.js.map