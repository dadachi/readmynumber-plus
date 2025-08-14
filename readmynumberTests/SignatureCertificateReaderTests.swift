import Testing
import Foundation
import CoreNFC
@testable import マイ証明書

@Suite("SignatureCertificateReader Tests")
struct SignatureCertificateReaderTests {
    
    @Suite("Initialization")
    struct InitializationTests {
        @Test("Reader should initialize with default values")
        func testInitialization() {
            let reader = SignatureCertificateReader()
            #expect(reader.description.contains("SignatureCertificateReader"))
        }
    }
    
    @Suite("Certificate Reading Flow")
    struct CertificateReadingTests {
        @Test("Successful certificate reading with 6-digit PIN")
        func testSuccessfulReading6DigitPIN() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.mockResponses = [
                Data(), 
                Data(), 
                Data(), 
                Data([0x00, 0x0A])  
            ]
            
            await confirmation("Certificate read with 6-digit PIN") { confirm in
                reader.readCertificate(pin: "123456", nfcTag: mockTag, session: mockSession) { success, data in
                    confirm()
                }
            }
            
            #expect(mockTag.commandHistory.count == 4)
            
            let selectPINCommand = mockTag.commandHistory[1].apdu
            #expect(selectPINCommand.data == Data([0x00, 0x1B]))
        }
        
        @Test("Successful certificate reading with 16-digit PIN")
        func testSuccessfulReading16DigitPIN() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            let longPIN = "1234567890123456"
            mockTag.mockResponses = [
                Data(),
                Data(),
                Data(),
                Data([0x00, 0x0A])
            ]
            
            await confirmation("Certificate read with 16-digit PIN") { confirm in
                reader.readCertificate(pin: longPIN, nfcTag: mockTag, session: mockSession) { success, data in
                    #expect(success == true)
                    confirm()
                }
            }
            
