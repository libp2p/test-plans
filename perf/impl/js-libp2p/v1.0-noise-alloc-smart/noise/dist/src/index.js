import { Noise } from './noise.js';
export { pureJsCrypto } from './crypto/js.js';
export function noise(init = {}) {
    return (components) => new Noise(components, init);
}
//# sourceMappingURL=index.js.map