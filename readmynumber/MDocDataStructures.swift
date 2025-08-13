//
//  MDocDataStructures.swift
//  readmynumber
//
//  M-Doc (ISO/IEC 18013-5:2021) Data Structures
//

import Foundation
import CryptoKit
import CoreBluetooth

// MARK: - M-Doc Core Structures

/// Device Response structure for M-Doc
struct DeviceResponse: Codable {
    let version: String
    let documents: [Document]?
    let documentErrors: [DocumentError]?
    let status: Int
    
    enum CodingKeys: String, CodingKey {
        case version
        case documents
        case documentErrors
        case status
    }
}

/// Document structure containing issuer-signed and device-signed data
struct Document: Codable {
    let docType: String
    let issuerSigned: IssuerSigned
    let deviceSigned: DeviceSigned?
    let errors: DocumentErrors?
    
    enum CodingKeys: String, CodingKey {
        case docType
        case issuerSigned
        case deviceSigned
        case errors
    }
}

/// Issuer-signed data structure
struct IssuerSigned: Codable {
    let nameSpaces: IssuerNameSpaces?
    let issuerAuth: IssuerAuth
    
    enum CodingKeys: String, CodingKey {
        case nameSpaces
        case issuerAuth
    }
}

/// Issuer name spaces containing signed data elements
struct IssuerNameSpaces: Codable {
    let nameSpaces: [String: [IssuerSignedItem]]
    
    init(nameSpaces: [String: [IssuerSignedItem]]) {
        self.nameSpaces = nameSpaces
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        nameSpaces = try container.decode([String: [IssuerSignedItem]].self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(nameSpaces)
    }
}

/// Individual signed item in issuer namespace
struct IssuerSignedItem: Codable {
    let digestID: UInt64
    let random: Data
    let elementIdentifier: String
    let elementValue: DataElementValue
    
    enum CodingKeys: String, CodingKey {
        case digestID
        case random
        case elementIdentifier
        case elementValue
    }
}

/// Data element value (can be various types)
enum DataElementValue: Codable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case date(Date)
    case data(Data)
    case dictionary([String: DataElementValue])
    case array([DataElementValue])
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .integer(intValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .boolean(boolValue)
        } else if let dateValue = try? container.decode(Date.self) {
            self = .date(dateValue)
        } else if let dataValue = try? container.decode(Data.self) {
            self = .data(dataValue)
        } else if let dictValue = try? container.decode([String: DataElementValue].self) {
            self = .dictionary(dictValue)
        } else if let arrayValue = try? container.decode([DataElementValue].self) {
            self = .array(arrayValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode DataElementValue")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .date(let value):
            try container.encode(value)
        case .data(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        }
    }
}

/// Issuer authentication data (COSE_Sign1)
struct IssuerAuth: Codable {
    let algorithm: String
    let signature: Data
    let certificateChain: [Data]
}

/// Device-signed data structure
struct DeviceSigned: Codable {
    let nameSpaces: DeviceNameSpaces
    let deviceAuth: DeviceAuth
}

/// Device name spaces
struct DeviceNameSpaces: Codable {
    let nameSpaces: [String: [String: DataElementValue]]
}

/// Device authentication
struct DeviceAuth: Codable {
    let deviceSignature: Data?
    let deviceMac: Data?
}

/// Document errors
struct DocumentErrors: Codable {
    let errors: [String: String]
}

/// Document error structure
struct DocumentError: Codable {
    let docType: String
    let errorCode: Int
    let errorMessage: String
}

// MARK: - Device Engagement

/// Device Engagement structure for QR code or NFC
struct DeviceEngagement: Codable {
    let version: String
    let security: SecurityInfo
    let deviceRetrievalMethods: [DeviceRetrievalMethod]
    let serverRetrievalMethods: [ServerRetrievalMethod]?
    let protocolInfo: ProtocolInfo?
    
    enum CodingKeys: String, CodingKey {
        case version = "0"
        case security = "1"
        case deviceRetrievalMethods = "2"
        case serverRetrievalMethods = "3"
        case protocolInfo = "4"
    }
}

/// Security information for device engagement
struct SecurityInfo: Codable {
    let cipherSuiteIdentifier: Int
    let eSenderKeyBytes: Data
    
    enum CodingKeys: String, CodingKey {
        case cipherSuiteIdentifier = "0"
        case eSenderKeyBytes = "1"
    }
}

/// Device retrieval method (BLE, NFC, etc.)
struct DeviceRetrievalMethod: Codable {
    let type: Int // 1 = NFC, 2 = BLE
    let version: Int
    let retrievalOptions: RetrievalOptions
    
    enum CodingKeys: String, CodingKey {
        case type = "0"
        case version = "1"
        case retrievalOptions = "2"
    }
}

/// Retrieval options for different transport methods
enum RetrievalOptions: Codable {
    case ble(BLEOptions)
    case nfc(NFCOptions)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bleOptions = try? container.decode(BLEOptions.self) {
            self = .ble(bleOptions)
        } else if let nfcOptions = try? container.decode(NFCOptions.self) {
            self = .nfc(nfcOptions)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode RetrievalOptions")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .ble(let options):
            try container.encode(options)
        case .nfc(let options):
            try container.encode(options)
        }
    }
}

