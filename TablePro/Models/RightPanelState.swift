//
//  RightPanelState.swift
//  TablePro
//
//  Shared state object for the right panel, owned by ContentView.
//  Inspector data is now passed directly via InspectorContext instead
//  of being cached here.
//

import Foundation
import os

@MainActor @Observable final class RightPanelState {
    private static let isPresentedKey = "com.TablePro.rightPanel.isPresented"
    private static let isPresentedChangedNotification = Notification.Name("com.TablePro.rightPanel.isPresentedChanged")

    private var isSyncing = false
    @ObservationIgnored private let _didTeardown = OSAllocatedUnfairLock(initialState: false)

    var isPresented: Bool {
        didSet {
            guard !isSyncing else { return }
            UserDefaults.standard.set(isPresented, forKey: Self.isPresentedKey)
            NotificationCenter.default.post(name: Self.isPresentedChangedNotification, object: self)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIsPresentedChanged(_:)),
            name: Self.isPresentedChangedNotification,
            object: nil
        )
    }

    /// Release all heavy data on disconnect so memory drops
    /// even if AppKit keeps the window alive.
    func teardown() {
        guard !_didTeardown.withLock({ $0 }) else { return }
        _didTeardown.withLock { $0 = true }
        onSave = nil
        aiViewModel.clearSessionData()
        editState.releaseData()
        NotificationCenter.default.removeObserver(self)
    }

    deinit {
        if !_didTeardown.withLock({ $0 }) {
            NotificationCenter.default.removeObserver(self)
        }
    }

    @objc private func handleIsPresentedChanged(_ notification: Notification) {
        guard let sender = notification.object as? RightPanelState, sender !== self else { return }
        let newValue = UserDefaults.standard.bool(forKey: Self.isPresentedKey)
        guard newValue != isPresented else { return }
        isSyncing = true
        isPresented = newValue
        isSyncing = false
    }
}
