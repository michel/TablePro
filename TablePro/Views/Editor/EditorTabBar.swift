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

    /// Optional direct tab switch handler that bypasses SwiftUI .onChange delay.
    /// When provided, called instead of `tabManager.selectTab(tab)`.
    var onDirectSelect: ((QueryTab) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            // Scrollable tab list
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(tabManager.tabs) { tab in
                            EditorTabItem(
                                tab: tab,
                                isSelected: tab.id == tabManager.selectedTabId,
                                onSelect: {
                                    if let onDirectSelect {
                                        onDirectSelect(tab)
                                    } else {
                                        tabManager.selectTab(tab)
                                    }
                                },
                                onClose: { tabManager.closeTab(tab) }
                            )
                            .id(tab.id)
                            .contextMenu { tabContextMenu(for: tab) }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onAppear {
                    if let id = tabManager.selectedTabId {
                        proxy.scrollTo(id)
                    }
                }
                .onChange(of: tabManager.selectedTabId) { newId in
                    guard let id = newId else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(id)
                    }
                }
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
        Button(String(localized: "Duplicate Tab")) {
            tabManager.duplicateTab(tab)
        }

        Button(tab.isPinned ? String(localized: "Unpin Tab") : String(localized: "Pin Tab")) {
            tabManager.togglePin(tab)
        }

        Divider()

        if !tab.isPinned {
            Button(String(localized: "Close Tab")) {
                tabManager.closeTab(tab)
            }
        }

        Button(String(localized: "Close Other Tabs")) {
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
                Image(systemName: tab.isView ? "eye" : tab.tabType == .table ? "tablecells" : "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(
                        tab.tabType == .table ? (tab.isView ? Color.purple : Color.blue) : Color.secondary
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
