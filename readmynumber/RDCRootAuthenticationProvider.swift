import Foundation

protocol RDCRootAuthenticationProvider {
    func performAuthentication(executor: RDCNFCCommandExecutor) async throws -> Data
}