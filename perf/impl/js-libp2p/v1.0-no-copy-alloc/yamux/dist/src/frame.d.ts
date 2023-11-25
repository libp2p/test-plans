export declare enum FrameType {
    /** Used to transmit data. May transmit zero length payloads depending on the flags. */
    Data = 0,
    /** Used to updated the senders receive window size. This is used to implement per-session flow control. */
    WindowUpdate = 1,
    /** Used to measure RTT. It can also be used to heart-beat and do keep-alives over TCP. */
    Ping = 2,
    /** Used to close a session. */
    GoAway = 3
}
export declare enum Flag {
    /** Signals the start of a new stream. May be sent with a data or window update message. Also sent with a ping to indicate outbound. */
    SYN = 1,
    /** Acknowledges the start of a new stream. May be sent with a data or window update message. Also sent with a ping to indicate response. */
    ACK = 2,
    /** Performs a half-close of a stream. May be sent with a data message or window update. */
    FIN = 4,
    /** Reset a stream immediately. May be sent with a data or window update message. */
    RST = 8
}
export declare const YAMUX_VERSION = 0;
export declare enum GoAwayCode {
    NormalTermination = 0,
    ProtocolError = 1,
    InternalError = 2
}
export declare const HEADER_LENGTH = 12;
export interface FrameHeader {
    /**
     * The version field is used for future backward compatibility.
     * At the current time, the field is always set to 0, to indicate the initial version.
     */
    version?: number;
    /** The type field is used to switch the frame message type. */
    type: FrameType;
    /** The flags field is used to provide additional information related to the message type. */
    flag: number;
    /**
     * The StreamID field is used to identify the logical stream the frame is addressing.
     * The client side should use odd ID's, and the server even.
     * This prevents any collisions. Additionally, the 0 ID is reserved to represent the session.
     */
    streamID: number;
    /**
     * The meaning of the length field depends on the message type:
     * * Data - provides the length of bytes following the header
     * * Window update - provides a delta update to the window size
     * * Ping - Contains an opaque value, echoed back
     * * Go Away - Contains an error code
     */
    length: number;
}
export declare function stringifyHeader(header: FrameHeader): string;
//# sourceMappingURL=frame.d.ts.map