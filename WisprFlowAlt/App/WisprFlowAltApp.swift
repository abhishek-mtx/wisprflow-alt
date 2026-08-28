import SwiftUI
import SwiftData

@main
struct WisprFlowAltApp: App {
    @NSApplicationDelegateAdaptor(CadenceAppDelegate.self) private var appDelegate
    @State private var appModel = AppModel()

    init() {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appModel)
                .modelContainer(appModel.modelContainer)
                .frame(minWidth: 560, minHeight: 420)
                .background(PinWindowToActiveSpace())
        }

        Window("Onboarding", id: "onboarding") {
            OnboardingView()
                .environment(appModel)
                .modelContainer(appModel.modelContainer)
                .frame(width: 520, height: 460)
                .background(PinWindowToActiveSpace())
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: AppSettings.onboardingDefaultsKey) ? .suppressed : .presented)
        .restorationBehavior(.disabled)
    }
}
