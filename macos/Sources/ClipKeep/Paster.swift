import AppKit
import ApplicationServices

/// 把历史记录写回剪贴板，并（可选）模拟 ⌘V 粘贴到当前应用。
enum Paster {
    @discardableResult
    static func write(_ payload: ClipPayload, plainText: String?) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let plainText {
            return pb.setString(plainText, forType: .string)
        }
        let items = payload.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            return item
        }
        return pb.writeObjects(items)
    }

    static func plainString(of payload: ClipPayload) -> String? {
        for dict in payload {
            if let data = dict[NSPasteboard.PasteboardType.string.rawValue],
               let s = String(data: data, encoding: .utf8) { return s }
        }
        return nil
    }

    static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        postKey(source: source, keyCode: vKey, flags: .maskCommand)
    }

    /// 发 n 次退格（删掉刚输入的缩写）。
    static func sendBackspaces(_ count: Int) {
        for _ in 0..<count { postKey(source: nil, keyCode: 51, flags: []) }
    }

    /// 不经过剪贴板，直接把文字“打”进当前输入框（适合短文本）。
    static func type(_ text: String) {
        let units = Array(text.utf16)
        var start = 0
        while start < units.count {
            let chunk = Array(units[start..<min(start + 20, units.count)])
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown)
                event?.flags = []
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                mark(event)
                event?.post(tap: .cgAnnotatedSessionEventTap)
            }
            start += chunk.count
        }
    }

    /// 备份当前剪贴板（展开长内容时借用剪贴板，用完要还原）。
    static func snapshot() -> ClipPayload {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var dict: [String: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { dict[type.rawValue] = data } }
            return dict
        }
    }

    private static func postKey(source: CGEventSource?, keyCode: CGKeyCode, flags: CGEventFlags) {
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            event?.flags = flags
            mark(event)
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private static func mark(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: TextExpander.syntheticMarker)
    }

    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
