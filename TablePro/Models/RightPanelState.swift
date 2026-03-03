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
    private static let isPresentedKey = "com.TablePro.rightPanel.isPresented"

    var isPresented: Bool {
        didSet {
            UserDefaults.standard.set(isPresented, forKey: Self.isPresentedKey)
        }
    }

    var activeTab: RightPanelTab = .details

    // Save closure — set by MainContentCommandActions, called by UnifiedRightPanelView
    var onSave: (() -> Void)?

    // Owned objects — lifted from MainContentView @StateObject
    let editState = MultiRowEditState()
    let aiViewModel = AIChatViewModel()

    init() {
        self.isPresented = UserDefaults.standard.bool(forKey: Self.isPresentedKey)
    }
}
