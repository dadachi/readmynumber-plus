//
//  AbstractionTests.swift
//  readmynumberTests
//
//  Created on 2025/09/09.
//

import Testing
import Foundation
import CoreNFC
@testable import readmynumber

// MARK: - NFCCommandExecutor Tests

struct NFCCommandExecutorTests {
    
    @Test("MockNFCCommandExecutor default behavior")
    func testMockCommandExecutorDefaults() {
        let executor = MockNFCCommandExecutor()
        
        #expect(executor.shouldSucceed == true)
        #expect(executor.errorSW1 == 0x6A)
        #expect(executor.errorSW2 == 0x82)
        #expect(executor.commandHistory.isEmpty)
        #expect(executor.mockResponses.isEmpty)
    }
    
    @Test("MockNFCCommandExecutor successful command execution")
    func testMockCommandExecutorSuccess() async throws {
        let executor = MockNFCCommandExecutor()
        
        let command = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x04,
            p2Parameter: 0x0C,
            data: Data([0xD3, 0x92, 0xF0]),
            expectedResponseLength: -1
        )
        
        let (data, sw1, sw2) = try await executor.sendCommand(apdu: command)
        
        #expect(data.isEmpty)
        #expect(sw1 == 0x90)
        #expect(sw2 == 0x00)
        #expect(executor.commandHistory.count == 1)
        #expect(executor.commandHistory[0].instructionCode == 0xA4)
    }
    
    @Test("MockNFCCommandExecutor failure scenario")
    func testMockCommandExecutorFailure() async {
        let executor = MockNFCCommandExecutor()
        executor.shouldSucceed = false
        executor.errorSW1 = 0x62
        executor.errorSW2 = 0x82
        
        let command = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xB0,
            p1Parameter: 0x81,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: 256
        )
        
        do {
            _ = try await executor.sendCommand(apdu: command)
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as CardReaderError {
            if case .cardError(let sw1, let sw2) = error {
                #expect(sw1 == 0x62)
                #expect(sw2 == 0x82)
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \\(error)")
        }
        
        #expect(executor.commandHistory.count == 1)
    }
    
    @Test("MockNFCCommandExecutor custom response configuration")
    func testMockCommandExecutorCustomResponse() async throws {
        let executor = MockNFCCommandExecutor()
        let expectedData = Data([0xCA, 0xFE, 0xBA, 0xBE])
        
        executor.configureMockResponse(for: 0xB0, response: expectedData, sw1: 0x91, sw2: 0x01)
        
        let command = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xB0,
            p1Parameter: 0x85,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: 256
        )
        
        let (data, sw1, sw2) = try await executor.sendCommand(apdu: command)
        
        #expect(data == expectedData)
        #expect(sw1 == 0x91)
        #expect(sw2 == 0x01)
    }
    
    @Test("MockNFCCommandExecutor parameter-specific response")
    func testMockCommandExecutorParameterSpecificResponse() async throws {
        let executor = MockNFCCommandExecutor()
        let specificData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        
        executor.configureMockResponse(for: 0xB0, p1: 0x85, p2: 0x00, response: specificData)
        
        let matchingCommand = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xB0,
            p1Parameter: 0x85,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: 256
        )
        
        let nonMatchingCommand = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xB0,
            p1Parameter: 0x86,  // Different parameter
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: 256
        )
        
        let (matchingData, _, _) = try await executor.sendCommand(apdu: matchingCommand)
        let (nonMatchingData, _, _) = try await executor.sendCommand(apdu: nonMatchingCommand)
        
        #expect(matchingData == specificData)
        #expect(nonMatchingData.isEmpty)  // Default empty response
    }
    
    @Test("MockNFCCommandExecutor reset functionality")
    func testMockCommandExecutorReset() async throws {
        let executor = MockNFCCommandExecutor()
        
        // Set up some state
        executor.shouldSucceed = false
        executor.errorSW1 = 0x6F
        executor.errorSW2 = 0x00
        executor.configureMockResponse(for: 0xA4, response: Data([0xFF]))
        
        let command = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: -1
        )
        
        do {
            _ = try await executor.sendCommand(apdu: command)
        } catch {
            // Expected to fail
        }
        
        #expect(!executor.commandHistory.isEmpty)
        #expect(!executor.mockResponses.isEmpty)
        
        // Reset and verify defaults
        executor.reset()
        
        #expect(executor.shouldSucceed == true)
        #expect(executor.errorSW1 == 0x6A)
        #expect(executor.errorSW2 == 0x82)
        #expect(executor.commandHistory.isEmpty)
        #expect(executor.mockResponses.isEmpty)
    }
}

