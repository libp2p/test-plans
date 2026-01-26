#!/usr/bin/env node

/**
 * Validation script to ensure test matrix generation matches versions.ts definitions
 * This script validates that the generated test matrix is consistent with the implementation
 * capabilities defined in versions.ts
 */

const fs = require('fs');
const path = require('path');

// Read versions.ts content
const versionsPath = path.join(__dirname, '..', 'versions.ts');
const matrixPath = path.join(__dirname, '..', 'test-matrix', 'test-matrix.json');

if (!fs.existsSync(versionsPath)) {
    console.error('Error: versions.ts not found at', versionsPath);
    process.exit(1);
}

if (!fs.existsSync(matrixPath)) {
    console.error('Error: test-matrix.json not found at', matrixPath);
    console.error('Run ./lib/test-matrix.sh generate first');
    process.exit(1);
}

const versionsContent = fs.readFileSync(versionsPath, 'utf8');
const matrixContent = JSON.parse(fs.readFileSync(matrixPath, 'utf8'));

console.log('Validating versions.ts integration with test matrix...');

// Extract implementation capabilities from versions.ts
function extractCapabilities() {
    const capabilities = {
        implementations: {},
        transports: new Set(),
        secureChannels: new Set(),
        muxers: new Set()
    };
    
    // Extract py-libp2p implementation
    const pyLibp2pMatch = versionsContent.match(/pyLibp2pImplementation[^}]+transports:\s*\[([^\]]+)\][^}]+secureChannels:\s*\[([^\]]+)\][^}]+muxers:\s*\[([^\]]+)\]/s);
    
    if (pyLibp2pMatch) {
        const transports = pyLibp2pMatch[1].match(/'([^']+)'/g) || [];
        const secureChannels = pyLibp2pMatch[2].match(/'([^']+)'/g) || [];
        const muxers = pyLibp2pMatch[3].match(/'([^']+)'/g) || [];
        
        capabilities.implementations['py-libp2p'] = {
            role: 'client',
            transports: transports.map(t => t.replace(/'/g, '')),
            secureChannels: secureChannels.map(s => s.replace(/'/g, '')),
            muxers: muxers.map(m => m.replace(/'/g, ''))
        };
        
        // Add to global sets
        transports.forEach(t => capabilities.transports.add(t.replace(/'/g, '')));
        secureChannels.forEach(s => capabilities.secureChannels.add(s.replace(/'/g, '')));
        muxers.forEach(m => capabilities.muxers.add(m.replace(/'/g, '')));
    }
    
    // Extract js-libp2p implementation
    const jsLibp2pMatch = versionsContent.match(/jsLibp2pEchoServerImplementation[^}]+transports:\s*\[([^\]]+)\][^}]+secureChannels:\s*\[([^\]]+)\][^}]+muxers:\s*\[([^\]]+)\]/s);
    
    if (jsLibp2pMatch) {
        const transports = jsLibp2pMatch[1].match(/'([^']+)'/g) || [];
        const secureChannels = jsLibp2pMatch[2].match(/'([^']+)'/g) || [];
        const muxers = jsLibp2pMatch[3].match(/'([^']+)'/g) || [];
        
        capabilities.implementations['js-libp2p'] = {
            role: 'server',
            transports: transports.map(t => t.replace(/'/g, '')),
            secureChannels: secureChannels.map(s => s.replace(/'/g, '')),
            muxers: muxers.map(m => m.replace(/'/g, ''))
        };
    }
    
    return {
        implementations: capabilities.implementations,
        transports: Array.from(capabilities.transports),
        secureChannels: Array.from(capabilities.secureChannels),
        muxers: Array.from(capabilities.muxers)
    };
}

// Validate test matrix against capabilities
function validateMatrix() {
    const capabilities = extractCapabilities();
    const errors = [];
    const warnings = [];
    
    console.log('Extracted capabilities from versions.ts:');
    console.log('- Implementations:', Object.keys(capabilities.implementations));
    console.log('- Transports:', capabilities.transports);
    console.log('- Security protocols:', capabilities.secureChannels);
    console.log('- Muxers:', capabilities.muxers);
    console.log();
    
    // Validate implementations
    const matrixImplementations = Object.keys(matrixContent.implementations);
    const versionsImplementations = Object.keys(capabilities.implementations);
    
    for (const impl of versionsImplementations) {
        if (!matrixImplementations.includes(impl)) {
            errors.push(`Implementation ${impl} from versions.ts not found in test matrix`);
        }
    }
    
    for (const impl of matrixImplementations) {
        if (!versionsImplementations.includes(impl)) {
            warnings.push(`Implementation ${impl} in test matrix not defined in versions.ts`);
        }
    }
    
    // Validate test combinations
    const expectedCombinations = [];
    
    // Generate expected combinations based on common protocols
    const commonTransports = capabilities.transports;
    const commonSecurity = capabilities.secureChannels;
    const commonMuxers = capabilities.muxers;
    
    const scenarios = ['basic', 'binary', 'large', 'concurrent'];
    
    for (const transport of commonTransports) {
        for (const security of commonSecurity) {
            for (const muxer of commonMuxers) {
                for (const scenario of scenarios) {
                    expectedCombinations.push(`${transport}-${security}-${muxer}-${scenario}`);
                }
            }
        }
    }
    
    console.log(`Expected ${expectedCombinations.length} test combinations`);
    console.log(`Found ${matrixContent.test_combinations.length} test combinations in matrix`);
    
    // Check if all expected combinations are present
    const actualCombinations = matrixContent.test_combinations.map(c => c.id);
    
    for (const expected of expectedCombinations) {
        if (!actualCombinations.includes(expected)) {
            errors.push(`Expected test combination ${expected} not found in matrix`);
        }
    }
    
    for (const actual of actualCombinations) {
        if (!expectedCombinations.includes(actual)) {
            warnings.push(`Unexpected test combination ${actual} found in matrix`);
        }
    }
    
    // Validate individual test combinations
    for (const combination of matrixContent.test_combinations) {
        const { transport, security, muxer } = combination;
        
        if (!capabilities.transports.includes(transport)) {
            errors.push(`Test combination ${combination.id} uses unsupported transport: ${transport}`);
        }
        
        if (!capabilities.secureChannels.includes(security)) {
            errors.push(`Test combination ${combination.id} uses unsupported security protocol: ${security}`);
        }
        
        if (!capabilities.muxers.includes(muxer)) {
            errors.push(`Test combination ${combination.id} uses unsupported muxer: ${muxer}`);
        }
        
        // Validate environment variables
        const env = combination.environment;
        if (env.TRANSPORT !== transport) {
            errors.push(`Test combination ${combination.id} has mismatched TRANSPORT env var`);
        }
        
        if (env.SECURITY !== security) {
            errors.push(`Test combination ${combination.id} has mismatched SECURITY env var`);
        }
        
        if (env.MUXER !== muxer) {
            errors.push(`Test combination ${combination.id} has mismatched MUXER env var`);
        }
    }
    
    return { errors, warnings };
}

// Run validation
const { errors, warnings } = validateMatrix();

// Report results
console.log('Validation Results:');
console.log('==================');

if (errors.length === 0) {
    console.log('✅ All validations passed!');
} else {
    console.log(`❌ Found ${errors.length} error(s):`);
    errors.forEach(error => console.log(`  - ${error}`));
}

if (warnings.length > 0) {
    console.log(`⚠️  Found ${warnings.length} warning(s):`);
    warnings.forEach(warning => console.log(`  - ${warning}`));
}

console.log();
console.log('Matrix Statistics:');
console.log(`- Total implementations: ${Object.keys(matrixContent.implementations).length}`);
console.log(`- Total test combinations: ${matrixContent.test_combinations.length}`);
console.log(`- Generated at: ${matrixContent.metadata.generated_at}`);

// Exit with appropriate code
process.exit(errors.length > 0 ? 1 : 0);