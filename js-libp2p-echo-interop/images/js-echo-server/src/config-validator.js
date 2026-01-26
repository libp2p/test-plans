/**
 * Configuration validation for JS-libp2p Echo Server
 * Provides comprehensive validation of environment variables and configuration
 * with clear error messages and debugging information.
 */

/**
 * Supported protocol options
 */
const SUPPORTED_PROTOCOLS = {
  transports: ['tcp', 'quic', 'websocket'],
  security: ['noise', 'tls'],
  muxers: ['yamux', 'mplex']
}

/**
 * Configuration validation rules
 */
const VALIDATION_RULES = {
  timeouts: {
    min: 1,
    max: 300,
    recommended_max: 60
  },
  ports: {
    min: 0,  // 0 means random port
    max: 65535,
    reserved_max: 1024
  },
  redis: {
    timeout_min: 1,
    timeout_max: 600,
    key_max_length: 512
  }
}

/**
 * Known problematic protocol combinations
 */
const PROBLEMATIC_COMBINATIONS = [
  // Add any known problematic combinations here
  // Example: { transport: 'websocket', security: 'noise', muxer: 'mplex', reason: 'Known compatibility issue' }
]

/**
 * Validate environment configuration
 * @param {Object} config - Configuration object
 * @returns {Object} Validation result with errors and warnings
 */
export function validateConfiguration(config) {
  const errors = []
  const warnings = []
  const info = []

  // Protocol stack validation
  validateProtocolStack(config, errors, warnings)
  
  // Network configuration validation
  validateNetworkConfig(config, errors, warnings)
  
  // Redis configuration validation
  validateRedisConfig(config, errors, warnings)
  
  // Performance and reliability checks
  checkPerformanceWarnings(config, warnings, info)
  
  // Environment-specific validations
  validateEnvironmentConfig(config, errors, warnings, info)

  return {
    isValid: errors.length === 0,
    errors,
    warnings,
    info,
    debugInfo: getDebugInfo(config)
  }
}

/**
 * Validate protocol stack configuration
 */
function validateProtocolStack(config, errors, warnings) {
  // Transport validation
  if (!SUPPORTED_PROTOCOLS.transports.includes(config.transport)) {
    errors.push(
      `Unsupported transport: ${config.transport}. ` +
      `Supported: ${SUPPORTED_PROTOCOLS.transports.join(', ')}`
    )
  }

  // Security protocol validation
  if (!SUPPORTED_PROTOCOLS.security.includes(config.security)) {
    errors.push(
      `Unsupported security protocol: ${config.security}. ` +
      `Supported: ${SUPPORTED_PROTOCOLS.security.join(', ')}`
    )
  }

  // Muxer validation
  if (!SUPPORTED_PROTOCOLS.muxers.includes(config.muxer)) {
    errors.push(
      `Unsupported muxer: ${config.muxer}. ` +
      `Supported: ${SUPPORTED_PROTOCOLS.muxers.join(', ')}`
    )
  }

  // Protocol compatibility checks
  if (config.transport === 'quic' && config.security === 'tls') {
    warnings.push('QUIC already includes TLS 1.3, additional TLS layer is redundant')
  }

  if (config.transport === 'websocket' && config.isDialer === false) {
    errors.push('WebSocket transport only supports dialer role in current implementation')
  }

  // Check for known problematic combinations
  for (const combo of PROBLEMATIC_COMBINATIONS) {
    if (config.transport === combo.transport &&
        config.security === combo.security &&
        config.muxer === combo.muxer) {
      errors.push(`Known problematic combination: ${combo.reason}`)
    }
  }

  // Deprecated protocol warnings
  if (config.muxer === 'mplex') {
    warnings.push('Mplex is deprecated, consider using Yamux for better performance and maintenance')
  }
}

/**
 * Validate network configuration
 */