// MARK: - SecureMessagingReader Tests

struct SecureMessagingReaderTests {
    
    @Test("SecureMessagingReader initialization")
    func testSecureMessagingReaderInitialization() {
        let executor = MockNFCCommandExecutor()
        let sessionKey = Data(repeating: 0xAA, count: 16)
        
        let reader = SecureMessagingReader(commandExecutor: executor, sessionKey: sessionKey)
        
        // Test passes if initialization succeeds without crash
        #expect(true)
    }
    
    @Test("MockSecureMessagingReader default behavior")
    func testMockSecureMessagingReaderDefaults() async throws {
        let executor = MockNFCCommandExecutor()
        let mockReader = MockSecureMessagingReader(commandExecutor: executor)
        
        let data = try await mockReader.readBinaryWithSM(p1: 0x85, p2: 0x00)
        
        #expect(data.count == 100)
        #expect(data.first == 0x00)  // Offset 0x8500 & 0xFF = 0x00
        #expect(!mockReader.shouldThrowError)
    }
    
    @Test("MockSecureMessagingReader with custom data")
    func testMockSecureMessagingReaderCustomData() async throws {
        let executor = MockNFCCommandExecutor()
        let mockReader = MockSecureMessagingReader(commandExecutor: executor)
        let customData = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        
        mockReader.mockDecryptedData = customData
        
        let data = try await mockReader.readBinaryWithSM(p1: 0x85, p2: 0x00)
        
        #expect(data == customData)
    }
    