/// BLE-specific options
struct BLEOptions: Codable {
    let supportPeripheralServerMode: Bool
    let supportCentralClientMode: Bool
    let peripheralServerModeUUID: UUID?
    let centralClientModeUUID: UUID?
    let peripheralServerDeviceAddress: Data?
    let centralClientDeviceAddress: Data?
    
    enum CodingKeys: String, CodingKey {
        case supportPeripheralServerMode = "0"
        case supportCentralClientMode = "1"
        case peripheralServerModeUUID = "10"
        case centralClientModeUUID = "11"
        case peripheralServerDeviceAddress = "20"
        case centralClientDeviceAddress = "21"
    }
}

/// NFC-specific options
struct NFCOptions: Codable {
    let maxAPDUResponseSize: Int
    let requiresSelectCommand: Bool
    
    enum CodingKeys: String, CodingKey {
        case maxAPDUResponseSize = "0"
        case requiresSelectCommand = "1"
    }
}

/// Server retrieval method
struct ServerRetrievalMethod: Codable {
    let webAPIEndpoint: String
    let token: String?
}

/// Protocol information
struct ProtocolInfo: Codable {
    let messageVersion: String
}

// MARK: - Device Request

/// Device Request structure for requesting specific data elements
struct DeviceRequest: Codable {
    let version: String
    let docRequests: [DocRequest]
    
    enum CodingKeys: String, CodingKey {
        case version
        case docRequests
    }
}

/// Document request for specific data elements
struct DocRequest: Codable {
    let itemsRequest: ItemsRequest
    let readerAuth: ReaderAuth?
    
    enum CodingKeys: String, CodingKey {
        case itemsRequest
        case readerAuth
    }
}

/// Items request structure
struct ItemsRequest: Codable {
    let docType: String
    let nameSpaces: [String: [String: Bool]]
    let requestInfo: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case docType
        case nameSpaces
        case requestInfo
    }
}

/// Reader authentication
struct ReaderAuth: Codable {
    let readerCertificateChain: [Data]
    let readerSignature: Data
}

// MARK: - Session Management

/// Session encryption for secure data transfer
struct SessionEncryption {
    let sessionEstablishmentObject: Data
    let deviceEngagementObject: Data
    let handOverObject: Data
    
    func decrypt(_ data: Data) throws -> Data {
        // Implementation would decrypt session data using established keys
        // This is a placeholder for the actual ECDH and AES-GCM implementation
        return data
    }
}

/// M-Doc Authentication structure
struct MDocAuthentication {
    let transcript: SessionTranscript
    let authKeys: [Data]
    
    func getDeviceAuthForTransfer(docType: String, deviceNameSpacesRawData: Data, bUseDeviceSign: Bool) throws -> DeviceAuth {
        // Implementation for device authentication
        return DeviceAuth(deviceSignature: nil, deviceMac: nil)
    }
}

/// Session transcript for authentication
struct SessionTranscript: Codable {
    let deviceEngagementBytes: Data?
    let eReaderKeyBytes: Data?
    let handover: Data
}

// MARK: - Common M-Doc Types

/// Mobile Driver's License specific namespace
struct MobileDrivingLicense {
    static let docType = "org.iso.18013.5.1.mDL"
    
    static let isoMdlNamespace = "org.iso.18013.5.1"
    
    static let isoMdlDataElements = [
        "family_name",
        "given_name",
        "birth_date",
        "issue_date",
        "expiry_date",
        "issuing_country",
        "issuing_authority",
        "document_number",
        "portrait",
        "driving_privileges",
        "un_distinguishing_sign",
        "administrative_number",
        "sex",
        "height",
        "weight",
        "eye_colour",
        "hair_colour",
        "birth_place",
        "resident_address",
        "portrait_capture_date",
        "age_in_years",
        "age_birth_year",
        "age_over_18",
        "age_over_21",
        "issuing_jurisdiction",
        "nationality",
        "resident_city",
        "resident_state",
        "resident_postal_code",
        "resident_country",
        "family_name_national_character",
        "given_name_national_character",
        "signature_usual_mark"
    ]
}

// MARK: - Error Types

enum MDocError: LocalizedError {
    case invalidFormat
    case unsupportedVersion
    case authenticationFailed
    case decryptionFailed
    case invalidCBOR
    case invalidCOSE
    case certificateValidationFailed
    case sessionEstablishmentFailed
    case bluetoothUnavailable
    case nfcUnavailable
    case qrCodeInvalid
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "M-Docフォーマットが無効です"
        case .unsupportedVersion:
            return "サポートされていないM-Docバージョンです"
        case .authenticationFailed:
            return "認証に失敗しました"
        case .decryptionFailed:
            return "データの復号化に失敗しました"
        case .invalidCBOR:
            return "CBORデータが無効です"
        case .invalidCOSE:
            return "COSE署名が無効です"
        case .certificateValidationFailed:
            return "証明書の検証に失敗しました"
        case .sessionEstablishmentFailed:
            return "セッション確立に失敗しました"
        case .bluetoothUnavailable:
            return "Bluetoothが利用できません"
        case .nfcUnavailable:
            return "NFCが利用できません"
        case .qrCodeInvalid:
            return "QRコードが無効です"
        }
    }
}