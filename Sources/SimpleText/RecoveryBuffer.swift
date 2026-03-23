import Foundation

enum RecoveryBuffer {
    private static let appSupportDir: URL? = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SimpleText")
    }()

    private static let bufferURL: URL? = {
        appSupportDir?.appendingPathComponent("unsaved_buffer.txt")
    }()

    // MARK: - Public API

    static func save(_ content: String) {
        guard let url = bufferURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save recovery buffer: \(error)")
        }
    }

    static func load() -> String? {
        guard let url = bufferURL else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func clear() {
        guard let url = bufferURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

}
