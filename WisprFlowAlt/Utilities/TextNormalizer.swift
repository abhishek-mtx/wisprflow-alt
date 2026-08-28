import Foundation

struct DictionaryReplacement: Equatable, Sendable {
    var phrase: String
    var replacement: String
    var caseSensitive: Bool
    var isEnabled: Bool

    init(phrase: String, replacement: String, caseSensitive: Bool = false, isEnabled: Bool = true) {
        self.phrase = phrase
        self.replacement = replacement
        self.caseSensitive = caseSensitive
        self.isEnabled = isEnabled
    }
}

struct SnippetReplacement: Equatable, Sendable {
    var trigger: String
    var expansion: String
    var isEnabled: Bool

    init(trigger: String, expansion: String, isEnabled: Bool = true) {
        self.trigger = trigger
        self.expansion = expansion
        self.isEnabled = isEnabled
    }
}

enum TextNormalizer {
    static func normalize(_ input: String) -> String {
        var text = input
        let spoken: [(String, String)] = [
            (#"(?i)\bnew\s+line\b"#, "\n"),
            (#"(?i)\bnewline\b"#, "\n"),
            (#"(?i)\bnew\s+paragraph\b"#, "\n\n"),
            (#"(?i)\bcomma\b"#, ","),
            (#"(?i)\bperiod\b"#, "."),
            (#"(?i)\bfull\s+stop\b"#, "."),
            (#"(?i)\bquestion\s+mark\b"#, "?"),
            (#"(?i)\bexclamation\s+(?:mark|point)\b"#, "!"),
            (#"(?i)\bcolon\b"#, ":"),
            (#"(?i)\bsemicolon\b"#, ";"),
            (#"(?i)\bopen\s+quote\b"#, "\""),
            (#"(?i)\bclose\s+quote\b"#, "\""),
        ]
        for (pattern, replacement) in spoken {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
            }
        }
        text = text.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func applyDictionary(_ text: String, entries: [DictionaryReplacement]) -> String {
        var result = text
        let enabled = entries.filter(\.isEnabled).sorted { $0.phrase.count > $1.phrase.count }
        for entry in enabled {
            let phrase = entry.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { continue }
            if entry.caseSensitive {
                result = result.replacingOccurrences(of: phrase, with: entry.replacement)
                continue
            }
            // Prefer whole-phrase matches so "ai" inside "said" is not rewritten.
            let pattern = #"\b\#(NSRegularExpression.escapedPattern(for: phrase))\b"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: NSRegularExpression.escapedTemplate(for: entry.replacement)
                )
            }
        }
        return result
    }

    static func applyDictionary(_ text: String, entries: [DictionaryEntry]) -> String {
        applyDictionary(
            text,
            entries: entries.map {
                DictionaryReplacement(
                    phrase: $0.phrase,
                    replacement: $0.replacement,
                    caseSensitive: $0.caseSensitive,
                    isEnabled: $0.isEnabled
                )
            }
        )
    }

    static func applySnippets(_ text: String, snippets: [SnippetReplacement]) -> String {
        var result = text
        let enabled = snippets.filter(\.isEnabled).sorted { $0.trigger.count > $1.trigger.count }
        for snippet in enabled {
            if let regex = try? NSRegularExpression(
                pattern: #"\b\#(NSRegularExpression.escapedPattern(for: snippet.trigger))\b"#,
                options: [.caseInsensitive]
            ) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: NSRegularExpression.escapedTemplate(for: snippet.expansion)
                )
            }
        }
        return result
    }

    static func applySnippets(_ text: String, snippets: [SnippetEntry]) -> String {
        applySnippets(
            text,
            snippets: snippets.map {
                SnippetReplacement(trigger: $0.trigger, expansion: $0.expansion, isEnabled: $0.isEnabled)
            }
        )
    }

    static func applyTransform(_ text: String, kind: TransformKind) -> String {
        switch kind {
        case .none:
            return text
        case .titleCase:
            return text.capitalized
        case .upperCase:
            return text.uppercased()
        case .lowerCase:
            return text.lowercased()
        case .trimWhitespace:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
