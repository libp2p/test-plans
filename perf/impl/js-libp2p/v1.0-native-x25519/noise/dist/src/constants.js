export const NOISE_MSG_MAX_LENGTH_BYTES = 65535;
export const NOISE_MSG_MAX_LENGTH_BYTES_WITHOUT_TAG = NOISE_MSG_MAX_LENGTH_BYTES - 16;
export const DUMP_SESSION_KEYS = Boolean(globalThis.process?.env?.DUMP_SESSION_KEYS);
//# sourceMappingURL=constants.js.map