import { Uint8ArrayList } from 'uint8arraylist';
import { fromString as uint8ArrayFromString } from 'uint8arrays';
import { alloc as uint8ArrayAlloc } from 'uint8arrays/alloc';
import { equals as uint8ArrayEquals } from 'uint8arrays/equals';
import { logger } from '../logger.js';
import { Nonce } from '../nonce.js';
export class AbstractHandshake {
    crypto;
    constructor(crypto) {
        this.crypto = crypto;
    }
    encryptWithAd(cs, ad, plaintext) {
        const e = this.encrypt(cs.k, cs.n, ad, plaintext);
        cs.n.increment();
        return e;
    }
    decryptWithAd(cs, ad, ciphertext, dst) {
        const { plaintext, valid } = this.decrypt(cs.k, cs.n, ad, ciphertext, dst);
        if (valid)
            cs.n.increment();
        return { plaintext, valid };
    }
    // Cipher state related
    hasKey(cs) {
        return !this.isEmptyKey(cs.k);
    }
    createEmptyKey() {
        return uint8ArrayAlloc(32);
    }
    isEmptyKey(k) {
        const emptyKey = this.createEmptyKey();
        return uint8ArrayEquals(emptyKey, k);
    }
    encrypt(k, n, ad, plaintext) {
        n.assertValue();
        return this.crypto.chaCha20Poly1305Encrypt(plaintext, n.getBytes(), ad, k);
    }
    encryptAndHash(ss, plaintext) {
        let ciphertext;
        if (this.hasKey(ss.cs)) {
            ciphertext = this.encryptWithAd(ss.cs, ss.h, plaintext);
        }
        else {
            ciphertext = plaintext;
        }
        this.mixHash(ss, ciphertext);
        return ciphertext;
    }
    decrypt(k, n, ad, ciphertext, dst) {
        n.assertValue();
        const encryptedMessage = this.crypto.chaCha20Poly1305Decrypt(ciphertext, n.getBytes(), ad, k, dst);
        if (encryptedMessage) {
            return {
                plaintext: encryptedMessage,
                valid: true
            };
        }
        else {
            return {
                plaintext: uint8ArrayAlloc(0),
                valid: false
            };
        }
    }
    decryptAndHash(ss, ciphertext) {
        let plaintext;
        let valid = true;
        if (this.hasKey(ss.cs)) {
            ({ plaintext, valid } = this.decryptWithAd(ss.cs, ss.h, ciphertext));
        }
        else {
            plaintext = ciphertext;
        }
        this.mixHash(ss, ciphertext);
        return { plaintext, valid };
    }
    dh(privateKey, publicKey) {
        try {
            const derivedU8 = this.crypto.generateX25519SharedKey(privateKey, publicKey);
            if (derivedU8.length === 32) {
                return derivedU8;
            }
            return derivedU8.subarray(0, 32);
        }
        catch (e) {
            const err = e;
            logger.error(err);
            return uint8ArrayAlloc(32);
        }
    }
    mixHash(ss, data) {
        ss.h = this.getHash(ss.h, data);
    }
    getHash(a, b) {
        const u = this.crypto.hashSHA256(new Uint8ArrayList(a, b));
        return u;
    }
    mixKey(ss, ikm) {
        const [ck, tempK] = this.crypto.getHKDF(ss.ck, ikm);
        ss.cs = this.initializeKey(tempK);
        ss.ck = ck;
    }
    initializeKey(k) {
        return { k, n: new Nonce() };
    }
    // Symmetric state related
    initializeSymmetric(protocolName) {
        const protocolNameBytes = uint8ArrayFromString(protocolName, 'utf-8');
        const h = this.hashProtocolName(protocolNameBytes);
        const ck = h;
        const key = this.createEmptyKey();
        const cs = this.initializeKey(key);
        return { cs, ck, h };
    }
    hashProtocolName(protocolName) {
        if (protocolName.length <= 32) {
            const h = uint8ArrayAlloc(32);
            h.set(protocolName);
            return h;
        }
        else {
            return this.getHash(protocolName, uint8ArrayAlloc(0));
        }
    }
    split(ss) {
        const [tempk1, tempk2] = this.crypto.getHKDF(ss.ck, uint8ArrayAlloc(0));
        const cs1 = this.initializeKey(tempk1);
        const cs2 = this.initializeKey(tempk2);
        return { cs1, cs2 };
    }
    writeMessageRegular(cs, payload) {
        const ciphertext = this.encryptWithAd(cs, uint8ArrayAlloc(0), payload);
        const ne = this.createEmptyKey();
        const ns = uint8ArrayAlloc(0);
        return { ne, ns, ciphertext };
    }
    readMessageRegular(cs, message) {
        return this.decryptWithAd(cs, uint8ArrayAlloc(0), message.ciphertext);
    }
}
//# sourceMappingURL=abstract-handshake.js.map