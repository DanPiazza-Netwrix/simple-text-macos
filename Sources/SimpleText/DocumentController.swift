import AppKit
import Foundation

protocol DocumentControllerDelegate: AnyObject {
    func documentDidLoad(url: URL?, content: String)
    func documentDidSave(url: URL)
    func currentContent() -> String
}

final class DocumentController {

    private(set) var currentURL: URL?
    var isModified: Bool = false
    weak var delegate: DocumentControllerDelegate?

    // MARK: - Public API

    func newDocument() {
        currentURL = nil
        isModified = false
        delegate?.documentDidLoad(url: nil, content: "")
    }

    /// Restore a tab from the session — sets URL and content without touching disk.
    func restore(content: String, url: URL?) {
        currentURL = url
        isModified = false
        delegate?.documentDidLoad(url: url, content: content)
        // documentDidLoad resets isModified to false; re-assert modified after.
        isModified = true
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.canChooseFiles        = true
        panel.canChooseDirectories  = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes   = [.text, .plainText, .sourceCode, .data]
        guard let w = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: w) { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self else { return }
            self.loadFile(at: url)
        }
    }

    func openFile(at url: URL) {
        loadFile(at: url)
    }

    func saveDocument() {
        guard let url = currentURL else { saveDocumentAs(); return }
        write(to: url)
    }

    func saveDocumentAs(completion: (() -> Void)? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = currentURL?.lastPathComponent ?? "Untitled.txt"
        guard let w = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: w) { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self else { return }
            self.currentURL = url
            self.write(to: url)
            completion?()
        }
    }

    // MARK: - Internals

    private func loadFile(at url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            currentURL  = url
            isModified  = false
            delegate?.documentDidLoad(url: url, content: content)
        } catch {
            // Try latin-1 fallback
            if let content = try? String(contentsOf: url, encoding: .isoLatin1) {
                currentURL  = url
                isModified  = false
                delegate?.documentDidLoad(url: url, content: content)
            } else {
                showError("Could not open file: \(error.localizedDescription)")
            }
        }
    }

    private func write(to url: URL) {
        guard let content = delegate?.currentContent() else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            currentURL = url
            isModified = false
            delegate?.documentDidSave(url: url)
        } catch {
            showError("Could not save file: \(error.localizedDescription)")
        }
    }

    /// Explicit user action: wipe the entire recovery session.
    func clearRecoveryBuffer() {
        RecoveryBuffer.clear()
    }

    private func showError(_ message: String) {
        let alert             = NSAlert()
        alert.messageText     = "Error"
        alert.informativeText = message
        alert.alertStyle      = .critical
        alert.runModal()
    }
}
