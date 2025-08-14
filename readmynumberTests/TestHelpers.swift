import Testing
import Foundation
import CoreNFC
@testable import マイ証明書

// MARK: - Mock NFC Components

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

// MARK: - Test Expectation Helper

class TestExpectation {
    private var fulfilled = false
    private let lock = NSLock()
    
    func fulfill() {
        lock.lock()
        fulfilled = true
        lock.unlock()
    }
    
    func wait(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            if fulfilled {
                lock.unlock()
                return
            }
            lock.unlock()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw TestError.timeout
    }
}

enum TestError: Error {
    case timeout
}

// MARK: - Mock Data Generators

func createMockCertificateData() -> Data {
    let mockCert = """
    MIIEKjCCAxKgAwIBAgIJAMJ+QwRORz8ZMA0GCSqGSIb3DQEBCwUAMIGrMQswCQYD
    VQQGEwJKUDEOMAwGA1UECAwFVG9reW8xEDAOBgNVBAcMB1NoaW5qdWt1MRgwFgYD
    """
    return Data(base64Encoded: mockCert.replacingOccurrences(of: "\n", with: "")) ?? Data()
}

func createMockMyNumberData() -> Data {
    return "123456789012".data(using: .utf8) ?? Data()
}

func createMockBasicInfoData() -> [String: String] {
    return [
        "name": "山田太郎",
        "address": "東京都千代田区霞が関1-1-1",
        "birthdate": "1990年1月1日",
        "sex": "男"
    ]
}