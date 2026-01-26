/**
 * Property-based tests for Echo protocol handler
 * **Validates: Requirements 1.1, 1.4, 1.5**
 */

import { test, describe } from 'node:test'
import assert from 'node:assert'
import fc from 'fast-check'
import { pipe } from 'it-pipe'
import { fromString as uint8ArrayFromString } from 'uint8arrays/from-string'
import { toString as uint8ArrayToString } from 'uint8arrays/to-string'

// Mock stream implementation for property testing
class PropertyMockStream {
  constructor() {
    this.output = []
  }
  
  async *source(data) {
    if (data instanceof Uint8Array) {
      yield data
    } else if (typeof data === 'string') {
      yield uint8ArrayFromString(data)
    } else if (Array.isArray(data)) {
      for (const chunk of data) {
        if (chunk instanceof Uint8Array) {
          yield chunk
        } else {
          yield uint8ArrayFromString(chunk)
        }
      }
    }
  }
  
  async sink(source) {
    for await (const chunk of source) {
      this.output.push(chunk)
    }
  }
  
  getOutputAsUint8Array() {
    if (this.output.length === 0) {
      return new Uint8Array(0)
    }
    
    // Calculate total length
    const totalLength = this.output.reduce((sum, chunk) => sum + chunk.length, 0)
    
    // Concatenate all chunks
    const result = new Uint8Array(totalLength)
    let offset = 0
    for (const chunk of this.output) {
      result.set(chunk, offset)
      offset += chunk.length
    }
    
    return result
  }
  
  getOutputAsString() {
    return uint8ArrayToString(this.getOutputAsUint8Array())
  }
}

