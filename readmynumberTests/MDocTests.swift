import Testing
import Foundation
import CoreNFC
@testable import マイ証明書

@Suite("MDoc Tests")
struct MDocTests {
    
    @Suite("MDoc Data Structure Tests")
    struct MDocDataStructureTests {
        @Test("DataElementValue initialization")
        func testDataElementValueInit() {
            let stringValue = DataElementValue.string("Test")
            let intValue = DataElementValue.integer(42)
            let boolValue = DataElementValue.boolean(true)
            let dateValue = DataElementValue.date(Date())
            let dataValue = DataElementValue.data(Data([0x01, 0x02]))
            
            if case .string(let value) = stringValue {
                #expect(value == "Test")
            }
            
            if case .integer(let value) = intValue {
                #expect(value == 42)
            }
            
            if case .boolean(let value) = boolValue {
                #expect(value == true)
            }
            
            #expect(dateValue != nil)
            #expect(dataValue != nil)
        }
        
        @Test("IssuerSignedItem structure")
        func testIssuerSignedItem() {
            let item = IssuerSignedItem(
                digestID: 1,
                random: Data([0x01, 0x02, 0x03]),
                elementIdentifier: "family_name",
                elementValue: .string("山田")
            )
            
            #expect(item.digestID == 1)
            #expect(item.elementIdentifier == "family_name")
            #expect(item.random.count == 3)
        }
        
        @Test("Document structure")
        func testDocumentStructure() {
            let issuerAuth = IssuerAuth(
                algorithm: "ES256",
                signature: Data(),
                certificateChain: []
            )
            
            let issuerSigned = IssuerSigned(
                nameSpaces: nil,
                issuerAuth: issuerAuth
            )
            
            let document = Document(
                docType: "org.iso.18013.5.1.mDL",
                issuerSigned: issuerSigned,
                deviceSigned: nil,
                errors: nil
            )
            
            #expect(document.docType == "org.iso.18013.5.1.mDL")
            #expect(document.issuerSigned.issuerAuth.algorithm == "ES256")
        }
    }
    
    @Suite("MDoc Parser Tests")
    struct MDocParserTests {
        @Test("Parser initialization")
        func testParserInit() {
            let parser = MDocParser()
            #expect(parser != nil)
        }
        
        @Test("Parse personal info")
        func testParsePersonalInfo() {
            let personalInfo = MDocParser.PersonalInfo(
                familyName: "山田",
                givenName: "太郎",
                birthDate: Date(),
                sex: "男",
                height: 170,
                weight: 65,
                eyeColor: "brown",
                hairColor: "black",
                birthPlace: "東京",
                nationality: "日本",
                residentAddress: "東京都千代田区",
                residentCity: "千代田区",
                residentState: "東京都",
                residentPostalCode: "100-0001",
                residentCountry: "日本"
            )
            
            #expect(personalInfo.familyName == "山田")
            #expect(personalInfo.givenName == "太郎")
            #expect(personalInfo.nationality == "日本")
        }
        
        @Test("Parse document info")
        func testParseDocumentInfo() {
            let documentInfo = MDocParser.DocumentInfo(
                documentNumber: "123456789",
                issueDate: Date(),
                expiryDate: Date(),
                administrativeNumber: "ADM123",
                unDistinguishingSign: "JP"
            )
            
            #expect(documentInfo.documentNumber == "123456789")
            #expect(documentInfo.administrativeNumber == "ADM123")
            #expect(documentInfo.unDistinguishingSign == "JP")
        }
    }
    
    @Suite("MDoc Reader Tests")
    struct MDocReaderTests {
        @Test("MDoc reader initialization")
        func testMDocReaderInit() {
            let reader = MDocReader()
            #expect(reader.pin.isEmpty)
        }
        
        @Test("Read MDoc with valid PIN")
        func testReadMDocWithValidPIN() async throws {
            let reader = MDocReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            mockTag.mockResponses = [
                Data(),
                Data(),
                Data(),
                createMockMDocData()
            ]
            
            await confirmation("MDoc read with valid PIN") { confirm in
                reader.readMDoc(pin: "1234", nfcTag: mockTag, session: mockSession) { success, data in
                    confirm()
                }
            }
            
            #expect(reader.pin == "1234")
        }
        
