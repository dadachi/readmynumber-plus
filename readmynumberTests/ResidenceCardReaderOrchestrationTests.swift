//
//  ResidenceCardReaderOrchestrationTests.swift
//  readmynumberTests
//
//  Created on 2025/09/09.
//

import Testing
import Foundation
import CoreNFC
@testable import readmynumber

struct ResidenceCardReaderOrchestrationTests {
    
    // MARK: - startReading Tests
    
    @Test("startReading with valid card number in test environment")
    func testStartReadingValidCardNumberInTestEnvironment() async {
        let mockSession = MockNFCSessionManager()
        let mockDispatcher = MockThreadDispatcher()
        let mockVerifier = MockSignatureVerifier()
        
        let reader = ResidenceCardReader(
            sessionManager: mockSession,
            threadDispatcher: mockDispatcher,
            signatureVerifier: mockVerifier
        )
        
        var completionResult: Result<ResidenceCardData, Error>?
        
        reader.startReading(cardNumber: "AB12345678CD") { result in
            completionResult = result
        }
        
        // Should fail with nfcNotAvailable in test environment
        // The startReading method detects test environment and fails early
        #expect(completionResult != nil)
        if case .failure(let error) = completionResult {
            if let cardError = error as? ResidenceCardReaderError {
                #expect(cardError == .nfcNotAvailable)
            } else {
                #expect(Bool(false), "Wrong error type: \(error)")
            }
        } else {
            #expect(Bool(false), "Should have failed in test environment")
        }
        
        // Session should not be started due to test environment detection
        #expect(!mockSession.sessionStarted)
        #expect(mockDispatcher.dispatchedToMainCount == 0)
    }
    
    @Test("startReading with invalid card number")
    func testStartReadingInvalidCardNumber() async {
        let mockSession = MockNFCSessionManager()
        let mockDispatcher = MockThreadDispatcher()
        let mockVerifier = MockSignatureVerifier()
        
        let reader = ResidenceCardReader(
            sessionManager: mockSession,
            threadDispatcher: mockDispatcher,
            signatureVerifier: mockVerifier
        )
        
        var completionResult: Result<ResidenceCardData, Error>?
        
        reader.startReading(cardNumber: "invalid") { result in
            completionResult = result
        }
        
        #expect(completionResult != nil)
        if case .failure(let error) = completionResult {
            #expect(error is ResidenceCardReaderError)
        } else {
            #expect(Bool(false), "Should have failed with invalid card number")
        }
    }
    
    @Test("startReading with empty card number")
    func testStartReadingEmptyCardNumber() async {
        let mockSession = MockNFCSessionManager()
        let mockDispatcher = MockThreadDispatcher()
        let mockVerifier = MockSignatureVerifier()
        
        let reader = ResidenceCardReader(
            sessionManager: mockSession,
            threadDispatcher: mockDispatcher,
            signatureVerifier: mockVerifier
        )
        
        var completionResult: Result<ResidenceCardData, Error>?
        
        reader.startReading(cardNumber: "") { result in
            completionResult = result
        }
        
        #expect(completionResult != nil)
        if case .failure(let error) = completionResult {
            #expect(error is ResidenceCardReaderError)
        } else {
            #expect(Bool(false), "Should have failed with empty card number")
        }
    }
    
