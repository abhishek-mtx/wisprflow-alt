import SwiftData
import SwiftUI
import AppKit

struct InjectionProfilesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InjectionProfile.appDisplayName) private var profiles: [InjectionProfile]

    @State private var appName = ""
    @State private var bundleID = ""
    @State private var strategy: InjectionStrategyPreference = .auto
    @State private var notes = ""

    var body: some View {
        VStack {
            Form {
                Section("Per-app injection strategy") {
                    Text("When Auto fails in a specific app, force Clipboard or Accessibility here.")
                        .foregroundStyle(.secondary)
                    TextField("App name", text: $appName)
                    TextField("Bundle identifier", text: $bundleID)
                    Picker("Strategy", selection: $strategy) {
                        ForEach(InjectionStrategyPreference.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField("Notes", text: $notes)
                    HStack {
                        Button("Use Frontmost App") {
                            if let app = NSWorkspace.shared.frontmostApplication {
                                appName = app.localizedName ?? ""
                                bundleID = app.bundleIdentifier ?? ""
                            }
                        }
                        Button("Add Profile") {
                            guard !bundleID.isEmpty else { return }
                            modelContext.insert(InjectionProfile(
                                bundleIdentifier: bundleID,
                                appDisplayName: appName.isEmpty ? bundleID : appName,
                                preferredStrategy: strategy,
                                notes: notes
                            ))
                            try? modelContext.save()
                            appName = ""
                            bundleID = ""
                            notes = ""
                            strategy = .auto
                        }
                        .disabled(bundleID.isEmpty)
                    }
                }
            }
            .formStyle(.grouped)

            List {
                ForEach(profiles, id: \.id) { profile in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(profile.appDisplayName).font(.headline)
                            Spacer()
                            Picker("Strategy", selection: Binding(
                                get: { profile.preferredStrategy },
                                set: {
                                    profile.preferredStrategy = $0
                                    try? modelContext.save()
                                }
                            )) {
                                ForEach(InjectionStrategyPreference.allCases) { item in
                                    Text(item.displayName).tag(item)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        }
                        Text(profile.bundleIdentifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        if !profile.notes.isEmpty {
                            Text(profile.notes)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { modelContext.delete(profiles[i]) }
                    try? modelContext.save()
                }
            }
        }
        .padding(.top, 8)
    }
}
