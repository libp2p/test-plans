import { pipe } from 'it-pipe';
export const ECHO_PROTOCOL = '/echo/1.0.0';
class EchoService {
    protocol;
    registrar;
    constructor(components, init = {}) {
        this.protocol = init.protocol ?? ECHO_PROTOCOL;
        this.registrar = components.registrar;
    }
    async start() {
        await this.registrar.handle(this.protocol, ({ stream }) => {
            void pipe(stream, stream)
                // sometimes connections are closed before multistream-select finishes
                // which causes an error
                .catch();
        });
    }
    async stop() {
        await this.registrar.unhandle(this.protocol);
    }
}
export function echo(init = {}) {
    return (components) => {
        return new EchoService(components, init);
    };
}
//# sourceMappingURL=echo-service.js.map