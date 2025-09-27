import Foundation

protocol RootAuthenticationProvider {
    func performAuthentication(executor: RDCNFCCommandExecutor) async throws -> Data
}