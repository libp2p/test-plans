import { createServer, Socket } from 'net';
import os from 'os';
import { defaultLogger } from '@libp2p/logger';
import { expect } from 'aegir/chai';
import defer from 'p-defer';
import { toMultiaddrConnection } from '../src/socket-to-conn.js';
async function setup(opts) {
    const serverListening = defer();
    const server = createServer(opts?.server);
    server.listen(0, () => {
        serverListening.resolve();
    });
    await serverListening.promise;
    const serverSocket = defer();
    const clientSocket = defer();
    server.once('connection', (socket) => {
        serverSocket.resolve(socket);
    });
    const address = server.address();
    if (address == null || typeof address === 'string') {
        throw new Error('Wrong socket type');
    }
    const client = new Socket(opts?.client);
    client.once('connect', () => {
        clientSocket.resolve(client);
    });
    client.connect(address.port, address.address);
    return {
        server,
        serverSocket: await serverSocket.promise,
        clientSocket: await clientSocket.promise
    };
}
describe('socket-to-conn', () => {
    let server;
    let clientSocket;
    let serverSocket;
    afterEach(async () => {
        if (serverSocket != null) {
            serverSocket.destroy();
        }
        if (clientSocket != null) {
            clientSocket.destroy();
        }
        if (server != null) {
            server.close();
        }
    });
    it('should destroy a socket that is closed by the client', async () => {
        ({ server, clientSocket, serverSocket } = await setup());
        // promise that is resolved when client socket is closed
        const clientClosed = defer();
        // promise that is resolved when client socket errors
        const clientErrored = defer();
        // promise that is resolved when our outgoing socket is closed
        const serverClosed = defer();
        // promise that is resolved when our outgoing socket errors
        const serverErrored = defer();
        const inboundMaConn = toMultiaddrConnection(serverSocket, {
            socketInactivityTimeout: 100,
            logger: defaultLogger()
        });
        expect(inboundMaConn.timeline.open).to.be.ok();
        expect(inboundMaConn.timeline.close).to.not.be.ok();
        clientSocket.once('close', () => {
            clientClosed.resolve(true);
        });
        clientSocket.once('error', err => {
            clientErrored.resolve(err);
        });
        serverSocket.once('close', () => {
            serverClosed.resolve(true);
        });
        serverSocket.once('error', err => {
            serverErrored.resolve(err);
        });
        // send some data between the client and server
        clientSocket.write('hello');
        serverSocket.write('goodbye');
        // close the client for writing
        clientSocket.end();
        // server socket was closed for reading and writing
        await expect(serverClosed.promise).to.eventually.be.true();
        // the connection closing was recorded
        expect(inboundMaConn.timeline.close).to.be.a('number');
        // server socket is destroyed
        expect(serverSocket.destroyed).to.be.true();
    });
    it('should destroy a socket that is forcibly closed by the client', async () => {
        ({ server, clientSocket, serverSocket } = await setup());
        // promise that is resolved when our outgoing socket is closed
        const serverClosed = defer();
        // promise that is resolved when our outgoing socket errors
        const serverErrored = defer();
        const inboundMaConn = toMultiaddrConnection(serverSocket, {
            socketInactivityTimeout: 100,
            logger: defaultLogger()
        });
        expect(inboundMaConn.timeline.open).to.be.ok();
        expect(inboundMaConn.timeline.close).to.not.be.ok();
        serverSocket.once('close', () => {
            serverClosed.resolve(true);
        });
        serverSocket.once('error', err => {
            serverErrored.resolve(err);
        });
        // send some data between the client and server
        clientSocket.write('hello');
        serverSocket.write('goodbye');
        // close the client for reading and writing immediately
        clientSocket.destroy();
        // client closed the connection - error code is platform specific
        if (os.platform() === 'linux') {
            await expect(serverErrored.promise).to.eventually.have.property('code', 'ERR_SOCKET_READ_TIMEOUT');
        }
        else {
            await expect(serverErrored.promise).to.eventually.have.property('code', 'ECONNRESET');
        }
        // server socket was closed for reading and writing
        await expect(serverClosed.promise).to.eventually.be.true();
        // the connection closing was recorded
        expect(inboundMaConn.timeline.close).to.be.a('number');
        // server socket is destroyed
        expect(serverSocket.destroyed).to.be.true();
    });
    it('should destroy a socket that is half-closed by the client', async () => {
        ({ server, clientSocket, serverSocket } = await setup({
            client: {
                allowHalfOpen: true
            }
        }));
        // promise that is resolved when our outgoing socket is closed
        const serverClosed = defer();
        // promise that is resolved when our outgoing socket errors
        const serverErrored = defer();
        const inboundMaConn = toMultiaddrConnection(serverSocket, {
            socketInactivityTimeout: 100,
            logger: defaultLogger()
        });
        expect(inboundMaConn.timeline.open).to.be.ok();
        expect(inboundMaConn.timeline.close).to.not.be.ok();
        serverSocket.once('close', () => {
            serverClosed.resolve(true);
        });
        serverSocket.once('error', err => {
            serverErrored.resolve(err);
        });
        // send some data between the client and server
        clientSocket.write('hello');
        serverSocket.write('goodbye');
        // close the client for writing
        clientSocket.end();
        // server socket was closed for reading and writing
        await expect(serverClosed.promise).to.eventually.be.true();
        // remote stopped sending us data
        await expect(serverErrored.promise).to.eventually.have.property('code', 'ERR_SOCKET_READ_TIMEOUT');
        // the connection closing was recorded
        expect(inboundMaConn.timeline.close).to.be.a('number');
        // server socket is destroyed
        expect(serverSocket.destroyed).to.be.true();
    });
    it('should destroy a socket after sinking', async () => {
        ({ server, clientSocket, serverSocket } = await setup());
        // promise that is resolved when our outgoing socket is closed
        const serverClosed = defer();
        // promise that is resolved when our outgoing socket errors
        const serverErrored = defer();
        const inboundMaConn = toMultiaddrConnection(serverSocket, {
            socketInactivityTimeout: 100,
            logger: defaultLogger()
        });
        expect(inboundMaConn.timeline.open).to.be.ok();
        expect(inboundMaConn.timeline.close).to.not.be.ok();
        serverSocket.once('close', () => {
            serverClosed.resolve(true);
        });
        serverSocket.once('error', err => {
            serverErrored.resolve(err);
        });
        // send some data between the client and server
        await inboundMaConn.sink(async function* () {
            yield Uint8Array.from([0, 1, 2, 3]);
        }());
        // server socket should no longer be writable
        expect(serverSocket.writable).to.be.false();
        // server socket was closed for reading and writing
        await expect(serverClosed.promise).to.eventually.be.true();
        // remote didn't send us any data
        await expect(serverErrored.promise).to.eventually.have.property('code', 'ERR_SOCKET_READ_TIMEOUT');
        // the connection closing was recorded
        expect(inboundMaConn.timeline.close).to.be.a('number');
        // server socket is destroyed
        expect(serverSocket.destroyed).to.be.true();
    });
    it('should destroy a socket when containing MultiaddrConnection is closed', async () => {
        ({ server, clientSocket, serverSocket } = await setup());
        // promise that is resolved when our outgoing socket is closed
        const serverClosed = defer();
        const inboundMaConn = toMultiaddrConnection(serverSocket, {
            socketInactivityTimeout: 100,
            socketCloseTimeout: 10,
            logger: defaultLogger()
        });
        expect(inboundMaConn.timeline.open).to.be.ok();
        expect(inboundMaConn.timeline.close).to.not.be.ok();
        clientSocket.once('error', () => { });
        serverSocket.once('close', () => {
            serverClosed.resolve(true);
        });
        // send some data between the client and server
        clientSocket.write('hello');
        serverSocket.write('goodbye');
        await inboundMaConn.close();
        // server socket was closed for reading and writing
        await expect(serverClosed.promise).to.eventually.be.true();
        // the connection closing was recorded
        expect(inboundMaConn.timeline.close).to.be.a('number');
        // server socket is destroyed
        expect(serverSocket.destroyed).to.be.true();
    });
    it('should destroy a socket by timeout when containing MultiaddrConnection is closed', async () => {
        ({ server, clientSocket, serverSocket } = await setup({
            server: {
                allowHalfOpen: true
            }
        }));
        // promise that is resolved when our outgoing socket is closed
        const serverClosed = defer();
        const inboundMaConn = toMultiaddrConnection(serverSocket, {
            socketInactivityTimeout: 100,
            socketCloseTimeout: 10,
            logger: defaultLogger()
        });
        expect(inboundMaConn.timeline.open).to.be.ok();
        expect(inboundMaConn.timeline.close).to.not.be.ok();
        clientSocket.once('error', () => { });
        serverSocket.once('close', () => {
            serverClosed.resolve(true);
        });
        // send some data between the client and server
        clientSocket.write('hello');
        serverSocket.write('goodbye');
        await inboundMaConn.close();
        // server socket was closed for reading and writing
        await expect(serverClosed.promise).to.eventually.be.true();
        // the connection closing was recorded
        expect(inboundMaConn.timeline.close).to.be.a('number');
        // server socket is destroyed
        expect(serverSocket.destroyed).to.be.true();
    });
    it('should destroy a socket by timeout when containing MultiaddrConnection is closed but remote keeps sending data', async () => {
        ({ server, clientSocket, serverSocket } = await setup({
            server: {
                allowHalfOpen: true
            }
        }));
        // promise that is resolved when our outgoing socket is closed
        const serverClosed = defer();
        const inboundMaConn = toMultiaddrConnection(serverSocket, {
            socketInactivityTimeout: 500,
            socketCloseTimeout: 100,
            logger: defaultLogger()
        });
        expect(inboundMaConn.timeline.open).to.be.ok();
        expect(inboundMaConn.timeline.close).to.not.be.ok();
        clientSocket.once('error', () => { });
        serverSocket.once('close', () => {
            serverClosed.resolve(true);
        });
        // send some data between the client and server
        clientSocket.write('hello');
        serverSocket.write('goodbye');
        setInterval(() => {
            clientSocket.write(`some data ${Date.now()}`);
        }, 10).unref();
        await inboundMaConn.close();
        // server socket was closed for reading and writing
        await expect(serverClosed.promise).to.eventually.be.true();
        // the connection closing was recorded
        expect(inboundMaConn.timeline.close).to.be.a('number');
        // server socket is destroyed
        expect(serverSocket.destroyed).to.be.true();
    });
    it('should destroy a socket by timeout when containing MultiaddrConnection is closed but closing remote times out', async () => {
        ({ server, clientSocket, serverSocket } = await setup());
        // promise that is resolved when our outgoing socket is closed
        const serverClosed = defer();
        // promise that is resolved when our outgoing socket errors
        const serverErrored = defer();
        const inboundMaConn = toMultiaddrConnection(serverSocket, {
            socketInactivityTimeout: 100,
            socketCloseTimeout: 100,
            logger: defaultLogger()
        });
        expect(inboundMaConn.timeline.open).to.be.ok();
        expect(inboundMaConn.timeline.close).to.not.be.ok();
        clientSocket.once('error', () => { });
        serverSocket.once('close', () => {
            serverClosed.resolve(true);
        });
        serverSocket.once('error', err => {
            serverErrored.resolve(err);
        });
        // send some data between the client and server
        clientSocket.write('hello');
        serverSocket.write('goodbye');
        // stop reading data
        clientSocket.pause();
        // have to write enough data quickly enough to overwhelm the client
        while (serverSocket.writableLength < 1024) {
            serverSocket.write('goodbyeeeeeeeeeeeeee');
        }
        await inboundMaConn.close();
        // server socket should no longer be writable
        expect(serverSocket.writable).to.be.false();
        // server socket was closed for reading and writing
        await expect(serverClosed.promise).to.eventually.be.true();
        // remote didn't read our data
        await expect(serverErrored.promise).to.eventually.have.property('code', 'ERR_SOCKET_READ_TIMEOUT');
        // the connection closing was recorded
        expect(inboundMaConn.timeline.close).to.be.a('number');
        // server socket is destroyed
        expect(serverSocket.destroyed).to.be.true();
    });
});
//# sourceMappingURL=socket-to-conn.spec.js.map