import AppKit

final class CadenceAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool { false }
    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        CadenceWindowSpace.pinVisibleChrome()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        CadenceWindowSpace.pinVisibleChrome()
        let onboardingDone = UserDefaults.standard.bool(forKey: AppSettings.onboardingDefaultsKey)
        if onboardingDone {
            CadenceStudioWindow.shared.present()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag == false {
            CadenceStudioWindow.shared.present()
        }
        return true
    }
}
