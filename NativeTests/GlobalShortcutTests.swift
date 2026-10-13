import Carbon.HIToolbox
import Testing

@testable import AppLauncher

@Suite
@MainActor
struct GlobalShortcutTests {
    private let modifiers: GlobalShortcut.Modifiers = [.command, .option, .control, .shift]

    @Test
    func exclusiveRegistrationRejectsASecondOwner() throws {
        let first = GlobalShortcut()
        let second = GlobalShortcut()
        let shortcut = GlobalShortcut.Shortcut(
            keyCode: UInt32(kVK_F19), modifiers: modifiers)
        defer {
            first.unregister()
            second.unregister()
        }

        try first.register(shortcut) {}
        #expect(throws: GlobalShortcut.RegistrationError.conflict) {
            try second.register(shortcut) {}
        }
    }

    @Test
    func conflictingReplacementPreservesThePreviousRegistration() throws {
        let service = GlobalShortcut()
        let blocker = GlobalShortcut()
        let previous = GlobalShortcut.Shortcut(
            keyCode: UInt32(kVK_F18), modifiers: modifiers)
        let conflict = GlobalShortcut.Shortcut(
            keyCode: UInt32(kVK_F19), modifiers: modifiers)
        defer {
            service.unregister()
            blocker.unregister()
        }

        try service.register(previous) {}
        try blocker.register(conflict) {}
        #expect(throws: GlobalShortcut.RegistrationError.conflict) {
            try service.register(conflict) {}
        }
        #expect(service.registeredShortcut == previous)
    }

    @Test
    func exclusiveRegistrationRejectsAnExistingNonexclusiveReservation() throws {
        let shortcut = GlobalShortcut.Shortcut(
            keyCode: UInt32(kVK_F17), modifiers: modifiers)
        var reservation: EventHotKeyRef?
        let reservationID = EventHotKeyID(signature: 0x5445_5354, id: 17)  // "TEST"
        let reservationStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers.rawValue,
            reservationID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyNoOptions),
            &reservation
        )
        guard reservationStatus == noErr, let reservation else {
            Issue.record(
                "Could not reserve the isolated nonexclusive test chord: \(reservationStatus)")
            return
        }
        defer { UnregisterEventHotKey(reservation) }

        let service = GlobalShortcut()
        defer { service.unregister() }
        #expect(throws: GlobalShortcut.RegistrationError.conflict) {
            try service.register(shortcut) {}
        }
    }
}
