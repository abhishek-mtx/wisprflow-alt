import Foundation
import Observation

@Observable
final class AppSettings {
    static let onboardingDefaultsKey = "settings.hasCompletedOnboarding"

    private let defaults = UserDefaults.standard

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.onboarding) }
        set { defaults.set(newValue, forKey: Keys.onboarding) }
    }

    var polishEnabled: Bool {
        get { defaults.object(forKey: Keys.polish) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.polish) }
    }

    var injectPolishedOnly: Bool {
        get { defaults.object(forKey: Keys.injectPolished) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.injectPolished) }
    }

    var showHUD: Bool {
        get { defaults.object(forKey: Keys.hud) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.hud) }
    }

    var preferredLocaleIdentifier: String {
        get {
            let raw = defaults.string(forKey: Keys.locale) ?? Locale.current.identifier
            return Self.normalizedSpeechLocale(raw)
        }
        set { defaults.set(Self.normalizedSpeechLocale(newValue), forKey: Keys.locale) }
    }

    private static func normalizedSpeechLocale(_ preferred: String) -> String {
        let stripped = preferred
            .replacingOccurrences(of: "_", with: "-")
            .components(separatedBy: "@").first ?? preferred
        if stripped.count >= 2 { return stripped }
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier ?? "US"
        return "\(lang)-\(region)"
    }

    var pushToTalkShortcut: KeyShortcut {
        get {
            let decoded = KeyShortcut.decode(defaults.data(forKey: Keys.ptt))
                ?? KeyShortcut.defaultPushToTalk
            if !defaults.bool(forKey: Keys.pttFnMigration) {
                return .defaultPushToTalk
            }
            return decoded
        }
        set {
            defaults.set(newValue.encode(), forKey: Keys.ptt)
            defaults.set(true, forKey: Keys.pttFnMigration)
        }
    }

    var commandModeShortcut: KeyShortcut {
        get {
            KeyShortcut.decode(defaults.data(forKey: Keys.command))
                ?? KeyShortcut.defaultCommandMode
        }
        set {
            defaults.set(newValue.encode(), forKey: Keys.command)
        }
    }

    var doubleTapHandsFreeEnabled: Bool {
        // Default off — Fn flagsChanged often looks like a double-tap and leaves Cadence
        // stuck in hands-free while the user thinks push-to-talk "isn't working".
        get { defaults.object(forKey: Keys.handsFree) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.handsFree) }
    }

    var doubleTapThresholdMs: Int {
        get {
            let value = defaults.integer(forKey: Keys.doubleTapMs)
            return value > 0 ? value : 350
        }
        set { defaults.set(newValue, forKey: Keys.doubleTapMs) }
    }

    private enum Keys {
        static let onboarding = AppSettings.onboardingDefaultsKey
        static let polish = "settings.polishEnabled"
        static let injectPolished = "settings.injectPolishedOnly"
        static let hud = "settings.showHUD"
        static let locale = "settings.preferredLocale"
        static let ptt = "settings.pushToTalkShortcut"
        static let pttFnMigration = "settings.pttMigratedToFn"
        static let command = "settings.commandModeShortcut"
        static let handsFree = "settings.doubleTapHandsFree"
        static let doubleTapMs = "settings.doubleTapThresholdMs"
    }
}
