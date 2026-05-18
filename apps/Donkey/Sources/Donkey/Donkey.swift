import SwiftUI

@main
struct Donkey: App {
    @NSApplicationDelegateAdaptor(DonkeyAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            LocalRuntimeSettingsView()
        }
    }
}

private struct LocalRuntimeSettingsView: View {
    @State private var runtimeSetupController: LocalRuntimeOnboardingWindowController?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Runtimes")
                .font(.headline)
            Text("Reopen setup to install, repair, or recheck Donkey's local model sidecars.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set Up Local Runtimes") {
                let controller = LocalRuntimeOnboardingWindowController()
                runtimeSetupController = controller
                controller.showSetup()
            }
        }
        .padding(20)
        .frame(width: 420, alignment: .leading)
    }
}
