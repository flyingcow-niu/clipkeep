import AppKit
import SwiftUI

/// 收藏管理窗口的数据。
final class FavoritesModel: ObservableObject {
    @Published var items: [ClipItem] = []   // 只放收藏
    @Published var query = ""
    @Published var selectedID: Int64?
    /// 每次点“新建”换一个值，让编辑区切到空白草稿。
    @Published var newDraftToken: UUID?

    var filtered: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.text.localizedCaseInsensitiveContains(q) || ($0.abbrev?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var selected: ClipItem? { items.first { $0.id == selectedID } }
}

struct FavoritesActions {
    let validateAbbrev: (_ abbrev: String, _ excluding: Int64?) -> FavoriteError?
    /// 新建；成功返回新 id，失败返回错误文案。
    let add: (_ text: String, _ abbrev: String) -> Result<Int64, FavoriteError>
    /// 保存修改；text 为 nil 表示内容不可编辑（图片、文件、富文本）。
    let save: (_ id: Int64, _ text: String?, _ abbrev: String) -> FavoriteError?
    let unfavorite: (_ id: Int64) -> Void
    let delete: (_ id: Int64) -> Void
    /// 完整文本（列表里存的只是预览）。
    let fullText: (_ id: Int64) -> String?
}

struct FavoritesView: View {
    @ObservedObject var model: FavoritesModel
    let actions: FavoritesActions

    @State private var draftText = ""
    @State private var draftAbbrev = ""
    @State private var isNew = false
    @State private var message = ""
    @FocusState private var editorFocused: Bool

    private var normalizedAbbrev: String {
        draftAbbrev.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var abbreviationError: FavoriteError? {
        actions.validateAbbrev(normalizedAbbrev, isNew ? nil : model.selectedID)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 300)
            Divider()
            editor.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 520)
        .onChange(of: model.selectedID) { _, _ in loadSelection() }
        .onChange(of: model.newDraftToken) { _, token in if token != nil { startNew() } }
    }

    // MARK: 左侧列表

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索内容或缩写", text: $model.query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                Button { startNew() } label: { Image(systemName: "plus") }
                    .help("新建收藏")
            }
            .padding(10)

            List(model.filtered, selection: $model.selectedID) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let a = item.abbrev { AbbrevChip(text: a) }
                        Text(kindLabel(item)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(item.text.replacingOccurrences(of: "\n", with: " "))
                        .lineLimit(2)
                        .font(.system(size: 12))
                }
                .padding(.vertical, 3)
                .tag(item.id)
            }
            .listStyle(.sidebar)
            .overlay {
                if model.filtered.isEmpty {
                    Text(model.query.isEmpty ? "还没有收藏，点 + 新建" : "没有匹配的收藏")
                        .foregroundStyle(.secondary)
                }
            }

            Text("共 \(model.items.count) 条收藏，\(model.items.filter { $0.abbrev != nil }.count) 条设了缩写")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    // MARK: 右侧编辑

    @ViewBuilder private var editor: some View {
        if isNew || model.selected != nil {
            let editable = isNew || model.selected?.kind == .text
            VStack(alignment: .leading, spacing: 12) {
                Text(isNew ? "新建收藏" : "编辑收藏").font(.title3.bold())

                VStack(alignment: .leading, spacing: 4) {
                    Text("缩写（可选）").font(.callout.weight(.medium))
                    TextField("例如 ;addr  ;mail  //sig", text: $draftAbbrev)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 260)
                        .onChange(of: draftAbbrev) { _, _ in message = "" }
                    if let error = abbreviationError {
                        Label(error.message, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(error.message)
                    }
                    Text("在任何地方输入这个缩写，会自动替换成下面的内容。建议用 ; 或 // 开头；中英文标点等价（如 ;;t 与 ；；t）。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("内容").font(.callout.weight(.medium))
                    if editable {
                        TextEditor(text: $draftText)
                            .font(.system(size: 13))
                            .focused($editorFocused)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
                    } else {
                        ScrollView {
                            Text(draftText).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(6)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        Text("这条是从剪贴板收藏的\(kindLabel(model.selected!))，内容不能在这里改，只能设置缩写。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button(isNew ? "添加" : "保存") { save(editable: editable) }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(abbreviationError != nil)
                    if !isNew, let id = model.selectedID {
                        Button("取消收藏") { actions.unfavorite(id); model.selectedID = nil }
                        Button("删除", role: .destructive) { confirmDelete(id) }
                    } else {
                        Button("取消") { isNew = false }
                    }
                    Spacer()
                    Text(message).font(.callout).foregroundStyle(message.hasPrefix("✓") ? Color.secondary : Color.orange)
                }
            }
            .padding(20)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "star.square.on.square").font(.system(size: 34)).foregroundStyle(.tertiary)
                Text("选择左侧的收藏进行编辑，或点 + 新建").foregroundStyle(.secondary)
                Button("新建收藏") { startNew() }
            }
        }
    }

    // MARK: 动作

    private func startNew() {
        model.selectedID = nil
        isNew = true
        draftText = ""
        draftAbbrev = ""
        message = ""
        editorFocused = true
    }

    private func loadSelection() {
        guard let item = model.selected else { return }
        isNew = false
        draftAbbrev = item.abbrev ?? ""
        draftText = (item.kind == .text || item.kind == .rich) ? (actions.fullText(item.id) ?? item.text) : item.text
        message = ""
    }

    private func save(editable: Bool) {
        let abbrev = normalizedAbbrev
        if let error = abbreviationError {
            message = error.message
            return
        }
        if isNew {
            switch actions.add(draftText, abbrev) {
            case .success(let id):
                isNew = false
                model.selectedID = id
                message = "✓ 已添加"
            case .failure(let error):
                message = error.message
            }
        } else if let id = model.selectedID {
            if let error = actions.save(id, editable ? draftText : nil, abbrev) {
                message = error.message
            } else {
                message = "✓ 已保存"
            }
        }
    }

    private func confirmDelete(_ id: Int64) {
        let alert = NSAlert()
        alert.messageText = "删除这条收藏？"
        alert.informativeText = "会从剪贴历史里彻底删除，无法恢复。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            actions.delete(id)
            model.selectedID = nil
        }
    }

    private func kindLabel(_ item: ClipItem) -> String {
        switch item.kind {
        case .text: return item.sourceName == "手动添加" ? "手动添加" : "文本"
        case .rich: return "富文本"
        case .image: return "图片"
        case .file: return "文件"
        }
    }
}

struct AbbrevChip: View {
    let text: String
    var onDark = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(onDark ? Color.white : Color.accentColor)
            .background(onDark ? Color.white.opacity(0.22) : Color.accentColor.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 4))
    }
}
