import AppKit
import SwiftUI

final class PanelModel: ObservableObject {
    enum Tab: Hashable { case all, favorites }

    @Published var items: [ClipItem] = []
    @Published var query = "" { didSet { selection = 0 } }
    @Published var tab: Tab = .all { didSet { selection = 0 } }
    @Published var selection = 0 { didSet { copyStatus = "" } }
    @Published var focusToken = UUID()
    @Published var copyStatus = ""
    /// 当前完整显示在屏幕上的卡片（从左到右，最多 9 张），编号按这个顺序。
    @Published private(set) var visibleIDs: [Int64] = []

    var onCopy: ((ClipItem) -> Bool)?
    var onCopySucceeded: (() -> Void)?
    var onPaste: ((ClipItem, _ plain: Bool) -> Void)?
    var onToggleFavorite: ((ClipItem) -> Void)?
    var onDelete: ((ClipItem) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenFavorites: (() -> Void)?

    var filtered: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return items.filter { item in
            (tab == .all || item.favorite)
                && (q.isEmpty || item.text.localizedCaseInsensitiveContains(q)
                    || (item.abbrev?.localizedCaseInsensitiveContains(q) ?? false)
                    || (item.sourceName?.localizedCaseInsensitiveContains(q) ?? false))
        }
    }

    var selectedItem: ClipItem? {
        let list = filtered
        return list.indices.contains(selection) ? list[selection] : nil
    }

    func updateVisible(_ frames: [CardFrame], viewportWidth: CGFloat) {
        let ids = frames
            .filter { $0.minX >= -6 && $0.maxX <= viewportWidth + 6 }
            .sorted { $0.minX < $1.minX }
            .prefix(9)
            .map(\.id)
        if ids != visibleIDs { visibleIDs = ids }
    }

    func badge(for id: Int64) -> Int? {
        guard let i = visibleIDs.firstIndex(of: id) else { return nil }
        return i + 1
    }

    /// 粘贴第 n 张可见卡片（n 从 1 开始）。返回是否找到。
    @discardableResult
    func quickPick(_ n: Int) -> Bool {
        guard visibleIDs.indices.contains(n - 1),
              let item = items.first(where: { $0.id == visibleIDs[n - 1] }) else { return false }
        onPaste?(item, false)
        return true
    }

    /// 搜索框选中文字时交给系统复制；否则复制当前卡片，不改变选择和顺序。
    @discardableResult
    func copySelected(hasTextSelection: Bool) -> Bool {
        guard !hasTextSelection else { return false }
        guard let item = selectedItem else {
            copyStatus = "没有可复制的卡片"
            return true
        }
        if onCopy?(item) == true {
            copyStatus = "已复制"
            onCopySucceeded?()
        } else {
            copyStatus = "复制失败"
        }
        return true
    }

    func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selection = min(max(selection + delta, 0), count - 1)
    }
}

