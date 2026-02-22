//
//  ConnectionHealthMonitor.swift
//  TablePro
//
//  Actor that monitors database connection health with periodic pings
//  and automatic reconnection with exponential backoff.
//

import Foundation
import os

// MARK: - Health State

extension ConnectionHealthMonitor {
    /// Represents the current health state of a monitored connection.
    enum HealthState: Sendable, Equatable {
        case healthy
        case checking
        case reconnecting(attempt: Int) // 1-based attempt number
        case failed
    }
}

// MARK: - Notification

extension Notification.Name {
    /// Posted when a connection's health state changes.
    /// userInfo: ["connectionId": UUID, "state": ConnectionHealthMonitor.HealthState]
    static let connectionHealthStateChanged = Notification.Name("connectionHealthStateChanged")
}

// MARK: - ConnectionHealthMonitor

/// Monitors a single database connection's health via periodic pings and
/// automatically attempts reconnection with exponential backoff on failure.
///
/// Uses closure-based dependency injection so it does not directly reference
/// `DatabaseDriver` (which is not `Sendable`). The caller provides `pingHandler`
/// and `reconnectHandler` closures.
actor ConnectionHealthMonitor {
    private static let logger = Logger(subsystem: "com.TablePro", category: "ConnectionHealthMonitor")

    // MARK: - Configuration

    private static let pingInterval: TimeInterval = 30.0
    private static let maxRetries = 3
    private static let backoffDelays: [TimeInterval] = [2.0, 4.0, 8.0]

    // MARK: - Dependencies

    private let connectionId: UUID
    private let pingHandler: @Sendable () async -> Bool
    private let reconnectHandler: @Sendable () async -> Bool
    private let onStateChanged: @Sendable (UUID, HealthState) async -> Void

    // MARK: - State

    private var state: HealthState = .healthy
    private var monitoringTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a new health monitor for a database connection.
    ///
    /// - Parameters:
    ///   - connectionId: The unique identifier of the connection to monitor.
    ///   - pingHandler: Closure that executes a lightweight query (e.g., `SELECT 1`)
    ///     and returns `true` if the connection is alive.
    ///   - reconnectHandler: Closure that attempts to re-establish the connection
    ///     and returns `true` on success.
    ///   - onStateChanged: Closure invoked whenever the health state transitions.
    init(
        connectionId: UUID,
        pingHandler: @escaping @Sendable () async -> Bool,
        reconnectHandler: @escaping @Sendable () async -> Bool,
        onStateChanged: @escaping @Sendable (UUID, HealthState) async -> Void
    ) {
        self.connectionId = connectionId
        self.pingHandler = pingHandler
        self.reconnectHandler = reconnectHandler
        self.onStateChanged = onStateChanged
    }

    // MARK: - Public API

    /// The current health state of the monitored connection.
    var currentState: HealthState {
        state
    }

    /// Starts periodic health monitoring.
    ///
    /// Creates a long-running task that pings the connection every 30 seconds.
    /// If monitoring is already active, this method does nothing.
    func startMonitoring() {
        guard monitoringTask == nil else {
            Self.logger.trace("Monitoring already active for connection \(self.connectionId)")
            return
        }

        Self.logger.trace("Starting health monitoring for connection \(self.connectionId)")

        monitoringTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pingInterval))

                guard !Task.isCancelled else { break }

                await self.performHealthCheck()
            }

            Self.logger.trace("Monitoring loop exited for connection \(self.connectionId)")
        }
    }

    /// Stops periodic health monitoring and cancels any in-flight reconnect attempts.
    func stopMonitoring() {
        Self.logger.trace("Stopping health monitoring for connection \(self.connectionId)")
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    /// Resets the monitor to `.healthy` after the user manually reconnects.
    ///
    /// Call this when an external reconnection succeeds so the monitor resumes
    /// normal periodic pings instead of staying in `.failed` state.
    func resetAfterManualReconnect() async {
        Self.logger.info("Manual reconnect succeeded, resetting to healthy for connection \(self.connectionId)")
        await transitionTo(.healthy)
    }

    // MARK: - Health Check

    /// Performs a single health check cycle.
    ///
    /// Skips the check if the monitor is already in a non-healthy state
    /// (e.g., mid-reconnect). On ping failure, triggers the reconnect sequence.
    private func performHealthCheck() async {
        guard state == .healthy else {
            Self.logger.debug("Skipping health check — state is \(String(describing: self.state)) for connection \(self.connectionId)")
            return
        }

        await transitionTo(.checking)

        let isAlive = await pingHandler()

        if isAlive {
            Self.logger.debug("Ping succeeded for connection \(self.connectionId)")
            await transitionTo(.healthy)
        } else {
            Self.logger.warning("Ping failed for connection \(self.connectionId), starting reconnect sequence")
            await attemptReconnect()
        }
    }

    // MARK: - Reconnection

    /// Attempts to reconnect with exponential backoff.
    ///
    /// Tries up to `maxRetries` times (3), waiting 2s, 4s, and 8s between attempts.
    /// On success, transitions back to `.healthy`. After all retries are exhausted,
    /// transitions to `.failed`.
    private func attemptReconnect() async {
        for attempt in 1...Self.maxRetries {
            guard !Task.isCancelled else {
                Self.logger.debug("Reconnect cancelled for connection \(self.connectionId)")
                return
            }

            let delay = Self.backoffDelays[attempt - 1]

            Self.logger.warning("Reconnect attempt \(attempt)/\(Self.maxRetries) for connection \(self.connectionId) — waiting \(delay)s")
            await transitionTo(.reconnecting(attempt: attempt))

            try? await Task.sleep(for: .seconds(delay))

            guard !Task.isCancelled else {
                Self.logger.debug("Reconnect cancelled during backoff for connection \(self.connectionId)")
                return
            }

            let success = await reconnectHandler()

            if success {
                Self.logger.info("Reconnect succeeded on attempt \(attempt) for connection \(self.connectionId)")
                await transitionTo(.healthy)
                return
            }

            Self.logger.warning("Reconnect attempt \(attempt) failed for connection \(self.connectionId)")
        }

        // All retries exhausted
        Self.logger.error("All \(Self.maxRetries) reconnect attempts failed for connection \(self.connectionId)")
        await transitionTo(.failed)
    }

    // MARK: - State Transitions

    /// Transitions to a new health state, logging the change and notifying observers.
    private func transitionTo(_ newState: HealthState) async {
        let oldState = state
        state = newState

        if oldState != newState {
            Self.logger.log(
                level: logLevel(for: newState),
                "Connection \(self.connectionId) health state: \(String(describing: oldState)) -> \(String(describing: newState))"
            )

            await onStateChanged(connectionId, newState)
        }
    }

    /// Returns the appropriate log level for a given health state.
    private func logLevel(for state: HealthState) -> OSLogType {
        switch state {
        case .healthy, .checking:
            return .debug
        case .reconnecting:
            return .default
        case .failed:
            return .error
        }
    }
}
