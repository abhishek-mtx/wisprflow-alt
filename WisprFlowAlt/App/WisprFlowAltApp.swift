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
        Window("Cadence", id: "studio") {
            CadenceStudioView()
                .environment(appModel)
                .modelContainer(appModel.modelContainer)
                .background(PinWindowToActiveSpace())
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: AppSettings.onboardingDefaultsKey) ? .presented : .suppressed)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            MenuBarView()
                .environment(appModel)
                .modelContainer(appModel.modelContainer)
        } label: {
            MenuBarLabel(state: appModel.session.state)
        }
        .menuBarExtraStyle(.menu)

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
