import AppKit
import SwiftUI

/// 贴在屏幕底部、横向铺满的浮动面板。弹出时激活 ClipKeep 保证焦点稳定，收起时把焦点还给原来的应用。
final class ClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelController: NSObject, NSWindowDelegate {
    let model = PanelModel()
    private let panel: ClipPanel
    private var keyMonitor: Any?
    /// 弹出面板之前在前台的应用，粘贴时要切回去。
    private var previousApp: NSRunningApplication?

    static let height: CGFloat = 330

    override init() {
        panel = ClipPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: Self.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PanelView(model: model))
        panel.delegate = self
        model.onCopySucceeded = { [weak self] in self?.hide(restoreFocus: true) }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { panel.isVisible ? hide(restoreFocus: true) : show() }

    func show() {
        model.query = ""
        model.tab = .all
        model.selection = 0
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        let target = dockToBottom()
        NSApp.activate(ignoringOtherApps: true)
        // 从屏幕下沿滑上来
        panel.setFrame(target.offsetBy(dx: 0, dy: -40), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
        model.focusToken = UUID()
        installKeyMonitor()
    }

    /// restoreFocus: 是否把焦点还给弹出前的应用（粘贴、esc 时需要；点了别处则不需要）。
    func hide(restoreFocus: Bool) {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if restoreFocus { previousApp?.activate() }
        previousApp = nil
    }

    func windowDidResignKey(_ notification: Notification) { hide(restoreFocus: false) }

    /// 鼠标所在屏幕的底部（Dock 之上），横向铺满。
    private func dockToBottom() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return panel.frame }
        return NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: Self.height)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    /// 返回 true 表示按键已处理、不再传给搜索框。
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        if flags.subtracting([.capsLock, .numericPad, .function]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            let editor = panel.firstResponder as? NSTextView
            return model.copySelected(hasTextSelection: (editor?.selectedRange().length ?? 0) > 0)
        }
        // 修饰键 + 1–9：粘贴第 N 张可见卡片
        if flags.contains(Settings.shared.quickModifier.flags), let n = ModifierChoice.digitKeyCodes[event.keyCode] {
            if !model.quickPick(n) { NSSound.beep() }
            return true
        }
        switch event.keyCode {
        case 124, 125: model.move(1); return true                  // → ↓
        case 123, 126: model.move(-1); return true                 // ← ↑
        case 36, 76:                                               // ↩
            if let item = model.selectedItem { model.onPaste?(item, flags.contains(.shift)) }
            return true
        case 53: hide(restoreFocus: true); return true             // esc
        case 51 where cmd:                                         // ⌘⌫
            if let item = model.selectedItem { model.onDelete?(item) }
            return true
        case 48:                                                   // tab 切换全部/收藏
            model.tab = model.tab == .all ? .favorites : .all
            return true
        default:
            if cmd, event.charactersIgnoringModifiers?.lowercased() == "d" {
                if let item = model.selectedItem { model.onToggleFavorite?(item) }
                return true
            }
            return false
        }
    }
}
