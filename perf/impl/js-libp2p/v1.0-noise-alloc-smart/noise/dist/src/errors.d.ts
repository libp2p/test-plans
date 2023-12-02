export declare class UnexpectedPeerError extends Error {
    code: string;
    constructor(message?: string);
    static readonly code = "ERR_UNEXPECTED_PEER";
}
export declare class InvalidCryptoExchangeError extends Error {
    code: string;
    constructor(message?: string);
    static readonly code = "ERR_INVALID_CRYPTO_EXCHANGE";
}
//# sourceMappingURL=errors.d.ts.map