//
//  EscapeKeyEnvironmentBridge.swift
//  TablePro
//
//  Bridges SwiftUI environment with the global ESC key coordinator.
//

import SwiftUI

// MARK: - Environment Bridge

/// ViewModifier that bridges the SwiftUI environment with the global coordinator
/// Should be applied at the root of the app
struct EscapeKeyEnvironmentBridge: ViewModifier {
    @Environment(\.escapeKeyContext) private var context
    @StateObject private var coordinator = EscapeKeyCoordinator.shared
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Install global ESC key monitor
                coordinator.install()
            }
            .onDisappear {
                // Cleanup on disappear (rare for root views)
                coordinator.uninstall()
            }
            .onChange(of: context.handlers.count) { _, _ in
                // Update coordinator whenever environment handlers change
                coordinator.updateContext(context)
            }
            .onReceive(coordinator.$currentContext) { _ in
                // Sync context (in case it's updated externally)
                if coordinator.currentContext.handlers.count != context.handlers.count {
                    coordinator.updateContext(context)
                }
            }
    }
}

extension View {
    /// Install the ESC key handling system at the root of your app
    ///
    /// Usage in TableProApp:
    /// ```swift
    /// ContentView()
    ///     .escapeKeySystem()
    /// ```
    public func escapeKeySystem() -> some View {
        modifier(EscapeKeyEnvironmentBridge())
    }
}
