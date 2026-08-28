import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranscriptRecord.createdAt, order: .reverse) private var records: [TranscriptRecord]
    @State private var selected: TranscriptRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(StatsStore.shared.todayWords) words today · streak \(StatsStore.shared.streak) · \(StatsStore.shared.totalWords) total")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Export JSON…", action: exportJSON)
                    .disabled(records.isEmpty)
                Button("Clear History", role: .destructive) {
                    for record in records { modelContext.delete(record) }
                    try? modelContext.save()
                }
                .disabled(records.isEmpty)
            }
            .padding(.horizontal)
            .padding(.top)

            List(selection: $selected) {
                ForEach(records, id: \.id) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(record.appDisplayName ?? "Unknown app")
                                .font(.headline)
                            Spacer()
                            Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(record.polishedText)
                            .lineLimit(3)
                        if record.rawText != record.polishedText {
                            Text("Raw: \(record.rawText)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                        Text("\(record.wordCount) words · \(record.durationSeconds.formatted(.number.precision(.fractionLength(1))))s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(record)
                    .contextMenu {
                        Button("Copy polished") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.polishedText, forType: .string)
                        }
                        Button("Copy raw") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.rawText, forType: .string)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { modelContext.delete(records[i]) }
                    try? modelContext.save()
                }
            }
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "transcripts.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let payload = records.map {
            [
                "id": $0.id.uuidString,
                "raw": $0.rawText,
                "polished": $0.polishedText,
                "app": $0.appDisplayName ?? "",
                "bundle": $0.appBundleIdentifier ?? "",
                "words": String($0.wordCount),
                "duration": String($0.durationSeconds),
                "createdAt": ISO8601DateFormatter().string(from: $0.createdAt)
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: url)
        }
    }
}

import AppKit
import UniformTypeIdentifiers
