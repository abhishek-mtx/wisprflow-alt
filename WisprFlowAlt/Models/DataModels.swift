import Foundation
import SwiftData

@Model
final class DictionaryEntry {
    var id: UUID
    var phrase: String
    var replacement: String
    var localeIdentifier: String
    var caseSensitive: Bool
    var isEnabled: Bool
    var sourceRaw: String
    var createdAt: Date
    var updatedAt: Date

    var source: DictionarySource {
        get { DictionarySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        phrase: String,
        replacement: String,
        localeIdentifier: String = Locale.current.identifier,
        caseSensitive: Bool = false,
        isEnabled: Bool = true,
        source: DictionarySource = .manual
    ) {
        self.id = UUID()
        self.phrase = phrase
        self.replacement = replacement
        self.localeIdentifier = localeIdentifier
        self.caseSensitive = caseSensitive
        self.isEnabled = isEnabled
        self.sourceRaw = source.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

enum DictionarySource: String, Codable, CaseIterable {
    case manual
    case learned
    case imported
}

@Model
final class StyleProfile {
    var id: UUID
    var name: String
    var promptFragment: String
    var isDefault: Bool
    var createdAt: Date

    init(name: String, promptFragment: String, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.promptFragment = promptFragment
        self.isDefault = isDefault
        self.createdAt = Date()
    }
}

@Model
final class AppStyleMapping {
    var id: UUID
    var bundleIdentifier: String
    var appDisplayName: String
    var styleProfileID: UUID
    var createdAt: Date

    init(bundleIdentifier: String, appDisplayName: String, styleProfileID: UUID) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.appDisplayName = appDisplayName
        self.styleProfileID = styleProfileID
        self.createdAt = Date()
    }
}

@Model
final class SnippetEntry {
    var id: UUID
    var trigger: String
    var expansion: String
    var isEnabled: Bool
    var createdAt: Date

    init(trigger: String, expansion: String, isEnabled: Bool = true) {
        self.id = UUID()
        self.trigger = trigger
        self.expansion = expansion
        self.isEnabled = isEnabled
        self.createdAt = Date()
    }
}

@Model
final class TransformRule {
    var id: UUID
    var name: String
    var bundleIdentifier: String?
    var transformKindRaw: String
    var isEnabled: Bool
    var createdAt: Date

    var transformKind: TransformKind {
        get { TransformKind(rawValue: transformKindRaw) ?? .none }
        set { transformKindRaw = newValue.rawValue }
    }

    init(name: String, bundleIdentifier: String? = nil, transformKind: TransformKind, isEnabled: Bool = true) {
        self.id = UUID()
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.transformKindRaw = transformKind.rawValue
        self.isEnabled = isEnabled
        self.createdAt = Date()
    }
}

enum TransformKind: String, Codable, CaseIterable, Identifiable {
    case none
    case titleCase
    case upperCase
    case lowerCase
    case trimWhitespace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .titleCase: "Title Case"
        case .upperCase: "UPPERCASE"
        case .lowerCase: "lowercase"
        case .trimWhitespace: "Trim Whitespace"
        }
    }
}

@Model
final class TranscriptRecord {
    var id: UUID
    var rawText: String
    var polishedText: String
    var appBundleIdentifier: String?
    var appDisplayName: String?
    var wordCount: Int
    var durationSeconds: Double
    var createdAt: Date

    init(
        rawText: String,
        polishedText: String,
        appBundleIdentifier: String?,
        appDisplayName: String?,
        wordCount: Int,
        durationSeconds: Double
    ) {
        self.id = UUID()
        self.rawText = rawText
        self.polishedText = polishedText
        self.appBundleIdentifier = appBundleIdentifier
        self.appDisplayName = appDisplayName
        self.wordCount = wordCount
        self.durationSeconds = durationSeconds
        self.createdAt = Date()
    }
}

@Model
final class InjectionProfile {
    var id: UUID
    var bundleIdentifier: String
    var appDisplayName: String
    var preferredStrategyRaw: String
    var notes: String
    var createdAt: Date

    var preferredStrategy: InjectionStrategyPreference {
        get { InjectionStrategyPreference(rawValue: preferredStrategyRaw) ?? .auto }
        set { preferredStrategyRaw = newValue.rawValue }
    }

    init(
        bundleIdentifier: String,
        appDisplayName: String,
        preferredStrategy: InjectionStrategyPreference = .auto,
        notes: String = ""
    ) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.appDisplayName = appDisplayName
        self.preferredStrategyRaw = preferredStrategy.rawValue
        self.notes = notes
        self.createdAt = Date()
    }
}

enum InjectionStrategyPreference: String, Codable, CaseIterable, Identifiable {
    case auto
    case accessibility
    case clipboard
    case keyEvents

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Auto (fallback chain)"
        case .accessibility: "Accessibility only"
        case .clipboard: "Clipboard paste"
        case .keyEvents: "Keyboard simulation"
        }
    }
}
