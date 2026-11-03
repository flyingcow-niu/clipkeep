/// 缩写匹配与冲突校验共用的标点规则。
enum AbbreviationText {
    // 每个标点一对一替换，保持字符数与退格数一致；不改变字母大小写。
    private static let punctuation: [Character: Character] = [
        "；": ";", "：": ":", "，": ",", "。": ".", "！": "!", "？": "?",
        "（": "(", "）": ")", "【": "[", "】": "]", "／": "/", "＃": "#", "＠": "@"
    ]

    static func normalize(_ text: String) -> String {
        String(text.map { punctuation[$0] ?? $0 })
    }

    static func matches(buffer: String, abbreviation: String) -> Bool {
        !abbreviation.isEmpty && normalize(buffer).hasSuffix(normalize(abbreviation))
    }
}
