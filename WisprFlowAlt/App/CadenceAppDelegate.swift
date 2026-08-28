import AppKit

final class CadenceAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool { false }
    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        CadenceWindowSpace.pinVisibleChrome()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        CadenceWindowSpace.pinVisibleChrome()
        let onboardingDone = UserDefaults.standard.bool(forKey: AppSettings.onboardingDefaultsKey)
        let studioVisible = NSApp.windows.contains { window in
            window.title == "Cadence" && window.isVisible && window.frame.height >= 40
        }
        if onboardingDone && studioVisible == false {
            CadenceWindowSpace.revealStudio()
        }
    }
}