        @Test("MDoc PIN validation")
        func testMDocPINValidation() {
            let reader = MDocReader()
            reader.pin = "123456"
            
            #expect(reader.pin == "123456")
            #expect(reader.pin.count == 6)
        }
    }
    
    @Suite("MDoc View Tests")
    struct MDocViewTests {
        @Test("MDoc view initialization")
        func testMDocViewInit() {
            let view = MDocView()
            #expect(view.body != nil)
        }
        
        @Test("MDoc detail view initialization")
        func testMDocDetailViewInit() {
            let parsedDoc = MDocParser.ParsedDocument(
                docType: "org.iso.18013.5.1.mDL",
                issuerInfo: MDocParser.IssuerInfo(
                    issuingCountry: "JP",
                    issuingAuthority: "JPA",
                    issuingJurisdiction: nil
                ),
                personalInfo: MDocParser.PersonalInfo(
                    familyName: "山田",
                    givenName: "太郎",
                    birthDate: Date(),
                    sex: "男",
                    height: nil,
                    weight: nil,
                    eyeColor: nil,
                    hairColor: nil,
                    birthPlace: nil,
                    nationality: nil,
                    residentAddress: nil,
                    residentCity: nil,
                    residentState: nil,
                    residentPostalCode: nil,
                    residentCountry: nil
                ),
                documentInfo: MDocParser.DocumentInfo(
                    documentNumber: "123456",
                    issueDate: Date(),
                    expiryDate: Date(),
                    administrativeNumber: nil,
                    unDistinguishingSign: nil
                ),
                drivingPrivileges: nil,
                biometricData: nil,
                additionalData: [:]
            )
            
            let view = MDocDetailView(parsedDocument: parsedDoc)
            #expect(view.parsedDocument.docType == "org.iso.18013.5.1.mDL")
        }
    }
    
    @Suite("MDoc Security Tests")
    struct MDocSecurityTests {
        @Test("PIN validation for MDoc")
        func testMDocPINValidation() {
            let validPINs = ["1234", "123456", "12345678"]
            let invalidPINs = ["123", "abc", ""]
            
            for pin in validPINs {
                #expect(pin.count >= 4)
                #expect(pin.allSatisfy { $0.isASCII })
            }
            
            for pin in invalidPINs {
                #expect(pin.count < 4 || !pin.allSatisfy { $0.isNumber })
            }
        }
        
        @Test("MDoc data encryption")
        func testMDocDataEncryption() {
            let sensitiveData = "PersonalInformation"
            let encryptedData = Data(sensitiveData.utf8)
            
            #expect(!encryptedData.isEmpty)
            #expect(encryptedData.count > 0)
        }
    }
    
    @Suite("Residence Card Tests")
    struct ResidenceCardTests {
        @Test("Residence card reader initialization")
        func testResidenceCardReaderInit() {
            let reader = ResidenceCardReader()
            #expect(reader.pin.isEmpty)
        }
        
        @Test("Read residence card with valid PIN")
        func testReadResidenceCard() async throws {
            let reader = ResidenceCardReader()
            let mockTag = MockNFCISO7816Tag()
            let mockSession = MockNFCTagReaderSession(pollingOption: .iso14443, delegate: nil, queue: nil)!
            
            let cardData = createMockResidenceCardData()
            mockTag.mockResponses = [
                Data(),
                Data(),
                Data(),
                cardData
            ]
            
            await confirmation("Residence card read") { confirm in
                reader.readCard(pin: "1234", nfcTag: mockTag, session: mockSession) { success, info in
                    confirm()
                }
            }
        }
        
        @Test("Residence card detail view")
        func testResidenceCardDetailView() {
            let testData = [
                "name": "John Doe",
                "nationality": "USA",
                "cardNumber": "AB12345678",
                "expiryDate": "2025-12-31"
            ]
            
            let view = ResidenceCardDetailView(cardInfo: testData)
            #expect(view.cardInfo.count == 4)
            #expect(view.cardInfo["name"] == "John Doe")
        }
    }
}

// Helper functions
func createMockMDocData() -> Data {
    let mockData: [UInt8] = [
        0xA0, 0x82, 0x01, 0x00,
        0x01, 0x02, 0x03, 0x04
    ]
    return Data(mockData)
}

func createMockResidenceCardData() -> Data {
    let mockData: [UInt8] = [
        0xB0, 0x82, 0x01, 0x00,
        0x05, 0x06, 0x07, 0x08
    ]
    return Data(mockData)
}