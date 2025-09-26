import Foundation

protocol AuthenticationProvider {
    func generateKeys(from cardNumber: String) throws -> (kEnc: Data, kMac: Data)
}