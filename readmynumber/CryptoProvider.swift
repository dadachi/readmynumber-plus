import Foundation
import CommonCrypto

protocol CryptoProvider {
    func calculateRetailMAC(data: Data, key: Data) throws -> Data
}

class CryptoProviderImpl: CryptoProvider {
    enum CryptoError: Error, LocalizedError {
        case invalidKeyLength(String)
        case invalidDataLength(String)
        case operationFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidKeyLength(let message):
                return message
            case .invalidDataLength(let message):
                return message
            case .operationFailed(let message):
                return message
            }
        }
    }

    func calculateRetailMAC(data: Data, key: Data) throws -> Data {
        guard key.count == 16 else {
            throw CryptoError.invalidKeyLength("Invalid key length for Retail MAC")
        }

        // ISO/IEC 9797-1 Padding Method 2: Add 0x80 followed by 0x00s
        var paddedData = data
        paddedData.append(0x80)
        while paddedData.count % 8 != 0 {
            paddedData.append(0x00)
        }

        // Split the key for DES operations
        let k1 = key.prefix(8)
        let k2 = key.suffix(8)

        // Process data in 8-byte blocks
        let numBlocks = paddedData.count / 8
        var mac = Data(repeating: 0, count: 8) // Initialize with zeros (IV)

        for i in 0..<numBlocks {
            let blockStart = i * 8
            let block = paddedData.subdata(in: blockStart..<(blockStart + 8))

            // XOR with previous MAC result (CBC mode)
            let xorBlock = Data(zip(block, mac).map { $0 ^ $1 })

            if i < numBlocks - 1 {
                // Initial transformation: Single DES with K1 for all blocks except the last
                mac = try performSingleDES(data: xorBlock, key: k1, encrypt: true)
            } else {
                // Final transformation: Triple DES for the last block
                // DES-EDE3: Encrypt with K1, Decrypt with K2, Encrypt with K1
                let step1 = try performSingleDES(data: xorBlock, key: k1, encrypt: true)
                let step2 = try performSingleDES(data: step1, key: k2, encrypt: false)
                mac = try performSingleDES(data: step2, key: k1, encrypt: true)
            }
        }

        return mac
    }

    private func performSingleDES(data: Data, key: Data, encrypt: Bool) throws -> Data {
        guard key.count == 8 && data.count == 8 else {
            throw CryptoError.invalidDataLength("Invalid data or key length for single DES")
        }

        var result = Data(repeating: 0, count: 8)
        var numBytesProcessed: size_t = 0

        let status = result.withUnsafeMutableBytes { resultBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmDES),
                        CCOptions(kCCOptionECBMode), // ECB mode for single block
                        keyBytes.bindMemory(to: UInt8.self).baseAddress, kCCKeySizeDES,
                        nil, // No IV for ECB mode
                        dataBytes.bindMemory(to: UInt8.self).baseAddress, 8,
                        resultBytes.bindMemory(to: UInt8.self).baseAddress, 8,
                        &numBytesProcessed
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw CryptoError.operationFailed("Single DES operation failed")
        }

        return result
    }
}