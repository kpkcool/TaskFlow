//
//  NetworkMonitor.swift
//  TaskFlow
//
//  Thin wrapper around NWPathMonitor. Network state is only a hint — every
//  Firebase call still handles its own errors — but it's what lets the
//  SyncEngine react immediately when connectivity returns instead of
//  waiting for the next manual sync.
//

import Foundation
import Network

final class NetworkMonitor: @unchecked Sendable {

    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.example.com.TaskFlow.NetworkMonitor")
    private let lock = NSLock()

    private var _pathConnected = false
    /// Debug-mode override so QA can exercise offline behavior on a
    /// simulator that actually has internet access.
    private var _simulatedOffline = false
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    /// True if the device reports a usable network path AND the debug
    /// "simulate offline" toggle isn't engaged.
    var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        return _pathConnected && !_simulatedOffline
    }

    var isSimulatingOffline: Bool {
        lock.lock(); defer { lock.unlock() }
        return _simulatedOffline
    }

    private init() {}

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.updatePathConnected(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    func setSimulatedOffline(_ simulated: Bool) {
        lock.lock()
        _simulatedOffline = simulated
        let effective = _pathConnected && !simulated
        let subscribers = continuations
        lock.unlock()
        for (_, continuation) in subscribers {
            continuation.yield(effective)
        }
    }

    /// Emits the current value immediately, then again on every change.
    func stream() -> AsyncStream<Bool> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            let id = UUID()
            self.lock.lock()
            self.continuations[id] = continuation
            let current = self._pathConnected && !self._simulatedOffline
            self.lock.unlock()
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuations[id] = nil
                self?.lock.unlock()
            }
        }
    }

    private func updatePathConnected(_ connected: Bool) {
        lock.lock()
        let changed = _pathConnected != connected
        _pathConnected = connected
        let simulatedOffline = _simulatedOffline
        let subscribers = continuations
        lock.unlock()
        guard changed else { return }
        let effective = connected && !simulatedOffline
        for (_, continuation) in subscribers {
            continuation.yield(effective)
        }
    }
}
