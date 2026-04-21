import Foundation
import OSLog

private let logger = Logger(subsystem: "com.simpletext.app", category: "RecoveryBuffer")

// MARK: - Session types

struct TabRecoveryEntry: Codable {
    /// File URL, if the tab had one. nil for unsaved/untitled tabs.
    var url: URL?
    /// Text content. nil for saved+unmodified tabs (file will be reopened on restore).
    var content: String?
}

struct PaneRecoveryEntry: Codable {
    var tabs: [TabRecoveryEntry]
    var selectedIndex: Int
}

struct RecoverySession: Codable {
    var panes: [PaneRecoveryEntry]
    var activePaneIndex: Int
    /// Divider position as a fraction of the split view width (0–1). nil when not split.
    var dividerFraction: Double?
}

/// Legacy format (pre-split-view) for one-time migration.
private struct LegacyRecoverySession: Codable {
    var tabs: [TabRecoveryEntry]
    var selectedIndex: Int
}

// MARK: - RecoveryBuffer

enum RecoveryBuffer {

    private static let dir: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("SimpleText")

    /// New multi-tab JSON session file.
    private static let sessionURL: URL? = dir?.appendingPathComponent("session.json")
    /// Legacy single-tab file — kept only for one-time migration.
    private static let legacyURL: URL?  = dir?.appendingPathComponent("unsaved_buffer.txt")

    // MARK: - Public API

    static func saveSession(_ session: RecoverySession) {
        guard let url = sessionURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(session).write(to: url, options: .atomic)
        } catch {
            logger.error("Session save failed: \(error)")
        }
    }

    static func loadSession() -> RecoverySession? {
        if let url = sessionURL, let data = try? Data(contentsOf: url) {
            // Try new pane-aware format first.
            if let session = try? JSONDecoder().decode(RecoverySession.self, from: data) {
                return session
            }
            // Fall back to pre-split-view format (flat tabs + selectedIndex).
            if let legacy = try? JSONDecoder().decode(LegacyRecoverySession.self, from: data) {
                return RecoverySession(
                    panes: [PaneRecoveryEntry(tabs: legacy.tabs, selectedIndex: legacy.selectedIndex)],
                    activePaneIndex: 0)
            }
        }
        // One-time migration from the old single-file format.
        if let url = legacyURL,
           let content = try? String(contentsOf: url, encoding: .utf8),
           !content.isEmpty {
            return RecoverySession(
                panes: [PaneRecoveryEntry(tabs: [TabRecoveryEntry(url: nil, content: content)], selectedIndex: 0)],
                activePaneIndex: 0)
        }
        return nil
    }

    static func clear() {
        [sessionURL, legacyURL].compactMap { $0 }.forEach {
            try? FileManager.default.removeItem(at: $0)
        }
    }
}
