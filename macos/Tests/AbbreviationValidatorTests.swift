import Darwin

@main
struct AbbreviationValidatorTests {
    static func main() {
        typealias Entry = AbbreviationValidator.Entry
        let short = Entry(id: 1, abbrev: ";a", title: "短语一")
        let long = Entry(id: 2, abbrev: ";addr", title: "地址")
        let cases: [(String, String, [Entry], Int64?, Bool)] = [
            ("新缩写以已有缩写开头", ";addr", [short], nil, false),
            ("新缩写是已有缩写的前缀", ";a", [long], nil, false),
            ("中文分号等价冲突", "；addr", [long], nil, false),
            ("中文分号前缀冲突", "；address", [long], nil, false),
            ("中文短缩写前缀冲突", "；a", [long], nil, false),
            ("中文等价编辑排除自己", "；addr", [long], 2, true),
            ("完全重复", ";addr", [long], nil, false),
            ("编辑时排除自身", ";addr", [long], 2, true),
            ("编辑时仍检查其他记录", ";addr", [short, long], 2, false),
            ("共同前缀但互不包含", ";admin", [long], nil, true),
            ("允许清空缩写", "", [long], nil, true),
            ("拒绝空格", "; a", [], nil, false),
            ("拒绝换行", ";a\n", [], nil, false),
            ("拒绝过短", ";", [], nil, false),
            ("允许32字符", String(repeating: "a", count: 32), [], nil, true),
            ("拒绝过长", String(repeating: "a", count: 33), [], nil, false),
            ("区分大小写，与展开匹配一致", ";ADDR", [long], nil, true),
            ("忽略空缩写条目", ";a", [Entry(id: 3, abbrev: "", title: "空")], nil, true),
        ]
        var failures = 0
        for (name, input, entries, id, valid) in cases {
            let result = AbbreviationValidator.validate(input, entries: entries, excluding: id)
            if (result == nil) != valid {
                print("FAIL: \(name)")
                failures += 1
            }
        }
        let matching: [(String, String, Bool)] = [
            ("；；t", ";;t", true), (";；t", ";;t", true), ("；;t", ";;t", true),
            (";;t", "；；t", true), ("前文；；t", ";;t", true),
            ("；；T", ";;t", false), ("；；tx", ";;t", false), ("anything", "", false),
            ("／／sig", "//sig", true), ("：mail", ":mail", true),
        ]
        for (input, abbreviation, expected) in matching {
            if AbbreviationText.matches(buffer: input, abbreviation: abbreviation) != expected {
                print("FAIL: 匹配 \(input) / \(abbreviation)")
                failures += 1
            }
        }
        let total = cases.count + matching.count
        print("\(total - failures)/\(total) abbreviation tests passed")
        if failures > 0 { exit(1) }
    }
}
