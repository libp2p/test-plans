import { Noise } from './noise.js';
export { pureJsCrypto } from './crypto/js.js';
export function noise(init = {}) {
    return () => new Noise(init);
}
//# sourceMappingURL=index.js.map