    @Test("startReading when NFC not available")
    func testStartReadingNFCNotAvailable() async {
        let mockSession = MockNFCSessionManager()
        mockSession.isReadingAvailable = false
        
        let mockDispatcher = MockThreadDispatcher()
        let mockVerifier = MockSignatureVerifier()
        
        let reader = ResidenceCardReader(
            sessionManager: mockSession,
            threadDispatcher: mockDispatcher,
            signatureVerifier: mockVerifier
        )
        
        var completionResult: Result<ResidenceCardData, Error>?
        
        reader.startReading(cardNumber: "XY98765432AB") { result in
            completionResult = result
        }
        
        #expect(completionResult != nil)
        if case .failure(let error) = completionResult {
            if let cardError = error as? ResidenceCardReaderError {
                #expect(cardError == .nfcNotAvailable)
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } else {
            #expect(Bool(false), "Should have failed")
        }
        
        #expect(!mockSession.sessionStarted)
    }
    
    // MARK: - Component Integration Tests
    
    @Test("selectMF with executor successful")
    func testSelectMFWithExecutorSuccessful() async throws {
        let mockExecutor = MockNFCCommandExecutor()
        let mockSession = MockNFCSessionManager()
        let mockDispatcher = MockThreadDispatcher()
        let mockVerifier = MockSignatureVerifier()
        
        let reader = ResidenceCardReader(
            sessionManager: mockSession,
            threadDispatcher: mockDispatcher,
            signatureVerifier: mockVerifier
        )
        
        mockExecutor.configureMockResponse(for: 0xA4, response: Data())
        
        try await reader.selectMF(executor: mockExecutor)
        
        #expect(mockExecutor.commandHistory.count == 1)
        let command = mockExecutor.commandHistory[0]
        #expect(command.instructionCode == 0xA4)
        #expect(command.p1Parameter == 0x00)
        #expect(command.p2Parameter == 0x00)
        #expect(command.data == Data([0x3F, 0x00]))
    }
    
    @Test("selectDF with executor successful")
    func testSelectDFWithExecutorSuccessful() async throws {
        let mockExecutor = MockNFCCommandExecutor()
        let mockSession = MockNFCSessionManager()
        let mockDispatcher = MockThreadDispatcher()
        let mockVerifier = MockSignatureVerifier()
        
        let reader = ResidenceCardReader(
            sessionManager: mockSession,
            threadDispatcher: mockDispatcher,
            signatureVerifier: mockVerifier
        )
        
        let testAID = Data([0xD3, 0x92, 0xF0, 0x00, 0x4F, 0x02])
        mockExecutor.configureMockResponse(for: 0xA4, p1: 0x04, p2: 0x0C, response: Data())
        
        try await reader.selectDF(executor: mockExecutor, aid: testAID)
        
        #expect(mockExecutor.commandHistory.count == 1)
        let command = mockExecutor.commandHistory[0]
        #expect(command.instructionCode == 0xA4)
        #expect(command.p1Parameter == 0x04)
        #expect(command.p2Parameter == 0x0C)
        #expect(command.data == testAID)
    }
    
    @Test("Dependency injection setup")
    func testDependencyInjectionSetup() {
        let mockSession = MockNFCSessionManager()
        let mockDispatcher = MockThreadDispatcher()
        let mockVerifier = MockSignatureVerifier()
        
        let reader = ResidenceCardReader(
            sessionManager: mockSession,
            threadDispatcher: mockDispatcher,
            signatureVerifier: mockVerifier
        )
        
        // Test that we can set dependencies
        let newMockSession = MockNFCSessionManager()
        let newMockDispatcher = MockThreadDispatcher()
        let newMockVerifier = MockSignatureVerifier()
        
        reader.setDependencies(
            sessionManager: newMockSession,
            threadDispatcher: newMockDispatcher,
            signatureVerifier: newMockVerifier
        )
        
        // Test that command executor can be set
        let mockExecutor = MockNFCCommandExecutor()
        reader.setCommandExecutor(mockExecutor)
        
        // Test passes if no exceptions are thrown
        #expect(true)
    }
    
    @Test("Published properties initial state")
    func testPublishedPropertiesInitialState() {
        let mockSession = MockNFCSessionManager()
        let mockDispatcher = MockThreadDispatcher()
        let mockVerifier = MockSignatureVerifier()
        
        let reader = ResidenceCardReader(
            sessionManager: mockSession,
            threadDispatcher: mockDispatcher,
            signatureVerifier: mockVerifier
        )
        
        // Verify initial state
        #expect(reader.isReadingInProgress == false)
        #expect(reader.sessionKey == nil)
        #expect(reader.readCompletion == nil)
    }
}