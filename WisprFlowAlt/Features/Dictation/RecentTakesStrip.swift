import AppKit
import SwiftData
import SwiftUI

enum RecentTakes {
    static let visibleLimit = 5

    static func newestFive<T>(_ records: [T]) -> [T] {
        Array(records.prefix(visibleLimit))
    }
}

struct RecentTakesStrip: View {
    var livePartial: String
    var isLive: Bool

    @Query private var records: [TranscriptRecord]

    @State private var copiedID: UUID?

    init(livePartial: String, isLive: Bool) {
        self.livePartial = livePartial
        self.isLive = isLive
        var descriptor = FetchDescriptor<TranscriptRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = RecentTakes.visibleLimit
        _records = Query(descriptor)
    }

    private var savedRows: [TranscriptRecord] {
        let cap = isLive ? RecentTakes.visibleLimit - 1 : RecentTakes.visibleLimit
        return Array(records.prefix(cap))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isLive ? "Listening" : "Recent takes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if isLive {
                Text(liveLine)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(livePartial.isEmpty ? "Listening" : livePartial)
            }

            if savedRows.isEmpty, isLive == false {
                Text("No takes yet")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(savedRows, id: \.id) { record in
                    takeRow(record)
                }
            }
        }
        .padding(12)
        .cadenceGlassCard(cornerRadius: 16)
        .onAppear {
            let started = CFAbsoluteTimeGetCurrent()
            let count = records.count
            CadenceLog.debug(
                "Recent takes fetch count=\(count) +\(Int((CFAbsoluteTimeGetCurrent() - started) * 1000))ms"
            )
        }
    }

    private var liveLine: String {
        let trimmed = livePartial.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Listening…" : trimmed
    }

    private func takeRow(_ record: TranscriptRecord) -> some View {
        HStack(spacing: 8) {
            Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(record.polishedText)
                .font(.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(record.polishedText)
            Button {
                copy(record)
            } label: {
                Image(systemName: copiedID == record.id ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy")
            .accessibilityLabel("Copy take")
        }
        .frame(minHeight: 22)
    }

    private func copy(_ record: TranscriptRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.polishedText, forType: .string)
        copiedID = record.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copiedID == record.id { copiedID = nil }
        }
    }
}
