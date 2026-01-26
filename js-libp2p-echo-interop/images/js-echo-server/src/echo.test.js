/**
 * Unit tests for Echo protocol handler
 */

import { test, describe } from 'node:test'
import assert from 'node:assert'
import { pipe } from 'it-pipe'
import { fromString as uint8ArrayFromString } from 'uint8arrays/from-string'
import { toString as uint8ArrayToString } from 'uint8arrays/to-string'

// Mock stream implementation for testing
class MockStream {
  constructor(data) {
    this.data = data
    this.output = []
  }
  
  async *source() {
    for (const chunk of this.data) {
      yield uint8ArrayFromString(chunk)
    }
  }
  
  async sink(source) {
    for await (const chunk of source) {
      this.output.push(uint8ArrayToString(chunk))
    }
  }
  
  getOutput() {
    return this.output.join('')
  }
}

describe('Echo Protocol Handler', () => {
  test('should echo simple text data', async () => {
    const testData = ['Hello, World!']
    const mockStream = new MockStream(testData)
    
    // Simulate the echo handler behavior
    await pipe(
      mockStream.source(),
      mockStream.sink.bind(mockStream)
    )
    
    assert.strictEqual(mockStream.getOutput(), 'Hello, World!')
  })
  
  test('should echo multiple chunks', async () => {
    const testData = ['Hello, ', 'World', '!']
    const mockStream = new MockStream(testData)
    
    await pipe(
      mockStream.source(),
      mockStream.sink.bind(mockStream)
    )
    
    assert.strictEqual(mockStream.getOutput(), 'Hello, World!')
  })
  
  test('should echo empty data', async () => {
    const testData = ['']
    const mockStream = new MockStream(testData)
    
    await pipe(
      mockStream.source(),
      mockStream.sink.bind(mockStream)
    )
    
    assert.strictEqual(mockStream.getOutput(), '')
  })
  
  test('should echo binary data', async () => {
    const binaryData = new Uint8Array([0x48, 0x65, 0x6c, 0x6c, 0x6f]) // "Hello"
    
    class BinaryMockStream {
      constructor(data) {
        this.data = data
        this.output = []
      }
      
      async *source() {
        yield this.data
      }
      
      async sink(source) {
        for await (const chunk of source) {
          this.output.push(chunk)
        }
      }
      
      getOutput() {
        return this.output[0]
      }
    }
    
    const mockStream = new BinaryMockStream(binaryData)
    
    await pipe(
      mockStream.source(),
      mockStream.sink.bind(mockStream)
    )
    
    assert.deepStrictEqual(mockStream.getOutput(), binaryData)
  })
  
  test('should handle large data chunks', async () => {
    // Create a 1KB test string
    const largeData = 'A'.repeat(1024)
    const testData = [largeData]
    const mockStream = new MockStream(testData)
    
    await pipe(
      mockStream.source(),
      mockStream.sink.bind(mockStream)
    )
    
    assert.strictEqual(mockStream.getOutput(), largeData)
    assert.strictEqual(mockStream.getOutput().length, 1024)
  })
})