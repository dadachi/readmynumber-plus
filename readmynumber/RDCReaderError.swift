//
//  RDCReaderError.swift
//  readmynumber
//
//  Created on 2025/09/28.
//

import Foundation

/// Error types for residence card reader operations
enum RDCReaderError: LocalizedError, Equatable {
    case nfcNotAvailable
    case invalidCardNumber
    case invalidCardNumberFormat
    case invalidCardNumberLength
    case invalidCardNumberCharacters
    case invalidResponse
    case cardError(sw1: UInt8, sw2: UInt8)
    case cryptographyError(String)

    var errorDescription: String? {
        switch self {
        case .nfcNotAvailable:
            return "NFCが利用できません"
        case .invalidCardNumber:
            return "無効な在留カード番号です"
        case .invalidCardNumberFormat:
            return "在留カード番号の形式が正しくありません（英字2桁+数字8桁+英字2桁）"
        case .invalidCardNumberLength:
            return "在留カード番号は12桁で入力してください"
        case .invalidCardNumberCharacters:
            return "在留カード番号に無効な文字が含まれています"
        case .invalidResponse:
            return "カードからの応答が不正です"
        case .cardError(let sw1, let sw2):
            return String(format: "カードエラー: SW1=%02X, SW2=%02X", sw1, sw2)
        case .cryptographyError(let message):
            return "暗号処理エラー: \(message)"
        }
    }
}
