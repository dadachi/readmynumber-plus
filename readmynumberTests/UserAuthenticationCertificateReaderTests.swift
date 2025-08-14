import Testing
import Foundation
import CoreNFC
@testable import マイ証明書

@Suite("UserAuthenticationCertificateReader Tests")
struct UserAuthenticationCertificateReaderTests {
    
    @Suite("Initialization")
    struct InitializationTests {
        @Test("Reader should initialize with empty PIN")
        func testInitialization() {
            let reader = UserAuthenticationCertificateReader()
            #expect(reader.pin.isEmpty)
        }
    }
    
    @Suite("Certificate Reading Flow")
    struct CertificateReadingTests {
        @Test("Successful certificate reading flow")
        func testSuccessfulCertificateReading() async throws {
            let reader = UserAuthenticationCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.mockResponses = [
                Data(), 
                Data(), 
                Data(), 
                Data([0x00, 0x0A])  
            ]
            
            await confirmation("Certificate read successfully") { confirm in
                reader.readCertificate(pin: "1234", nfcTag: mockTag, session: mockSession) { success, data in
                    confirm()
                }
            }
            
            #expect(reader.pin == "1234")
            #expect(mockTag.commandHistory.count == 4)
            
            let selectJPKICommand = mockTag.commandHistory[0].apdu
            #expect(selectJPKICommand.instructionClass == 0x00)
            #expect(selectJPKICommand.instructionCode == 0xA4)
            #expect(selectJPKICommand.p1Parameter == 0x04)
            #expect(selectJPKICommand.p2Parameter == 0x0C)
            
            let selectPINCommand = mockTag.commandHistory[1].apdu
            #expect(selectPINCommand.instructionClass == 0x00)
            #expect(selectPINCommand.instructionCode == 0xA4)
            #expect(selectPINCommand.p1Parameter == 0x02)
            #expect(selectPINCommand.p2Parameter == 0x0C)
            
            let verifyPINCommand = mockTag.commandHistory[2].apdu
            #expect(verifyPINCommand.instructionClass == 0x00)
            #expect(verifyPINCommand.instructionCode == 0x20)
            #expect(verifyPINCommand.p1Parameter == 0x00)
            #expect(verifyPINCommand.p2Parameter == 0x80)
        }
        
