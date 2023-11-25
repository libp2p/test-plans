export var FrameType;
(function (FrameType) {
    /** Used to transmit data. May transmit zero length payloads depending on the flags. */
    FrameType[FrameType["Data"] = 0] = "Data";
    /** Used to updated the senders receive window size. This is used to implement per-session flow control. */
    FrameType[FrameType["WindowUpdate"] = 1] = "WindowUpdate";
    /** Used to measure RTT. It can also be used to heart-beat and do keep-alives over TCP. */
    FrameType[FrameType["Ping"] = 2] = "Ping";
    /** Used to close a session. */
    FrameType[FrameType["GoAway"] = 3] = "GoAway";
})(FrameType || (FrameType = {}));
export var Flag;
(function (Flag) {
    /** Signals the start of a new stream. May be sent with a data or window update message. Also sent with a ping to indicate outbound. */
    Flag[Flag["SYN"] = 1] = "SYN";
    /** Acknowledges the start of a new stream. May be sent with a data or window update message. Also sent with a ping to indicate response. */
    Flag[Flag["ACK"] = 2] = "ACK";
    /** Performs a half-close of a stream. May be sent with a data message or window update. */
    Flag[Flag["FIN"] = 4] = "FIN";
    /** Reset a stream immediately. May be sent with a data or window update message. */
    Flag[Flag["RST"] = 8] = "RST";
})(Flag || (Flag = {}));
const flagCodes = Object.values(Flag).filter((x) => typeof x !== 'string');
export const YAMUX_VERSION = 0;
export var GoAwayCode;
(function (GoAwayCode) {
    GoAwayCode[GoAwayCode["NormalTermination"] = 0] = "NormalTermination";
    GoAwayCode[GoAwayCode["ProtocolError"] = 1] = "ProtocolError";
    GoAwayCode[GoAwayCode["InternalError"] = 2] = "InternalError";
})(GoAwayCode || (GoAwayCode = {}));
export const HEADER_LENGTH = 12;
export function stringifyHeader(header) {
    const flags = flagCodes.filter(f => (header.flag & f) === f).map(f => Flag[f]).join('|');
    return `streamID=${header.streamID} type=${FrameType[header.type]} flag=${flags} length=${header.length}`;
}
//# sourceMappingURL=frame.js.map