//
//  RightPanelStateTests.swift
//  TableProTests
//
//  Tests for RightPanelVisibility persistence and RightPanelState teardown.
//

import Foundation
@testable import TablePro
import Testing

@Suite("RightPanelState", .serialized)
struct RightPanelStateTests {
    private static let key = "com.TablePro.rightPanel.isPresented"

    @Test("isPresented defaults to false when no UserDefaults value")
    @MainActor
    func defaultsToFalse() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let visibility = RightPanelVisibility.shared
        visibility.isPresented = false
        #expect(visibility.isPresented == false)
    }

    @Test("isPresented persists to UserDefaults on change")
    @MainActor
    func persistsOnChange() {
        let visibility = RightPanelVisibility.shared
        visibility.isPresented = true
        #expect(UserDefaults.standard.bool(forKey: Self.key) == true)
        visibility.isPresented = false
        #expect(UserDefaults.standard.bool(forKey: Self.key) == false)
    }

    @Test("visibility is shared across references")
    @MainActor
    func sharedInstance() {
        let a = RightPanelVisibility.shared
        let b = RightPanelVisibility.shared
        a.isPresented = true
        #expect(b.isPresented == true)
        a.isPresented = false
    }

    @Test("teardown is idempotent - calling twice does not crash")
    @MainActor
    func teardownIdempotent() {
        let state = RightPanelState()
        state.teardown()
        state.teardown()
    }

    @Test("teardown nils schemaProvider on aiViewModel")
    @MainActor
    func teardown_nilsSchemaProvider() {
        let state = RightPanelState()
        state.aiViewModel.schemaProvider = SQLSchemaProvider()
        #expect(state.aiViewModel.schemaProvider != nil)

        state.teardown()

        #expect(state.aiViewModel.schemaProvider == nil)
    }

    @Test("teardown nils onSave closure")
    @MainActor
    func teardown_nilsOnSave() {
        let state = RightPanelState()
        state.onSave = { }
        #expect(state.onSave != nil)

        state.teardown()

        #expect(state.onSave == nil)
    }
}
