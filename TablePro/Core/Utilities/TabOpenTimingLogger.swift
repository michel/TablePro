//
//  TabOpenTimingLogger.swift
//  TablePro
//
//  Debug timing logger for "open table" / tab-switch operations.
//  Measures elapsed time from user action → query dispatch → data displayed.
//
//  Filter in Console.app: subsystem = "com.TablePro"  category = "TabTiming"
//
//  Lifecycle — new table from sidebar or direct call:
//    markTrigger("sidebar:users")      — user clicks table in sidebar
//    attach(tabId:source:)             — tab UUID known inside openTableTab
//    mark("dbQueryStart", tabId:)      — executeQueryInternal dispatches DB call
//    markDone(…"dataDisplayed")        — results committed on main thread
//
//  Lifecycle — tab navigation (Cmd+Shift+[/]):
//    markTrigger("keyboard:prevTab:…") — notification fires
//    attach(tabId:source:)             — inside handleTabChange
//    mark("tabConfigured", tabId:)     — reloadVersion bump issued
//    markDone(…"tabSwitch-cachedData") — done if data already present
//    — OR —
//    mark("dbQueryStart", tabId:)      — lazy load triggers a query
//    markDone(…"dataDisplayed")        — results in
//

import Foundation
import os

/// Debug-only timing logger for open-table and tab-switch latency.
/// All methods run on @MainActor. In .receive(on: .main) Combine sinks,
/// call via MainActor.assumeIsolated { }.
@MainActor
final class TabOpenTimingLogger {
    static let shared = TabOpenTimingLogger()

    private let logger = Logger(subsystem: "com.TablePro", category: "TabTiming")

    private struct Entry {
        let source: String
        let start: Date
    }

    /// Keyed by tab UUID string; "pending" is used before the tab UUID is known.
    private var entries: [String: Entry] = [:]

    private init() {}

    // MARK: - Public API

    /// Step 1 — earliest moment the user action is detected (before tab UUID is known).
    func markTrigger(source: String) {
        entries["pending"] = Entry(source: source, start: Date())
        logger.debug("⏱ [TabOpen] TRIGGER  src=\(source, privacy: .public)")
    }

    /// Step 2 — tie the pending trigger to the real tab UUID, or start fresh.
    /// Call once the tab UUID is known (openTableTab / handleTabChange).
    func attach(tabId: UUID, source: String? = nil) {
        let key = tabId.uuidString
        let short = String(tabId.uuidString.prefix(8))

        if let pending = entries.removeValue(forKey: "pending") {
            let ms = elapsed(since: pending.start)
            entries[key] = pending
            logger.debug(
                "⏱ [TabOpen] ATTACH   tab=\(short, privacy: .public) src=\(pending.source, privacy: .public) +\(ms, privacy: .public)ms since trigger"
            )
        } else if entries[key] == nil {
            let label = source ?? "direct"
            entries[key] = Entry(source: label, start: Date())
            logger.debug(
                "⏱ [TabOpen] START    tab=\(short, privacy: .public) src=\(label, privacy: .public)"
            )
        }
    }

    /// Record an intermediate milestone.
    func mark(_ milestone: String, tabId: UUID) {
        guard let entry = entries[tabId.uuidString] else { return }
        let ms = elapsed(since: entry.start)
        let short = String(tabId.uuidString.prefix(8))
        logger.debug(
            "⏱ [TabOpen]   →\(milestone, privacy: .public)  tab=\(short, privacy: .public) +\(ms, privacy: .public)ms"
        )
    }

    /// Record the final milestone, log total time, and clear the entry.
    func markDone(tabId: UUID, milestone: String, extra: String = "") {
        guard let entry = entries.removeValue(forKey: tabId.uuidString) else { return }
        let ms = elapsed(since: entry.start)
        let short = String(tabId.uuidString.prefix(8))
        let tail = extra.isEmpty ? "" : " \(extra)"
        logger.debug(
            "⏱ [TabOpen] ✓ DONE   tab=\(short, privacy: .public) \(milestone, privacy: .public)\(tail, privacy: .public) — TOTAL \(ms, privacy: .public)ms [src=\(entry.source, privacy: .public)]"
        )
    }

    /// Discard without logging (error / cancel / stale entry).
    func cancel(tabId: UUID) {
        entries.removeValue(forKey: tabId.uuidString)
    }

    func cancelPending() {
        entries.removeValue(forKey: "pending")
    }

    // MARK: - Helpers

    private func elapsed(since start: Date) -> String {
        String(format: "%.1f", Date().timeIntervalSince(start) * 1_000)
    }
}
