import Carbon.HIToolbox
import Foundation

/// Owns one process-wide Carbon hot key without requiring Accessibility access.
@MainActor
public final class GlobalShortcut {
    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let command = Self(rawValue: UInt32(cmdKey))
        public static let option = Self(rawValue: UInt32(optionKey))
        public static let control = Self(rawValue: UInt32(controlKey))
        public static let shift = Self(rawValue: UInt32(shiftKey))
    }

    public struct Shortcut: Sendable, Hashable {
        public var keyCode: UInt32
        public var modifiers: Modifiers

        public init(keyCode: UInt32, modifiers: Modifiers) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    public enum RegistrationError: Error, Sendable, Equatable {
        case conflict
        case eventHandlerInstallationFailed(OSStatus)
        case registrationFailed(OSStatus)
    }

    public private(set) var registeredShortcut: Shortcut?

    private static let signature: OSType = 0x4150_4C52  // "APLR"
    private static let identifier: UInt32 = 1

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var callback: (@MainActor () -> Void)?

    public init() {}

    isolated deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    public func register(
        _ shortcut: Shortcut,
        callback: @escaping @MainActor () -> Void
    ) throws {
        if registeredShortcut == shortcut, hotKey != nil {
            self.callback = callback
            return
        }

        var installedHandlerForAttempt = false
        if eventHandler == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            var installedHandler: EventHandlerRef?
            let context = Unmanaged.passUnretained(self).toOpaque()
            let handlerStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                Self.eventHandlerCallback,
                1,
                &eventType,
                context,
                &installedHandler
            )
            guard handlerStatus == noErr, let installedHandler else {
                throw RegistrationError.eventHandlerInstallationFailed(handlerStatus)
            }
            eventHandler = installedHandler
            installedHandlerForAttempt = true
        }

        var registeredHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let registrationStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers.rawValue,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &registeredHotKey
        )
        guard registrationStatus == noErr, let registeredHotKey else {
            if installedHandlerForAttempt, let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            if registrationStatus == eventHotKeyExistsErr {
                throw RegistrationError.conflict
            }
            throw RegistrationError.registrationFailed(registrationStatus)
        }

        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = registeredHotKey
        registeredShortcut = shortcut
        self.callback = callback
    }

    public func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        hotKey = nil
        eventHandler = nil
        registeredShortcut = nil
        callback = nil
    }

    private func invokeCallback() {
        callback?()
    }

    private static let eventHandlerCallback: EventHandlerUPP = { _, event, context in
        guard let event, let context else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard
            status == noErr,
            hotKeyID.signature == GlobalShortcut.signature,
            hotKeyID.id == GlobalShortcut.identifier
        else {
            return OSStatus(eventNotHandledErr)
        }

        let service = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
        service.invokeCallback()
        return noErr
    }
}
