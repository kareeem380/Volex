import SwiftUI

@main
struct VeloxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty scene as the window is managed by NSPanel in AppDelegate
        Settings { 
            EmptyView()
        }
    }
}
