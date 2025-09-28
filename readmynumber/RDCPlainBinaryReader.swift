//
//  RDCPlainBinaryReader.swift
//  readmynumber
//
//  Created on 2025/09/09.
//

import Foundation
import CoreNFC

/// Handles plain (non-encrypted) READ BINARY operations
class RDCPlainBinaryReader {
    
    private let commandExecutor: RDCNFCCommandExecutor

    /// Initialize with an NFC command executor
    /// - Parameter commandExecutor: The executor for sending NFC commands
    init(commandExecutor: RDCNFCCommandExecutor) {
        self.commandExecutor = commandExecutor
    }
    
    /// Read binary data without encryption
    /// - Parameters:
    ///   - p1: Parameter 1 (offset high byte or file identifier)
    ///   - p2: Parameter 2 (offset low byte)
    /// - Returns: Plain binary data
    func readBinaryPlain(p1: UInt8, p2: UInt8 = 0x00) async throws -> Data {
        // Read entire file content with maximum response length
        // All residence card files fit within maxAPDUResponseLength bytes, so no chunking needed
        let command = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xB0, // READ BINARY
            p1Parameter: p1,
            p2Parameter: p2,
            data: Data(),
            expectedResponseLength: maxAPDUResponseLength
        )
        
        let (data, sw1, sw2) = try await commandExecutor.sendCommand(apdu: command)
        try checkStatusWord(sw1: sw1, sw2: sw2)
        
        return data
    }

    /// Check status words for errors
    private func checkStatusWord(sw1: UInt8, sw2: UInt8) throws {
        guard sw1 == 0x90 && sw2 == 0x00 else {
            throw RDCReaderError.cardError(sw1: sw1, sw2: sw2)
        }
    }
}
