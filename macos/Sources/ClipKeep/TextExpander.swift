import AppKit
import Carbon

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<TextExpander>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
    }
    return Unmanaged.passUnretained(event)  // 只看不改，按键照常送达
}

/// 收藏缩写展开：全局监听键入的字符，结尾命中某个缩写就通知外部去替换。
/// 思路参考 aText：CGEventTap 取字符、退格删缩写、再输入内容；密码框（安全输入）里不工作。
final class TextExpander {
    /// 我们自己发出的键盘事件带这个标记，监听时跳过，避免自己触发自己。
    static let syntheticMarker: Int64 = 0x434B_4550

    /// (收藏 id, 需要删掉的缩写字符数)
    var onExpand: ((Int64, Int) -> Void)?
    private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer = ""
    private var snippets: [(abbrev: String, id: Int64)] = []

    func update(_ items: [ClipItem]) {
        snippets = items.compactMap { item -> (abbrev: String, id: Int64)? in
            guard item.favorite, let a = item.abbrev, !a.isEmpty else { return nil }
            return (a, item.id)
        }
        .sorted { $0.abbrev.count > $1.abbrev.count }  // 长的优先，避免 ;a 抢掉 ;addr
    }

    /// 需要“辅助功能”权限；没有权限时返回 false，之后可以再调用重试。
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        guard Paster.trusted else { return false }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        isRunning = true
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        isRunning = false
        buffer = ""
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }  // 被系统停掉后重新打开
            return
        case .leftMouseDown, .rightMouseDown:
            buffer = ""  // 点了别处，光标位置变了
            return
        case .keyDown:
            break
        default:
            return
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return }
        if snippets.isEmpty || IsSecureEventInputEnabled() { buffer = ""; return }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) { buffer = ""; return }

        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case Int64(kVK_Delete):
            if !buffer.isEmpty { buffer.removeLast() }
            return
        case Int64(kVK_Return), Int64(kVK_ANSI_KeypadEnter), Int64(kVK_Tab), Int64(kVK_Escape),
             Int64(kVK_LeftArrow), Int64(kVK_RightArrow), Int64(kVK_UpArrow), Int64(kVK_DownArrow),
             Int64(kVK_Home), Int64(kVK_End), Int64(kVK_PageUp), Int64(kVK_PageDown), Int64(kVK_ForwardDelete):
            buffer = ""
            return
        default:
            break
        }
        if !Settings.shared.expandInIME && !Self.isASCIIInputSource() { buffer = ""; return }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return }
        buffer += String(utf16CodeUnits: chars, count: length)
        if buffer.count > 64 { buffer = String(buffer.suffix(64)) }

        guard let hit = snippets.first(where: { AbbreviationText.matches(buffer: buffer, abbreviation: $0.abbrev) }) else { return }
        buffer = ""
        let id = hit.id, count = hit.abbrev.count
        // 等这次按键先送到目标应用，再删缩写、填内容
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in self?.onExpand?(id, count) }
    }

    /// 当前输入源是否是英文这类 ASCII 键盘（拼音、日文等输入法返回 false）。
    static func isASCIIInputSource() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else { return true }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }
}
