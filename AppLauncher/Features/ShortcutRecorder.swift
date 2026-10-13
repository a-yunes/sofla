import AppKit
import Carbon.HIToolbox
import LauncherCore
import SwiftUI

struct ShortcutRecorder: View {
    let shortcut: HotKeyPreference
    let onCommit: @MainActor (HotKeyPreference) -> Bool

    @State private var isRecording = false
    @State private var showsConflict = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ZStack {
                Button(isRecording ? "Type shortcut…" : Self.label(for: shortcut)) {
                    showsConflict = false
                    isRecording = true
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Keyboard shortcut")
                .accessibilityValue(isRecording ? "Recording" : Self.label(for: shortcut))

                ShortcutCaptureView(isRecording: isRecording) { event in
                    if event.keyCode == UInt16(kVK_Escape) {
                        isRecording = false
                        return
                    }
                    guard let preference = Self.preference(from: event) else { return }
                    if onCommit(preference) {
                        isRecording = false
                        showsConflict = false
                    } else {
                        showsConflict = true
                    }
                }
                .allowsHitTesting(false)
            }

            if showsConflict {
                Text("Shortcut is already in use")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("preferences.shortcutConflict")
            }
        }
    }

    private static func preference(from event: NSEvent) -> HotKeyPreference? {
        guard event.keyCode <= 127 else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= HotKeyPreference.commandModifier }
        if flags.contains(.shift) { modifiers |= HotKeyPreference.shiftModifier }
        if flags.contains(.option) { modifiers |= HotKeyPreference.optionModifier }
        if flags.contains(.control) { modifiers |= HotKeyPreference.controlModifier }
        return try? HotKeyPreference(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    private static func label(for shortcut: HotKeyPreference) -> String {
        var label = ""
        if shortcut.modifiers & HotKeyPreference.controlModifier != 0 { label += "⌃" }
        if shortcut.modifiers & HotKeyPreference.optionModifier != 0 { label += "⌥" }
        if shortcut.modifiers & HotKeyPreference.shiftModifier != 0 { label += "⇧" }
        if shortcut.modifiers & HotKeyPreference.commandModifier != 0 { label += "⌘" }
        label += keyName(shortcut.keyCode)
        return label
    }

    private static func keyName(_ keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let isRecording: Bool
    let onKeyDown: @MainActor (NSEvent) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ view: ShortcutCaptureNSView, context: Context) {
        view.onKeyDown = onKeyDown
        if isRecording, view.window?.firstResponder !== view {
            Task { @MainActor in
                view.window?.makeFirstResponder(view)
            }
        } else if !isRecording, view.window?.firstResponder === view {
            view.window?.makeFirstResponder(nil)
        }
    }
}

@MainActor
private final class ShortcutCaptureNSView: NSView {
    var onKeyDown: (@MainActor (NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}