function validateNetworkConfig(config, errors, warnings) {
  // Port validation
  if (typeof config.port !== 'number' || isNaN(config.port)) {
    errors.push(`Port must be a number, got: ${config.port}`)
  } else {
    if (config.port < VALIDATION_RULES.ports.min || config.port > VALIDATION_RULES.ports.max) {
      errors.push(
        `Port out of valid range: ${config.port}. ` +
        `Must be ${VALIDATION_RULES.ports.min}-${VALIDATION_RULES.ports.max}`
      )
    }

    if (config.port > 0 && config.port <= VALIDATION_RULES.ports.reserved_max) {
      warnings.push(
        `Port ${config.port} is in reserved range (1-${VALIDATION_RULES.ports.reserved_max}). ` +
        `May require elevated privileges`
      )
    }
  }

  // Host validation
  if (!config.host || typeof config.host !== 'string') {
    errors.push('Host must be a non-empty string')
  } else {
    // Basic IP address format validation
    const ipv4Regex = /^(\d{1,3}\.){3}\d{1,3}$/
    const ipv6Regex = /^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$/
    
    if (config.host !== '0.0.0.0' && 
        config.host !== '127.0.0.1' && 
        config.host !== 'localhost' &&
        !ipv4Regex.test(config.host) && 
        !ipv6Regex.test(config.host)) {
      warnings.push(`Host format may be invalid: ${config.host}`)
    }

    if (config.host === '127.0.0.1') {
      warnings.push('Binding to localhost (127.0.0.1) - server will only be accessible locally')
    }
  }
}

/**
 * Validate Redis configuration
 */
function validateRedisConfig(config, errors, warnings) {
  // Redis address validation
  if (!config.redisAddr || typeof config.redisAddr !== 'string') {
    errors.push('Redis address must be a non-empty string')
    return
  }

  // Parse Redis URL or host:port
  let redisHost, redisPort
  
  if (config.redisAddr.startsWith('redis://')) {
    try {
      const url = new URL(config.redisAddr)
      redisHost = url.hostname
      redisPort = parseInt(url.port) || 6379
    } catch (error) {
      errors.push(`Invalid Redis URL format: ${config.redisAddr}`)
      return
    }
  } else {
    // Assume host:port format
    const parts = config.redisAddr.split(':')
    if (parts.length !== 2) {
      errors.push(
        `Redis address should be in format 'host:port' or 'redis://host:port', ` +
        `got: ${config.redisAddr}`
      )
      return
    }
    
    redisHost = parts[0]
    redisPort = parseInt(parts[1])
    
    if (isNaN(redisPort)) {
      errors.push(`Invalid Redis port: ${parts[1]}`)
      return
    }
  }

  // Validate Redis host
  if (!redisHost) {
    errors.push('Redis host cannot be empty')
  }

  // Validate Redis port
  if (redisPort <= 0 || redisPort > 65535) {
    errors.push(`Redis port out of valid range: ${redisPort}. Must be 1-65535`)
  }

  // Redis connectivity warnings
  if (redisHost === 'localhost' || redisHost === '127.0.0.1') {
    warnings.push('Redis configured for localhost - ensure Redis is running locally')
  }
}

/**
 * Check for performance and reliability warnings
 */
function checkPerformanceWarnings(config, warnings, info) {
  // Role-specific performance notes
  if (config.isDialer) {
    info.push('Running in dialer mode - will initiate connections')
  } else {
    info.push('Running in listener mode - will accept connections')
  }

  // Transport-specific performance notes
  if (config.transport === 'websocket') {
    info.push('WebSocket transport may have higher latency than TCP')
  }

  if (config.transport === 'quic') {
    info.push('QUIC transport provides built-in encryption and multiplexing')
  }

  // Muxer performance notes
  if (config.muxer === 'yamux') {
    info.push('Yamux provides good performance and is actively maintained')
  }

  if (config.muxer === 'mplex') {
    warnings.push('Mplex may have different performance characteristics than Yamux')
  }

  // Security protocol notes
  if (config.security === 'noise') {
    info.push('Noise protocol provides modern cryptographic security')
  }

  if (config.security === 'tls') {
    info.push('TLS provides standard transport security')
  }
}

/**
 * Validate environment-specific configuration
 */
