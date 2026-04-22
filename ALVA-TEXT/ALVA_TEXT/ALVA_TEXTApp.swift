import SwiftUI

@main
struct ALVA_TEXTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Pure menu-bar app: the actual settings window is opened by
    // AppCoordinator.openSettings() as a standalone NSWindow.
    // SwiftUI's App protocol still requires at least one Scene,
    // so we keep a minimal, never-shown Settings scene as a stub.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
