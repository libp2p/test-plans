export const symbol = Symbol.for('@libp2p/transport');
export function isTransport(other) {
    return other != null && Boolean(other[symbol]);
}
/**
 * Enum Transport Manager Fault Tolerance values
 */
export var FaultTolerance;
(function (FaultTolerance) {
    /**
     * should be used for failing in any listen circumstance
     */
    FaultTolerance[FaultTolerance["FATAL_ALL"] = 0] = "FATAL_ALL";
    /**
     * should be used for not failing when not listening
     */
    FaultTolerance[FaultTolerance["NO_FATAL"] = 1] = "NO_FATAL";
})(FaultTolerance || (FaultTolerance = {}));
//# sourceMappingURL=index.js.map