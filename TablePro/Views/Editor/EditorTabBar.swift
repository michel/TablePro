//
//  EditorTabBar.swift
//  TablePro
//
//  Pure SwiftUI tab bar replacement for NativeTabBar/NativeTabBarView.
//

import SwiftUI

/// SwiftUI tab bar for query/table tabs
struct EditorTabBar: View {
    @ObservedObject var tabManager: QueryTabManager

    var body: some View {
        HStack(spacing: 0) {
            // Scrollable tab list
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(tabManager.tabs) { tab in
                        EditorTabItem(
                            tab: tab,
                            isSelected: tab.id == tabManager.selectedTabId,
                            onSelect: { tabManager.selectTab(tab) },
                            onClose: { tabManager.closeTab(tab) }
                        )
                        .contextMenu { tabContextMenu(for: tab) }
                    }
                }
                .padding(.horizontal, 4)
            }

            // Add tab button
            Button(action: { tabManager.addTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("New Query Tab (⌘T)")
            .padding(.trailing, 8)
        }
        .frame(height: 32)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func tabContextMenu(for tab: QueryTab) -> some View {
        Button("Duplicate Tab") {
            tabManager.duplicateTab(tab)
        }

        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
            tabManager.togglePin(tab)
        }

        Divider()

        if !tab.isPinned {
            Button("Close Tab") {
                tabManager.closeTab(tab)
            }
        }

        Button("Close Other Tabs") {
            let kept = tabManager.tabs.filter { $0.id == tab.id || $0.isPinned }
            tabManager.tabs = kept.isEmpty ? [] : kept
            tabManager.selectedTabId = tab.id
        }
    }
}

// MARK: - EditorTabItem

/// Individual tab item view
private struct EditorTabItem: View {
    let tab: QueryTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            // Pin indicator
            if tab.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }

            // Status icon or spinner
            if tab.isExecuting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 11, height: 11)
            } else {
                Image(systemName: tab.tabType == .table ? "tablecells" : "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(
                        tab.tabType == .table ? Color.blue : Color.secondary
                    )
            }

            // Title
            Text(tab.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .primary : .secondary)

            // Close button (on hover, hidden for pinned)
            if isHovered && !tab.isPinned {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(minWidth: 80, maxWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(tabBackground)
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }

    private var tabBackground: Color {
        if isSelected {
            Color.accentColor.opacity(0.15)
        } else if isHovered {
            Color(nsColor: .quaternaryLabelColor)
        } else {
            Color.clear
        }
    }
}
