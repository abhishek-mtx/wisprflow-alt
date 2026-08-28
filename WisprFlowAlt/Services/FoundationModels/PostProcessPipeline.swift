import AppKit
import Foundation
import SwiftData

struct PostProcessResult: Equatable {
    var raw: String
    var polished: String
    var styleName: String?
    var appBundleIdentifier: String?
    var appDisplayName: String?
}

@MainActor
final class PostProcessPipeline {
    private let polish: FoundationModelsPolish

    init(polish: FoundationModelsPolish) {
        self.polish = polish
    }

    func run(
        raw: String,
        settings: AppSettings,
        context: ModelContext,
        targetBundleID: String? = nil,
        targetAppName: String? = nil
    ) async -> PostProcessResult {
        let front = NSWorkspace.shared.frontmostApplication
        let bundleID = targetBundleID ?? front?.bundleIdentifier
        let appName = targetAppName ?? front?.localizedName

        let dictionary = (try? context.fetch(FetchDescriptor<DictionaryEntry>())) ?? []
        let snippets = (try? context.fetch(FetchDescriptor<SnippetEntry>())) ?? []
        let transforms = (try? context.fetch(FetchDescriptor<TransformRule>())) ?? []
        let styles = (try? context.fetch(FetchDescriptor<StyleProfile>())) ?? []
        let mappings = (try? context.fetch(FetchDescriptor<AppStyleMapping>())) ?? []

        var text = TextNormalizer.normalize(raw)
        text = TextNormalizer.applyDictionary(text, entries: dictionary)
        text = TextNormalizer.applySnippets(text, snippets: snippets)

        let style = resolveStyle(bundleID: bundleID, mappings: mappings, styles: styles)
        let hints = dictionary.filter(\.isEnabled).prefix(80).map(\.replacement)

        let polished: String
        if settings.polishEnabled {
            polished = await polish.polish(
                raw: text,
                styleFragment: style?.promptFragment,
                dictionaryHints: hints
            )
        } else {
            polished = text
        }

        var output = settings.injectPolishedOnly ? polished : text
        if let kind = resolveTransform(bundleID: bundleID, transforms: transforms) {
            output = TextNormalizer.applyTransform(output, kind: kind)
        }

        return PostProcessResult(
            raw: raw,
            polished: output,
            styleName: style?.name,
            appBundleIdentifier: bundleID,
            appDisplayName: appName
        )
    }

    private func resolveStyle(
        bundleID: String?,
        mappings: [AppStyleMapping],
        styles: [StyleProfile]
    ) -> StyleProfile? {
        if let bundleID,
           let mapping = mappings.first(where: { $0.bundleIdentifier == bundleID }),
           let style = styles.first(where: { $0.id == mapping.styleProfileID })
        {
            return style
        }
        return styles.first(where: \.isDefault) ?? styles.first
    }

    private func resolveTransform(
        bundleID: String?,
        transforms: [TransformRule]
    ) -> TransformKind? {
        let enabled = transforms.filter(\.isEnabled)
        if let bundleID,
           let specific = enabled.first(where: { $0.bundleIdentifier == bundleID })
        {
            return specific.transformKind
        }
        return enabled.first(where: { $0.bundleIdentifier == nil })?.transformKind
    }
}
