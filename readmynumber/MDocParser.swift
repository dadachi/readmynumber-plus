//
//  MDocParser.swift
//  readmynumber
//
//  M-Doc Parser and Data Processor
//

import Foundation
import UIKit

// MARK: - M-Doc Parser

/// Parser for M-Doc data elements
class MDocParser {
    
    // MARK: - Parsed Document Structure
    
    struct ParsedDocument {
        let docType: String
        let issuerInfo: IssuerInfo
        let personalInfo: PersonalInfo
        let documentInfo: DocumentInfo
        let drivingPrivileges: [DrivingPrivilege]?
        let biometricData: BiometricData?
        let additionalData: [String: String]
    }
    
    struct IssuerInfo {
        let issuingCountry: String
        let issuingAuthority: String
        let issuingJurisdiction: String?
    }
    
    struct PersonalInfo {
        let familyName: String
        let givenName: String
        let birthDate: Date
        let sex: String?
        let height: Int?
        let weight: Int?
        let eyeColor: String?
        let hairColor: String?
        let birthPlace: String?
        let nationality: String?
        let residentAddress: String?
        let residentCity: String?
        let residentState: String?
        let residentPostalCode: String?
        let residentCountry: String?
    }
    
    struct DocumentInfo {
        let documentNumber: String
        let issueDate: Date
        let expiryDate: Date
        let administrativeNumber: String?
        let unDistinguishingSign: String?
    }
    
    struct DrivingPrivilege {
        let vehicleCategoryCode: String
        let issueDate: Date?
        let expiryDate: Date?
        let codes: [String]?
        let sign: String?
        let value: String?
    }
    
    struct BiometricData {
        let portrait: UIImage?
        let portraitCaptureDate: Date?
        let signatureOrUsualMark: UIImage?
        let fingerprints: [Data]?
    }
    
    // MARK: - Parsing Methods
    
    /// Parse M-Doc document into structured data
    static func parse(_ document: Document) -> ParsedDocument? {
        guard let nameSpaces = document.issuerSigned.nameSpaces?.nameSpaces else {
            return nil
        }
        
        // Extract data from the appropriate namespace
        let mdlNamespace = nameSpaces[MobileDrivingLicense.isoMdlNamespace] ?? []
        
        // Parse issuer information
        let issuerInfo = parseIssuerInfo(from: mdlNamespace)
        
        // Parse personal information
        let personalInfo = parsePersonalInfo(from: mdlNamespace)
        
        // Parse document information
        let documentInfo = parseDocumentInfo(from: mdlNamespace)
        
        // Parse driving privileges if available
        let drivingPrivileges = parseDrivingPrivileges(from: mdlNamespace)
        
        // Parse biometric data
        let biometricData = parseBiometricData(from: mdlNamespace)
        
        // Parse additional data
        let additionalData = parseAdditionalData(from: mdlNamespace)
        
        guard let issuerInfo = issuerInfo,
              let personalInfo = personalInfo,
              let documentInfo = documentInfo else {
            return nil
        }
        
        return ParsedDocument(
            docType: document.docType,
            issuerInfo: issuerInfo,
            personalInfo: personalInfo,
            documentInfo: documentInfo,
            drivingPrivileges: drivingPrivileges,
            biometricData: biometricData,
            additionalData: additionalData
        )
    }
    
    // MARK: - Private Parsing Methods
    
    private static func parseIssuerInfo(from items: [IssuerSignedItem]) -> IssuerInfo? {
        var issuingCountry: String?
        var issuingAuthority: String?
        var issuingJurisdiction: String?
        
        for item in items {
            switch item.elementIdentifier {
            case "issuing_country":
                if case .string(let value) = item.elementValue {
                    issuingCountry = value
                }
            case "issuing_authority":
                if case .string(let value) = item.elementValue {
                    issuingAuthority = value
                }
            case "issuing_jurisdiction":
                if case .string(let value) = item.elementValue {
                    issuingJurisdiction = value
                }
            default:
                break
            }
        }
        
        guard let country = issuingCountry,
              let authority = issuingAuthority else {
            return nil
        }
        
        return IssuerInfo(
            issuingCountry: country,
            issuingAuthority: authority,
            issuingJurisdiction: issuingJurisdiction
        )
    }
    
