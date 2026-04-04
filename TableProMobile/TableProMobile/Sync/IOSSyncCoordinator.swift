//
//  IOSSyncCoordinator.swift
//  TableProMobile
//

import CloudKit
import Foundation
import Observation
import os
import TableProModels
import TableProSync

@MainActor @Observable
final class IOSSyncCoordinator {
    private static let logger = Logger(subsystem: "com.TablePro", category: "Sync")

    var status: SyncStatus = .idle
    var lastSyncDate: Date?

    private var engine: CloudKitSyncEngine?
    private let metadata = SyncMetadataStorage()
    private var cachedRecords: [UUID: CKRecord] = [:]

    private func getEngine() -> CloudKitSyncEngine {
        if let engine { return engine }
        let newEngine = CloudKitSyncEngine()
        engine = newEngine
        return newEngine
    }
    private var debounceTask: Task<Void, Never>?

    // Callback to update AppState connections
    var onConnectionsChanged: (([DatabaseConnection]) -> Void)?

    // MARK: - Sync

    func sync(localConnections: [DatabaseConnection], isRetry: Bool = false) async {
        guard status != .syncing else { return }
        status = .syncing

        do {
            let accountStatus = try await getEngine().accountStatus()
            guard accountStatus == .available else {
                status = .error("iCloud account not available")
                return
            }

            try await getEngine().ensureZoneExists()
            let remoteChanges = try await pull()
            Self.logger.info("Pulled \(remoteChanges.changed.count) changed, \(remoteChanges.deletedIDs.count) deleted")

            // Merge before push: incorporate remote changes into local state first,
            // then push the merged result so the remote gets the correct final state.
            let merged = merge(local: localConnections, remote: remoteChanges)
            Self.logger.info("Merged: local=\(localConnections.count), result=\(merged.count)")
            try await push(localConnections: merged)
            onConnectionsChanged?(merged)

            metadata.lastSyncDate = Date()
            lastSyncDate = metadata.lastSyncDate
            status = .idle
        } catch let error as SyncError where error == .tokenExpired {
            guard !isRetry else {
                status = .error("Sync failed after token refresh")
                return
            }
            metadata.saveToken(nil)
            status = .idle
            await sync(localConnections: localConnections, isRetry: true)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func markDirty(_ connectionId: UUID) {
        metadata.markDirty(connectionId.uuidString, type: .connection)
    }

    func markDeleted(_ connectionId: UUID) {
        metadata.addTombstone(connectionId.uuidString, type: .connection)
    }

    func scheduleSyncAfterChange(localConnections: [DatabaseConnection]) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await sync(localConnections: localConnections)
        }
    }

    // MARK: - Push

    private func push(localConnections: [DatabaseConnection]) async throws {
        let zoneID = await getEngine().currentZoneID

        // Dirty connections
        let dirtyIDs = metadata.dirtyIDs(for: .connection)
        let dirtyRecords = localConnections
            .filter { dirtyIDs.contains($0.id.uuidString) }
            .map { connection -> CKRecord in
                if let existing = cachedRecords[connection.id] {
                    SyncRecordMapper.updateRecord(existing, with: connection)
                    return existing
                } else {
                    return SyncRecordMapper.toRecord(connection, zoneID: zoneID)
                }
            }

        // Tombstones
        let tombstones = metadata.tombstones(for: .connection)
        let deletions = tombstones.map {
            CKRecord.ID(recordName: "Connection_\($0.id)", zoneID: zoneID)
        }

        guard !dirtyRecords.isEmpty || !deletions.isEmpty else { return }

        try await getEngine().push(records: dirtyRecords, deletions: deletions)
        metadata.clearDirty(type: .connection)
        metadata.clearTombstones(type: .connection)
    }

    // MARK: - Pull

    private struct PullChanges {
        var changed: [DatabaseConnection] = []
        var deletedIDs: Set<UUID> = []
    }

    private func pull() async throws -> PullChanges {
        let token = metadata.loadToken()
        let result = try await getEngine().pull(since: token)

        if let newToken = result.newToken {
            metadata.saveToken(newToken)
        }

        var changes = PullChanges()

        for record in result.changedRecords {
            if record.recordType == SyncRecordType.connection.rawValue {
                if let connection = SyncRecordMapper.toConnection(record) {
                    cachedRecords[connection.id] = record
                    changes.changed.append(connection)
                }
            }
        }

        for recordID in result.deletedRecordIDs {
            let name = recordID.recordName
            if name.hasPrefix("Connection_") {
                let uuidStr = String(name.dropFirst("Connection_".count))
                if let uuid = UUID(uuidString: uuidStr) {
                    changes.deletedIDs.insert(uuid)
                }
            }
        }

        return changes
    }

    // MARK: - Merge (last-write-wins)

    private func merge(local: [DatabaseConnection], remote: PullChanges) -> [DatabaseConnection] {
        // Remove deleted connections
        var result = local.filter { !remote.deletedIDs.contains($0.id) }

        let localMap = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })

        for remoteConn in remote.changed {
            if localMap[remoteConn.id] != nil {
                if let index = result.firstIndex(where: { $0.id == remoteConn.id }) {
                    result[index] = remoteConn
                }
            } else if !remote.deletedIDs.contains(remoteConn.id) {
                result.append(remoteConn)
            }
        }

        return result
    }
}

