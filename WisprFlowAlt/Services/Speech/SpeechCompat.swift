import AVFoundation
import Speech

extension SpeechTranscriber {
    /// Hook for locale preparation after AssetInventory install.
    /// Current macOS 26 Speech SDK does not expose `allocate(locale:)`.
    func prepareLocale(_ locale: Locale) async throws {
        _ = locale
    }
}

extension SpeechAnalyzer {
    static func preferredFormat(for modules: [any SpeechModule]) async -> AVAudioFormat? {
        await bestAvailableAudioFormat(compatibleWith: modules)
    }
}