    private static func parsePersonalInfo(from items: [IssuerSignedItem]) -> PersonalInfo? {
        var familyName: String?
        var givenName: String?
        var birthDate: Date?
        var sex: String?
        var height: Int?
        var weight: Int?
        var eyeColor: String?
        var hairColor: String?
        var birthPlace: String?
        var nationality: String?
        var residentAddress: String?
        var residentCity: String?
        var residentState: String?
        var residentPostalCode: String?
        var residentCountry: String?
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        
        for item in items {
            switch item.elementIdentifier {
            case "family_name":
                if case .string(let value) = item.elementValue {
                    familyName = value
                }
            case "given_name":
                if case .string(let value) = item.elementValue {
                    givenName = value
                }
            case "birth_date":
                if case .string(let value) = item.elementValue {
                    birthDate = dateFormatter.date(from: value)
                } else if case .date(let value) = item.elementValue {
                    birthDate = value
                }
            case "sex":
                if case .string(let value) = item.elementValue {
                    sex = value
                }
            case "height":
                if case .integer(let value) = item.elementValue {
                    height = value
                }
            case "weight":
                if case .integer(let value) = item.elementValue {
                    weight = value
                }
            case "eye_colour":
                if case .string(let value) = item.elementValue {
                    eyeColor = value
                }
            case "hair_colour":
                if case .string(let value) = item.elementValue {
                    hairColor = value
                }
            case "birth_place":
                if case .string(let value) = item.elementValue {
                    birthPlace = value
                }
            case "nationality":
                if case .string(let value) = item.elementValue {
                    nationality = value
                }
            case "resident_address":
                if case .string(let value) = item.elementValue {
                    residentAddress = value
                }
            case "resident_city":
                if case .string(let value) = item.elementValue {
                    residentCity = value
                }
            case "resident_state":
                if case .string(let value) = item.elementValue {
                    residentState = value
                }
            case "resident_postal_code":
                if case .string(let value) = item.elementValue {
                    residentPostalCode = value
                }
            case "resident_country":
                if case .string(let value) = item.elementValue {
                    residentCountry = value
                }
            default:
                break
            }
        }
        
        guard let family = familyName,
              let given = givenName,
              let birth = birthDate else {
            return nil
        }
        
        return PersonalInfo(
            familyName: family,
            givenName: given,
            birthDate: birth,
            sex: sex,
            height: height,
            weight: weight,
            eyeColor: eyeColor,
            hairColor: hairColor,
            birthPlace: birthPlace,
            nationality: nationality,
            residentAddress: residentAddress,
            residentCity: residentCity,
            residentState: residentState,
            residentPostalCode: residentPostalCode,
            residentCountry: residentCountry
        )
    }
    
    private static func parseDocumentInfo(from items: [IssuerSignedItem]) -> DocumentInfo? {
        var documentNumber: String?
        var issueDate: Date?
        var expiryDate: Date?
        var administrativeNumber: String?
        var unDistinguishingSign: String?
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        
        for item in items {
            switch item.elementIdentifier {
            case "document_number":
                if case .string(let value) = item.elementValue {
                    documentNumber = value
                }
            case "issue_date":
                if case .string(let value) = item.elementValue {
                    issueDate = dateFormatter.date(from: value)
                } else if case .date(let value) = item.elementValue {
                    issueDate = value
                }
            case "expiry_date":
                if case .string(let value) = item.elementValue {
                    expiryDate = dateFormatter.date(from: value)
                } else if case .date(let value) = item.elementValue {
                    expiryDate = value
                }
            case "administrative_number":
                if case .string(let value) = item.elementValue {
                    administrativeNumber = value
                }
            case "un_distinguishing_sign":
                if case .string(let value) = item.elementValue {
                    unDistinguishingSign = value
                }
            default:
                break
            }
        }
        
        guard let number = documentNumber,
              let issue = issueDate,
              let expiry = expiryDate else {
            return nil
        }
        
        return DocumentInfo(
            documentNumber: number,
            issueDate: issue,
            expiryDate: expiry,
            administrativeNumber: administrativeNumber,
            unDistinguishingSign: unDistinguishingSign
        )
    }
    
