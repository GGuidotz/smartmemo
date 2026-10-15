// La scorciatoia globale ⌃⌥Spazio, con RegisterEventHotKey di Carbon: funziona da qualsiasi app e non chiede il
// permesso Accessibilità (non legge la tastiera, riceve solo quella combinazione).

import Carbon

@MainActor
final class HotKey {
    nonisolated(unsafe) private static var action: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Il testo da mostrare nei menu e nelle impostazioni.
    static let display = "⌃⌥Spazio"

    func register(_ action: @escaping () -> Void) {
        unregister()
        HotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x534D_454D), id: 1)   // 'SMEM'
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        // Già presa da un'altra app o dal sistema (⌃⌥Spazio è anche "sorgente di input successiva").
        if status != noErr { diag(.app, "hot key not registered: \(status)") }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        HotKey.action = nil
    }
}