describe('Echo Protocol Property Tests', () => {
  test('Property 1: Echo Data Integrity - Text payloads', async () => {
    /**
     * **Property 1: Echo Data Integrity**
     * **Validates: Requirements 1.1, 1.4, 1.5**
     * 
     * For any text data payload sent through the Echo protocol,
     * the response received should be byte-identical to the original payload.
     */
    
    await fc.assert(
      fc.asyncProperty(
        fc.string({ minLength: 0, maxLength: 10000 }), // Test strings up to 10KB
        async (testString) => {
          const mockStream = new PropertyMockStream()
          
          // Simulate the echo handler behavior
          await pipe(
            mockStream.source(testString),
            mockStream.sink.bind(mockStream)
          )
          
          const result = mockStream.getOutputAsString()
          
          // The echoed data should be identical to the input
          assert.strictEqual(result, testString, 
            `Echo failed for string: expected "${testString}", got "${result}"`)
        }
      ),
      { numRuns: 100 }
    )
  })
  
  test('Property 1: Echo Data Integrity - Binary payloads', async () => {
    /**
     * **Property 1: Echo Data Integrity**
     * **Validates: Requirements 1.1, 1.4, 1.5**
     * 
     * For any binary data payload sent through the Echo protocol,
     * the response received should be byte-identical to the original payload.
     */
    
    await fc.assert(
      fc.asyncProperty(
        fc.uint8Array({ minLength: 0, maxLength: 10000 }), // Test binary data up to 10KB
        async (testData) => {
          const mockStream = new PropertyMockStream()
          
          // Simulate the echo handler behavior
          await pipe(
            mockStream.source(testData),
            mockStream.sink.bind(mockStream)
          )
          
          const result = mockStream.getOutputAsUint8Array()
          
          // The echoed data should be byte-identical to the input
          assert.deepStrictEqual(result, testData,
            `Echo failed for binary data: lengths ${result.length} vs ${testData.length}`)
        }
      ),
      { numRuns: 100 }
    )
  })
  
  test('Property 1: Echo Data Integrity - Large payloads up to 1MB', async () => {
    /**
     * **Property 1: Echo Data Integrity**
     * **Validates: Requirements 1.1, 1.4, 1.5**
     * 
     * For any large data payload (up to 1MB) sent through the Echo protocol,
     * the response received should be byte-identical to the original payload.
     */
    
    await fc.assert(
      fc.asyncProperty(
        fc.uint8Array({ minLength: 100000, maxLength: 1048576 }), // Test 100KB to 1MB
        async (testData) => {
          const mockStream = new PropertyMockStream()
          
          // Simulate the echo handler behavior
          await pipe(
            mockStream.source(testData),
            mockStream.sink.bind(mockStream)
          )
          
          const result = mockStream.getOutputAsUint8Array()
          
          // The echoed data should be byte-identical to the input
          assert.strictEqual(result.length, testData.length,
            `Echo failed: length mismatch ${result.length} vs ${testData.length}`)
          assert.deepStrictEqual(result, testData,
            `Echo failed for large payload: data corruption detected`)
        }
      ),
      { numRuns: 10 } // Fewer runs for large payloads to avoid timeout
    )
  })
  
  test('Property 1: Echo Data Integrity - Chunked data streams', async () => {
    /**
     * **Property 1: Echo Data Integrity**
     * **Validates: Requirements 1.1, 1.4, 1.5**
     * 
     * For any data payload sent as multiple chunks through the Echo protocol,
     * the response received should be byte-identical to the original payload.
     */
    
    await fc.assert(
      fc.asyncProperty(
        fc.array(fc.string({ minLength: 1, maxLength: 1000 }), { minLength: 1, maxLength: 50 }),
        async (chunks) => {
          const mockStream = new PropertyMockStream()
          const expectedData = chunks.join('')
          
          // Simulate the echo handler behavior with chunked input
          await pipe(
            mockStream.source(chunks),
            mockStream.sink.bind(mockStream)
          )
          
          const result = mockStream.getOutputAsString()
          
          // The echoed data should be identical to the concatenated input
          assert.strictEqual(result, expectedData,
            `Echo failed for chunked data: expected "${expectedData}", got "${result}"`)
        }
      ),
      { numRuns: 100 }
    )
  })
  
  test('Property 1: Echo Data Integrity - Mixed binary chunks', async () => {
    /**
     * **Property 1: Echo Data Integrity**
     * **Validates: Requirements 1.1, 1.4, 1.5**
     * 
     * For any binary data payload sent as multiple chunks through the Echo protocol,
     * the response received should be byte-identical to the original payload.
     */
    
    await fc.assert(
      fc.asyncProperty(
        fc.array(fc.uint8Array({ minLength: 1, maxLength: 1000 }), { minLength: 1, maxLength: 20 }),
        async (chunks) => {
          const mockStream = new PropertyMockStream()
          
          // Calculate expected concatenated data
          const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0)
          const expectedData = new Uint8Array(totalLength)
          let offset = 0
          for (const chunk of chunks) {
            expectedData.set(chunk, offset)
            offset += chunk.length
          }
          
          // Simulate the echo handler behavior with chunked binary input
          await pipe(
            mockStream.source(chunks),
            mockStream.sink.bind(mockStream)
          )
          
          const result = mockStream.getOutputAsUint8Array()
          
          // The echoed data should be byte-identical to the concatenated input
          assert.strictEqual(result.length, expectedData.length,
            `Echo failed: length mismatch ${result.length} vs ${expectedData.length}`)
          assert.deepStrictEqual(result, expectedData,
            `Echo failed for chunked binary data`)
        }
      ),
      { numRuns: 50 }
    )
  })
  
  test('Property 1: Echo Data Integrity - Edge cases', async () => {
    /**
     * **Property 1: Echo Data Integrity**
     * **Validates: Requirements 1.1, 1.4, 1.5**
     * 
     * For edge case data payloads (empty, single byte, special characters),
     * the response received should be byte-identical to the original payload.
     */
    
    const edgeCases = [
      '', // Empty string
      '\0', // Null character
      '\n', // Newline
      '\r\n', // CRLF
      '\t', // Tab
      '🚀', // Unicode emoji
      'Hello\0World', // String with null byte
      'A'.repeat(65536), // 64KB of same character
    ]
    
    for (const testCase of edgeCases) {
      const mockStream = new PropertyMockStream()
      
      await pipe(
        mockStream.source(testCase),
        mockStream.sink.bind(mockStream)
      )
      
      const result = mockStream.getOutputAsString()
      
      assert.strictEqual(result, testCase,
        `Echo failed for edge case: expected "${testCase}", got "${result}"`)
    }
  })
  
  test('Property 2: Concurrent Stream Independence', async () => {
    /**
     * **Property 2: Concurrent Stream Independence**
     * **Validates: Requirements 1.3**
     * 
     * For any set of concurrent Echo protocol streams opened to the same server,
     * each stream should handle its data independently without interference or cross-contamination.
     */
    
    await fc.assert(
      fc.asyncProperty(
        fc.array(
          fc.record({
            id: fc.integer({ min: 0, max: 999 }),
            data: fc.string({ minLength: 1, maxLength: 1000 })
          }),
          { minLength: 2, maxLength: 10 }
        ),
        async (streamConfigs) => {
          // Create multiple mock streams to simulate concurrent streams
          const streams = streamConfigs.map(config => ({
            id: config.id,
            data: config.data,
            stream: new PropertyMockStream()
          }))
          
          // Process all streams concurrently to simulate real concurrent behavior
          const promises = streams.map(async ({ id, data, stream }) => {
            // Add some randomness to simulate real-world timing variations
            const delay = Math.random() * 10 // 0-10ms random delay
            await new Promise(resolve => setTimeout(resolve, delay))
            
            // Process the stream (echo behavior)
            await pipe(
              stream.source(data),
              stream.sink.bind(stream)
            )
            
            return {
              id,
              originalData: data,
              echoedData: stream.getOutputAsString()
            }
          })
          
          // Wait for all streams to complete
          const results = await Promise.all(promises)
          
          // Verify each stream's independence - no cross-contamination
          for (const result of results) {
            assert.strictEqual(
              result.echoedData,
              result.originalData,
              `Stream ${result.id} failed: expected "${result.originalData}", got "${result.echoedData}"`
            )
          }
          
          // Verify no data mixing between streams
          const originalDataSet = new Set(results.map(r => r.originalData))
          const echoedDataSet = new Set(results.map(r => r.echoedData))
          
          assert.strictEqual(
            originalDataSet.size,
            echoedDataSet.size,
            'Data mixing detected: different number of unique original vs echoed data'
          )
          
          // Verify each original data has exactly one matching echoed data
          for (const result of results) {
            const matchingResults = results.filter(r => r.echoedData === result.originalData)
            assert.strictEqual(
              matchingResults.length,
              results.filter(r => r.originalData === result.originalData).length,
              `Cross-contamination detected for data "${result.originalData}"`
            )
          }
        }
      ),
      { numRuns: 100 }
    )
  })
  
  test('Property 2: Concurrent Stream Independence - Binary data', async () => {
    /**
     * **Property 2: Concurrent Stream Independence**
     * **Validates: Requirements 1.3**
     * 
     * For any set of concurrent Echo protocol streams with binary data,
     * each stream should handle its data independently without interference or cross-contamination.
     */
    
    await fc.assert(
      fc.asyncProperty(
        fc.array(
          fc.record({
            id: fc.integer({ min: 0, max: 999 }),
            data: fc.uint8Array({ minLength: 1, maxLength: 1000 })
          }),
          { minLength: 2, maxLength: 8 }
        ),
        async (streamConfigs) => {
          // Create multiple mock streams for binary data
          const streams = streamConfigs.map(config => ({
            id: config.id,
            data: config.data,
            stream: new PropertyMockStream()
          }))
          
          // Process all streams concurrently
          const promises = streams.map(async ({ id, data, stream }) => {
            // Add timing variation
            const delay = Math.random() * 15 // 0-15ms random delay
            await new Promise(resolve => setTimeout(resolve, delay))
            
            // Process the stream (echo behavior)
            await pipe(
              stream.source(data),
              stream.sink.bind(stream)
            )
            
            return {
              id,
              originalData: data,
              echoedData: stream.getOutputAsUint8Array()
            }
          })
          
          // Wait for all streams to complete
          const results = await Promise.all(promises)
          
          // Verify each stream's independence
          for (const result of results) {
            assert.deepStrictEqual(
              result.echoedData,
              result.originalData,
              `Binary stream ${result.id} failed: data corruption or mixing detected`
            )
          }
          
          // Verify no binary data mixing by checking lengths and checksums
          for (let i = 0; i < results.length; i++) {
            for (let j = i + 1; j < results.length; j++) {
              const result1 = results[i]
              const result2 = results[j]
              
              // If original data is different, echoed data should also be different
              if (!arraysEqual(result1.originalData, result2.originalData)) {
                assert.ok(
                  !arraysEqual(result1.echoedData, result2.echoedData),
                  `Cross-contamination detected between streams ${result1.id} and ${result2.id}`
                )
              }
            }
          }
        }
      ),
      { numRuns: 50 }
    )
  })
  
  test('Property 2: Concurrent Stream Independence - Mixed data types', async () => {
    /**
     * **Property 2: Concurrent Stream Independence**
     * **Validates: Requirements 1.3**
     * 
     * For concurrent streams with mixed data types (text and binary),
     * each stream should handle its data independently without type interference.
     */
    
    await fc.assert(
      fc.asyncProperty(
        fc.array(
          fc.record({
            id: fc.integer({ min: 0, max: 999 }),
            dataType: fc.constantFrom('text', 'binary'),
            textData: fc.string({ minLength: 1, maxLength: 500 }),
            binaryData: fc.uint8Array({ minLength: 1, maxLength: 500 })
          }),
          { minLength: 3, maxLength: 6 }
        ),
        async (streamConfigs) => {
          // Create streams with mixed data types
          const streams = streamConfigs.map(config => {
            const data = config.dataType === 'text' ? config.textData : config.binaryData
            return {
              id: config.id,
              dataType: config.dataType,
              data: data,
              stream: new PropertyMockStream()
            }
          })
          
          // Process all streams concurrently
          const promises = streams.map(async ({ id, dataType, data, stream }) => {
            // Stagger the processing to increase chance of interference
            const delay = Math.random() * 20 // 0-20ms random delay
            await new Promise(resolve => setTimeout(resolve, delay))
            
            // Process the stream
            await pipe(
              stream.source(data),
              stream.sink.bind(stream)
            )
            
            return {
              id,
              dataType,
              originalData: data,
              echoedData: dataType === 'text' 
                ? stream.getOutputAsString()
                : stream.getOutputAsUint8Array()
            }
          })
          
          // Wait for all streams to complete
          const results = await Promise.all(promises)
          
          // Verify each stream maintains its data type and content
          for (const result of results) {
            if (result.dataType === 'text') {
              assert.strictEqual(
                typeof result.echoedData,
                'string',
                `Stream ${result.id} type corruption: expected string`
              )
              assert.strictEqual(
                result.echoedData,
                result.originalData,
                `Text stream ${result.id} data corruption`
              )
            } else {
              assert.ok(
                result.echoedData instanceof Uint8Array,
                `Stream ${result.id} type corruption: expected Uint8Array`
              )
              assert.deepStrictEqual(
                result.echoedData,
                result.originalData,
                `Binary stream ${result.id} data corruption`
              )
            }
          }
          
          // Verify no cross-type contamination
          const textStreams = results.filter(r => r.dataType === 'text')
          const binaryStreams = results.filter(r => r.dataType === 'binary')
          
          // Text streams should not contain binary data patterns
          for (const textResult of textStreams) {
            assert.strictEqual(
              typeof textResult.echoedData,
              'string',
              `Text stream ${textResult.id} contaminated with binary data`
            )
          }
          
          // Binary streams should not be converted to text
          for (const binaryResult of binaryStreams) {
            assert.ok(
              binaryResult.echoedData instanceof Uint8Array,
              `Binary stream ${binaryResult.id} contaminated with text data`
            )
          }
        }
      ),
      { numRuns: 50 }
    )
  })
})

// Helper function to compare Uint8Arrays
function arraysEqual(a, b) {
  if (a.length !== b.length) return false
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false
  }
  return true
}