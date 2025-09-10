//
//  SecureMessagingReaderTests.swift
//  readmynumberTests
//
//  Created on 2025/09/10.
//

import Testing
import Foundation
import CoreNFC
@testable import readmynumber

// Mock TDESCryptography for testing
class MockTDESCryptography: TDESCryptography {
    var shouldSucceed = true
    var decryptedData = Data([0x01, 0x02, 0x03, 0x04, 0x80, 0x00, 0x00, 0x00]) // Data with ISO7816-4 padding
    var encryptedData = Data([0xFF, 0xFE, 0xFD, 0xFC])
    
    override func performTDES(data: Data, key: Data, encrypt: Bool) throws -> Data {
        guard shouldSucceed else {
            throw CardReaderError.cryptographyError("Mock decryption failed")
        }
        
        return encrypt ? encryptedData : decryptedData
    }
    
    func reset() {
        shouldSucceed = true
        decryptedData = Data([0x01, 0x02, 0x03, 0x04, 0x80, 0x00, 0x00, 0x00]) // Reset with padding
        encryptedData = Data([0xFF, 0xFE, 0xFD, 0xFC])
    }
}

struct SecureMessagingReaderTests {

    @Test("SecureMessagingReader initialization with session key")
    func testSecureMessagingReaderInitialization() {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let mockCrypto = MockTDESCryptography()

        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey, tdesCryptography: mockCrypto)