        @Test("Failed JPKI AP selection")
        func testFailedJPKISelection() async throws {
            let reader = UserAuthenticationCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.shouldFailAt = 0
            
            reader.readCertificate(pin: "1234", nfcTag: mockTag, session: mockSession) { success, data in
                #expect(success == false)
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(mockSession.invalidateCallCount > 0)
            #expect(mockSession.invalidateErrorMessage?.contains("公的個人認証AP") == true)
        }
        
        @Test("Failed PIN verification with wrong status")
        func testFailedPINVerification() async throws {
            let reader = UserAuthenticationCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.customStatusWords = [
                (0x90, 0x00), 
                (0x90, 0x00), 
                (0x63, 0xC3)  
            ]
            
            reader.readCertificate(pin: "1234", nfcTag: mockTag, session: mockSession) { success, data in
                #expect(success == false)
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(mockSession.invalidateCallCount > 0)
        }
    }
    
    @Suite("PIN Handling")
    struct PINHandlingTests {
        @Test("PIN should be stored correctly")
        func testPINStorage() {
            let reader = UserAuthenticationCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            reader.readCertificate(pin: "9876", nfcTag: mockTag, session: mockSession) { _, _ in }
            
            #expect(reader.pin == "9876")
        }
        
        @Test("Empty PIN handling")
        func testEmptyPIN() {
            let reader = UserAuthenticationCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            reader.readCertificate(pin: "", nfcTag: mockTag, session: mockSession) { _, _ in }
            
            #expect(reader.pin.isEmpty)
        }
        
        @Test("PIN with special characters")
        func testSpecialPIN() {
            let reader = UserAuthenticationCertificateReader()
            let specialPIN = "1234!@#$"
            
            reader.pin = specialPIN
            #expect(reader.pin == specialPIN)
        }
    }
    
    @Suite("My Number Reading")
    struct MyNumberReadingTests {
        @Test("Successful My Number reading")
        func testReadMyNumber() async throws {
            let reader = UserAuthenticationCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            let myNumberData = "123456789012".data(using: .utf8)!
            mockTag.mockResponses = [
                Data(), 
                Data(),
                Data(),
                myNumberData 
            ]
            
            await confirmation("My Number read successfully") { confirm in
                reader.readMyNumber(pin: "1234", nfcTag: mockTag, session: mockSession) { success, number in
                    #expect(success == true)
                    #expect(number == "123456789012")
                    confirm()
                }
            }
        }
        
        @Test("Failed My Number reading")
        func testFailedMyNumberReading() async throws {
            let reader = UserAuthenticationCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.shouldFailAt = 3
            
            reader.readMyNumber(pin: "1234", nfcTag: mockTag, session: mockSession) { success, number in
                #expect(success == false)
                #expect(number.isEmpty)
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    @Suite("Basic Info Reading")
    struct BasicInfoReadingTests {
        @Test("Successful basic info reading")
        func testReadBasicInfo() async throws {
            let reader = UserAuthenticationCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            let infoDict = ["name": "Test User", "address": "Test Address"]
            let infoData = try JSONSerialization.data(withJSONObject: infoDict)
            
            mockTag.mockResponses = [
                Data(),
                Data(),
                Data(),
                infoData
            ]
            
            await confirmation("Basic info read successfully") { confirm in
                reader.readBasicInfo(pin: "1234", nfcTag: mockTag, session: mockSession) { success, info in
                    #expect(success == true)
                    #expect(info["name"] == "Test User")
                    #expect(info["address"] == "Test Address")
                    confirm()
                }
            }
        }
    }
    
    @Suite("Error Handling")
    struct ErrorHandlingTests {
        @Test("Handle network error during command")
        func testNetworkError() async throws {
            let reader = UserAuthenticationCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.shouldFailAt = 0
            
            reader.readCertificate(pin: "1234", nfcTag: mockTag, session: mockSession) { success, _ in
                #expect(success == false)
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            #expect(mockSession.invalidateCallCount > 0)
        }
        
        @Test("Handle invalid status words")
        func testInvalidStatusWords() async throws {
            let reader = UserAuthenticationCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.customStatusWords = [(0x6A, 0x82)]
            
            reader.readCertificate(pin: "1234", nfcTag: mockTag, session: mockSession) { success, _ in
                #expect(success == false)
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            #expect(mockSession.invalidateErrorMessage?.contains("6A82") == true)
        }
    }
}

// MARK: - Mock Objects

protocol MockNFCTag: NFCISO7816Tag {
    var commandHistory: [(apdu: NFCISO7816APDU, response: (Data, UInt8, UInt8, Error?))] { get set }
}

class MockNFCISO7816Tag: NSObject, NFCISO7816Tag {
    var isAvailable: Bool = true
    var identifier: Data = Data()
    var historicalBytes: Data?
    var applicationData: Data?
    var proprietaryApplicationDataCoding: Bool = false
    var initialSelectedAID: String = ""
    
    var commandHistory: [(apdu: NFCISO7816APDU, response: (Data, UInt8, UInt8, Error?))] = []
    var mockResponses: [Data] = []
    var currentResponseIndex = 0
    var shouldFailAt: Int? = nil
    var customStatusWords: [(UInt8, UInt8)] = []
    
    func sendCommand(apdu: NFCISO7816APDU, completionHandler: @escaping (Data, UInt8, UInt8, Error?) -> Void) {
        if let failIndex = shouldFailAt, commandHistory.count == failIndex {
            let error = NSError(domain: "MockNFC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
            commandHistory.append((apdu, (Data(), 0x6A, 0x82, error)))
            completionHandler(Data(), 0x6A, 0x82, error)
            return
        }
        
        let responseData = currentResponseIndex < mockResponses.count ? mockResponses[currentResponseIndex] : Data()
        let (sw1, sw2) = currentResponseIndex < customStatusWords.count ? customStatusWords[currentResponseIndex] : (0x90, 0x00)
        
        commandHistory.append((apdu, (responseData, sw1, sw2, nil)))
        completionHandler(responseData, sw1, sw2, nil)
        currentResponseIndex += 1
    }
}

class MockNFCTagReaderSession: NFCTagReaderSession {
    var invalidateCallCount = 0
    var invalidateErrorMessage: String?
    var alertMessage: String?
    
    override func invalidate() {
        invalidateCallCount += 1
    }
    
    override func invalidate(errorMessage: String) {
        invalidateCallCount += 1
        invalidateErrorMessage = errorMessage
    }
}