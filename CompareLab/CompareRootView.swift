import SwiftUI

struct CompareRootView: View {
    @Environment(CompareSession.self) private var session
    @State private var showKey = false
    @State private var showPaste = false

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 20) {
            header
            recordControl
            HStack(alignment: .top, spacing: 14) {
                EngineCard(result: session.cadence, accent: .blue)
                EngineCard(result: session.parakeet, accent: .indigo)
                wisprColumn
            }
            .frame(maxHeight: .infinity)
        }
        .padding(24)
        .frame(width: 1080, height: 620)
        .onAppear { session.bootstrap() }
        .sheet(isPresented: $showKey) {
            WisprKeySheet()
                .environment(session)
        }
        .sheet(isPresented: $showPaste) {
            WisprPasteSheet()
                .environment(session)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compare")
                    .font(.title2.weight(.semibold))
                Text("Hold Fn once. Cadence, Compare (Parakeet), and Wispr Flow all listen. Set Wispr’s hotkey to Fn in the Wispr Flow app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                if session.parakeetLoading {
                    Text("Loading Parakeet in background…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let load = session.parakeetLoadMs {
                    Text("Parakeet ready · \(load) ms load")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button("Wispr API key") { showKey = true }
                        .buttonStyle(.bordered)
                    if WisprEngine.desktopInstalled {
                        Button("Paste from desktop") { showPaste = true }
                            .buttonStyle(.bordered)
                    }
                    if session.hasWisprAPIKey {
                        Label("API key saved", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var wisprColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            EngineCard(result: session.wispr, accent: .orange)
            if !session.hasWisprAPIKey {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No Wispr API key")
                        .font(.caption.weight(.semibold))
                    Text("Set Wispr Flow’s push-to-talk to Fn. Hold Fn with Compare and Cadence open — all three capture the same take. If Wispr pastes, Compare picks it up from the clipboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Add API key") { showKey = true }
                            .font(.caption)
                        if WisprEngine.desktopInstalled {
                            Button("Open Wispr Flow") { WisprEngine.openDesktopApp() }
                                .font(.caption)
                            Button("Paste transcript") { showPaste = true }
                                .font(.caption)
                        }
                        Button("API docs") { WisprEngine.openDocs() }
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var recordControl: some View {
        VStack(spacing: 8) {
            Button {
                Task { await session.toggleRecord() }
            } label: {
                Image(systemName: session.isRecording ? "stop.fill" : "mic.fill")
                    .font(.title2.weight(.semibold))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(session.isRecording ? .red : .accentColor)
            .disabled(session.isBusy)
            .accessibilityLabel(session.isRecording ? "Stop recording" : "Hold Fn or click to record")
            .help(session.isRecording ? "Release Fn or click to stop" : "Hold Fn — or click the mic")

            Text(statusCaption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Set Wispr Flow’s hotkey to Fn in Wispr’s settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if let err = session.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var statusCaption: String {
        if session.isRecording { return "Listening… release Fn (or click) to stop" }
        if session.isBusy { return "Transcribing…" }
        if session.fnArmed { return "Hold Fn — Cadence, Parakeet, and Wispr all listen" }
        return "Click record, or allow Input Monitoring so Fn works"
    }
}

struct EngineCard: View {
    let result: EngineResult
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(result.name)
                    .font(.headline)
                Spacer()
            }
            Text(result.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(result.statusLine)
                .font(.caption.weight(.semibold))
                .foregroundStyle(result.status == .failed ? .red : .primary)
            Divider()
            ScrollView {
                Text(displayBody)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if let first = result.firstPartialMs, result.status == .done {
                Text("First partial \(first) ms")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.name). \(result.statusLine). \(displayBody)")
    }

    private var displayBody: String {
        if result.status == .failed {
            return result.error ?? "Failed"
        }
        if result.transcript.isEmpty {
            return result.status == .running || result.status == .warming
                ? "…"
                : "Waiting for a recording."
        }
        return result.transcript
    }
}

struct WisprKeySheet: View {
    @Environment(CompareSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: 16) {
            Text("Wispr Flow API key")
                .font(.headline)
            Text("Create a key at platform.wisprflow.ai (API access is enterprise / invite-only). Compare sends the same 16 kHz WAV clip to Wispr’s REST endpoint documented at api-docs.wisprflow.ai.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Open developer platform") { WisprEngine.openPlatform() }
                Button("REST API docs") { WisprEngine.openDocs() }
            }
            .buttonStyle(.link)
            SecureField("Bearer API key (fl-…)", text: $session.wisprKeyDraft)
                .textFieldStyle(.roundedBorder)
            Text("Or set WISPR_FLOW_API_KEY in the environment for local testing.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    session.saveWisprKey()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

struct WisprPasteSheet: View {
    @Environment(CompareSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste from Wispr Flow desktop")
                .font(.headline)
            Text("Record in Compare, then dictate the same words in Wispr Flow (their hotkey). Copy Wispr’s transcript and paste it here — no API key needed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Open Wispr Flow") { WisprEngine.openDesktopApp() }
                    .buttonStyle(.bordered)
            }
            TextEditor(text: $session.wisprPasteDraft)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator, lineWidth: 1)
                )
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Use transcript") {
                    session.applyWisprPaste()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 340)
    }
}
