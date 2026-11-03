import AppKit

@main
struct PanelTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { print("FAIL: \(name)"); exit(1) }
            checks += 1
        }
        let model = PanelModel()
        func item(_ id: Int64, _ text: String) -> ClipItem {
            ClipItem(id: id, created: Date(), kind: .text, text: text, thumb: nil,
                     sourceBundle: nil, sourceName: nil, favorite: false, size: text.count, abbrev: nil)
        }
        model.items = [item(7, "first"), item(8, "second")]
        model.updateVisible([CardFrame(id: 7, minX: 0, maxX: 236), CardFrame(id: 8, minX: 250, maxX: 486)], viewportWidth: 600)
        check(model.badge(for: 7) == 1 && model.badge(for: 8) == 2, "编号默认显示")
        check(model.badge(for: 99) == nil, "不显示屏幕外编号")
        var dismissed = 0
        model.onCopySucceeded = { dismissed += 1 }
        var copied: Int64?
        model.onCopy = { copied = $0.id; return true }
        model.move(1)
        check(model.copySelected(hasTextSelection: false), "复制快捷键被处理")
        check(dismissed == 1, "复制成功后收起面板")
        check(copied == 8, "复制左右选择的卡片")
        check(model.selection == 1 && model.items.map(\.id) == [7, 8], "复制不改变选择和顺序")
        check(model.copyStatus == "已复制", "成功反馈")
        copied = nil
        check(!model.copySelected(hasTextSelection: true) && copied == nil, "选中文字保留系统复制")
        check(dismissed == 1, "复制搜索文字时不收起面板")
        model.query = "first"
        model.copySelected(hasTextSelection: false)
        check(copied == 7, "复制搜索结果中的选择")
        model.onCopy = { _ in false }
        model.copySelected(hasTextSelection: false)
        check(dismissed == 2, "复制失败时不收起面板")
        check(model.copyStatus == "复制失败", "失败不报告成功")
        model.query = "missing"
        copied = nil
        model.copySelected(hasTextSelection: false)
        check(copied == nil && model.copyStatus == "没有可复制的卡片", "空结果安全处理")
        check(dismissed == 2, "空结果时不收起面板")
        print("\(checks)/\(checks) panel tests passed")
    }
}
