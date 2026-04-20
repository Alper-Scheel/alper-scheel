import SwiftUI

@main
struct ALVA_TEXTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.coordinator)
                .frame(width: 520, height: 420)
        }
    }
}