function validateEnvironmentConfig(config, errors, warnings, info) {
  // Check for required environment variables
  const requiredEnvVars = ['TRANSPORT', 'SECURITY', 'MUXER']
  const missingVars = []

  for (const varName of requiredEnvVars) {
    if (!process.env[varName]) {
      missingVars.push(varName)
    }
  }

  if (missingVars.length > 0) {
    warnings.push(
      `Missing environment variables (using defaults): ${missingVars.join(', ')}`
    )
  }

  // Development vs production checks
  const nodeEnv = process.env.NODE_ENV || 'development'
  
  if (nodeEnv === 'development') {
    info.push('Running in development mode')
    
    if (config.port === 0) {
      info.push('Using random port assignment (port=0) - suitable for development')
    }
  } else if (nodeEnv === 'production') {
    info.push('Running in production mode')
    
    if (config.port === 0) {
      warnings.push('Using random port in production - ensure proper service discovery')
    }
    
    if (config.host === '0.0.0.0') {
      warnings.push('Binding to all interfaces (0.0.0.0) in production - ensure proper firewall configuration')
    }
  }

  // Debug mode checks
  if (process.env.DEBUG === 'true') {
    warnings.push('Debug mode enabled - may impact performance and expose sensitive information')
  }
}

/**
 * Get comprehensive debug information
 */
function getDebugInfo(config) {
  return {
    protocol_stack: {
      transport: config.transport,
      security: config.security,
      muxer: config.muxer,
      combination_supported: !PROBLEMATIC_COMBINATIONS.some(combo =>
        config.transport === combo.transport &&
        config.security === combo.security &&
        config.muxer === combo.muxer
      )
    },
    network: {
      host: config.host,
      port: config.port,
      role: config.isDialer ? 'dialer' : 'listener',
      bind_address: `${config.host}:${config.port}`
    },
    redis: {
      address: config.redisAddr,
      parsed_url: (() => {
        try {
          if (config.redisAddr.startsWith('redis://')) {
            const url = new URL(config.redisAddr)
            return {
              host: url.hostname,
              port: parseInt(url.port) || 6379,
              protocol: url.protocol
            }
          } else {
            const [host, port] = config.redisAddr.split(':')
            return {
              host,
              port: parseInt(port),
              protocol: 'redis:'
            }
          }
        } catch (error) {
          return { error: error.message }
        }
      })()
    },
    environment: {
      node_env: process.env.NODE_ENV || 'development',
      debug_enabled: process.env.DEBUG === 'true',
      platform: process.platform,
      node_version: process.version
    },
    validation_rules: VALIDATION_RULES,
    supported_protocols: SUPPORTED_PROTOCOLS
  }
}

/**
 * Validate configuration and exit with error if invalid
 * @param {Object} config - Configuration object
 */
export function validateConfigurationOrExit(config) {
  console.error('[INFO] Starting configuration validation...')
  
  const validation = validateConfiguration(config)
  
  // Log validation results
  if (validation.info.length > 0) {
    console.error('[INFO] Configuration information:')
    validation.info.forEach(info => console.error(`[INFO]   ${info}`))
  }
  
  if (validation.warnings.length > 0) {
    console.error('[WARN] Configuration warnings:')
    validation.warnings.forEach(warning => console.error(`[WARN]   ${warning}`))
  }
  
  if (validation.errors.length > 0) {
    console.error('[ERROR] Configuration validation failed:')
    validation.errors.forEach(error => console.error(`[ERROR]   ${error}`))
    
    console.error('[DEBUG] Configuration debug info:')
    console.error(JSON.stringify(validation.debugInfo, null, 2))
    
    console.error('[FATAL] Server cannot start with invalid configuration')
    process.exit(1)
  }
  
  console.error('[INFO] Configuration validation completed successfully')
  
  // Log debug info if debug mode is enabled
  if (process.env.DEBUG === 'true') {
    console.error('[DEBUG] Configuration debug info:')
    console.error(JSON.stringify(validation.debugInfo, null, 2))
  }
  
  return validation
}

/**
 * Get configuration validation summary for health checks
 * @param {Object} config - Configuration object
 * @returns {Object} Validation summary
 */
export function getValidationSummary(config) {
  const validation = validateConfiguration(config)
  
  return {
    valid: validation.isValid,
    error_count: validation.errors.length,
    warning_count: validation.warnings.length,
    info_count: validation.info.length,
    protocol_stack: `${config.transport}/${config.security}/${config.muxer}`,
    role: config.isDialer ? 'dialer' : 'listener',
    network: `${config.host}:${config.port}`,
    redis: config.redisAddr
  }
}