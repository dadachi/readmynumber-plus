import Foundation

// Test file to verify address parsing functions
// This can be run in a Swift Playground or as a unit test

func testAddressParsing() {
    // Sample TLV data structure based on specification
    // Tag 0xD2 (追記書き込み年月日): "20240315" (2024年3月15日)
    // Tag 0xD3 (市町村コード): "131016" (東京都千代田区)
    // Tag 0xD4 (住居地): "東京都千代田区霞が関1-2-3"
    
    var testData = Data()
    
    // Add tag 0xD2 - 追記書き込み年月日
    testData.append(0xD2) // Tag
    testData.append(0x08) // Length
    testData.append("20240315".data(using: .ascii)!) // Value: YYYYMMDD
    
    // Add tag 0xD3 - 市町村コード
    testData.append(0xD3) // Tag
    testData.append(0x06) // Length
    testData.append("131016".data(using: .ascii)!) // Value: 6-digit code
    
    // Add tag 0xD4 - 住居地
    let address = "東京都千代田区霞が関1-2-3"
    let addressData = address.data(using: .utf8)!
    testData.append(0xD4) // Tag
    
    // Handle length encoding (if > 127 bytes, use extended format)
    if addressData.count <= 127 {
        testData.append(UInt8(addressData.count)) // Length
    } else {
        // Extended length format: 0x81 followed by actual length
        testData.append(0x81)
        testData.append(UInt8(addressData.count))
    }
    testData.append(addressData) // Value
    
    // Add padding to make it 320 bytes as per spec
    let paddingLength = 320 - addressData.count
    if paddingLength > 0 {
        testData.append(Data(repeating: 0x00, count: paddingLength))
    }
    
    print("Test Data Created:")
    print("Total length: \(testData.count) bytes")
    print("Hex: \(testData.map { String(format: "%02X", $0) }.prefix(50).joined(separator: " "))...")
    
    // Expected outputs:
    // 追記書き込み年月日: "2024年03月15日"
    // 市町村コード: "131016"
    // 住居地: "東京都千代田区霞が関1-2-3"
}

// Run the test
testAddressParsing()