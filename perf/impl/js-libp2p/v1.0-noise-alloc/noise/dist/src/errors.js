export class UnexpectedPeerError extends Error {
    code;
    constructor(message = 'Unexpected Peer') {
        super(message);
        this.code = UnexpectedPeerError.code;
    }
    static code = 'ERR_UNEXPECTED_PEER';
}
export class InvalidCryptoExchangeError extends Error {
    code;
    constructor(message = 'Invalid crypto exchange') {
        super(message);
        this.code = InvalidCryptoExchangeError.code;
    }
    static code = 'ERR_INVALID_CRYPTO_EXCHANGE';
}
//# sourceMappingURL=errors.js.map