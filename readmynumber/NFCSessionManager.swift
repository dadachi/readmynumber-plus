//
//  NFCSessionManager.swift
//  readmynumber
//
//  Created on 2025/09/09.
//

import Foundation
import CoreNFC

/// Protocol for managing NFC tag reader sessions
protocol NFCSessionManager {
    /// Start an NFC reading session
    /// - Parameters:
    ///   - pollingOption: The NFC polling option
    ///   - delegate: The session delegate
    ///   - alertMessage: Message to show to the user
    func startSession(
        pollingOption: NFCTagReaderSession.PollingOption,
        delegate: NFCTagReaderSessionDelegate,
        alertMessage: String
    )
    
    /// Connect to an NFC tag
    /// - Parameter tag: The NFC tag to connect to
    func connect(to tag: NFCTag) async throws
    
    /// Invalidate the session
    func invalidate()
    
    /// Invalidate the session with an error message
    /// - Parameter errorMessage: Error message to display
    func invalidate(errorMessage: String)
    
    /// Check if NFC reading is available
    var isReadingAvailable: Bool { get }
}

/// Concrete implementation of NFCSessionManager
class NFCSessionManagerImpl: NFCSessionManager {
    private var session: NFCTagReaderSession?
    
    var isReadingAvailable: Bool {
        return NFCTagReaderSession.readingAvailable
    }
    
    func startSession(
        pollingOption: NFCTagReaderSession.PollingOption,
        delegate: NFCTagReaderSessionDelegate,
        alertMessage: String
    ) {
        session = NFCTagReaderSession(pollingOption: pollingOption, delegate: delegate)
        session?.alertMessage = alertMessage
        session?.begin()
    }
    
    func connect(to tag: NFCTag) async throws {
        guard let session = session else {
            throw NFCSessionError.noActiveSession
        }
        try await session.connect(to: tag)
    }
    
    func invalidate() {
        session?.invalidate()
        session = nil
    }
    
    func invalidate(errorMessage: String) {
        session?.invalidate(errorMessage: errorMessage)
        session = nil
    }
}

/// Mock implementation for testing
class MockNFCSessionManager: NFCSessionManager {
    var isReadingAvailable: Bool = true
    var shouldFailConnection = false
    var connectionError: Error = NFCSessionError.connectionFailed
    var sessionStarted = false
    var connected = false
    var invalidated = false
    var invalidationErrorMessage: String?
    var alertMessage: String?
    var pollingOption: NFCTagReaderSession.PollingOption?
    var delegate: NFCTagReaderSessionDelegate?
    
    // Simulate tag detection after session start
    var mockTags: [NFCTag] = []
    var shouldSimulateTagDetection = true
    var tagDetectionDelay: TimeInterval = 0.1
    
    func startSession(
        pollingOption: NFCTagReaderSession.PollingOption,
        delegate: NFCTagReaderSessionDelegate,
        alertMessage: String
    ) {
        self.pollingOption = pollingOption
        self.delegate = delegate
        self.alertMessage = alertMessage
        sessionStarted = true
        
        // Note: For testing, we don't actually create delegate calls here
        // The test will explicitly call the delegate methods when needed
    }
    
    func connect(to tag: NFCTag) async throws {
        if shouldFailConnection {
            throw connectionError
        }
        connected = true
    }
    
    func invalidate() {
        invalidated = true
    }
    
    func invalidate(errorMessage: String) {
        invalidated = true
        invalidationErrorMessage = errorMessage
    }
    
    // Test helpers
    func simulateError(_ error: Error) {
        // In tests, we'll call the delegate methods directly on the test subject
        // This is just for tracking that the error was triggered
    }
    
    func simulateTagDetection(tags: [NFCTag]) {
        // In tests, we'll call the delegate methods directly on the test subject
        mockTags = tags
    }
    
    func reset() {
        isReadingAvailable = true
        shouldFailConnection = false
        sessionStarted = false
        connected = false
        invalidated = false
        invalidationErrorMessage = nil
        alertMessage = nil
        pollingOption = nil
        delegate = nil
        mockTags = []
        shouldSimulateTagDetection = true
    }
}

/// Mock NFC Tag Reader Session for testing
class MockNFCTagReaderSession {
    // This is a placeholder implementation
    // We don't inherit from NFCTagReaderSession to avoid initialization issues
}

/// Errors that can occur during NFC session management
enum NFCSessionError: Error {
    case noActiveSession
    case connectionFailed
    case invalidTag
    case sessionNotStarted
    
    var localizedDescription: String {
        switch self {
        case .noActiveSession:
            return "No active NFC session"
        case .connectionFailed:
            return "Failed to connect to NFC tag"
        case .invalidTag:
            return "Invalid NFC tag"
        case .sessionNotStarted:
            return "NFC session not started"
        }
    }
}