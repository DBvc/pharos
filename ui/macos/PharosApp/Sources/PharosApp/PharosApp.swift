import SwiftUI
import AppKit

@main
struct PharosApp: App {
    @StateObject private var appState = AppState(api: APIClient())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task { await appState.refreshToday() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Quick Capture") {
                    appState.showCapture = true
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }

        MenuBarExtra("Pharos", systemImage: "antenna.radiowaves.left.and.right") {
            Button("Open Pharos") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Quick Capture") {
                appState.showCapture = true
            }
            Divider()
            Button("Refresh") {
                Task { await appState.refreshToday() }
            }
            Divider()
            Text("Needs Decision: \(appState.snapshot?.needsDecision.count ?? 0)")
        }
    }
}
