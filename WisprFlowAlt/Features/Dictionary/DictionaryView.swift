import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DictionaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DictionaryEntry.phrase) private var entries: [DictionaryEntry]
    @State private var phrase = ""
    @State private var replacementText = ""
    @State private var search = ""
    @State private var caseSensitive = false

    private var filtered: [DictionaryEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter {
            $0.phrase.localizedCaseInsensitiveContains(search)
                || $0.replacement.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Add word or replacement") {
                    TextField("Phrase (as spoken / recognized)", text: $phrase)
                    TextField("Written form", text: $replacementText)
                    Toggle("Case sensitive", isOn: $caseSensitive)
                    Button("Add to Dictionary") { addEntry() }
                        .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .formStyle(.grouped)
            .frame(height: 180)

            HStack {
                TextField("Search dictionary", text: $search)
                    .textFieldStyle(.roundedBorder)
                Button("Import CSV…", action: importCSV)
                Button("Export CSV…", action: exportCSV)
                    .disabled(entries.isEmpty)
            }
            .padding(.horizontal)

            List {
                ForEach(filtered, id: \.id) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.phrase).font(.body.weight(.medium))
                            if entry.replacement != entry.phrase {
                                Text("→ \(entry.replacement)")
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.source.rawValue.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle("On", isOn: Binding(
                            get: { entry.isEnabled },
                            set: {
                                entry.isEnabled = $0
                                entry.updatedAt = Date()
                                try? modelContext.save()
                            }
                        ))
                        .labelsHidden()
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .padding(.top, 8)
    }

    private func addEntry() {
        let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        let entry = DictionaryEntry(
            phrase: p,
            replacement: r.isEmpty ? p : r,
            caseSensitive: caseSensitive,
            source: .manual
        )
        modelContext.insert(entry)
        try? modelContext.save()
        phrase = ""
        replacementText = ""
        caseSensitive = false
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filtered[index])
        }
        try? modelContext.save()
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? String(contentsOf: url, encoding: .utf8)
        else { return }

        for line in data.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let phrase = parts.first, !phrase.isEmpty, phrase.lowercased() != "phrase" else { continue }
            let replacement = parts.count > 1 ? parts[1] : phrase
            modelContext.insert(DictionaryEntry(
                phrase: phrase,
                replacement: replacement,
                source: .imported
            ))
        }
        try? modelContext.save()
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "dictionary.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var csv = "phrase,replacement\n"
        for entry in entries {
            csv += "\(escapeCSV(entry.phrase)),\(escapeCSV(entry.replacement))\n"
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

import AppKit
