import AppKit
import Combine

struct ClipboardItem: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let timestamp: Date
    
    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? ""
        return firstLine.count > 100 ? String(firstLine.prefix(100)) + "..." : firstLine
    }
}

class ClipboardManager: ObservableObject {
    @Published var history: [ClipboardItem] = []
    
    private let pasteboard = NSPasteboard.general
    private var changeCount: Int
    private var timer: AnyCancellable?
    
    init() {
        self.changeCount = pasteboard.changeCount
        startMonitoring()
    }
    
    private func startMonitoring() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkPasteboard()
            }
    }
    
    private func checkPasteboard() {
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        
        if let newString = pasteboard.string(forType: .string), !newString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Avoid duplicates in recent history
            if history.first?.text != newString {
                let newItem = ClipboardItem(text: newString, timestamp: Date())
                DispatchQueue.main.async {
                    self.history.insert(newItem, at: 0)
                    // Keep last 50 items
                    if self.history.count > 50 {
                        self.history.removeLast()
                    }
                }
            }
        }
    }
    
    func copyToPasteboard(_ item: ClipboardItem) {
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        self.changeCount = pasteboard.changeCount
    }
    
    func simulatePaste() {
        // Small delay to allow the Velox window to hide and the previous app to regain focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .combinedSessionState)
            
            // Cmd Key Down
            let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
            cmdDown?.flags = .maskCommand
            
            // V Key Down
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            vDown?.flags = .maskCommand
            
            // V Key Up
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            vUp?.flags = .maskCommand
            
            // Cmd Key Up
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
            cmdUp?.flags = .maskNonCoalesced
            
            cmdDown?.post(tap: .cghidEventTap)
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
            cmdUp?.post(tap: .cghidEventTap)
        }
    }
}
