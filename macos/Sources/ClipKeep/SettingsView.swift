import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsActions {
    let counts: () -> (total: Int, favorites: Int)
    let purgeNow: () -> Int
    let clearHistory: () -> Int
    let dataPath: String
    let openFavorites: () -> Void
    let expanderRunning: () -> Bool
}

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    let actions: SettingsActions

    @State private var axTrusted = Paster.trusted
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var message = ""
    @State private var counts = (total: 0, favorites: 0)

    private let dayOptions = [1, 3, 7, 14, 30, 60, 90, 180, 365]
    private let maxOptions = [500, 1000, 2000, 5000, 10000, 0]

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("自动删除超过")
                    TextField("", value: $settings.retentionDays, format: .number)
                        .frame(width: 56)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $settings.retentionDays, in: 0...3650).labelsHidden()
                    Text("天的记录")
                    Spacer()
                    Menu("常用") {
                        ForEach(dayOptions, id: \.self) { d in Button("\(d) 天") { settings.retentionDays = d } }
                        Divider()
                        Button("永不删除") { settings.retentionDays = 0 }
                    }
                    .fixedSize()
                }
                Picker("最多保留", selection: $settings.maxItems) {
                    ForEach(maxOptions, id: \.self) { n in Text(n == 0 ? "不限条数" : "\(n) 条").tag(n) }
                }
                HStack {
                    Button("立即清理") {
                        let n = actions.purgeNow()
                        message = n > 0 ? "已清理 \(n) 条" : "没有需要清理的记录"
                        refreshCounts()
                    }
                    Button("清空全部历史…", role: .destructive) { confirmClear() }
                    Spacer()
                    Text(message).foregroundStyle(.secondary).font(.callout)
                }
            } header: {
                Text("保留规则")
            } footer: {
                Text(settings.retentionDays == 0
                     ? "当前：不按时间删除。收藏的记录永远不会被自动删除。"
                     : "每小时自动检查一次。收藏的记录永远不会被自动删除。")
                    .foregroundStyle(.secondary)
            }

            Section("快捷键与粘贴") {
                Picker("呼出面板", selection: $settings.hotkeyIndex) {
                    ForEach(HotkeyPreset.all.indices, id: \.self) { i in Text(HotkeyPreset.all[i].title).tag(i) }
                }
                Toggle("选中后直接粘贴到当前应用", isOn: $settings.pasteDirectly)
                if settings.pasteDirectly && !axTrusted {
                    HStack {
                        Label("自动粘贴需要“辅助功能”权限", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("去授权") {
                            Paster.requestTrust()
                            Paster.openAccessibilitySettings()
                        }
                        Button("刷新") { axTrusted = Paster.trusted }
                    }
                }
            }

            Section {
                Toggle("输入收藏的缩写时自动展开", isOn: $settings.expansionEnabled)
                if settings.expansionEnabled {
                    Toggle("中文等输入法下也展开", isOn: $settings.expandInIME)
                    if !axTrusted {
                        Label("需要“辅助功能”权限才能监听缩写", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else if !actions.expanderRunning() {
                        Text("正在启动监听…").foregroundStyle(.secondary)
                    }
                }
                Button("管理收藏与缩写…") { actions.openFavorites() }
            } header: {
                Text("快捷短语")
            } footer: {
                Text("给收藏设一个缩写（如 ;addr），在任何输入框里打出来就会替换成收藏内容。密码框里不会触发。默认只在英文输入状态下展开，拼音组字时可能删错字。")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("面板快选修饰键", selection: $settings.quickModifierIndex) {
                    ForEach(ModifierChoice.panel.indices, id: \.self) { i in
                        Text(ModifierChoice.panel[i].title).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("面板收起时也能用全局快捷键", isOn: $settings.globalQuickEnabled)
                if settings.globalQuickEnabled {
                    Picker("全局组合", selection: $settings.globalQuickModifierIndex) {
                        ForEach(ModifierChoice.global.indices, id: \.self) { i in
                            Text(ModifierChoice.global[i].title + " + 数字").tag(i)
                        }
                    }
                    if !settings.globalQuickStatus.isEmpty {
                        Text(settings.globalQuickStatus)
                            .font(.callout)
                            .foregroundStyle(settings.globalQuickStatus.hasPrefix("已启用") ? Color.secondary : Color.orange)
                    }
                }
            } header: {
                Text("数字快选")
            } footer: {
                let m = settings.quickModifier.title
                let g = settings.globalQuickModifier.title
                Text(settings.globalQuickEnabled
                     ? "可见卡片角落常驻显示 1–9，按 \(m)+数字直接粘贴。面板收起时按 \(g)+数字，粘贴最近第 N 条（不改变历史顺序）。"
                     : "可见卡片角落常驻显示 1–9，按 \(m)+数字直接粘贴。")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(settings.excludedApps) { app in
                    HStack {
                        if let icon = AppIcons.icon(for: app.bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "app.dashed").frame(width: 18, height: 18)
                        }
                        Text(app.name)
                        Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("移除") { settings.excludedApps.removeAll { $0 == app } }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button("添加应用…") { addExcludedApp() }
                    Button("恢复默认") { settings.excludedApps = Settings.defaultExcluded }
                }
            } header: {
                Text("不记录这些应用里的复制")
            } footer: {
                Text("另外，密码管理器标记为敏感（ConcealedType / TransientType）的内容一律不记录。")
                    .foregroundStyle(.secondary)
            }

            Section("通用") {
                Toggle("登录时自动启动", isOn: Binding(
                    get: { loginEnabled },
                    set: { setLogin($0) }))
                Toggle("暂停记录", isOn: $settings.paused)
                LabeledContent("记录数", value: "共 \(counts.total) 条，其中收藏 \(counts.favorites) 条")
                LabeledContent("数据位置") {
                    Button(actions.dataPath) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: actions.dataPath)])
                    }
                    .buttonStyle(.link)
                }
                Text("内容用 AES-GCM 加密后存储，密钥保存在钥匙串里。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 820)
        .onAppear {
            refreshCounts()
            axTrusted = Paster.trusted
        }
    }

    private func refreshCounts() { counts = actions.counts() }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "清空全部剪贴历史？"
        alert.informativeText = "收藏的记录会保留，其余全部删除，无法恢复。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            message = "已删除 \(actions.clearHistory()) 条"
            refreshCounts()
        }
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  !settings.isExcluded(id) else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            settings.excludedApps.append(ExcludedApp(bundleID: id, name: name))
        }
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "设置开机启动失败：\(error.localizedDescription)"
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}
