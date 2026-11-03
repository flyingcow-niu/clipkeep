import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipStore!
    private var monitor: ClipboardMonitor!
    private let panel = PanelController()
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var openItem: NSMenuItem!
    private var settingsWindow: NSWindow?
    private var favoritesWindow: NSWindow?
    private let favorites = FavoritesModel()
    private let expander = TextExpander()
    private var purgeTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Vault.ready else {
            fail("无法从钥匙串读取加密密钥", "请在弹出的钥匙串对话框里选择“始终允许”，然后重新打开 ClipKeep。")
            return
        }
        do {
            store = try ClipStore()
        } catch {
            fail("无法打开数据库", "\(error)")
            return
        }

        monitor = ClipboardMonitor(store: store)
        monitor.onNewClip = { [weak self] in self?.reloadItems() }
        monitor.start()

        let model = panel.model
        model.onCopy = { [weak self] item in
            guard let self, let payload = self.store.payload(item.id) else { return false }
            let copied = Paster.write(payload, plainText: nil)
            self.monitor.skipCurrent()
            return copied
        }
        model.onPaste = { [weak self] item, plain in self?.paste(item, plain: plain) }
        model.onToggleFavorite = { [weak self] item in
            self?.store.setFavorite(item.id, !item.favorite)
            self?.reloadItems()
        }
        model.onDelete = { [weak self] item in
            self?.store.delete(item.id)
            self?.reloadItems()
        }
        model.onOpenSettings = { [weak self] in
            self?.panel.hide(restoreFocus: false)
            self?.openSettings()
        }

        model.onOpenFavorites = { [weak self] in
            self?.panel.hide(restoreFocus: false)
            self?.openFavorites()
        }
        expander.onExpand = { [weak self] id, count in self?.expand(id, deleting: count) }

        setupStatusItem()
        bindSettings()

        purge()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.purge() }
        RunLoop.main.add(timer, forMode: .common)
        purgeTimer = timer
        // 用户可能是启动之后才去授权“辅助功能”，隔一会儿重试开启缩写监听
        let retry = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.startExpanderIfNeeded() }
        RunLoop.main.add(retry, forMode: .common)
        reloadItems()

        // 调试用：open ClipKeep.app --args --show 启动后直接弹出面板
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.togglePanel() }
        }
    }

    // MARK: - 动作

    private func togglePanel() {
        if !panel.isVisible { reloadItems() }
        panel.toggle()
    }

    private func reloadItems() {
        let items = store.loadAll()
        panel.model.items = items
        favorites.items = items.filter(\.favorite)
        expander.update(items)
    }

    private func startExpanderIfNeeded() {
        guard Settings.shared.expansionEnabled, !expander.isRunning else { return }
        expander.start()
    }

    /// 缩写命中：先删掉刚打的缩写，再填入收藏内容。
    private func expand(_ id: Int64, deleting count: Int) {
        guard let item = panel.model.items.first(where: { $0.id == id }),
              let payload = store.payload(id) else { return }
        Paster.sendBackspaces(count)
        if item.kind == .text, let text = Paster.plainString(of: payload), text.count <= 300, !text.contains("\n") {
            // 短的单行文本直接打出来，不动剪贴板
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { Paster.type(text) }
            return
        }
        // 长文本、多行、富文本、图片：借用剪贴板粘贴，用完还原
        let saved = Paster.snapshot()
        Paster.write(payload, plainText: nil)
        monitor.skipCurrent()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Paster.sendCommandV() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            Paster.write(saved, plainText: nil)
            self?.monitor.skipCurrent()
        }
    }

    // MARK: - 收藏管理

    /// 输入提示和保存使用同一套规则，编辑时排除当前记录。
    private func validateAbbrev(_ abbrev: String, excluding id: Int64?) -> FavoriteError? {
        AbbreviationValidator.validate(abbrev, entries: favorites.items.compactMap { item in
            guard let abbrev = item.abbrev else { return nil }
            return .init(id: item.id, abbrev: abbrev, title: item.text)
        }, excluding: id)
    }

    @objc private func openFavorites() {
        if favoritesWindow == nil {
            let actions = FavoritesActions(
                validateAbbrev: { [unowned self] abbrev, id in
                    self.validateAbbrev(abbrev, excluding: id)
                },
                add: { [unowned self] text, abbrev in
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return .failure(FavoriteError(message: "内容不能为空"))
                    }
                    if let error = self.validateAbbrev(abbrev, excluding: nil) { return .failure(error) }
                    guard let id = self.store.addManual(text: text, abbrev: abbrev) else {
                        return .failure(FavoriteError(message: "保存失败"))
                    }
                    self.reloadItems()
                    return .success(id)
                },
                save: { [unowned self] id, text, abbrev in
                    if let error = self.validateAbbrev(abbrev, excluding: id) { return error }
                    if let text {
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return FavoriteError(message: "内容不能为空")
                        }
                        if !self.store.updateText(id, text: text) {
                            return FavoriteError(message: "已经有一条一模一样的记录了")
                        }
                    }
                    self.store.setAbbrev(id, abbrev)
                    self.reloadItems()
                    return nil
                },
                unfavorite: { [unowned self] id in
                    self.store.setFavorite(id, false)
                    self.reloadItems()
                },
                delete: { [unowned self] id in
                    self.store.delete(id)
                    self.reloadItems()
                },
                fullText: { [unowned self] id in self.store.payload(id).flatMap(Paster.plainString) })
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: FavoritesView(model: favorites, actions: actions)))
            window.title = "收藏与快捷短语"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 860, height: 560))
            window.center()
            favoritesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        favoritesWindow?.makeKeyAndOrderFront(nil)
    }

    private func paste(_ item: ClipItem, plain: Bool) {
        guard let payload = store.payload(item.id) else { NSSound.beep(); return }
        let text = plain ? (Paster.plainString(of: payload) ?? item.text) : nil
        Paster.write(payload, plainText: text)
        monitor.skipCurrent()
        store.touch(item.id)
        panel.hide(restoreFocus: true)
        reloadItems()

        guard Settings.shared.pasteDirectly else { return }
        if Paster.trusted {
            // 等原应用重新拿到焦点再发 ⌘V
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { Paster.sendCommandV() }
        } else {
            Paster.requestTrust()
        }
    }

    /// 面板收起时的全局数字快选：修饰键 + 1–9。
    private func registerGlobalQuick(enabled: Bool, modifierIndex: Int) {
        for n in 1...9 { HotKeys.unregister(id: HotKeys.quickID(n)) }
        guard enabled else {
            Settings.shared.globalQuickStatus = ""
            return
        }
        let modifier = Settings.pick(ModifierChoice.global, modifierIndex)
        var failed: [Int] = []
        for (i, key) in ModifierChoice.digitCarbonKeys.enumerated() {
            let n = i + 1
            let ok = HotKeys.register(id: HotKeys.quickID(n), keyCode: key, modifiers: modifier.carbon) { [weak self] in
                self?.globalQuickPaste(n)
            }
            if !ok { failed.append(n) }
        }
        Settings.shared.globalQuickStatus = failed.isEmpty
            ? "已启用：\(modifier.title)1 … \(modifier.title)9"
            : "这些组合被其他应用占用：" + failed.map { "\(modifier.title)\($0)" }.joined(separator: "、")
    }

    /// 全局快选第 n 条。面板开着时按可见卡片编号；收起时按最近第 n 条，且不改变顺序。
    private func globalQuickPaste(_ n: Int) {
        if panel.isVisible {
            if !panel.model.quickPick(n) { NSSound.beep() }
            return
        }
        let items = panel.model.items
        guard items.indices.contains(n - 1), let payload = store.payload(items[n - 1].id) else {
            NSSound.beep()
            return
        }
        Paster.write(payload, plainText: nil)
        monitor.skipCurrent()
        if Paster.trusted {
            // 用户还按着修饰键；⌘V 事件自己带 flags，不受影响
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Paster.sendCommandV() }
        } else {
            Paster.requestTrust()
        }
    }

    @discardableResult
    private func purge() -> Int {
        let s = Settings.shared
        let n = store.purge(retentionDays: s.retentionDays, maxItems: s.maxItems)
        if n > 0 { reloadItems() }
        return n
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipKeep")

        let menu = NSMenu()
        openItem = menu.addItem(withTitle: "打开剪贴历史", action: #selector(openPanel), keyEquivalent: "")
        pauseItem = menu.addItem(withTitle: "暂停记录", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "收藏与快捷短语…", action: #selector(openFavorites), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "清空历史（保留收藏）…", action: #selector(clearHistory), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 ClipKeep", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func bindSettings() {
        let s = Settings.shared
        s.$hotkeyIndex
            .sink { [weak self] index in
                let preset = Settings.pick(HotkeyPreset.all, index)
                HotKeys.register(id: HotKeys.panelID, keyCode: preset.keyCode, modifiers: preset.modifiers) {
                    self?.togglePanel()
                }
                self?.openItem.title = "打开剪贴历史  \(preset.title)"
            }
            .store(in: &cancellables)
        s.$globalQuickEnabled.combineLatest(s.$globalQuickModifierIndex)
            .sink { [weak self] enabled, index in self?.registerGlobalQuick(enabled: enabled, modifierIndex: index) }
            .store(in: &cancellables)
        s.$expansionEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.expander.start() } else { self.expander.stop() }
            }
            .store(in: &cancellables)
        s.$paused
            .sink { [weak self] paused in
                self?.pauseItem.state = paused ? .on : .off
                self?.statusItem.button?.appearsDisabled = paused
            }
            .store(in: &cancellables)
        s.$retentionDays.combineLatest(s.$maxItems)
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.purge() }
            .store(in: &cancellables)
    }

    @objc private func openPanel() { togglePanel() }

    @objc private func togglePause() { Settings.shared.paused.toggle() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let actions = SettingsActions(
                counts: { [unowned self] in self.store.counts() },
                purgeNow: { [unowned self] in self.purge() },
                clearHistory: { [unowned self] in
                    let n = self.store.clearNonFavorites()
                    self.reloadItems()
                    return n
                },
                dataPath: store.fileURL.path,
                openFavorites: { [unowned self] in self.openFavorites() },
                expanderRunning: { [unowned self] in self.expander.isRunning })
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(actions: actions)))
            window.title = "ClipKeep 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func clearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "清空剪贴历史？"
        alert.informativeText = "收藏的记录会保留，其余全部删除，无法恢复。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearNonFavorites()
            reloadItems()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func fail(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
        NSApp.terminate(nil)
    }
}