// MARK: - 面板

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        let list = model.filtered
        VStack(spacing: 0) {
            toolbar
            if list.isEmpty {
                emptyState
            } else {
                GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                                ClipCard(item: item, selected: index == model.selection,
                                         badge: model.badge(for: item.id),
                                         badgePrefix: Settings.shared.quickModifier.title,
                                         onStar: { model.onToggleFavorite?(item) })
                                    .background(GeometryReader { g in
                                        let f = g.frame(in: .named(Self.stripSpace))
                                        Color.clear.preference(key: CardFramesKey.self,
                                                               value: [CardFrame(id: item.id, minX: f.minX, maxX: f.maxX)])
                                    })
                                    .id(item.id)
                                    .onTapGesture(count: 2) { model.onPaste?(item, false) }
                                    .onTapGesture { model.selection = index }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                    .coordinateSpace(name: Self.stripSpace)
                    .onPreferenceChange(CardFramesKey.self) { frames in
                        model.updateVisible(frames, viewportWidth: viewport.size.width)
                    }
                    .onChange(of: model.selection) { _, new in
                        let current = model.filtered
                        guard current.indices.contains(new) else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(current[new].id, anchor: .center)
                        }
                    }
                    .onChange(of: model.query) { _, _ in
                        if let first = model.filtered.first { proxy.scrollTo(first.id, anchor: .leading) }
                    }
                }
                }
            }
            Text("←→ 选择   ↩ 粘贴   ⌘C 复制   \(Settings.shared.quickModifier.title)1–9 快速粘贴   ⇧↩ 纯文本   ⌘D 收藏   ⌘⌫ 删除   esc 关闭")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { _, _ in searchFocused = true }
    }

    private static let stripSpace = "clip-strip"

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(width: 240)
            .background(Color.primary.opacity(0.06), in: Capsule())

            TabChip(title: "全部", count: model.items.count, active: model.tab == .all) { model.tab = .all }
            TabChip(title: "收藏", count: model.items.filter(\.favorite).count,
                    active: model.tab == .favorites) { model.tab = .favorites }

            Spacer()
            Text(model.copyStatus)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)

            Button { model.onOpenFavorites?() } label: {
                Label("管理收藏", systemImage: "square.and.pencil").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("新建、编辑收藏，设置快捷缩写")

            Button { model.onOpenSettings?() } label: {
                Image(systemName: "gearshape").font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("设置")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.tab == .favorites ? "star" : "doc.on.clipboard")
                .font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(!model.query.isEmpty ? "没有匹配的记录"
                 : model.tab == .favorites ? "还没有收藏。选中卡片按 ⌘D 收藏" : "复制点东西试试")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TabChip: View {
    let title: String
    let count: Int
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)").foregroundStyle(active ? Color.primary.opacity(0.6) : Color.secondary.opacity(0.7))
            }
            .font(.system(size: 12, weight: active ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(active ? Color.primary.opacity(0.1) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 卡片

struct ClipCard: View {
    let item: ClipItem
    let selected: Bool
    var badge: Int? = nil
    var badgePrefix = "⌘"
    let onStar: () -> Void

    static let size = CGSize(width: 236, height: 236)

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: selected ? 3 : 1))
        .shadow(color: .black.opacity(selected ? 0.22 : 0.10), radius: selected ? 8 : 4, y: 2)
        .overlay(alignment: .bottomTrailing) {
            if let badge {
                Text("\(badgePrefix)\(badge)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .padding(.trailing, 10)
                    .padding(.bottom, 30)
            }
        }
        .scaleEffect(selected ? 1.0 : 0.97)
        .animation(.easeOut(duration: 0.12), value: selected)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var style: CardStyle { CardStyle(item) }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: style.symbol).font(.system(size: 11, weight: .semibold))
            Text(style.title).font(.system(size: 13, weight: .semibold))
            if let abbrev = item.abbrev, item.favorite { AbbrevChip(text: abbrev, onDark: true) }
            Spacer()
            Button(action: onStar) {
                Image(systemName: item.favorite ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(item.favorite ? Color.yellow : Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help(item.favorite ? "取消收藏" : "收藏（收藏的记录不会被自动删除）")
            if let icon = AppIcons.icon(for: item.sourceBundle) {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    .help(item.sourceName ?? "")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(style.color.gradient)
    }

    @ViewBuilder private var content: some View {
        if let data = item.thumb, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
        } else if item.kind == .file {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(item.text.split(separator: "\n").prefix(5).enumerated()), id: \.offset) { _, path in
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: String(path)))
                            .resizable().frame(width: 22, height: 22)
                        Text((path as NSString).lastPathComponent)
                            .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .padding(10)
        } else {
            Text(String(item.text.prefix(600)))
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .padding(10)
        }
    }

    private var footer: some View {
        HStack {
            Text(Self.formatter.localizedString(for: item.created, relativeTo: Date()))
            Spacer()
            Text(style.detail)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f
    }()
}

/// 卡片头部的类型、颜色和右下角说明。
private struct CardStyle {
    let title: String
    let symbol: String
    let color: Color
    let detail: String

    init(_ item: ClipItem) {
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.kind {
        case .image:
            title = "图片"; symbol = "photo"; color = Color(red: 0.93, green: 0.55, blue: 0.24)
            detail = text.replacingOccurrences(of: "图片 ", with: "")
        case .file:
            let n = text.split(separator: "\n").count
            title = n > 1 ? "\(n) 个文件" : "文件"; symbol = "doc"; color = Color(red: 0.55, green: 0.42, blue: 0.85)
            detail = ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)
        case .text, .rich:
            if Self.isLink(text) {
                title = "链接"; symbol = "link"; color = Color(red: 0.16, green: 0.62, blue: 0.62)
            } else if item.kind == .rich {
                title = "富文本"; symbol = "doc.richtext"; color = Color(red: 0.33, green: 0.45, blue: 0.86)
            } else {
                title = "文本"; symbol = "text.alignleft"; color = Color(red: 0.24, green: 0.56, blue: 0.92)
            }
            detail = "\(item.text.count) 字"
        }
    }

    private static func isLink(_ s: String) -> Bool {
        guard !s.contains(where: \.isWhitespace), let url = URL(string: s), let scheme = url.scheme else { return false }
        return ["http", "https", "ftp", "mailto"].contains(scheme.lowercased())
    }
}

enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

// MARK: - 可见卡片追踪

struct CardFrame: Equatable {
    let id: Int64
    let minX: CGFloat
    let maxX: CGFloat
}

struct CardFramesKey: PreferenceKey {
    static var defaultValue: [CardFrame] = []
    static func reduce(value: inout [CardFrame], nextValue: () -> [CardFrame]) {
        value.append(contentsOf: nextValue())
    }
}
