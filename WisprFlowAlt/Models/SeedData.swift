import Foundation
import SwiftData

enum SeedData {
    static func ensureDefaults(in context: ModelContext) {
        let styleDescriptor = FetchDescriptor<StyleProfile>()
        let existingStyles = (try? context.fetch(styleDescriptor)) ?? []
        if existingStyles.isEmpty {
            let casual = StyleProfile(
                name: "Casual",
                promptFragment: "Write casually and warmly, like a text message. Keep it concise.",
                isDefault: true
            )
            let formal = StyleProfile(
                name: "Formal",
                promptFragment: "Write in a clear, professional tone suitable for email or workplace chat. Prefer complete sentences.",
                isDefault: false
            )
            let code = StyleProfile(
                name: "Technical",
                promptFragment: "Preserve identifiers, code tokens, and technical terms exactly. Prefer precise, terse wording.",
                isDefault: false
            )
            context.insert(casual)
            context.insert(formal)
            context.insert(code)

            let mappings: [(String, String, StyleProfile)] = [
                ("com.apple.MobileSMS", "Messages", casual),
                ("com.tinyspeck.slackmacgap", "Slack", formal),
                ("com.apple.mail", "Mail", formal),
                ("com.microsoft.Outlook", "Outlook", formal),
                ("com.todesktop.230313mzl4w4u92", "Cursor", code),
                ("com.microsoft.VSCode", "Visual Studio Code", code),
                ("com.apple.Terminal", "Terminal", code),
                ("com.googlecode.iterm2", "iTerm2", code)
            ]
            for (bundle, name, style) in mappings {
                context.insert(AppStyleMapping(
                    bundleIdentifier: bundle,
                    appDisplayName: name,
                    styleProfileID: style.id
                ))
            }
        }

        let snippetDescriptor = FetchDescriptor<SnippetEntry>()
        if ((try? context.fetch(snippetDescriptor)) ?? []).isEmpty {
            context.insert(SnippetEntry(trigger: "my email", expansion: "you@example.com"))
            context.insert(SnippetEntry(trigger: "my phone", expansion: "+1-555-0100"))
        }

        let injectDescriptor = FetchDescriptor<InjectionProfile>()
        let existingProfiles = (try? context.fetch(injectDescriptor)) ?? []
        if existingProfiles.isEmpty {
            context.insert(InjectionProfile(
                bundleIdentifier: "com.apple.Terminal",
                appDisplayName: "Terminal",
                preferredStrategy: .clipboard,
                notes: "AX insertion is unreliable in Terminal; prefer clipboard paste."
            ))
            context.insert(InjectionProfile(
                bundleIdentifier: "com.googlecode.iterm2",
                appDisplayName: "iTerm2",
                preferredStrategy: .clipboard,
                notes: "Prefer clipboard paste for terminal emulators."
            ))
            context.insert(InjectionProfile(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                appDisplayName: "Slack",
                preferredStrategy: .auto,
                notes: "Electron app — try AX then clipboard."
            ))
        }
        ensureInjectionProfile(
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            appDisplayName: "Cursor",
            strategy: .clipboard,
            notes: "Electron chat composer — clipboard paste; keep text on pasteboard.",
            in: context
        )
        ensureInjectionProfile(
            bundleIdentifier: "com.microsoft.VSCode",
            appDisplayName: "Visual Studio Code",
            strategy: .clipboard,
            notes: "Electron — clipboard paste.",
            in: context
        )

        seedCorporateAIDictionary(in: context)

        try? context.save()
    }

    private static let dictionarySeedKey = "seed.corporateAIDictionaryVersion"

    private static func seedCorporateAIDictionary(in context: ModelContext) {
        let defaults = UserDefaults.standard
        let installed = defaults.integer(forKey: dictionarySeedKey)
        let existing = ((try? context.fetch(FetchDescriptor<DictionaryEntry>())) ?? [])
        let existingKeys = Set(existing.map { $0.phrase.lowercased() })

        var added = 0
        for (phrase, replacement) in CorporateAIDictionary.corrections {
            let key = phrase.lowercased()
            guard !existingKeys.contains(key) else { continue }
            context.insert(DictionaryEntry(
                phrase: phrase,
                replacement: replacement,
                caseSensitive: false,
                isEnabled: true,
                source: .imported
            ))
            added += 1
        }
        for hint in CorporateAIDictionary.vocabularyHints {
            let key = hint.lowercased()
            guard !existingKeys.contains(key) else { continue }
            // Skip if already covered as a correction phrase.
            if CorporateAIDictionary.corrections.contains(where: { $0.0.lowercased() == key }) {
                continue
            }
            context.insert(DictionaryEntry(
                phrase: hint,
                replacement: hint,
                caseSensitive: false,
                isEnabled: true,
                source: .imported
            ))
            added += 1
        }

        if installed < CorporateAIDictionary.seedVersion || added > 0 {
            defaults.set(CorporateAIDictionary.seedVersion, forKey: dictionarySeedKey)
            CadenceLog.info("Dictionary seed v\(CorporateAIDictionary.seedVersion) added \(added) terms")
        }
    }

    private static func ensureInjectionProfile(
        bundleIdentifier: String,
        appDisplayName: String,
        strategy: InjectionStrategyPreference,
        notes: String,
        in context: ModelContext
    ) {
        let bundle = bundleIdentifier
        var descriptor = FetchDescriptor<InjectionProfile>(
            predicate: #Predicate { $0.bundleIdentifier == bundle }
        )
        descriptor.fetchLimit = 1
        if (try? context.fetch(descriptor).first) != nil { return }
        context.insert(InjectionProfile(
            bundleIdentifier: bundleIdentifier,
            appDisplayName: appDisplayName,
            preferredStrategy: strategy,
            notes: notes
        ))
    }
}
