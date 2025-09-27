//
//  PlainBinaryReaderTests.swift
//  readmynumberTests
//
//  Created on 2025/09/10.
//

import Testing
import Foundation
import CoreNFC
@testable import readmynumber

struct PlainBinaryReaderTests {

    @Test("PlainBinaryReader initialization")
    func testPlainBinaryReaderInitialization() {
        let executor = MockRDCNFCCommandExecutor()
        let reader = PlainBinaryReader(commandExecutor: executor)

        // Test passes if initialization succeeds
        #expect(true)
    }

    @Test("PlainBinaryReader successful read")
    func testPlainBinaryReaderSuccess() async throws {
        let executor = MockRDCNFCCommandExecutor()
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
        let executor = MockRDCNFCCommandExecutor()
        let reader = PlainBinaryReader(commandExecutor: executor)

        executor.shouldSucceed = false
        executor.errorSW1 = 0x6A
        executor.errorSW2 = 0x82

        do {
            _ = try await reader.readBinaryPlain(p1: 0x8A, p2: 0x00)
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as ResidenceCardReaderError {
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

    @Test("PlainBinaryReader with different p1/p2 parameter combinations")
    func testPlainBinaryReaderParameterCombinations() async throws {
        let executor = MockRDCNFCCommandExecutor()
        let reader = PlainBinaryReader(commandExecutor: executor)
        
        let testCases: [(p1: UInt8, p2: UInt8, data: Data)] = [
            (0x80, 0x00, Data([0x01, 0x02, 0x03])),
            (0x81, 0x10, Data([0x04, 0x05, 0x06])),
            (0x85, 0xFF, Data([0x07, 0x08, 0x09])),
            (0x8B, 0x20, Data([0x0A, 0x0B, 0x0C]))
        ]
        
        for testCase in testCases {
            executor.reset()
            executor.configureMockResponse(
                for: 0xB0, 
                p1: testCase.p1, 
                p2: testCase.p2, 
                response: testCase.data
            )
            
            let result = try await reader.readBinaryPlain(p1: testCase.p1, p2: testCase.p2)
            
            #expect(result == testCase.data)
            #expect(executor.commandHistory.count == 1)
            #expect(executor.commandHistory[0].p1Parameter == testCase.p1)
            #expect(executor.commandHistory[0].p2Parameter == testCase.p2)
        }
    }

    @Test("PlainBinaryReader with large response data")
    func testPlainBinaryReaderLargeResponse() async throws {
        let executor = MockRDCNFCCommandExecutor()
        let reader = PlainBinaryReader(commandExecutor: executor)
        
        // Create data close to maxAPDUResponseLength (1693 bytes)
        let largeData = Data(repeating: 0xAB, count: 1693)
        
        executor.configureMockResponse(for: 0xB0, response: largeData)
        
        let result = try await reader.readBinaryPlain(p1: 0x85, p2: 0x00)
        
        #expect(result == largeData)
        #expect(result.count == 1693)
        #expect(executor.commandHistory.count == 1)
        #expect(executor.commandHistory[0].expectedResponseLength == 1693)
    }

    @Test("PlainBinaryReader with empty response data")
    func testPlainBinaryReaderEmptyResponse() async throws {
        let executor = MockRDCNFCCommandExecutor()
        let reader = PlainBinaryReader(commandExecutor: executor)
        
        // Configure empty response
        let emptyData = Data()
        executor.configureMockResponse(for: 0xB0, response: emptyData)
        
        let result = try await reader.readBinaryPlain(p1: 0x82, p2: 0x00)
        
        #expect(result.isEmpty)
        #expect(result.count == 0)
        #expect(executor.commandHistory.count == 1)
        #expect(executor.commandHistory[0].instructionCode == 0xB0)
    }

    @Test("PlainBinaryReader parameter validation")
    func testPlainBinaryReaderParameterValidation() async throws {
        let executor = MockRDCNFCCommandExecutor()
        let reader = PlainBinaryReader(commandExecutor: executor)
        let testData = Data([0xFF, 0xEE, 0xDD, 0xCC])
        
        executor.configureMockResponse(for: 0xB0, response: testData)
        
        // Test default p2 parameter (should be 0x00)
        let result = try await reader.readBinaryPlain(p1: 0x89)
        
        #expect(result == testData)
        #expect(executor.commandHistory.count == 1)
        let command = executor.commandHistory[0]
        
        // Verify APDU command structure
        #expect(command.instructionClass == 0x00)
        #expect(command.instructionCode == 0xB0) // READ BINARY
        #expect(command.p1Parameter == 0x89)
        #expect(command.p2Parameter == 0x00) // Default value
        #expect(command.data?.isEmpty ?? true)
        #expect(command.expectedResponseLength == 1693) // maxAPDUResponseLength
    }

    @Test("PlainBinaryReader different status word combinations")
    func testPlainBinaryReaderDifferentStatusWords() async {
        let executor = MockRDCNFCCommandExecutor()
        let reader = PlainBinaryReader(commandExecutor: executor)
        
        let errorCases: [(sw1: UInt8, sw2: UInt8, description: String)] = [
            (0x6A, 0x82, "File not found"),
            (0x69, 0x82, "Security status not satisfied"),
            (0x67, 0x00, "Wrong length"),
            (0x6E, 0x00, "Class not supported"),
            (0x6D, 0x00, "Instruction not supported"),
            (0x62, 0x81, "Part of returned data may be corrupted"),
            (0x63, 0xC0, "PIN verification failed")
        ]
        
        for errorCase in errorCases {
            executor.reset()
            executor.shouldSucceed = false
            executor.errorSW1 = errorCase.sw1
            executor.errorSW2 = errorCase.sw2
            
            do {
                _ = try await reader.readBinaryPlain(p1: 0x84, p2: 0x00)
                #expect(Bool(false), "Should have thrown error for \(errorCase.description)")
            } catch let error as ResidenceCardReaderError {
                if case .cardError(let sw1, let sw2) = error {
                    #expect(sw1 == errorCase.sw1, "SW1 mismatch for \(errorCase.description)")
                    #expect(sw2 == errorCase.sw2, "SW2 mismatch for \(errorCase.description)")
                } else {
                    #expect(Bool(false), "Wrong error type for \(errorCase.description)")
                }
            } catch {
                #expect(Bool(false), "Unexpected error type for \(errorCase.description): \(error)")
            }
        }
    }
}