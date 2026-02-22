//
//  RightPanelState.swift
//  TablePro
//
//  Shared state object for the right panel, owned by ContentView.
//  Inspector data is now passed directly via InspectorContext instead
//  of being cached here.
//

import Foundation

@MainActor @Observable final class RightPanelState {
    // Panel visibility
    var isPresented: Bool = false

    // Tab switcher state
    var activeTab: RightPanelTab = .details

    // Save closure — set by MainContentCommandActions, called by UnifiedRightPanelView
    var onSave: (() -> Void)?

    // Owned objects — lifted from MainContentView @StateObject
    let editState = MultiRowEditState()
    let aiViewModel = AIChatViewModel()
}
