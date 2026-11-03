using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace ClipKeep.Core;

public sealed record ClipRecord
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public DateTimeOffset Created { get; init; } = DateTimeOffset.UtcNow;
    public string Kind { get; init; } = "text";
    public string Text { get; init; } = "";
    public string? Html { get; init; }
    public string? Rtf { get; init; }
    public byte[]? ImagePng { get; init; }
    public string[] Files { get; init; } = [];
    public string Source { get; init; } = "";
    public bool Favorite { get; init; }
    [System.Text.Json.Serialization.JsonIgnore]
    public string Preview => Kind switch
    {
        "image" => "图片",
        "files" => string.Join("\n", Files.Select(Path.GetFileName)),
        _ => Text.Length > 600 ? Text[..600] : Text
    };
    [System.Text.Json.Serialization.JsonIgnore]
    public long PayloadBytes => Encoding.UTF8.GetByteCount(Text) + Encoding.UTF8.GetByteCount(Html ?? "")
        + Encoding.UTF8.GetByteCount(Rtf ?? "") + (ImagePng?.LongLength ?? 0)
        + Files.Sum(path => (long)Encoding.UTF8.GetByteCount(path));
    [System.Text.Json.Serialization.JsonIgnore]
    public long SerializedBytes => JsonSerializer.SerializeToUtf8Bytes(this).LongLength;
    public string Fingerprint() => Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(
        new { Kind, Text, Html, Rtf, ImagePng, Files })));
}

public sealed record ClipSettings
{
    public bool Paused { get; init; }
    public bool PasteDirectly { get; init; } = true;
    public int RetentionDays { get; init; } = 30;
    public int MaxItems { get; init; } = 500;
    public string[] ExcludedProcesses { get; init; } = ["1Password", "Bitwarden", "KeePass", "KeePassXC"];
}

public static class History
{
    public const long MaxItemBytes = 8 * 1024 * 1024;
    public const long MaxTotalBytes = 64 * 1024 * 1024;
    public const long MaxSerializedBytes = 96 * 1024 * 1024;
    public static List<ClipRecord> Add(IEnumerable<ClipRecord> records, ClipRecord incoming,
        ClipSettings settings, DateTimeOffset now)
    {
        if (incoming.PayloadBytes > MaxItemBytes) throw new InvalidOperationException("单条记录超过 8 MiB。");
        var list = records.ToList();
        var fingerprint = incoming.Fingerprint();
        var old = list.FirstOrDefault(item => item.Fingerprint() == fingerprint);
        if (old is not null) list.Remove(old);
        list.Insert(0, incoming with { Id = old?.Id ?? incoming.Id,
            Favorite = (old?.Favorite ?? false) || incoming.Favorite, Created = now });
        var result = Prune(list, settings, now);
        if (!result.Any(item => item.Id == (old?.Id ?? incoming.Id)))
            throw new InvalidOperationException("收藏占满存储空间，未记录新内容；请减少收藏后重试。");
        return result;
    }
    public static List<ClipRecord> Prune(IEnumerable<ClipRecord> records, ClipSettings settings,
        DateTimeOffset now)
    {
        if (settings.RetentionDays < 0 || settings.RetentionDays > 3650 || settings.MaxItems < 0)
            throw new ArgumentOutOfRangeException(nameof(settings));
        var cutoff = now.AddDays(-settings.RetentionDays);
        var list = records.Where(item => item.Favorite || settings.RetentionDays == 0 || item.Created >= cutoff)
            .OrderByDescending(item => item.Created).ToList();
        if (settings.MaxItems > 0)
        {
            var keep = list.Where(item => !item.Favorite).Take(settings.MaxItems).Select(item => item.Id).ToHashSet();
            list.RemoveAll(item => !item.Favorite && !keep.Contains(item.Id));
        }
        var bytes = list.Sum(item => item.PayloadBytes);
        var storedBytes = list.Sum(item => item.SerializedBytes);
        foreach (var item in list.Where(item => !item.Favorite).Reverse().ToArray())
        {
            if (bytes <= MaxTotalBytes && storedBytes <= MaxSerializedBytes) break;
            list.Remove(item); bytes -= item.PayloadBytes; storedBytes -= item.SerializedBytes;
        }
        if (bytes > MaxTotalBytes || storedBytes > MaxSerializedBytes)
            throw new InvalidOperationException("收藏超过存储容量，请先减少收藏内容。");
        return list;
    }
    public static IEnumerable<ClipRecord> Search(IEnumerable<ClipRecord> records, string query, bool favorites)
    {
        var term = query.Trim();
        return records.Where(item => (!favorites || item.Favorite) && (term.Length == 0
            || item.Text.Contains(term, StringComparison.OrdinalIgnoreCase)
            || item.Source.Contains(term, StringComparison.OrdinalIgnoreCase)
            || item.Files.Any(path => path.Contains(term, StringComparison.OrdinalIgnoreCase))))
            .OrderByDescending(item => item.Created);
    }
}
