import Foundation

protocol RootAuthenticationProvider {
    func performAuthentication(executor: NFCCommandExecutor) async throws -> Data
}