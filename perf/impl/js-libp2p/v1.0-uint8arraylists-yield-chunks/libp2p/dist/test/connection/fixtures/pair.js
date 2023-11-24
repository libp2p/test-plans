import map from 'it-map';
import defer from 'p-defer';
import { Uint8ArrayList } from 'uint8arraylist';
/**
 * A pair of streams where one drains from the other
 */
export function pair() {
    const deferred = defer();
    let piped = false;
    return {
        sink: async (source) => {
            if (piped) {
                throw new Error('already piped');
            }
            piped = true;
            deferred.resolve(source);
        },
        source: (async function* () {
            const source = await deferred.promise;
            yield* map(source, (buf) => buf instanceof Uint8Array ? new Uint8ArrayList(buf) : buf);
        }())
    };
}
//# sourceMappingURL=pair.js.map