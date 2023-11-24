import { Yamux } from './muxer.js';
export { GoAwayCode } from './frame.js';
export function yamux(init = {}) {
    return () => new Yamux(init);
}
//# sourceMappingURL=index.js.map