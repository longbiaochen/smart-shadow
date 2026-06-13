import Carbon
import Foundation

final class MacGlobalHotkeyAdapter {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func registerDefaultHotkey() {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard hotKeyID.id == 1 else { return noErr }
                let adapter = Unmanaged<MacGlobalHotkeyAdapter>.fromOpaque(userData).takeUnretainedValue()
                adapter.action()
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: fourCharCode("SSVO"), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        unregister()
    }
}

private func fourCharCode(_ value: String) -> OSType {
    var result: UInt32 = 0
    for scalar in value.unicodeScalars.prefix(4) {
        result = (result << 8) + scalar.value
    }
    return result
}
