struct FavoriteError: Error {
    let message: String
}

enum AbbreviationValidator {
    struct Entry {
        let id: Int64
        let abbrev: String
        let title: String
    }

    static func validate(_ abbrev: String, entries: [Entry], excluding id: Int64?) -> FavoriteError? {
        guard !abbrev.isEmpty else { return nil }
        if abbrev.contains(where: \.isWhitespace) { return FavoriteError(message: "缩写里不能有空格") }
        if abbrev.count < 2 || abbrev.count > 32 { return FavoriteError(message: "缩写长度需要 2–32 个字符") }
        let normalized = AbbreviationText.normalize(abbrev)
        if let other = entries.first(where: { AbbreviationText.normalize($0.abbrev) == normalized && $0.id != id }) {
            return FavoriteError(message: "缩写与「\(other.abbrev)」重复或中英文标点等价，已被「\(other.title.prefix(12))」使用")
        }
        if let other = entries.first(where: {
            $0.id != id && !$0.abbrev.isEmpty
                && (normalized.hasPrefix(AbbreviationText.normalize($0.abbrev)) || AbbreviationText.normalize($0.abbrev).hasPrefix(normalized))
        }) {
            return FavoriteError(message: "与已有缩写「\(other.abbrev)」冲突：一个是另一个的前缀，会提前触发展开，请换一个缩写")
        }
        return nil
    }
}
