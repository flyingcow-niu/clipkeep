import AppKit
import Carbon

struct ExcludedApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

struct HotkeyPreset {
    let title: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let all: [HotkeyPreset] = [
        HotkeyPreset(title: "⇧⌘V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)),
        HotkeyPreset(title: "⌥⌘V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey)),
        HotkeyPreset(title: "⌃⌘V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | controlKey)),
        HotkeyPreset(title: "⌃⌥V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey)),
    ]
}

/// 数字快选用的修饰键组合。
struct ModifierChoice {
    let title: String
    let carbon: UInt32
    let flags: NSEvent.ModifierFlags

    /// 面板数字快选使用的修饰键；编号常驻显示。
    static let panel: [ModifierChoice] = [
        ModifierChoice(title: "⌘", carbon: UInt32(cmdKey), flags: .command),
        ModifierChoice(title: "⌃", carbon: UInt32(controlKey), flags: .control),
        ModifierChoice(title: "⌥", carbon: UInt32(optionKey), flags: .option),
    ]

    /// 面板收起时的全局组合。不提供 ⇧⌘（⇧⌘3/4/5 是系统截图）和单独 ⌘（会抢浏览器切标签）。
    static let global: [ModifierChoice] = [
        ModifierChoice(title: "⌃⌥", carbon: UInt32(controlKey | optionKey), flags: [.control, .option]),
        ModifierChoice(title: "⌃⇧", carbon: UInt32(controlKey | shiftKey), flags: [.control, .shift]),
        ModifierChoice(title: "⌥⇧", carbon: UInt32(optionKey | shiftKey), flags: [.option, .shift]),
        ModifierChoice(title: "⌃⌘", carbon: UInt32(controlKey | cmdKey), flags: [.control, .command]),
        ModifierChoice(title: "⌥⌘", carbon: UInt32(optionKey | cmdKey), flags: [.option, .command]),
    ]

    /// 数字 1–9 的键码（主键盘那一排）。
    static let digitKeyCodes: [UInt16: Int] = [
        UInt16(kVK_ANSI_1): 1, UInt16(kVK_ANSI_2): 2, UInt16(kVK_ANSI_3): 3,
        UInt16(kVK_ANSI_4): 4, UInt16(kVK_ANSI_5): 5, UInt16(kVK_ANSI_6): 6,
        UInt16(kVK_ANSI_7): 7, UInt16(kVK_ANSI_8): 8, UInt16(kVK_ANSI_9): 9,
    ]
    static let digitCarbonKeys: [UInt32] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ].map { UInt32($0) }
}

/// 用户设置，全部存在 UserDefaults。
final class Settings: ObservableObject {
    static let shared = Settings()

    static let defaultExcluded: [ExcludedApp] = [
        ExcludedApp(bundleID: "com.apple.keychainaccess", name: "钥匙串访问"),
        ExcludedApp(bundleID: "com.apple.Passwords", name: "密码"),
        ExcludedApp(bundleID: "com.1password.1password", name: "1Password"),
        ExcludedApp(bundleID: "com.agilebits.onepassword7", name: "1Password 7"),
        ExcludedApp(bundleID: "com.bitwarden.desktop", name: "Bitwarden"),
    ]

    private let defaults = UserDefaults.standard

    /// 超过多少天的非收藏记录自动删除；0 = 永不删除。
    @Published var retentionDays: Int { didSet { defaults.set(max(0, retentionDays), forKey: Keys.retention) } }
    /// 非收藏记录最多保留条数；0 = 不限。
    @Published var maxItems: Int { didSet { defaults.set(maxItems, forKey: Keys.maxItems) } }
    @Published var hotkeyIndex: Int { didSet { defaults.set(hotkeyIndex, forKey: Keys.hotkey) } }
    /// 选中后是否直接模拟 ⌘V 粘贴到当前应用（需要辅助功能权限）。
    @Published var pasteDirectly: Bool { didSet { defaults.set(pasteDirectly, forKey: Keys.pasteDirectly) } }
    @Published var paused: Bool { didSet { defaults.set(paused, forKey: Keys.paused) } }
    /// 面板内数字快选的修饰键，见 ModifierChoice.panel。
    @Published var quickModifierIndex: Int { didSet { defaults.set(quickModifierIndex, forKey: Keys.quickModifier) } }
    /// 面板收起时，修饰键 + 1–9 直接粘贴最近第 N 条。
    @Published var globalQuickEnabled: Bool { didSet { defaults.set(globalQuickEnabled, forKey: Keys.globalQuick) } }
    @Published var globalQuickModifierIndex: Int {
        didSet { defaults.set(globalQuickModifierIndex, forKey: Keys.globalQuickModifier) }
    }
    /// 收藏缩写展开（类似 aText）。
    @Published var expansionEnabled: Bool { didSet { defaults.set(expansionEnabled, forKey: Keys.expansion) } }
    /// 中文等非 ASCII 输入法下也展开（拼音组字时可能删错字，默认关）。
    @Published var expandInIME: Bool { didSet { defaults.set(expandInIME, forKey: Keys.expandInIME) } }
    /// 全局快捷键注册结果，给设置页显示用（不持久化）。
    @Published var globalQuickStatus = ""
    @Published var excludedApps: [ExcludedApp] {
        didSet { defaults.set(try? JSONEncoder().encode(excludedApps), forKey: Keys.excluded) }
    }

    var hotkey: HotkeyPreset { HotkeyPreset.all[min(max(hotkeyIndex, 0), HotkeyPreset.all.count - 1)] }
    var quickModifier: ModifierChoice { Self.pick(ModifierChoice.panel, quickModifierIndex) }
    var globalQuickModifier: ModifierChoice { Self.pick(ModifierChoice.global, globalQuickModifierIndex) }

    static func pick<T>(_ list: [T], _ index: Int) -> T { list[min(max(index, 0), list.count - 1)] }

    private enum Keys {
        static let retention = "retentionDays"
        static let maxItems = "maxItems"
        static let hotkey = "hotkeyIndex"
        static let pasteDirectly = "pasteDirectly"
        static let paused = "paused"
        static let excluded = "excludedApps"
        static let quickModifier = "quickModifierIndex"
        static let globalQuick = "globalQuickEnabled"
        static let globalQuickModifier = "globalQuickModifierIndex"
        static let expansion = "expansionEnabled"
        static let expandInIME = "expandInIME"
    }

    private init() {
        defaults.register(defaults: [
            Keys.retention: 30,
            Keys.maxItems: 2000,
            Keys.hotkey: 0,
            Keys.pasteDirectly: true,
            Keys.paused: false,
            Keys.quickModifier: 0,
            Keys.globalQuick: false,
            Keys.globalQuickModifier: 0,
            Keys.expansion: true,
            Keys.expandInIME: false,
        ])
        retentionDays = defaults.integer(forKey: Keys.retention)
        maxItems = defaults.integer(forKey: Keys.maxItems)
        hotkeyIndex = defaults.integer(forKey: Keys.hotkey)
        pasteDirectly = defaults.bool(forKey: Keys.pasteDirectly)
        paused = defaults.bool(forKey: Keys.paused)
        quickModifierIndex = defaults.integer(forKey: Keys.quickModifier)
        globalQuickEnabled = defaults.bool(forKey: Keys.globalQuick)
        globalQuickModifierIndex = defaults.integer(forKey: Keys.globalQuickModifier)
        expansionEnabled = defaults.bool(forKey: Keys.expansion)
        expandInIME = defaults.bool(forKey: Keys.expandInIME)
        if let data = defaults.data(forKey: Keys.excluded),
           let apps = try? JSONDecoder().decode([ExcludedApp].self, from: data) {
            excludedApps = apps
        } else {
            excludedApps = Self.defaultExcluded
        }
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains { $0.bundleID == bundleID }
    }
}