        // Test passes if initialization succeeds without crash
        #expect(true)
    }

    @Test("SecureMessagingReader initialization without session key")
    func testSecureMessagingReaderInitializationNoKey() {
        let executor = MockNFCCommandExecutor()
        let mockCrypto = MockTDESCryptography()

        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: nil, tdesCryptography: mockCrypto)

        // Test passes if initialization succeeds without crash
        #expect(true)
    }

    @Test("SecureMessagingReader successful read with SM")
    func testSecureMessagingReaderSuccess() async throws {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let mockCrypto = MockTDESCryptography()
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey, tdesCryptography: mockCrypto)
        
        // Create mock encrypted TLV response: 0x86 (tag) + 0x05 (length) + 0x01 (padding indicator) + encrypted data (4 bytes)
        let mockEncryptedData = Data([0x86, 0x05, 0x01, 0xFF, 0xFE, 0xFD, 0xFC])
        executor.configureMockResponse(for: 0xB0, response: mockEncryptedData)

        let result = try await reader.readBinaryWithSM(p1: 0x8A, p2: 0x00)

        // Expect the unpadded result (without the 0x80 and trailing zeros)
        let expectedUnpaddedData = Data([0x01, 0x02, 0x03, 0x04])
        #expect(result == expectedUnpaddedData)
        #expect(executor.commandHistory.count == 1)
        #expect(executor.commandHistory[0].instructionClass == 0x08) // SM command class
        #expect(executor.commandHistory[0].instructionCode == 0xB0)
        #expect(executor.commandHistory[0].p1Parameter == 0x8A)
        #expect(executor.commandHistory[0].p2Parameter == 0x00)
    }

    @Test("SecureMessagingReader error handling - no session key")
    func testSecureMessagingReaderNoSessionKey() async {
        let executor = MockNFCCommandExecutor()
        let mockCrypto = MockTDESCryptography()
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: nil, tdesCryptography: mockCrypto)
        
        // Create mock encrypted TLV response
        let mockEncryptedData = Data([0x86, 0x05, 0x01, 0xFF, 0xFE, 0xFD, 0xFC])
        executor.configureMockResponse(for: 0xB0, response: mockEncryptedData)

        do {
            _ = try await reader.readBinaryWithSM(p1: 0x8A, p2: 0x00)
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as CardReaderError {
            if case .cryptographyError(let message) = error {
                #expect(message == "Session key not available")
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("SecureMessagingReader error handling - card error")
    func testSecureMessagingReaderCardError() async {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let mockCrypto = MockTDESCryptography()
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey, tdesCryptography: mockCrypto)

        executor.shouldSucceed = false
        executor.errorSW1 = 0x6A
        executor.errorSW2 = 0x82

        do {
            _ = try await reader.readBinaryWithSM(p1: 0x8A, p2: 0x00)
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as CardReaderError {
            if case .cardError(let sw1, let sw2) = error {
                #expect(sw1 == 0x6A)
                #expect(sw2 == 0x82)
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("SecureMessagingReader invalid TLV response")
    func testSecureMessagingReaderInvalidTLV() async {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let mockCrypto = MockTDESCryptography()
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey, tdesCryptography: mockCrypto)
        
        // Invalid TLV response (wrong tag)
        let invalidTLVData = Data([0x85, 0x05, 0x01, 0xFF, 0xFE, 0xFD, 0xFC])
        executor.configureMockResponse(for: 0xB0, response: invalidTLVData)

        do {
            _ = try await reader.readBinaryWithSM(p1: 0x8A, p2: 0x00)
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as CardReaderError {
            if case .invalidResponse = error {
                // Expected
            } else {
                #expect(Bool(false), "Wrong error type: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("SecureMessagingReader BER length parsing")
    func testBERLengthParsing() throws {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let mockCrypto = MockTDESCryptography()
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey, tdesCryptography: mockCrypto)

        // Test short form length (≤ 127)
        let shortData = Data([0x7F])
        let (shortLength, shortNext) = try reader.parseBERLength(data: shortData, offset: 0)
        #expect(shortLength == 127)
        #expect(shortNext == 1)

        // Test long form with 1 byte length
        let longData1 = Data([0x81, 0xFF])
        let (longLength1, longNext1) = try reader.parseBERLength(data: longData1, offset: 0)
        #expect(longLength1 == 255)
        #expect(longNext1 == 2)

        // Test long form with 2 bytes length  
        let longData2 = Data([0x82, 0x01, 0x00])
        let (longLength2, longNext2) = try reader.parseBERLength(data: longData2, offset: 0)
        #expect(longLength2 == 256)
        #expect(longNext2 == 3)
    }

    @Test("SecureMessagingReader BER length parsing errors")
    func testBERLengthParsingErrors() {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let mockCrypto = MockTDESCryptography()
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey, tdesCryptography: mockCrypto)

        // Test offset out of bounds
        let data = Data([0x81])
        do {
            _ = try reader.parseBERLength(data: data, offset: 5)
            #expect(Bool(false), "Should have thrown error for out of bounds offset")
        } catch let error as CardReaderError {
            if case .invalidResponse = error {
                // Expected
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }

        // Test incomplete long form
        let incompleteData = Data([0x82, 0x01])
        do {
            _ = try reader.parseBERLength(data: incompleteData, offset: 0)
            #expect(Bool(false), "Should have thrown error for incomplete data")
        } catch let error as CardReaderError {
            if case .invalidResponse = error {
                // Expected
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test("SecureMessagingReader ISO 7816-4 padding removal")
    func testISO7816PaddingRemoval() throws {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let mockCrypto = MockTDESCryptography()
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey, tdesCryptography: mockCrypto)

        // Test valid ISO 7816-4 padding (0x80 followed by zeros)
        let paddedData = Data([0x01, 0x02, 0x03, 0x80, 0x00, 0x00, 0x00, 0x00])
        let result = try reader.removePadding(data: paddedData)
        #expect(result == Data([0x01, 0x02, 0x03]))

        // Test ISO 7816-4 padding at the end
        let paddedDataEnd = Data([0x01, 0x02, 0x03, 0x04, 0x80])
        let resultEnd = try reader.removePadding(data: paddedDataEnd)
        #expect(resultEnd == Data([0x01, 0x02, 0x03, 0x04]))
    }

    @Test("SecureMessagingReader PKCS7 padding removal")
    func testPKCS7PaddingRemoval() throws {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let mockCrypto = MockTDESCryptography()
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey, tdesCryptography: mockCrypto)

        // Test valid PKCS#7 padding - padding value should be 4 (length), not the actual bytes
        let pkcs7Data = Data([0x01, 0x02, 0x03, 0x04, 0x04, 0x04, 0x04, 0x04])
        let result = try reader.removePKCS7Padding(data: pkcs7Data)
        #expect(result == Data([0x01, 0x02, 0x03, 0x04]))

        // Test single byte PKCS#7 padding
        let singlePaddingData = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x01])
        let singleResult = try reader.removePKCS7Padding(data: singlePaddingData)
        #expect(singleResult == Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]))
    }

    @Test("SecureMessagingReader invalid padding scenarios")
    func testInvalidPaddingScenarios() {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let mockCrypto = MockTDESCryptography()
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey, tdesCryptography: mockCrypto)

        // Test invalid ISO 7816-4 padding (has non-zero after 0x80)
        let invalidISO = Data([0x01, 0x02, 0x80, 0xFF, 0x00])
        do {
            _ = try reader.removePadding(data: invalidISO)
            #expect(Bool(false), "Should have thrown error for invalid ISO padding")
        } catch let error as CardReaderError {
            if case .invalidResponse = error {
                // Expected
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }

        // Test invalid PKCS#7 padding (inconsistent padding bytes)
        let invalidPKCS7 = Data([0x01, 0x02, 0x03, 0x04, 0x03, 0x03, 0x02])
        do {
            _ = try reader.removePKCS7Padding(data: invalidPKCS7)
            #expect(Bool(false), "Should have thrown error for invalid PKCS7 padding")
        } catch let error as CardReaderError {
            if case .invalidResponse = error {
                // Expected  
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }

        // Test empty data
        let emptyData = Data()
        do {
            _ = try reader.removePadding(data: emptyData)
            #expect(Bool(false), "Should have thrown error for empty data")
        } catch let error as CardReaderError {
            if case .invalidResponse = error {
                // Expected
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test("SecureMessagingReader standard read with SM")
    func testStandardReadWithSM() async throws {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let mockCrypto = MockTDESCryptography()
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey, tdesCryptography: mockCrypto)

        // Create a standard TLV response that doesn't trigger chunked reading
        let standardTLVData = Data([0x86, 0x05, 0x01, 0xFF, 0xFE, 0xFD, 0xFC])
        executor.configureMockResponse(for: 0xB0, p1: 0x8A, p2: 0x00, response: standardTLVData)

        let result = try await reader.readBinaryWithSM(p1: 0x8A, p2: 0x00)

        // Expect the unpadded result (without the 0x80 and trailing zeros)
        let expectedUnpaddedData = Data([0x01, 0x02, 0x03, 0x04])
        #expect(result == expectedUnpaddedData)
        #expect(executor.commandHistory.count == 1)
        #expect(executor.commandHistory[0].instructionClass == 0x08)
        #expect(executor.commandHistory[0].instructionCode == 0xB0)
    }

    @Test("SecureMessagingReader chunked reading single chunk")
    func testReadBinaryChunkedWithSMSingleChunk() async throws {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey)
        
        // Create small single chunk test data using MockTestUtils with real encryption
        let plainData = Data([0x01, 0x02, 0x03, 0x04, 0x80, 0x00, 0x00, 0x00]) // Small data with ISO7816-4 padding
        let singleChunkData = try MockTestUtils.createSingleChunkTestData(plaintext: plainData, sessionKey: sessionKey)
        
        executor.reset()
        // Configure the response for the READ BINARY command
        // readBinaryChunkedWithSM always makes an initial read, and if all data fits, no additional reads
        executor.configureMockResponse(for: 0xB0, p1: 0x8A, p2: 0x00, response: singleChunkData)
        
        // Call chunked reading method directly
        let result = try await reader.readBinaryChunkedWithSM(p1: 0x8A, p2: 0x00)
        
        // Expect the unpadded result (without the 0x80 padding)
        let expectedUnpaddedData = Data([0x01, 0x02, 0x03, 0x04])
        #expect(result == expectedUnpaddedData)
        
        // readBinaryChunkedWithSM makes an initial read - if data fits completely, no additional reads
        // The test verifies that the entire TLV structure fits in the initial response
        #expect(executor.commandHistory.count >= 1)
        #expect(executor.commandHistory[0].instructionClass == 0x08)
        #expect(executor.commandHistory[0].instructionCode == 0xB0)
        #expect(executor.commandHistory[0].p1Parameter == 0x8A)
        #expect(executor.commandHistory[0].p2Parameter == 0x00)
    }

    @Test("SecureMessagingReader chunked reading multiple chunks")
    func testReadBinaryChunkedWithSMMultipleChunks() async throws {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey)
        
        // Create chunked test data using MockTestUtils with real encryption
        // Need > 512 bytes of plaintext to ensure encrypted TLV exceeds initial read
        var plainData = Data(repeating: 0xAB, count: 520) // 520 bytes of data
        plainData.append(0x80) // ISO 7816-4 padding marker
        // Add padding zeros to make it a multiple of 8 for TDES
        while plainData.count % 8 != 0 {
            plainData.append(0x00)
        }
        let firstChunkSize = 512 // Match the initial chunk size used by readBinaryChunkedWithSM
        
        let (firstChunk, secondChunk, offsetP1, offsetP2) = try MockTestUtils.createChunkedTestData(
            plaintext: plainData,
            sessionKey: sessionKey,
            firstChunkSize: firstChunkSize
        )
        
        executor.reset()
        
        // Configure first response (initial read at offset 0)
        executor.configureMockResponse(for: 0xB0, p1: 0x8B, p2: 0x00, response: firstChunk)
        
        // Configure second response (continuation read at calculated offset)
        executor.configureMockResponse(for: 0xB0, p1: offsetP1, p2: offsetP2, response: secondChunk)
        
        // Call chunked reading method directly
        let result = try await reader.readBinaryChunkedWithSM(p1: 0x8B, p2: 0x00)
        
        // Expect the unpadded result (without the 0x80 and trailing zeros)
        let expectedUnpaddedData = Data(repeating: 0xAB, count: 520) // Original data without padding
        #expect(result == expectedUnpaddedData)
        
        // Verify two commands were sent (initial + continuation)
        #expect(executor.commandHistory.count == 2)
        
        // Verify first command
        #expect(executor.commandHistory[0].instructionClass == 0x08)
        #expect(executor.commandHistory[0].instructionCode == 0xB0)
        #expect(executor.commandHistory[0].p1Parameter == 0x8B)
        #expect(executor.commandHistory[0].p2Parameter == 0x00)
        
        // Verify second command uses correct offset
        #expect(executor.commandHistory[1].instructionClass == 0x08)
        #expect(executor.commandHistory[1].instructionCode == 0xB0)
        #expect(executor.commandHistory[1].p1Parameter == offsetP1)
        #expect(executor.commandHistory[1].p2Parameter == offsetP2)
    }

    @Test("SecureMessagingReader chunked reading with empty continuation chunk")
    func testReadBinaryChunkedWithSMEmptyChunk() async throws {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey)
        
        // Create incomplete TLV data using real encryption
        let plainData = Data([0x01, 0x02, 0x03, 0x04, 0x80, 0x00, 0x00, 0x00])
        let firstChunkSize = 50
        
        let (firstChunk, _, offsetP1, offsetP2) = try MockTestUtils.createChunkedTestData(
            plaintext: plainData,
            sessionKey: sessionKey,
            firstChunkSize: firstChunkSize
        )
        
        // Second chunk: empty (simulates card returning no more data)
        let secondChunk = Data()
        
        executor.reset()
        
        // Configure first response
        executor.configureMockResponse(for: 0xB0, p1: 0x8C, p2: 0x00, response: firstChunk)
        
        // Configure second response to return empty data
        executor.configureMockResponse(for: 0xB0, p1: offsetP1, p2: offsetP2, response: secondChunk)
        
        // This test should handle empty chunks gracefully - the reader should break out of the loop
        // when it receives an empty chunk and decrypt the data it has collected so far
        let result = try await reader.readBinaryChunkedWithSM(p1: 0x8C, p2: 0x00)
        
        // Should successfully decrypt the partial data from the first chunk
        let expectedUnpaddedData = Data([0x01, 0x02, 0x03, 0x04])
        #expect(result == expectedUnpaddedData)
        
        // Verify that two commands were sent (initial + continuation)
        #expect(executor.commandHistory.count == 2)
        #expect(executor.commandHistory[0].p1Parameter == 0x8C)
        #expect(executor.commandHistory[0].p2Parameter == 0x00)
        #expect(executor.commandHistory[1].p1Parameter == offsetP1)
        #expect(executor.commandHistory[1].p2Parameter == offsetP2)
    }

    @Test("SecureMessagingReader cryptography failure")
    func testCryptographyFailure() async {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        let mockCrypto = MockTDESCryptography()
        mockCrypto.shouldSucceed = false
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey, tdesCryptography: mockCrypto)
        
        // Create mock encrypted TLV response
        let mockEncryptedData = Data([0x86, 0x05, 0x01, 0xFF, 0xFE, 0xFD, 0xFC])
        executor.configureMockResponse(for: 0xB0, response: mockEncryptedData)

        do {
            _ = try await reader.readBinaryWithSM(p1: 0x8A, p2: 0x00)
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as CardReaderError {
            if case .cryptographyError(let message) = error {
                #expect(message == "Mock decryption failed")
            } else {
                #expect(Bool(false), "Wrong error type: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
}
