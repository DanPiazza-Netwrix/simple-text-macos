import Foundation

// MARK: - Session types

struct TabRecoveryEntry: Codable {
    /// File URL, if the tab had one. nil for unsaved/untitled tabs.
    var url: URL?
    /// Text content. nil for saved+unmodified tabs (file will be reopened on restore).
    var content: String?
}

struct RecoverySession: Codable {
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
            print("RecoveryBuffer: save failed: \(error)")
        }
    }

    static func loadSession() -> RecoverySession? {
        // Try the current JSON format first.
        if let url = sessionURL,
           let data = try? Data(contentsOf: url),
           let session = try? JSONDecoder().decode(RecoverySession.self, from: data) {
            return session
        }
        // One-time migration from the old single-file format.
        if let url = legacyURL,
           let content = try? String(contentsOf: url, encoding: .utf8),
           !content.isEmpty {
            return RecoverySession(
                tabs: [TabRecoveryEntry(url: nil, content: content)],
                selectedIndex: 0)
        }
        return nil
    }

    static func clear() {
        [sessionURL, legacyURL].compactMap { $0 }.forEach {
            try? FileManager.default.removeItem(at: $0)
        }
    }
}
