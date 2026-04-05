//
//  WindowTabGroupingTests.swift
//  TableProTests
//
//  Tests for correct window tab grouping behavior:
//  - Same-connection tabs merge into the same window
//  - Different-connection tabs stay in separate windows
//  - WindowOpener tracks pending payloads for tab-group attachment
//

import Foundation
import Testing

@testable import TablePro

@Suite("WindowTabGrouping")
@MainActor
struct WindowTabGroupingTests {
    // MARK: - WindowOpener pending payload tracking

    @Test("openNativeTab without openWindow action drops payload and removes from pending")
    func openNativeTabWithoutOpenWindowDropsPayload() {
        let connectionId = UUID()
        let opener = WindowOpener.shared

        opener.openWindow = nil
        let payload = EditorTabPayload(connectionId: connectionId, tabType: .table, tableName: "users")
        opener.openNativeTab(payload)

        #expect(opener.pendingPayloads[payload.id] == nil)
    }

    @Test("pendingPayloads is empty initially")
    func pendingPayloadsEmptyInitially() {
        let opener = WindowOpener.shared
        for id in opener.pendingPayloads.keys {
            opener.acknowledgePayload(id)
        }

        #expect(opener.pendingPayloads.isEmpty)
    }

    @Test("acknowledgePayload removes the id from pending")
    func acknowledgePayloadRemovesId() {
        let opener = WindowOpener.shared
        let payloadId = UUID()

        opener.acknowledgePayload(payloadId)
        #expect(opener.pendingPayloads[payloadId] == nil)
    }

    // MARK: - TabbingIdentifier resolution

    @Test("tabbingIdentifier produces connection-specific identifier")
    func tabbingIdentifierUsesConnectionId() {
        let connectionId = UUID()
        let expected = "com.TablePro.main.\(connectionId.uuidString)"

        let result = WindowOpener.tabbingIdentifier(for: connectionId)

        #expect(result == expected)
    }

    // MARK: - Multi-connection tab grouping scenarios

    @Test("Two connections produce different tabbingIdentifiers")
    func twoConnectionsProduceDifferentIdentifiers() {
        let connectionA = UUID()
        let connectionB = UUID()

        let idA = WindowOpener.tabbingIdentifier(for: connectionA)
        let idB = WindowOpener.tabbingIdentifier(for: connectionB)

        #expect(idA != idB)
        #expect(idA.contains(connectionA.uuidString))
        #expect(idB.contains(connectionB.uuidString))
    }

    @Test("Same connection produces same tabbingIdentifier")
    func sameConnectionProducesSameIdentifier() {
        let connectionId = UUID()

        let id1 = WindowOpener.tabbingIdentifier(for: connectionId)
        let id2 = WindowOpener.tabbingIdentifier(for: connectionId)

        #expect(id1 == id2)
    }
}