    @Test("MockSecureMessagingReader error throwing")
    func testMockSecureMessagingReaderError() async {
        let executor = MockNFCCommandExecutor()
        let mockReader = MockSecureMessagingReader(commandExecutor: executor)
        
        mockReader.shouldThrowError = true
        mockReader.errorToThrow = CardReaderError.invalidResponse
        
        do {
            _ = try await mockReader.readBinaryWithSM(p1: 0x85, p2: 0x00)
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as CardReaderError {
            #expect(error == CardReaderError.invalidResponse)
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }
    
    @Test("MockSecureMessagingReader chunked reading")
    func testMockSecureMessagingReaderChunked() async throws {
        let executor = MockNFCCommandExecutor()
        let mockReader = MockSecureMessagingReader(commandExecutor: executor)
        
        let data = try await mockReader.readBinaryChunkedWithSM(p1: 0x85, p2: 0x00)
        
        // Should return TLV formatted data with 100 bytes of 0xAA
        #expect(data.count == 104)  // 4 bytes TLV header + 100 bytes data
        #expect(data[0] == 0x5F)     // Tag byte 1
        #expect(data[1] == 0x01)     // Tag byte 2
        #expect(data[2] == 0x00)     // Length high
        #expect(data[3] == 0x64)     // Length low (100 bytes)
    }
}

// MARK: - PlainBinaryReader Tests

struct PlainBinaryReaderTests {
    
    @Test("PlainBinaryReader initialization")
    func testPlainBinaryReaderInitialization() {
        let executor = MockNFCCommandExecutor()
        let reader = PlainBinaryReader(commandExecutor: executor)
        
        // Test passes if initialization succeeds
        #expect(true)
    }
    
    @Test("PlainBinaryReader successful read")
    func testPlainBinaryReaderSuccess() async throws {
        let executor = MockNFCCommandExecutor()
        let reader = PlainBinaryReader(commandExecutor: executor)
        let expectedData = Data([0x30, 0x31, 0x32, 0x33])  // "0123"
        
        executor.configureMockResponse(for: 0xB0, response: expectedData)
        
        let data = try await reader.readBinaryPlain(p1: 0x8B, p2: 0x00)
        
        #expect(data == expectedData)
        #expect(executor.commandHistory.count == 1)
        #expect(executor.commandHistory[0].instructionCode == 0xB0)
        #expect(executor.commandHistory[0].p1Parameter == 0x8B)
        #expect(executor.commandHistory[0].p2Parameter == 0x00)
    }
    
    @Test("PlainBinaryReader error handling")
    func testPlainBinaryReaderError() async {
        let executor = MockNFCCommandExecutor()
        let reader = PlainBinaryReader(commandExecutor: executor)
        
        executor.shouldSucceed = false
        executor.errorSW1 = 0x6A
        executor.errorSW2 = 0x82
        
        do {
            _ = try await reader.readBinaryPlain(p1: 0x8A, p2: 0x00)
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
    
    @Test("MockPlainBinaryReader default behavior")
    func testMockPlainBinaryReaderDefaults() async throws {
        let executor = MockNFCCommandExecutor()
        let mockReader = MockPlainBinaryReader(commandExecutor: executor)
        
        let data = try await mockReader.readBinaryPlain(p1: 0x8B)
        
        #expect(data.count == 256)
        #expect(data.allSatisfy { $0 == 0xFF })
    }
    
    @Test("MockPlainBinaryReader custom data")
    func testMockPlainBinaryReaderCustomData() async throws {
        let executor = MockNFCCommandExecutor()
        let mockReader = MockPlainBinaryReader(commandExecutor: executor)
        let customData = Data("Hello, World!".utf8)
        
        mockReader.mockData = customData
        
        let data = try await mockReader.readBinaryPlain(p1: 0x81)
        
        #expect(data == customData)
    }
    
    @Test("MockPlainBinaryReader chunked reading")
    func testMockPlainBinaryReaderChunked() async throws {
        let executor = MockNFCCommandExecutor()
        let mockReader = MockPlainBinaryReader(commandExecutor: executor)
        
        let data = try await mockReader.readBinaryChunked(p1: 0x82)
        
        #expect(data.count == 512)
        #expect(data.allSatisfy { $0 == 0xAA })
    }
}

// MARK: - ThreadDispatcher Tests

struct ThreadDispatcherTests {
    
    @Test("MockThreadDispatcher initialization")
    func testMockThreadDispatcherInitialization() {
        let dispatcher = MockThreadDispatcher()
        
        #expect(dispatcher.dispatchedToMainCount == 0)
        #expect(dispatcher.dispatchedToMainActorCount == 0)
        #expect(dispatcher.executeImmediately == true)
        #expect(!dispatcher.hasPendingMainQueue())
        #expect(!dispatcher.hasPendingMainActorQueue())
    }
    
    @Test("MockThreadDispatcher immediate execution")
    func testMockThreadDispatcherImmediate() {
        let dispatcher = MockThreadDispatcher()
        var executed = false
        
        dispatcher.dispatchToMain {
            executed = true
        }
        
        #expect(executed == true)
        #expect(dispatcher.dispatchedToMainCount == 1)
        #expect(!dispatcher.hasPendingMainQueue())
    }
    
    @Test("MockThreadDispatcher deferred execution")
    func testMockThreadDispatcherDeferred() {
        let dispatcher = MockThreadDispatcher()
        dispatcher.executeImmediately = false
        var executed = false
        
        dispatcher.dispatchToMain {
            executed = true
        }
        
        #expect(executed == false)
        #expect(dispatcher.dispatchedToMainCount == 1)
        #expect(dispatcher.hasPendingMainQueue())
        
        // Execute pending
        dispatcher.executePendingMainQueue()
        
        #expect(executed == true)
        #expect(!dispatcher.hasPendingMainQueue())
    }
    
    @Test("MockThreadDispatcher main actor execution")
    func testMockThreadDispatcherMainActor() async {
        let dispatcher = MockThreadDispatcher()
        var executed = false
        
        await dispatcher.dispatchToMainActor {
            executed = true
        }
        
        #expect(executed == true)
        #expect(dispatcher.dispatchedToMainActorCount == 1)
        #expect(!dispatcher.hasPendingMainActorQueue())
    }
    
    @Test("MockThreadDispatcher reset")
    func testMockThreadDispatcherReset() {
        let dispatcher = MockThreadDispatcher()
        dispatcher.executeImmediately = false
        
        dispatcher.dispatchToMain { }
        dispatcher.dispatchToMain { }
        
        #expect(dispatcher.dispatchedToMainCount == 2)
        #expect(dispatcher.hasPendingMainQueue())
        
        dispatcher.reset()
        
        #expect(dispatcher.dispatchedToMainCount == 0)
        #expect(dispatcher.dispatchedToMainActorCount == 0)
        #expect(dispatcher.executeImmediately == true)
        #expect(!dispatcher.hasPendingMainQueue())
        #expect(!dispatcher.hasPendingMainActorQueue())
    }
}

// MARK: - NFCSessionManager Tests

struct NFCSessionManagerTests {
    
    @Test("MockNFCSessionManager initialization")
    func testMockNFCSessionManagerInitialization() {
        let manager = MockNFCSessionManager()
        
        #expect(manager.isReadingAvailable == true)
        #expect(manager.shouldFailConnection == false)
        #expect(manager.sessionStarted == false)
        #expect(manager.connected == false)
        #expect(manager.invalidated == false)
        #expect(manager.invalidationErrorMessage == nil)
        #expect(manager.shouldSimulateTagDetection == true)
    }
    
    @Test("MockNFCSessionManager session start")
    func testMockNFCSessionManagerSessionStart() {
        let manager = MockNFCSessionManager()
        
        manager.startSession(
            pollingOption: .iso14443,
            delegate: MockNFCDelegate(),
            alertMessage: "Test message"
        )
        
        #expect(manager.sessionStarted == true)
        #expect(manager.alertMessage == "Test message")
        #expect(manager.pollingOption == .iso14443)
    }
    
    @Test("MockNFCSessionManager connection flags")
    func testMockNFCSessionManagerConnectionFlags() {
        let manager = MockNFCSessionManager()
        
        // Test connection failure configuration
        #expect(manager.shouldFailConnection == false)
        #expect(manager.connected == false)
        
        manager.shouldFailConnection = true
        manager.connectionError = NFCSessionError.connectionFailed
        
        #expect(manager.shouldFailConnection == true)
    }
    
    @Test("MockNFCSessionManager invalidation")
    func testMockNFCSessionManagerInvalidation() {
        let manager = MockNFCSessionManager()
        
        manager.invalidate()
        #expect(manager.invalidated == true)
        #expect(manager.invalidationErrorMessage == nil)
        
        manager.reset()
        manager.invalidate(errorMessage: "Test error")
        #expect(manager.invalidated == true)
        #expect(manager.invalidationErrorMessage == "Test error")
    }
    
    @Test("MockNFCSessionManager reset")
    func testMockNFCSessionManagerReset() {
        let manager = MockNFCSessionManager()
        
        // Set up some state
        manager.isReadingAvailable = false
        manager.shouldFailConnection = true
        manager.sessionStarted = true
        manager.connected = true
        manager.invalidated = true
        manager.invalidationErrorMessage = "Test"
        
        manager.reset()
        
        #expect(manager.isReadingAvailable == true)
        #expect(manager.shouldFailConnection == false)
        #expect(manager.sessionStarted == false)
        #expect(manager.connected == false)
        #expect(manager.invalidated == false)
        #expect(manager.invalidationErrorMessage == nil)
    }
}

// MARK: - Helper Classes

class MockNFCDelegate: NSObject, NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Mock implementation
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // Mock implementation
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        // Mock implementation
    }
}

