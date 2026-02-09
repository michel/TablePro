//
//  UpdaterBridge.swift
//  TablePro
//
//  Thin ObservableObject wrapping SPUStandardUpdaterController for SwiftUI integration
//

import Combine
import Sparkle

@MainActor
final class UpdaterBridge: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false

    private var cancellable: AnyCancellable?

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe canCheckForUpdates via KVO and publish to SwiftUI
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
    }

    /// The underlying Sparkle updater for direct property access (e.g. automaticallyChecksForUpdates)
    var updater: SPUUpdater {
        controller.updater
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
