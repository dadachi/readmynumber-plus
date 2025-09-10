//
//  NFCCommandExecutor.swift
//  readmynumber
//
//  Created on 2025/09/09.
//

import Foundation
import CoreNFC

/// Protocol for executing NFC commands, allowing for testability
protocol NFCCommandExecutor {
    /// Execute an NFC command and return the response
    /// - Parameter apdu: The APDU command to execute
    /// - Returns: Tuple containing response data, SW1, and SW2
    func sendCommand(apdu: NFCISO7816APDU) async throws -> (Data, UInt8, UInt8)
}

/// Concrete implementation that wraps actual NFCISO7816Tag
class NFCCommandExecutorImpl: NFCCommandExecutor {
    private let tag: NFCISO7816Tag
    
    init(tag: NFCISO7816Tag) {
        self.tag = tag
    }
    
    func sendCommand(apdu: NFCISO7816APDU) async throws -> (Data, UInt8, UInt8) {
        return try await tag.sendCommand(apdu: apdu)
    }
}

/// Mock implementation for testing
class MockNFCCommandExecutor: NFCCommandExecutor {
    var shouldSucceed = true
    var errorSW1: UInt8 = 0x6A
    var errorSW2: UInt8 = 0x82
    var commandHistory: [NFCISO7816APDU] = []
    var mockResponses: [String: (Data, UInt8, UInt8)] = [:]
    
    /// Configure a mock response for a specific command
    /// - Parameters:
    ///   - instructionCode: The instruction code to match
    ///   - response: The response data
    ///   - sw1: Status word 1
    ///   - sw2: Status word 2
    func configureMockResponse(for instructionCode: UInt8, response: Data, sw1: UInt8 = 0x90, sw2: UInt8 = 0x00) {
        let key = String(format: "%02X", instructionCode)
        mockResponses[key] = (response, sw1, sw2)
    }
    
    /// Configure a mock response for a specific command with parameters
    /// - Parameters:
    ///   - instructionCode: The instruction code
    ///   - p1: Parameter 1
    ///   - p2: Parameter 2
    ///   - response: The response data
    ///   - sw1: Status word 1
    ///   - sw2: Status word 2
    func configureMockResponse(for instructionCode: UInt8, p1: UInt8, p2: UInt8, response: Data, sw1: UInt8 = 0x90, sw2: UInt8 = 0x00) {
        let key = String(format: "%02X-%02X-%02X", instructionCode, p1, p2)
        mockResponses[key] = (response, sw1, sw2)
    }
    
    func sendCommand(apdu: NFCISO7816APDU) async throws -> (Data, UInt8, UInt8) {
        // Record command in history
        commandHistory.append(apdu)
        
        // Check for specific mock response with parameters
        let keyWithParams = String(format: "%02X-%02X-%02X", apdu.instructionCode, apdu.p1Parameter, apdu.p2Parameter)
        if let response = mockResponses[keyWithParams] {
            return response
        }
        
        // Check for mock response based on instruction code only
        let key = String(format: "%02X", apdu.instructionCode)
        if let response = mockResponses[key] {
            return response
        }
        
        // Default response based on shouldSucceed flag
        if shouldSucceed {
            // Return empty data with success status
            return (Data(), 0x90, 0x00)
        } else {
            throw CardReaderError.cardError(sw1: errorSW1, sw2: errorSW2)
        }
    }
    
    // Reset the mock for fresh test
    func reset() {
        commandHistory.removeAll()
        mockResponses.removeAll()
        shouldSucceed = true
        errorSW1 = 0x6A
        errorSW2 = 0x82
    }
}