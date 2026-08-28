import Foundation
import FoundationModels
import Observation

@MainActor
@Observable
final class FoundationModelsPolish {
    var isAvailable: Bool = false
    var lastError: String?

    private var session: LanguageModelSession?

    init() {
        refreshAvailability()
    }

    func refreshAvailability() {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            isAvailable = true
            if session == nil {
                session = LanguageModelSession(model: model)
            }
        default:
            isAvailable = false
            session = nil
        }
    }

    func polish(
        raw: String,
        styleFragment: String?,
        dictionaryHints: [String]
    ) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        refreshAvailability()
        guard isAvailable, let session else {
            lastError = "Apple Intelligence / Foundation Models unavailable"
            return SpokenTextCleanup.minimal(trimmed)
        }

        var instructions = """
        You clean spoken dictation into written text.
        Remove filler words (um, uh, like, you know) when they are not meaningful.
        Fix punctuation and capitalization.
        Apply mid-sentence corrections (keep the corrected intent, drop retracted words).
        Preserve proper nouns, code identifiers, and user dictionary terms exactly.
        Do NOT insert periods before words like I, I'm, or after conjunctions (and, or, but).
        Return ONLY the cleaned text with no quotes or commentary.
        """
        if let styleFragment, !styleFragment.isEmpty {
            instructions += "\nStyle guidance: \(styleFragment)"
        }
        if !dictionaryHints.isEmpty {
            instructions += "\nPreferred spellings: \(dictionaryHints.joined(separator: ", "))"
        }

        do {
            let prompt = """
            \(instructions)

            Dictation:
            \(trimmed)
            """
            let response = try await session.respond(to: prompt)
            let text = String(describing: response.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? SpokenTextCleanup.minimal(trimmed) : text
        } catch {
            lastError = error.localizedDescription
            return SpokenTextCleanup.minimal(trimmed)
        }
    }

    func rewrite(instruction: String, target: String) async -> String {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, !target.isEmpty else { return target }
        refreshAvailability()
        guard isAvailable, let session else {
            lastError = "Apple Intelligence / Foundation Models unavailable"
            return target
        }

        let prompt = """
        You edit text based on a spoken instruction.
        Apply the instruction to the text.
        Return ONLY the rewritten text with no quotes or commentary.
        Do not execute system actions; text rewrite only.

        Instruction:
        \(instruction)

        Text:
        \(target)
        """
        do {
            let response = try await session.respond(to: prompt)
            let text = String(describing: response.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? target : text
        } catch {
            lastError = error.localizedDescription
            return target
        }
    }
}
