import Carbon
import Foundation

private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?,
                           _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let id = hotKeyID.id
    DispatchQueue.main.async { HotKeys.actions[id]?() }
    return noErr
}

/// 全局快捷键（Carbon RegisterEventHotKey，不需要辅助功能权限），按 id 管理多个。
enum HotKeys {
    static let panelID: UInt32 = 1
    /// 全局数字快选 1–9 用 11…19。
    static func quickID(_ n: Int) -> UInt32 { UInt32(10 + n) }

    fileprivate static var actions: [UInt32: () -> Void] = [:]
    private static var refs: [UInt32: EventHotKeyRef] = [:]
    private static var handlerInstalled = false
    private static let signature = OSType(0x434B_4550)  // "CKEP"

    @discardableResult
    static func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        unregister(id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("ClipKeep: 快捷键 id=%u 注册失败 (%d)", id, status)
            return false
        }
        refs[id] = ref
        actions[id] = action
        return true
    }

    static func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        actions[id] = nil
    }
}
