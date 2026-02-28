import SwiftUI
import AppKit
import Carbon
import Carbon.HIToolbox

class CommandBarPanel: NSPanel {
    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: backing, defer: flag)
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        
        // Extra large rounded corners for the "Liquid" feel
        self.cornerRadius = 32
        
        // The background is handled by the SwiftUI VisualEffectView for more control
        self.contentView = NSHostingView(rootView: EmptyView())
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension NSWindow {
    var cornerRadius: CGFloat {
        get { return self.contentView?.layer?.cornerRadius ?? 0 }
        set {
            self.contentView?.wantsLayer = true
            self.contentView?.layer?.cornerRadius = newValue
            self.contentView?.layer?.cornerCurve = .continuous // This is the magic for Squircles
            self.contentView?.layer?.masksToBounds = true
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: CommandBarPanel?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupPanel()
        registerGlobalHotkey()
        
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            self?.hidePanel()
        }
    }
    
    func setupPanel() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let width: CGFloat = 680
        let height: CGFloat = 480
        let rect = NSRect(x: (screen.width - width) / 2, y: screen.height - height - 150, width: width, height: height)
        
        panel = CommandBarPanel(contentRect: rect, backing: .buffered, defer: false)
        
        let contentView = ContentView { [weak self] in
            self?.hidePanel()
        }
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        
        // Directly set the hosting view to enjoy full control over background and vibrancy
        panel?.contentView = hostingView
    }
    
    @objc func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }
    
    func showPanel() {
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Ensure focus returns to the panel's content
        if let firstResponder = panel?.contentView?.subviews.first(where: { $0 is NSHostingView<ContentView> }) {
            panel?.makeFirstResponder(firstResponder)
        }
    }
    
    @objc func hidePanel() {
        panel?.orderOut(nil)
    }
    
    // MARK: - Global Hotkey (Carbon API)
    
    func registerGlobalHotkey() {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x56454c4f), id: 1) // "VELO"
        
        let status = RegisterEventHotKey(49, UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        if status == noErr {
            var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            
            let handler: EventHandlerUPP = { (nextHandler, event, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                appDelegate.togglePanel()
                return noErr
            }
            
            var handlerRef: EventHandlerRef?
            InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        }
    }
}
