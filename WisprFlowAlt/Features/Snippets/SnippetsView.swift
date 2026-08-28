import SwiftData
import SwiftUI

struct SnippetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SnippetEntry.trigger) private var snippets: [SnippetEntry]
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack {
            Form {
                Section("Add snippet") {
                    TextField("Spoken trigger", text: $trigger)
                    TextField("Expansion", text: $expansion, axis: .vertical)
                        .lineLimit(2...5)
                    Button("Add Snippet") {
                        let t = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty, !expansion.isEmpty else { return }
                        modelContext.insert(SnippetEntry(trigger: t, expansion: expansion))
                        try? modelContext.save()
                        trigger = ""
                        expansion = ""
                    }
                }
            }
            .formStyle(.grouped)

            List {
                ForEach(snippets, id: \.id) { snippet in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(snippet.trigger).font(.headline)
                            Spacer()
                            Toggle("On", isOn: Binding(
                                get: { snippet.isEnabled },
                                set: {
                                    snippet.isEnabled = $0
                                    try? modelContext.save()
                                }
                            ))
                            .labelsHidden()
                        }
                        Text(snippet.expansion)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { modelContext.delete(snippets[i]) }
                    try? modelContext.save()
                }
            }
        }
        .padding(.top, 8)
    }
}

struct TransformsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransformRule.name) private var rules: [TransformRule]
    @State private var name = ""
    @State private var bundleID = ""
    @State private var kind: TransformKind = .titleCase

    var body: some View {
        VStack {
            Form {
                Section("Add transform") {
                    TextField("Name", text: $name)
                    TextField("Bundle ID (optional — empty = global)", text: $bundleID)
                    Picker("Transform", selection: $kind) {
                        ForEach(TransformKind.allCases.filter { $0 != .none }) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    Button("Add Rule") {
                        guard !name.isEmpty else { return }
                        modelContext.insert(TransformRule(
                            name: name,
                            bundleIdentifier: bundleID.isEmpty ? nil : bundleID,
                            transformKind: kind
                        ))
                        try? modelContext.save()
                        name = ""
                        bundleID = ""
                    }
                }
            }
            .formStyle(.grouped)

            List {
                ForEach(rules, id: \.id) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.name).font(.headline)
                            Text(rule.transformKind.displayName)
                                .foregroundStyle(.secondary)
                            Text(rule.bundleIdentifier ?? "All apps")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle("On", isOn: Binding(
                            get: { rule.isEnabled },
                            set: {
                                rule.isEnabled = $0
                                try? modelContext.save()
                            }
                        ))
                        .labelsHidden()
                    }
                }
                .onDelete { offsets in
                    for i in offsets { modelContext.delete(rules[i]) }
                    try? modelContext.save()
                }
            }
        }
        .padding(.top, 8)
    }
}
