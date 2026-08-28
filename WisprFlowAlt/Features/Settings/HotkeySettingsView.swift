import AppKit
import SwiftUI

struct HotkeySettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var recordingTarget: RecordingTarget?
    @State private var validationMessage: String?

    enum RecordingTarget {
        case pushToTalk
        case commandMode
    }

    var body: some View {
        Form {
            Section("Shortcuts") {
                hotkeyRow(
                    title: "Push-to-talk",
                    shortcut: appModel.settings.pushToTalkShortcut,
                    target: .pushToTalk
                )
                hotkeyRow(
                    title: "Command Mode",
                    shortcut: appModel.settings.commandModeShortcut,
                    target: .commandMode
                )
                Toggle(
                    "Double-tap push-to-talk for hands-free",
                    isOn: Binding(
                        get: { appModel.settings.doubleTapHandsFreeEnabled },
                        set: { newValue in
                            appModel.settings.doubleTapHandsFreeEnabled = newValue
                            applyAndValidate()
                        }
                    )
                )
            }

            Section("Presets") {
                Button("Use Fn (shared with Compare / Wispr)") {
                    appModel.settings.pushToTalkShortcut = .defaultPushToTalk
                    applyAndValidate()
                }
                Button("Use Option (⌥)") {
                    appModel.settings.pushToTalkShortcut = .optionPushToTalk
                    applyAndValidate()
                }
                Button("Use Right Option") {
                    appModel.settings.pushToTalkShortcut = KeyShortcut(keyCode: 61, modifiers: [])
                    applyAndValidate()
                }
                Button("Use ⌃Space") {
                    appModel.settings.pushToTalkShortcut = .controlSpace
                    applyAndValidate()
                }
                Button("Command Mode → ⌘⌃C") {
                    appModel.settings.commandModeShortcut = .defaultCommandMode
                    applyAndValidate()
                }
            }

            if let validationMessage {
                Section("Validation") {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                }
            } else if let tapError = appModel.hotkeys.lastValidationError {
                Section("Validation") {
                    Text(tapError)
                        .foregroundStyle(.orange)
                }
            } else {
                Section("Validation") {
                    Text("Shortcuts look valid.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Help") {
                Text("Hold Fn to dictate; release to insert. Compare and Wispr Flow can use the same Fn key. Cadence listens only and does not swallow it. Set Wispr Flow’s hotkey to Fn in Wispr’s settings. Hands-free double-tap is off by default. Escape cancels.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .background(HotkeyCaptureRepresentable(target: $recordingTarget) { shortcut in
            guard let recordingTarget else { return }
            switch recordingTarget {
            case .pushToTalk:
                appModel.settings.pushToTalkShortcut = shortcut
            case .commandMode:
                appModel.settings.commandModeShortcut = shortcut
            }
            self.recordingTarget = nil
            applyAndValidate()
        })
    }

    private func hotkeyRow(title: String, shortcut: KeyShortcut, target: RecordingTarget) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut.displayString)
                .font(.body.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Button(recordingTarget == target ? "Press keys…" : "Record") {
                recordingTarget = target
            }
        }
    }

    private func applyAndValidate() {
        if let error = appModel.settings.pushToTalkShortcut.conflictsWithSystem() {
            validationMessage = "Push-to-talk: \(error)"
        } else if let error = appModel.settings.commandModeShortcut.conflictsWithSystem() {
            validationMessage = "Command Mode: \(error)"
        } else if appModel.settings.pushToTalkShortcut == appModel.settings.commandModeShortcut {
            validationMessage = "Shortcuts must be different."
        } else {
            validationMessage = nil
        }
        appModel.applyHotkeySettings()
    }
}

/// Invisible view that listens for the next key combination while recording.
struct HotkeyCaptureRepresentable: NSViewRepresentable {
    @Binding var target: HotkeySettingsView.RecordingTarget?
    var onCapture: (KeyShortcut) -> Void

    func makeNSView(context: Context) -> HotkeyCaptureView {
        let view = HotkeyCaptureView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: HotkeyCaptureView, context: Context) {
        nsView.onCapture = onCapture
        nsView.isCapturing = target != nil
        if target != nil {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class HotkeyCaptureView: NSView {
    var isCapturing = false
    var onCapture: ((KeyShortcut) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        let shortcut = KeyShortcut(
            keyCode: UInt16(event.keyCode),
            modifiers: event.modifierFlags.intersection([.control, .option, .shift, .command])
        )
        onCapture?(shortcut)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isCapturing else {
            super.flagsChanged(with: event)
            return
        }
        // Capture modifier-only shortcuts when a modifier is pressed alone.
        let mods = event.modifierFlags.intersection([.control, .option, .shift, .command, .function])
        let keyCode = UInt16(event.keyCode)
        if [55, 56, 58, 59, 60, 61, 62, 63].contains(keyCode), !mods.isEmpty || true {
            // For modifier-only, store the key itself with empty modifiers.
            let shortcut = KeyShortcut(keyCode: keyCode, modifiers: [])
            // Only fire on key-down-ish: when flag is present
            if KeyShortcut.nsModifiers(from: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))).isEmpty == false
                || [58, 61, 59, 55, 56, 63].contains(keyCode)
            {
                // Debounce: accept Option/Control keys as standalone PTT.
                if [58, 61, 59, 63].contains(keyCode) {
                    onCapture?(KeyShortcut(keyCode: keyCode, modifiers: []))
                }
            }
        }
    }
}
