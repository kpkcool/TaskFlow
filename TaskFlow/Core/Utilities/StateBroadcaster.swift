//
//  StateBroadcaster.swift
//  TaskFlow
//
//  A multicast + last-value-replay wrapper around AsyncStream.
//
//  WHY THIS EXISTS: a bare `AsyncStream` supports exactly ONE consumer.
//  If two `for await` loops iterate the same AsyncStream instance, each
//  yielded element is delivered to only one of them (whichever is waiting) —
//  the other silently misses it.
//
//  That's what broke sync-state observation: both TaskBoardViewModel and
//  DebugViewController subscribed to the same `SyncEngine.stateStream`, so
//  they stole events from each other. The board would receive
//  `.syncing(1)` but the Debug screen would consume the follow-up
//  `.synced`, leaving the board permanently stuck showing "Syncing 1
//  change...".
//
//  This type gives every subscriber its own continuation (true multicast)
//  and immediately replays the latest value so a newly-presented screen
//  renders the correct state instantly instead of waiting for the next change.
//

import Foundation

final class StateBroadcaster<Value: Sendable>: @unchecked Sendable {

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]
    private var currentValue: Value

    init(initialValue: Value) {
        self.currentValue = initialValue
    }

    /// The most recently broadcast value.
    var value: Value {
        lock.lock(); defer { lock.unlock() }
        return currentValue
    }

    /// Sends `newValue` to every active subscriber and stores it for replay.
    func send(_ newValue: Value) {
        lock.lock()
        currentValue = newValue
        let subscribers = continuations
        lock.unlock()
        for (_, continuation) in subscribers {
            continuation.yield(newValue)
        }
    }

    /// Returns a fresh independent stream. Immediately replays the current
    /// value, then delivers every subsequent `send`.
    func stream() -> AsyncStream<Value> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            let id = UUID()
            self.lock.lock()
            self.continuations[id] = continuation
            let replay = self.currentValue
            self.lock.unlock()

            continuation.yield(replay)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }
}
