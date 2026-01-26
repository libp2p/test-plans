/**
 * Implementation version definitions for JS-libp2p Echo Interoperability Tests
 * This file defines the py-libp2p implementation capabilities and metadata
 */

export interface TransportType {
  readonly name: 'tcp' | 'quic-v1' | 'ws' | 'wss' | 'webtransport' | 'webrtc-direct' | 'webrtc';
}

export interface SecurityType {
  readonly name: 'noise' | 'tls';
}

export interface MuxerType {
  readonly name: 'yamux' | 'mplex';
}

export interface ConnectionRole {
  readonly role: 'dialer' | 'listener';
}

export interface ImplementationVersion {
  readonly id: string;
  readonly containerImageID: string;
  readonly transports: readonly TransportType['name'][];
  readonly secureChannels: readonly SecurityType['name'][];
  readonly muxers: readonly MuxerType['name'][];
  readonly role?: ConnectionRole['role'];
  readonly version: string;
  readonly source: {
    readonly type: 'github' | 'local';
    readonly repo?: string;
    readonly commit?: string;
    readonly dockerfile?: string;
    readonly path?: string;
  };
}

export interface TestConfiguration {
  readonly implementation: string;
  readonly version: string;
  readonly transport: TransportType['name'];
  readonly security: SecurityType['name'];
  readonly muxer: MuxerType['name'];
  readonly role: ConnectionRole['role'];
}

/**
 * py-libp2p implementation definition for Echo protocol interoperability tests
 * This implementation acts as the client/dialer in Echo tests
 */
export const pyLibp2pImplementation: ImplementationVersion = {
  id: 'py-libp2p-v0.5.0',
  containerImageID: 'py-libp2p-v0.5.0:latest',
  version: 'v0.5.0',
  transports: ['tcp'],
  secureChannels: ['noise'],
  muxers: ['yamux', 'mplex'],
  role: 'dialer',
  source: {
    type: 'github',
    repo: 'libp2p/py-libp2p',
    commit: 'cd3ae48b35ef140622b275ea8ac2ad00a64db68c',
    dockerfile: 'interop/echo/Dockerfile'
  }
} as const;

/**
 * js-libp2p Echo server implementation definition
 * This implementation acts as the server/listener in Echo tests
 */
export const jsLibp2pEchoServerImplementation: ImplementationVersion = {
  id: 'js-libp2p-echo-server',
  containerImageID: 'js-libp2p-echo-server:latest',
  version: 'latest',
  transports: ['tcp'],
  secureChannels: ['noise'],
  muxers: ['yamux', 'mplex'],
  role: 'listener',
  source: {
    type: 'local',
    path: 'images/js-echo-server',
    dockerfile: 'Dockerfile'
  }
} as const;

/**
 * All implementations available for Echo interoperability tests
 */
export const implementations: readonly ImplementationVersion[] = [
  pyLibp2pImplementation,
  jsLibp2pEchoServerImplementation
] as const;

/**
 * Generate test configurations for all valid implementation combinations
 */
export function generateTestConfigurations(): TestConfiguration[] {
  const configurations: TestConfiguration[] = [];
  
  const server = jsLibp2pEchoServerImplementation;
  const client = pyLibp2pImplementation;
  
  // Find common protocols between server and client
  const commonTransports = server.transports.filter(t => client.transports.includes(t));
  const commonSecure = server.secureChannels.filter(s => client.secureChannels.includes(s));
  const commonMuxers = server.muxers.filter(m => client.muxers.includes(m));
  
  // Generate all valid combinations
  for (const transport of commonTransports) {
    for (const security of commonSecure) {
      for (const muxer of commonMuxers) {
        // Server configuration
        configurations.push({
          implementation: server.id,
          version: server.version,
          transport,
          security,
          muxer,
          role: 'listener'
        });
        
        // Client configuration
        configurations.push({
          implementation: client.id,
          version: client.version,
          transport,
          security,
          muxer,
          role: 'dialer'
        });
      }
    }
  }
  
  return configurations;
}

/**
 * Get implementation by ID
 */
export function getImplementation(id: string): ImplementationVersion | undefined {
  return implementations.find(impl => impl.id === id);
}

/**
 * Validate test configuration compatibility
 */
export function validateTestConfiguration(config: TestConfiguration): boolean {
  const impl = getImplementation(config.implementation);
  if (!impl) {
    return false;
  }
  
  return (
    impl.transports.includes(config.transport) &&
    impl.secureChannels.includes(config.security) &&
    impl.muxers.includes(config.muxer) &&
    (impl.role === undefined || impl.role === config.role)
  );
}