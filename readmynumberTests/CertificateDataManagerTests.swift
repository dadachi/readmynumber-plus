import Testing
import Foundation
@testable import マイ証明書

@Suite("CertificateDataManager Tests", .serialized)
struct CertificateDataManagerTests {
    
    @Suite("Initialization Tests")
    struct InitializationTests {
        @Test("Manager should be singleton")
        func testSingleton() {
            let instance1 = CertificateDataManager.shared
            let instance2 = CertificateDataManager.shared
            #expect(instance1 === instance2)
        }
        
        @Test("Initial values should be empty")
        func testInitialValues() {
            let manager = CertificateDataManager.shared
            manager.clearAllData()
            
            #expect(manager.signatureCertificateBase64.isEmpty)
            #expect(manager.authenticationCertificateBase64.isEmpty)
            #expect(manager.myNumber.isEmpty)
            #expect(manager.basicInfo.isEmpty)
            #expect(manager.shouldNavigateToDetail == false)
        }
    }
    
    @Suite("Certificate Data Management")
    struct CertificateDataTests {
        let manager = CertificateDataManager.shared
        
        @Test("Setting signature certificate data")
        func testSetSignatureCertificateData() {
            manager.clearAllData()
            let testBase64 = "testSignatureBase64Data"
            
            manager.setSignatureCertificateData(testBase64)
            
            #expect(manager.signatureCertificateBase64 == testBase64)
            #expect(manager.isAuthenticationMode == false)
            #expect(manager.shouldNavigateToDetail == true)
        }
        
        @Test("Setting authentication certificate data")
        func testSetAuthenticationCertificateData() {
            manager.clearAllData()
            let testBase64 = "testAuthenticationBase64Data"
            
            manager.setAuthenticationCertificateData(testBase64)
            
            #expect(manager.authenticationCertificateBase64 == testBase64)
            #expect(manager.isAuthenticationMode == true)
            #expect(manager.shouldNavigateToDetail == true)
        }
        
        @Test("Resetting navigation state")
        func testResetNavigation() {
            manager.setAuthenticationCertificateData("test")
            #expect(manager.shouldNavigateToDetail == true)
            
            manager.resetNavigation()
            
            #expect(manager.shouldNavigateToDetail == false)
        }
    }
    
    @Suite("UserDefaults Integration", .serialized)
    struct UserDefaultsTests {
        let manager = CertificateDataManager.shared
        let userDefaults = UserDefaults.standard
        
        @Test("Loading MyNumber from UserDefaults via notification")
        func testMyNumberNotificationLoading() async throws {
            manager.clearAllData()
            let testMyNumber = "123456789012"
            
            userDefaults.set(testMyNumber, forKey: "MyNumber")
            
            NotificationCenter.default.post(name: Notification.Name("MyNumberDidLoad"), object: nil)
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(manager.myNumber == testMyNumber)
            
            userDefaults.removeObject(forKey: "MyNumber")
        }
        
        @Test("Loading BasicInfo from UserDefaults via notification")
        func testBasicInfoNotificationLoading() async throws {
            manager.clearAllData()
            let testBasicInfo = [
                "name": "Test User",
                "address": "Test Address",
                "birthdate": "2000-01-01"
            ]
            
            userDefaults.set(testBasicInfo, forKey: "BasicInfo")
            
            NotificationCenter.default.post(name: Notification.Name("BasicInfoDidLoad"), object: nil)
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(manager.basicInfo == testBasicInfo)
            
            userDefaults.removeObject(forKey: "BasicInfo")
        }
    }
    
    @Suite("Data Clearing")
    struct DataClearingTests {
        let manager = CertificateDataManager.shared
        let userDefaults = UserDefaults.standard
        
        @Test("Clear all data should reset all properties")
        func testClearAllData() {
            manager.signatureCertificateBase64 = "signature"
            manager.authenticationCertificateBase64 = "auth"
            manager.myNumber = "123456789012"
            manager.basicInfo = ["key": "value"]
            
            userDefaults.set("123456789012", forKey: "MyNumber")
            userDefaults.set(["key": "value"], forKey: "BasicInfo")
            
            manager.clearAllData()
            
            #expect(manager.signatureCertificateBase64.isEmpty)
            #expect(manager.authenticationCertificateBase64.isEmpty)
            #expect(manager.myNumber.isEmpty)
            #expect(manager.basicInfo.isEmpty)
            #expect(userDefaults.string(forKey: "MyNumber") == nil)
            #expect(userDefaults.dictionary(forKey: "BasicInfo") == nil)
        }
    }
    
    @Suite("Edge Cases")
    struct EdgeCaseTests {
        let manager = CertificateDataManager.shared
        
        @Test("Setting empty certificate data")
        func testEmptyCertificateData() {
            manager.clearAllData()
            
            manager.setSignatureCertificateData("")
            #expect(manager.signatureCertificateBase64.isEmpty)
            #expect(manager.shouldNavigateToDetail == true)
            
            manager.setAuthenticationCertificateData("")
            #expect(manager.authenticationCertificateBase64.isEmpty)
            #expect(manager.shouldNavigateToDetail == true)
        }
        
        @Test("Multiple rapid certificate updates")
        func testRapidCertificateUpdates() {
            manager.clearAllData()
            
            for i in 1...10 {
                let data = "data\(i)"
                if i % 2 == 0 {
                    manager.setSignatureCertificateData(data)
                    #expect(manager.isAuthenticationMode == false)
                } else {
                    manager.setAuthenticationCertificateData(data)
                    #expect(manager.isAuthenticationMode == true)
                }
            }
            
            #expect(manager.authenticationCertificateBase64 == "data9")
            #expect(manager.isAuthenticationMode == true)
        }
        
        @Test("Special characters in data")
        func testSpecialCharacters() {
            manager.clearAllData()
            let specialData = "日本語テスト🔐📱"
            let specialInfo = [
                "名前": "田中太郎",
                "住所": "東京都渋谷区",
                "生年月日": "令和2年1月1日"
            ]
            
            manager.setSignatureCertificateData(specialData)
            manager.basicInfo = specialInfo
            
            #expect(manager.signatureCertificateBase64 == specialData)
            #expect(manager.basicInfo == specialInfo)
        }
    }
    
    @Suite("Thread Safety", .serialized)
    struct ThreadSafetyTests {
        let manager = CertificateDataManager.shared
        
        @Test("Concurrent access to certificate data")
        func testConcurrentAccess() async throws {
            manager.clearAllData()
            
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<100 {
                    group.addTask {
                        if i % 2 == 0 {
                            self.manager.setSignatureCertificateData("sig\(i)")
                        } else {
                            self.manager.setAuthenticationCertificateData("auth\(i)")
                        }
                    }
                }
            }
            
            #expect(!manager.signatureCertificateBase64.isEmpty || !manager.authenticationCertificateBase64.isEmpty)
            #expect(manager.shouldNavigateToDetail == true)
        }
    }
}