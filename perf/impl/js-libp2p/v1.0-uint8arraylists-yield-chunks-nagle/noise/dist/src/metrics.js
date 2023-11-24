export function registerMetrics(metrics) {
    return {
        xxHandshakeSuccesses: metrics.registerCounter('libp2p_noise_xxhandshake_successes_total', {
            help: 'Total count of noise xxHandshakes successes_'
        }),
        xxHandshakeErrors: metrics.registerCounter('libp2p_noise_xxhandshake_error_total', {
            help: 'Total count of noise xxHandshakes errors'
        }),
        encryptedPackets: metrics.registerCounter('libp2p_noise_encrypted_packets_total', {
            help: 'Total count of noise encrypted packets successfully'
        }),
        decryptedPackets: metrics.registerCounter('libp2p_noise_decrypted_packets_total', {
            help: 'Total count of noise decrypted packets'
        }),
        decryptErrors: metrics.registerCounter('libp2p_noise_decrypt_errors_total', {
            help: 'Total count of noise decrypt errors'
        })
    };
}
//# sourceMappingURL=metrics.js.map