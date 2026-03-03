//
//  RightPanelStateTests.swift
//  TableProTests
//
//  Tests for RightPanelState persistence of isPresented via UserDefaults.
//

import Foundation
@testable import TablePro
import Testing

@Suite("RightPanelState")
struct RightPanelStateTests {
    private static let key = "com.TablePro.rightPanel.isPresented"

    @Test("isPresented defaults to false when no UserDefaults value")
    @MainActor
    func defaultsToFalse() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let state = RightPanelState()
        #expect(state.isPresented == false)
    }

    @Test("isPresented initializes from UserDefaults when true")
    @MainActor
    func initializesFromUserDefaults() {
        UserDefaults.standard.set(true, forKey: Self.key)
        let state = RightPanelState()
        #expect(state.isPresented == true)
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("isPresented persists to UserDefaults on change")
    @MainActor
    func persistsOnChange() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let state = RightPanelState()
        state.isPresented = true
        #expect(UserDefaults.standard.bool(forKey: Self.key) == true)
        state.isPresented = false
        #expect(UserDefaults.standard.bool(forKey: Self.key) == false)
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("new instance reads persisted state from previous instance")
    @MainActor
    func newInstanceReadsPersisted() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let state1 = RightPanelState()
        state1.isPresented = true

        let state2 = RightPanelState()
        #expect(state2.isPresented == true)
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
