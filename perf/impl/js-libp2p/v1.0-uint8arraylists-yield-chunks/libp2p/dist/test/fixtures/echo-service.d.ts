import type { Registrar } from '@libp2p/interface-internal/registrar';
export declare const ECHO_PROTOCOL = "/echo/1.0.0";
export interface EchoInit {
    protocol?: string;
}
export interface EchoComponents {
    registrar: Registrar;
}
export declare function echo(init?: EchoInit): (components: EchoComponents) => unknown;
//# sourceMappingURL=echo-service.d.ts.map