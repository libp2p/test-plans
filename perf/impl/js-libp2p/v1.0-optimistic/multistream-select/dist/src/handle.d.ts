import type { MultistreamSelectInit, ProtocolStream } from './index.js';
import type { Duplex } from 'it-stream-types';
/**
 * Handle multistream protocol selections for the given list of protocols.
 *
 * Note that after a protocol is handled `listener` can no longer be used.
 *
 * @param stream - A duplex iterable stream to listen on
 * @param protocols - A list of protocols (or single protocol) that this listener is able to speak.
 * @param options - an options object containing an AbortSignal and an optional boolean `writeBytes` - if this is true, `Uint8Array`s will be written into `duplex`, otherwise `Uint8ArrayList`s will
 * @returns A stream for the selected protocol and the protocol that was selected from the list of protocols provided to `select`
 * @example
 *
 * ```js
 * import { pipe } from 'it-pipe'
 * import * as mss from '@libp2p/multistream-select'
 * import { Mplex } from '@libp2p/mplex'
 *
 * const muxer = new Mplex({
 *   async onStream (muxedStream) {
 *   // mss.handle(handledProtocols)
 *   // Returns selected stream and protocol
 *   const { stream, protocol } = await mss.handle(muxedStream, [
 *     '/ipfs-dht/1.0.0',
 *     '/ipfs-bitswap/1.0.0'
 *   ])
 *
 *   // Typically here we'd call the handler function that was registered in
 *   // libp2p for the given protocol:
 *   // e.g. handlers[protocol].handler(stream)
 *   //
 *   // If protocol was /ipfs-dht/1.0.0 it might do something like this:
 *   // try {
 *   //   await pipe(
 *   //     dhtStream,
 *   //     source => (async function * () {
 *   //       for await (const chunk of source)
 *   //         // Incoming DHT data -> process and yield to respond
 *   //     })(),
 *   //     dhtStream
 *   //   )
 *   // } catch (err) {
 *   //   // Error in stream
 *   // }
 *   }
 * })
 * ```
 */
export declare function handle<Stream extends Duplex<any, any, any>>(stream: Stream, protocols: string | string[], options: MultistreamSelectInit): Promise<ProtocolStream<Stream>>;
//# sourceMappingURL=handle.d.ts.map