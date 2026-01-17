//
//  EscapeKeyCoordinator.swift
//  TablePro
//
//  Coordinates ESC key handling across the app using SwiftUI environment.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Coordinator

/// Manages global ESC key handling and coordinates with SwiftUI environment
@MainActor
public final class EscapeKeyCoordinator: ObservableObject {
    public static let shared = EscapeKeyCoordinator()
    
    /// The current environment context (updated by root view)
    @Published private(set) var currentContext: EscapeKeyContext = EscapeKeyContext()
    
    /// NSEvent monitor for capturing ESC key globally
    private var eventMonitor: Any?
    
    private init() {}
    
    // MARK: - Setup
    
    /// Install global ESC key monitor
    /// Should be called once at app startup
    public func install() {
        guard eventMonitor == nil else { return }
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Check if it's the ESC key (keyCode 53)
            if event.keyCode == 53 {
                // Process through environment handlers
                if self.handleEscape() {
                    return nil // Consumed
                }
            }
            
            return event // Pass through
        }
    }
    
    /// Remove global ESC key monitor
    public func uninstall() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    // MARK: - Context Management
    
    /// Update the current context (called by root view's environment reader)
    public func updateContext(_ context: EscapeKeyContext) {
        self.currentContext = context
    }
    
    // MARK: - Processing
    
    /// Process ESC key through all registered handlers
    /// Returns true if handled, false if ignored by all
    public func handleEscape() -> Bool {
        // Check for special cases first (popups, autocomplete)
        if shouldIgnoreForSpecialWindows() {
            return false
        }
        
        // Process handlers in priority order (highest first)
        let handlers = currentContext.sortedHandlers()
        
        for handler in handlers {
            let result = handler.handle()
            
            switch result {
            case .handled:
                // Handler consumed the ESC key, stop propagation
                return true
                
            case .ignored:
                // Handler didn't process, try next
                continue
            }
        }
        
        // No handler processed the ESC key
        return false
    }
    
    // MARK: - Special Cases
    
    /// Check if ESC should be ignored for special windows (autocomplete, popups, etc.)
    private func shouldIgnoreForSpecialWindows() -> Bool {
        // Check if autocomplete/popup window is visible
        if let frontmostWindow = NSApp.keyWindow,
           frontmostWindow.level == .popUpMenu,
           frontmostWindow.isVisible {
            // Let the popup handle ESC
            return true
        }
        
        return false
    }
}
