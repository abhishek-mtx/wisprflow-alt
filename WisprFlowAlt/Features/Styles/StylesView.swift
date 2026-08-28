import SwiftData
import SwiftUI

struct StylesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StyleProfile.name) private var styles: [StyleProfile]
    @Query(sort: \AppStyleMapping.appDisplayName) private var mappings: [AppStyleMapping]

    @State private var name = ""
    @State private var prompt = ""
    @State private var bundleID = ""
    @State private var appName = ""
    @State private var selectedStyleID: UUID?

    var body: some View {
        HSplitView {
            List {
                Section("Style profiles") {
                    ForEach(styles, id: \.id) { style in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(style.name).font(.headline)
                                if style.isDefault {
                                    Text("Default")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.15), in: Capsule())
                                }
                            }
                            Text(style.promptFragment)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            Button("Make default") {
                                for s in styles { s.isDefault = false }
                                style.isDefault = true
                                try? modelContext.save()
                            }
                            .disabled(style.isDefault)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        for i in indexSet { modelContext.delete(styles[i]) }
                        try? modelContext.save()
                    }
                }

                Section("Add profile") {
                    TextField("Name", text: $name)
                    TextField("Prompt guidance", text: $prompt, axis: .vertical)
                        .lineLimit(3...6)
                    Button("Add Style") {
                        let style = StyleProfile(name: name, promptFragment: prompt)
                        modelContext.insert(style)
                        try? modelContext.save()
                        name = ""
                        prompt = ""
                    }
                    .disabled(name.isEmpty || prompt.isEmpty)
                }
            }
            .frame(minWidth: 280)

            List {
                Section("Per-app mappings") {
                    ForEach(mappings, id: \.id) { mapping in
                        VStack(alignment: .leading) {
                            Text(mapping.appDisplayName).font(.headline)
                            Text(mapping.bundleIdentifier)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text("Style: \(styles.first(where: { $0.id == mapping.styleProfileID })?.name ?? "Missing")")
                                .font(.caption)
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet { modelContext.delete(mappings[i]) }
                        try? modelContext.save()
                    }
                }

                Section("Map frontmost / custom app") {
                    TextField("Display name", text: $appName)
                    TextField("Bundle identifier", text: $bundleID)
                    Picker("Style", selection: $selectedStyleID) {
                        Text("Select…").tag(Optional<UUID>.none)
                        ForEach(styles, id: \.id) { style in
                            Text(style.name).tag(Optional(style.id))
                        }
                    }
                    Button("Use Frontmost App") {
                        if let app = NSWorkspace.shared.frontmostApplication {
                            appName = app.localizedName ?? appName
                            bundleID = app.bundleIdentifier ?? bundleID
                        }
                    }
                    Button("Add Mapping") {
                        guard let selectedStyleID, !bundleID.isEmpty else { return }
                        modelContext.insert(AppStyleMapping(
                            bundleIdentifier: bundleID,
                            appDisplayName: appName.isEmpty ? bundleID : appName,
                            styleProfileID: selectedStyleID
                        ))
                        try? modelContext.save()
                        appName = ""
                        bundleID = ""
                    }
                    .disabled(selectedStyleID == nil || bundleID.isEmpty)
                }
            }
            .frame(minWidth: 280)
        }
        .padding()
    }
}

import AppKit
