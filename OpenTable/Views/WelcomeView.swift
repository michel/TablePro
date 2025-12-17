//
//  WelcomeView.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import SwiftUI

/// Welcome view shown when no connection is selected
struct WelcomeView: View {
    var onAddConnection: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            // Logo
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "tablecells")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
                }
                
                Text("OpenTable")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("A modern database client for macOS")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            // Supported databases
            HStack(spacing: 24) {
                DatabaseBadge(name: "MySQL", icon: "cylinder.split.1x2.fill", color: .orange)
                DatabaseBadge(name: "MariaDB", icon: "cylinder.split.1x2.fill", color: .cyan)
                DatabaseBadge(name: "SQLite", icon: "doc.fill", color: .green)
            }
            
            // Get started
            VStack(spacing: 16) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Button(action: onAddConnection) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create New Connection")
                    }
                    .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            
            // Keyboard shortcuts hint
            VStack(spacing: 8) {
                Text("Quick Tips")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                
                HStack(spacing: 20) {
                    ShortcutHint(keys: "⌘ + Enter", action: "Execute Query")
                    ShortcutHint(keys: "⌘ + T", action: "New Tab")
                    ShortcutHint(keys: "⌘ + S", action: "Save Changes")
                }
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Badge showing a supported database type
struct DatabaseBadge: View {
    let name: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Keyboard shortcut hint display
struct ShortcutHint: View {
    let keys: String
    let action: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            Text(action)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    WelcomeView(onAddConnection: {})
        .frame(width: 700, height: 500)
}
