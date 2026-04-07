//
//  RightPanelVisibility.swift
//  TablePro
//
//  Shared visibility and width preferences for the right panel.
//  Single @Observable instance shared by all windows — no NotificationCenter sync needed.
//

import Foundation

@MainActor @Observable
final class RightPanelVisibility {
    static let shared = RightPanelVisibility()

    static let minWidth: CGFloat = 280
    static let maxWidth: CGFloat = 500
    static let defaultWidth: CGFloat = 320

    private static let isPresentedKey = "com.TablePro.rightPanel.isPresented"
    private static let panelWidthKey = "com.TablePro.rightPanel.width"

    var isPresented: Bool {
        didSet { UserDefaults.standard.set(isPresented, forKey: Self.isPresentedKey) }
    }

    var panelWidth: CGFloat {
        didSet {
            let clamped = min(max(panelWidth, Self.minWidth), Self.maxWidth)
            if panelWidth != clamped { panelWidth = clamped }
            UserDefaults.standard.set(Double(clamped), forKey: Self.panelWidthKey)
        }
    }

    private init() {
        isPresented = UserDefaults.standard.bool(forKey: Self.isPresentedKey)
        let stored = CGFloat(UserDefaults.standard.double(forKey: Self.panelWidthKey))
        panelWidth = stored > 0 ? min(max(stored, Self.minWidth), Self.maxWidth) : Self.defaultWidth
    }
}
