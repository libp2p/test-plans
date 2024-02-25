/* eslint-disable import/export */
/* eslint-disable complexity */
/* eslint-disable @typescript-eslint/no-namespace */
/* eslint-disable @typescript-eslint/no-unnecessary-boolean-literal-compare */
/* eslint-disable @typescript-eslint/no-empty-interface */
import { decodeMessage, encodeMessage, enumeration, message } from 'protons-runtime';
export var KeyType;
(function (KeyType) {
    KeyType["RSA"] = "RSA";
    KeyType["Ed25519"] = "Ed25519";
    KeyType["Secp256k1"] = "Secp256k1";
    KeyType["ECDSA"] = "ECDSA";
})(KeyType || (KeyType = {}));
var __KeyTypeValues;
(function (__KeyTypeValues) {
    __KeyTypeValues[__KeyTypeValues["RSA"] = 0] = "RSA";
    __KeyTypeValues[__KeyTypeValues["Ed25519"] = 1] = "Ed25519";
    __KeyTypeValues[__KeyTypeValues["Secp256k1"] = 2] = "Secp256k1";
    __KeyTypeValues[__KeyTypeValues["ECDSA"] = 3] = "ECDSA";
})(__KeyTypeValues || (__KeyTypeValues = {}));
(function (KeyType) {
    KeyType.codec = () => {
        return enumeration(__KeyTypeValues);
    };
})(KeyType || (KeyType = {}));
export var PublicKey;
(function (PublicKey) {
    let _codec;
    PublicKey.codec = () => {
        if (_codec == null) {
            _codec = message((obj, w, opts = {}) => {
                if (opts.lengthDelimited !== false) {
                    w.fork();
                }
                if (obj.type != null) {
                    w.uint32(8);
                    KeyType.codec().encode(obj.type, w);
                }
                if (obj.data != null) {
                    w.uint32(18);
                    w.bytes(obj.data);
                }
                if (opts.lengthDelimited !== false) {
                    w.ldelim();
                }
            }, (reader, length) => {
                const obj = {};
                const end = length == null ? reader.len : reader.pos + length;
                while (reader.pos < end) {
                    const tag = reader.uint32();
                    switch (tag >>> 3) {
                        case 1: {
                            obj.type = KeyType.codec().decode(reader);
                            break;
                        }
                        case 2: {
                            obj.data = reader.bytes();
                            break;
                        }
                        default: {
                            reader.skipType(tag & 7);
                            break;
                        }
                    }
                }
                return obj;
            });
        }
        return _codec;
    };
    PublicKey.encode = (obj) => {
        return encodeMessage(obj, PublicKey.codec());
    };
    PublicKey.decode = (buf) => {
        return decodeMessage(buf, PublicKey.codec());
    };
})(PublicKey || (PublicKey = {}));
//# sourceMappingURL=index.js.map