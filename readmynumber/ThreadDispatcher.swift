//
//  ThreadDispatcher.swift
//  readmynumber
//
//  Created on 2025/09/09.
//

import Foundation

/// Protocol for dispatching operations to different threads
protocol ThreadDispatcher {
    /// Execute a closure on the main thread asynchronously
    /// - Parameter closure: The closure to execute
    func dispatchToMain(_ closure: @escaping () -> Void)
    
    /// Execute an async closure on the main actor
    /// - Parameter closure: The async closure to execute
    func dispatchToMainActor(_ closure: @MainActor @escaping () -> Void) async
}

/// Concrete implementation using system dispatch queues
class SystemThreadDispatcher: ThreadDispatcher {
    func dispatchToMain(_ closure: @escaping () -> Void) {
        DispatchQueue.main.async {
            closure()
        }
    }
    
    func dispatchToMainActor(_ closure: @MainActor @escaping () -> Void) async {
        await MainActor.run {
            closure()
        }
    }
}

/// Mock implementation for testing
class MockThreadDispatcher: ThreadDispatcher {
    private var mainQueue: [(closure: () -> Void, id: UUID)] = []
    private var mainActorQueue: [(@MainActor () -> Void, UUID)] = []
    
    var dispatchedToMainCount = 0
    var dispatchedToMainActorCount = 0
    
    // Control whether dispatched closures are executed immediately (for synchronous testing)
    var executeImmediately = true
    
    func dispatchToMain(_ closure: @escaping () -> Void) {
        dispatchedToMainCount += 1
        
        if executeImmediately {
            closure()
        } else {
            let id = UUID()
            mainQueue.append((closure: closure, id: id))
        }
    }
    
    func dispatchToMainActor(_ closure: @MainActor @escaping () -> Void) async {
        dispatchedToMainActorCount += 1
        
        if executeImmediately {
            await MainActor.run {
                closure()
            }
        } else {
            let id = UUID()
            mainActorQueue.append((closure, id))
        }
    }
    
    // Test helper methods
    func executePendingMainQueue() {
        let queued = mainQueue
        mainQueue.removeAll()
        for item in queued {
            item.closure()
        }
    }
    
    func executePendingMainActorQueue() async {
        let queued = mainActorQueue
        mainActorQueue.removeAll()
        for item in queued {
            await MainActor.run {
                item.0()
            }
        }
    }
    
    func hasPendingMainQueue() -> Bool {
        return !mainQueue.isEmpty
    }
    
    func hasPendingMainActorQueue() -> Bool {
        return !mainActorQueue.isEmpty
    }
    
    func reset() {
        mainQueue.removeAll()
        mainActorQueue.removeAll()
        dispatchedToMainCount = 0
        dispatchedToMainActorCount = 0
        executeImmediately = true
    }
}