            let verifyPINCommand = mockTag.commandHistory[2].apdu
            #expect(verifyPINCommand.data == longPIN.data(using: .ascii))
        }
        
        @Test("Failed JPKI AP selection for signature")
        func testFailedJPKISelection() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.shouldFailAt = 0
            
            reader.readCertificate(pin: "123456", nfcTag: mockTag, session: mockSession) { success, data in
                #expect(success == false)
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(mockSession.invalidateCallCount > 0)
            #expect(mockSession.invalidateErrorMessage?.contains("公的個人認証AP") == true)
        }
        
        @Test("Failed signature PIN selection")
        func testFailedSignaturePINSelection() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.customStatusWords = [
                (0x90, 0x00),
                (0x6A, 0x82)
            ]
            
            reader.readCertificate(pin: "123456", nfcTag: mockTag, session: mockSession) { success, data in
                #expect(success == false)
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(mockSession.invalidateErrorMessage?.contains("署名用PIN") == true)
        }
        
        @Test("Failed PIN verification")
        func testFailedPINVerification() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.customStatusWords = [
                (0x90, 0x00),
                (0x90, 0x00),
                (0x63, 0xC3)
            ]
            
            reader.readCertificate(pin: "wrongpin", nfcTag: mockTag, session: mockSession) { success, data in
                #expect(success == false)
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(mockSession.invalidateCallCount > 0)
        }
    }
    
    @Suite("PIN Validation")
    struct PINValidationTests {
        @Test("Minimum length PIN (6 digits)")
        func testMinimumLengthPIN() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.mockResponses = [Data(), Data(), Data(), Data()]
            
            await confirmation("Minimum length PIN verified") { confirm in
                reader.readCertificate(pin: "123456", nfcTag: mockTag, session: mockSession) { _, _ in
                    confirm()
                }
            }
            
            let verifyCommand = mockTag.commandHistory[2].apdu
            #expect(verifyCommand.data == "123456".data(using: .ascii))
        }
        
        @Test("Maximum length PIN (16 digits)")
        func testMaximumLengthPIN() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            let maxPIN = "1234567890123456"
            mockTag.mockResponses = [Data(), Data(), Data(), Data()]
            
            await confirmation("Maximum length PIN verified") { confirm in
                reader.readCertificate(pin: maxPIN, nfcTag: mockTag, session: mockSession) { _, _ in
                    confirm()
                }
            }
            
            let verifyCommand = mockTag.commandHistory[2].apdu
            #expect(verifyCommand.data?.count == 16)
        }
        
        @Test("PIN with alphanumeric characters")
        func testAlphanumericPIN() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            let alphanumericPIN = "abc123def456"
            mockTag.mockResponses = [Data(), Data(), Data(), Data()]
            
            await confirmation("Alphanumeric PIN verified") { confirm in
                reader.readCertificate(pin: alphanumericPIN, nfcTag: mockTag, session: mockSession) { _, _ in
                    confirm()
                }
            }
            
            let verifyCommand = mockTag.commandHistory[2].apdu
            #expect(verifyCommand.data == alphanumericPIN.data(using: .ascii))
        }
    }
    
    @Suite("Certificate Data Handling")
    struct CertificateDataTests {
        @Test("Handle empty certificate data")
        func testEmptyCertificateData() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.mockResponses = [
                Data(),
                Data(),
                Data(),
                Data()
            ]
            
            await confirmation("Empty certificate handled") { confirm in
                reader.readCertificate(pin: "123456", nfcTag: mockTag, session: mockSession) { success, data in
                    #expect(data.isEmpty || data == "AAAA")
                    confirm()
                }
            }
        }
        
        @Test("Handle large certificate data")
        func testLargeCertificateData() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            let largeCertData = Data(repeating: 0xFF, count: 1024)
            mockTag.mockResponses = [
                Data(),
                Data(),
                Data(),
                largeCertData
            ]
            
            await confirmation("Large certificate handled") { confirm in
                reader.readCertificate(pin: "123456", nfcTag: mockTag, session: mockSession) { success, data in
                    #expect(success == true)
                    confirm()
                }
            }
        }
    }
    
    @Suite("Error Recovery")
    struct ErrorRecoveryTests {
        @Test("Handle session timeout")
        func testSessionTimeout() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.shouldFailAt = 2
            
            reader.readCertificate(pin: "123456", nfcTag: mockTag, session: mockSession) { success, _ in
                #expect(success == false)
            }
            
            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(mockSession.invalidateCallCount > 0)
        }
        
        @Test("Handle card removal during reading")
        func testCardRemovalDuringReading() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.isAvailable = false
            mockTag.shouldFailAt = 1
            
            reader.readCertificate(pin: "123456", nfcTag: mockTag, session: mockSession) { success, _ in
                #expect(success == false)
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    @Suite("Command Sequence Validation")
    struct CommandSequenceTests {
        @Test("Verify correct APDU command sequence")
        func testAPDUCommandSequence() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.mockResponses = [Data(), Data(), Data(), Data()]
            
            await confirmation("APDU sequence verified") { confirm in
                reader.readCertificate(pin: "123456", nfcTag: mockTag, session: mockSession) { _, _ in
                    confirm()
                }
            }
            
            #expect(mockTag.commandHistory.count == 4)
            
            let jpkiCommand = mockTag.commandHistory[0].apdu
            #expect(jpkiCommand.instructionClass == 0x00)
            #expect(jpkiCommand.instructionCode == 0xA4)
            #expect(jpkiCommand.p1Parameter == 0x04)
            #expect(jpkiCommand.p2Parameter == 0x0C)
            #expect(jpkiCommand.data == Data([0xD3, 0x92, 0xF0, 0x00, 0x26, 0x01, 0x00, 0x00, 0x00, 0x01]))
            
            let pinSelectCommand = mockTag.commandHistory[1].apdu
            #expect(pinSelectCommand.instructionClass == 0x00)
            #expect(pinSelectCommand.instructionCode == 0xA4)
            #expect(pinSelectCommand.p1Parameter == 0x02)
            #expect(pinSelectCommand.p2Parameter == 0x0C)
            #expect(pinSelectCommand.data == Data([0x00, 0x1B]))
            
            let verifyCommand = mockTag.commandHistory[2].apdu
            #expect(verifyCommand.instructionClass == 0x00)
            #expect(verifyCommand.instructionCode == 0x20)
            #expect(verifyCommand.p1Parameter == 0x00)
            #expect(verifyCommand.p2Parameter == 0x80)
            
            let readCommand = mockTag.commandHistory[3].apdu
            #expect(readCommand.instructionClass == 0x00)
            #expect(readCommand.instructionCode == 0xA4)
        }
        
        @Test("Verify signature-specific file identifier")
        func testSignatureFileIdentifier() async throws {
            let reader = SignatureCertificateReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.mockResponses = [Data(), Data(), Data(), Data()]
            
            await confirmation("Signature file identifier verified") { confirm in
                reader.readCertificate(pin: "123456", nfcTag: mockTag, session: mockSession) { _, _ in
                    confirm()
                }
            }
            
            let pinSelectCommand = mockTag.commandHistory[1].apdu
            #expect(pinSelectCommand.data == Data([0x00, 0x1B]))
            #expect(pinSelectCommand.data != Data([0x00, 0x18]))
        }
    }
}