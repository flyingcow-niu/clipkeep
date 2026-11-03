import Foundation
import SQLite3

enum ClipKind: String {
    case text, rich, image, file

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .rich: return "doc.richtext"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}

struct ClipItem: Identifiable, Equatable {
    let id: Int64
    var created: Date
    let kind: ClipKind
    let text: String
    let thumb: Data?
    let sourceBundle: String?
    let sourceName: String?
    var favorite: Bool
    let size: Int
    /// 收藏的快捷缩写，比如 ";addr"。输入命中就自动展开成这条内容。
    var abbrev: String?
}

/// 一次复制的完整内容：每个 pasteboard item 的 [类型: 数据]。
typealias ClipPayload = [[String: Data]]

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class ClipStore {
    enum StoreError: Error { case open(String) }

    private var db: OpaquePointer?
    let fileURL: URL

    init() throws {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipKeep", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        fileURL = dir.appendingPathComponent("clips.sqlite")

        guard sqlite3_open(fileURL.path, &db) == SQLITE_OK else {
            throw StoreError.open(String(cString: sqlite3_errmsg(db)))
        }
        exec("PRAGMA auto_vacuum = INCREMENTAL;")
        exec("PRAGMA journal_mode = WAL;")
        exec("PRAGMA secure_delete = ON;")
        exec("""
            CREATE TABLE IF NOT EXISTS clips(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created REAL NOT NULL,
                kind TEXT NOT NULL,
                hash TEXT NOT NULL UNIQUE,
                preview BLOB NOT NULL,
                thumb BLOB,
                payload BLOB NOT NULL,
                source_bundle TEXT,
                source_name TEXT,
                favorite INTEGER NOT NULL DEFAULT 0,
                size INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_clips_created ON clips(created DESC);
            """)
        // v0.2：收藏缩写。列已存在时这条会失败，忽略即可。
        exec("ALTER TABLE clips ADD COLUMN abbrev TEXT;")
    }

    deinit { sqlite3_close(db) }

    // MARK: - 写入

    /// 新增一条；内容相同的旧记录会被顶到最前面，而不是重复保存。
    @discardableResult
    func upsert(payload: ClipPayload, identity: Data, kind: ClipKind, text: String, thumb: Data?,
                sourceBundle: String?, sourceName: String?) -> Int64? {
        guard let plain = try? PropertyListSerialization.data(
            fromPropertyList: payload, format: .binary, options: 0) else { return nil }
        let hash = Vault.fingerprint(Data(kind.rawValue.utf8) + identity)
        let now = Date().timeIntervalSince1970
        let sealedPayload = Vault.seal(plain)

        if let id = query("SELECT id FROM clips WHERE hash = ?", [hash], { sqlite3_column_int64($0, 0) }).first {
            run("UPDATE clips SET created = ?, payload = ?, size = ?, source_bundle = ?, source_name = ? WHERE id = ?",
                [now, sealedPayload, plain.count, sourceBundle, sourceName, id])
            return id
        }
        let ok = run("""
            INSERT INTO clips(created, kind, hash, preview, thumb, payload, source_bundle, source_name, favorite, size)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
            """,
            [now, kind.rawValue, hash, Vault.seal(Data(text.utf8)), thumb.map(Vault.seal), sealedPayload,
             sourceBundle, sourceName, plain.count])
        return ok ? sqlite3_last_insert_rowid(db) : nil
    }

    static let plainTextType = "public.utf8-plain-text"

    /// 手动新建一条收藏（纯文本）。
    func addManual(text: String, abbrev: String?) -> Int64? {
        guard let id = upsert(payload: [[Self.plainTextType: Data(text.utf8)]], identity: Data(text.utf8),
                              kind: .text, text: String(text.prefix(20_000)), thumb: nil,
                              sourceBundle: nil, sourceName: "手动添加") else { return nil }
        setFavorite(id, true)
        setAbbrev(id, abbrev)
        return id
    }

    /// 修改纯文本记录的内容。和别的记录内容重复时返回 false。
    func updateText(_ id: Int64, text: String) -> Bool {
        let plain = (try? PropertyListSerialization.data(
            fromPropertyList: [[Self.plainTextType: Data(text.utf8)]] as ClipPayload, format: .binary, options: 0)) ?? Data()
        let hash = Vault.fingerprint(Data(ClipKind.text.rawValue.utf8) + Data(text.utf8))
        if let other = query("SELECT id FROM clips WHERE hash = ?", [hash], { sqlite3_column_int64($0, 0) }).first,
           other != id { return false }
        return run("UPDATE clips SET kind = 'text', hash = ?, preview = ?, payload = ?, size = ? WHERE id = ?",
                   [hash, Vault.seal(Data(String(text.prefix(20_000)).utf8)), Vault.seal(plain), plain.count, id])
    }

    func setAbbrev(_ id: Int64, _ abbrev: String?) {
        let value = abbrev.flatMap { $0.isEmpty ? nil : $0 }
        run("UPDATE clips SET abbrev = ? WHERE id = ?", [value, id])
    }

    func touch(_ id: Int64) {
        run("UPDATE clips SET created = ? WHERE id = ?", [Date().timeIntervalSince1970, id])
    }

    func setFavorite(_ id: Int64, _ favorite: Bool) {
        run("UPDATE clips SET favorite = ? WHERE id = ?", [favorite ? 1 : 0, id])
    }

    func delete(_ id: Int64) {
        run("DELETE FROM clips WHERE id = ?", [id])
    }

    /// 按保留天数和条数上限清理；收藏的记录永远不删。返回删除条数。
    @discardableResult
    func purge(retentionDays: Int, maxItems: Int) -> Int {
        var removed = 0
        if retentionDays > 0 {
            let cutoff = Date().timeIntervalSince1970 - Double(retentionDays) * 86_400
            run("DELETE FROM clips WHERE favorite = 0 AND created < ?", [cutoff])
            removed += Int(sqlite3_changes(db))
        }
        if maxItems > 0 {
            run("""
                DELETE FROM clips WHERE favorite = 0 AND id NOT IN
                (SELECT id FROM clips WHERE favorite = 0 ORDER BY created DESC LIMIT ?)
                """, [maxItems])
            removed += Int(sqlite3_changes(db))
        }
        if removed > 0 { exec("PRAGMA incremental_vacuum;") }
        return removed
    }

    @discardableResult
    func clearNonFavorites() -> Int {
        run("DELETE FROM clips WHERE favorite = 0", [])
        let n = Int(sqlite3_changes(db))
        exec("PRAGMA incremental_vacuum;")
        return n
    }

    // MARK: - 读取

    func loadAll() -> [ClipItem] {
        query("""
            SELECT id, created, kind, preview, thumb, source_bundle, source_name, favorite, size, abbrev
            FROM clips ORDER BY created DESC
            """, []) { s -> ClipItem in
            let preview = Self.blob(s, 3).flatMap(Vault.open).flatMap { String(data: $0, encoding: .utf8) }
            return ClipItem(
                id: sqlite3_column_int64(s, 0),
                created: Date(timeIntervalSince1970: sqlite3_column_double(s, 1)),
                kind: ClipKind(rawValue: Self.text(s, 2) ?? "") ?? .text,
                text: preview ?? "（无法解密）",
                thumb: Self.blob(s, 4).flatMap(Vault.open),
                sourceBundle: Self.text(s, 5),
                sourceName: Self.text(s, 6),
                favorite: sqlite3_column_int(s, 7) != 0,
                size: Int(sqlite3_column_int64(s, 8)),
                abbrev: Self.text(s, 9))
        }
    }

    func payload(_ id: Int64) -> ClipPayload? {
        guard let sealed = query("SELECT payload FROM clips WHERE id = ?", [id], { Self.blob($0, 0) }).first,
              let plain = sealed.flatMap(Vault.open) else { return nil }
        return try? PropertyListSerialization.propertyList(from: plain, format: nil) as? ClipPayload
    }

    func counts() -> (total: Int, favorites: Int) {
        let row = query("SELECT COUNT(*), COALESCE(SUM(favorite), 0) FROM clips", []) {
            (Int(sqlite3_column_int64($0, 0)), Int(sqlite3_column_int64($0, 1)))
        }.first
        return row ?? (0, 0)
    }

    // MARK: - SQLite 小封装

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    @discardableResult
    private func run(_ sql: String, _ args: [Any?]) -> Bool {
        guard let s = prepare(sql, args) else { return false }
        defer { sqlite3_finalize(s) }
        return sqlite3_step(s) == SQLITE_DONE
    }

    private func query<T>(_ sql: String, _ args: [Any?], _ row: (OpaquePointer) -> T) -> [T] {
        guard let s = prepare(sql, args) else { return [] }
        defer { sqlite3_finalize(s) }
        var out: [T] = []
        while sqlite3_step(s) == SQLITE_ROW { out.append(row(s)) }
        return out
    }

    private func prepare(_ sql: String, _ args: [Any?]) -> OpaquePointer? {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK else {
            NSLog("ClipKeep SQL error: %@", String(cString: sqlite3_errmsg(db)))
            return nil
        }
        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            switch arg {
            case let v as Int64: sqlite3_bind_int64(s, idx, v)
            case let v as Int: sqlite3_bind_int64(s, idx, Int64(v))
            case let v as Double: sqlite3_bind_double(s, idx, v)
            case let v as String: sqlite3_bind_text(s, idx, v, -1, SQLITE_TRANSIENT)
            case let v as Data:
                _ = v.withUnsafeBytes { sqlite3_bind_blob(s, idx, $0.baseAddress, Int32(v.count), SQLITE_TRANSIENT) }
            default: sqlite3_bind_null(s, idx)
            }
        }
        return s
    }

    private static func blob(_ s: OpaquePointer, _ i: Int32) -> Data? {
        guard let p = sqlite3_column_blob(s, i) else { return nil }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(s, i)))
    }

    private static func text(_ s: OpaquePointer, _ i: Int32) -> String? {
        guard let p = sqlite3_column_text(s, i) else { return nil }
        return String(cString: p)
    }
}