    private static func parseDrivingPrivileges(from items: [IssuerSignedItem]) -> [DrivingPrivilege]? {
        for item in items {
            if item.elementIdentifier == "driving_privileges" {
                if case .array(let privilegesArray) = item.elementValue {
                    var privileges: [DrivingPrivilege] = []
                    
                    for privilegeValue in privilegesArray {
                        if case .dictionary(let privilegeDict) = privilegeValue {
                            var vehicleCategoryCode: String?
                            var issueDate: Date?
                            var expiryDate: Date?
                            var codes: [String]?
                            
                            let dateFormatter = ISO8601DateFormatter()
                            dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
                            
                            for (key, value) in privilegeDict {
                                switch key {
                                case "vehicle_category_code":
                                    if case .string(let code) = value {
                                        vehicleCategoryCode = code
                                    }
                                case "issue_date":
                                    if case .string(let dateStr) = value {
                                        issueDate = dateFormatter.date(from: dateStr)
                                    } else if case .date(let date) = value {
                                        issueDate = date
                                    }
                                case "expiry_date":
                                    if case .string(let dateStr) = value {
                                        expiryDate = dateFormatter.date(from: dateStr)
                                    } else if case .date(let date) = value {
                                        expiryDate = date
                                    }
                                case "codes":
                                    if case .array(let codesArray) = value {
                                        codes = codesArray.compactMap {
                                            if case .string(let code) = $0 { return code }
                                            return nil
                                        }
                                    }
                                default:
                                    break
                                }
                            }
                            
                            if let categoryCode = vehicleCategoryCode {
                                let privilege = DrivingPrivilege(
                                    vehicleCategoryCode: categoryCode,
                                    issueDate: issueDate,
                                    expiryDate: expiryDate,
                                    codes: codes,
                                    sign: nil,
                                    value: nil
                                )
                                privileges.append(privilege)
                            }
                        }
                    }
                    
                    return privileges.isEmpty ? nil : privileges
                }
            }
        }
        
        return nil
    }
    
    private static func parseBiometricData(from items: [IssuerSignedItem]) -> BiometricData? {
        var portrait: UIImage?
        var portraitCaptureDate: Date?
        var signatureOrUsualMark: UIImage?
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        
        for item in items {
            switch item.elementIdentifier {
            case "portrait":
                if case .data(let imageData) = item.elementValue {
                    portrait = UIImage(data: imageData)
                }
            case "portrait_capture_date":
                if case .string(let value) = item.elementValue {
                    portraitCaptureDate = dateFormatter.date(from: value)
                } else if case .date(let value) = item.elementValue {
                    portraitCaptureDate = value
                }
            case "signature_usual_mark":
                if case .data(let imageData) = item.elementValue {
                    signatureOrUsualMark = UIImage(data: imageData)
                }
            default:
                break
            }
        }
        
        if portrait != nil || signatureOrUsualMark != nil {
            return BiometricData(
                portrait: portrait,
                portraitCaptureDate: portraitCaptureDate,
                signatureOrUsualMark: signatureOrUsualMark,
                fingerprints: nil
            )
        }
        
        return nil
    }
    
    private static func parseAdditionalData(from items: [IssuerSignedItem]) -> [String: String] {
        var additionalData: [String: String] = [:]
        
        // Known M-Doc elements that we haven't parsed into specific structures
        let knownElements = Set(MobileDrivingLicense.isoMdlDataElements)
        let parsedElements = Set([
            "family_name", "given_name", "birth_date", "sex", "height", "weight",
            "eye_colour", "hair_colour", "birth_place", "nationality",
            "resident_address", "resident_city", "resident_state",
            "resident_postal_code", "resident_country",
            "document_number", "issue_date", "expiry_date",
            "administrative_number", "un_distinguishing_sign",
            "issuing_country", "issuing_authority", "issuing_jurisdiction",
            "driving_privileges", "portrait", "portrait_capture_date",
            "signature_usual_mark"
        ])
        
        for item in items {
            if knownElements.contains(item.elementIdentifier) &&
               !parsedElements.contains(item.elementIdentifier) {
                switch item.elementValue {
                case .string(let value):
                    additionalData[item.elementIdentifier] = value
                case .integer(let value):
                    additionalData[item.elementIdentifier] = String(value)
                case .boolean(let value):
                    additionalData[item.elementIdentifier] = value ? "true" : "false"
                case .date(let value):
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    additionalData[item.elementIdentifier] = formatter.string(from: value)
                default:
                    break
                }
            }
        }
        
        return additionalData
    }
    
    // MARK: - Utility Methods
    
    /// Format date for display
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    /// Calculate age from birth date
    static func calculateAge(from birthDate: Date) -> Int {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birthDate, to: Date())
        return ageComponents.year ?? 0
    }
    
    /// Check if document is expired
    static func isExpired(_ expiryDate: Date) -> Bool {
        return expiryDate < Date()
    }
}