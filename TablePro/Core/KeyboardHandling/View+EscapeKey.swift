//
//  View+EscapeKey.swift
//  TablePro
//
//  Declarative SwiftUI API for ESC key handling.
//

import SwiftUI

// MARK: - ViewModifier

/// ViewModifier that registers an ESC key handler in the environment
struct EscapeKeyHandlerModifier: ViewModifier {
    let priority: EscapeKeyPriority
    let handler: () -> EscapeKeyResult
    
    @Environment(\.escapeKeyContext) private var context
    
    func body(content: Content) -> some View {
        content
            .transformEnvironment(\.escapeKeyContext) { context in
                let escapeHandler = EscapeKeyHandler(
                    priority: priority,
                    handle: handler
                )
                context.addHandler(escapeHandler)
            }
    }
}

// MARK: - View Extension

extension View {
    /// Declare an ESC key handler for this view
    ///
    /// Usage:
    /// ```swift
    /// .escapeKeyHandler(priority: .sheet) {
    ///     dismiss()
    ///     return .handled
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - priority: Priority level for this handler
    ///   - handler: Closure to handle ESC key, returns .handled or .ignored
    public func escapeKeyHandler(
        priority: EscapeKeyPriority = .view,
        _ handler: @escaping () -> EscapeKeyResult
    ) -> some View {
        modifier(EscapeKeyHandlerModifier(priority: priority, handler: handler))
    }
    
    /// Convenience: Handle ESC to dismiss a sheet/dialog
    ///
    /// Usage:
    /// ```swift
    /// .escapeKeyDismiss(isPresented: $showSheet, priority: .sheet)
    /// ```
    public func escapeKeyDismiss(
        isPresented: Binding<Bool>,
        priority: EscapeKeyPriority = .sheet
    ) -> some View {
        self.escapeKeyHandler(priority: priority) {
            isPresented.wrappedValue = false
            return .handled
        }
    }
    
    /// Convenience: Handle ESC to dismiss using Environment dismiss
    ///
    /// Usage:
    /// ```swift
    /// .escapeKeyDismiss(priority: .sheet)
    /// ```
    public func escapeKeyDismiss(
        priority: EscapeKeyPriority = .sheet
    ) -> some View {
        EscapeKeyDismissView(priority: priority) {
            self
        }
    }
}

// MARK: - Helper View

/// Helper view that has access to @Environment(\.dismiss)
private struct EscapeKeyDismissView<Content: View>: View {
    let priority: EscapeKeyPriority
    let content: () -> Content
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        content()
            .escapeKeyHandler(priority: priority) {
                dismiss()
                return .handled
            }
    }
}
