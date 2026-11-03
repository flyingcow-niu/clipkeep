using ClipKeep.Core;

var checks = 0;
void Check(bool condition, string name)
{
    if (!condition) throw new Exception("FAIL: " + name);
    checks++;
}
var now = DateTimeOffset.Parse("2026-11-03T12:00:00Z");
var settings = new ClipSettings { MaxItems = 2, RetentionDays = 30 };
var first = new ClipRecord { Text = "hello", Created = now.AddDays(-1), Favorite = true };
var duplicate = first with { Id = Guid.NewGuid(), Created = now, Favorite = false, Source = "editor" };
try
{
    var deduped = History.Add([first], duplicate, settings, now);
    Check(deduped.Count == 1, "duplicate is merged");
    Check(deduped[0].Id == first.Id && deduped[0].Favorite, "duplicate preserves identity and favorite");
    Check(deduped[0].Source == "editor" && deduped[0].Created == now, "duplicate refreshes source and time");
    var old = new ClipRecord { Text = "old", Created = now.AddDays(-40) };
    Check(History.Prune([old, first with { Created = old.Created }], settings, now).Single().Favorite,
        "age purge preserves favorites");
    var many = Enumerable.Range(0, 5).Select(i => new ClipRecord { Text = i.ToString(), Created = now.AddMinutes(-i) });
    var limited = History.Prune(many.Append(first), settings, now);
    Check(limited.Count == 3 && limited.Count(x => !x.Favorite) == 2, "count limit excludes favorites");
    Check(limited.Any(x => x.Text == "0") && limited.Any(x => x.Text == "1"), "newest records retained");
    Check(History.Prune([old], settings with { RetentionDays = 0, MaxItems = 0 }, now).Count == 1, "zero disables age/count limits");
    Check(History.Search([first, old], "HELLO", false).Single().Id == first.Id, "case-insensitive content search");
    Check(!History.Search([old], "", true).Any(), "favorite filtering");
    Check(History.Search([first with { Source = "Notepad" }], "notepad", false).Any(), "source search");
    Check(first.Fingerprint() == duplicate.Fingerprint(), "fingerprint excludes metadata");
    Check(first.Fingerprint() != (first with { Html = "<b>hello</b>" }).Fingerprint(), "rich formats distinguish identity");
    Check((first with { Text = "你好" }).PayloadBytes == 6, "size counts UTF-8 bytes");
    var file = new ClipRecord { Kind = "files", Files = ["a.txt", "b.txt"] };
    Check(file.Preview.Contains("b.txt"), "file preview");
    Check(new ClipRecord { Text = new string('x', 700) }.Preview.Length == 600, "bounded preview");
    var oversized = new ClipRecord { ImagePng = new byte[History.MaxItemBytes + 1] };
    try { History.Add([], oversized, settings, now); Check(false, "oversized rejected"); }
    catch (InvalidOperationException) { checks++; }
    try { History.Prune([], settings with { RetentionDays = -1 }, now); Check(false, "negative retention rejected"); }
    catch (ArgumentOutOfRangeException) { checks++; }
    var heavy = Enumerable.Range(0, 9).Select(i => new ClipRecord {
        Kind = "image", ImagePng = new byte[History.MaxItemBytes], Created = now.AddMinutes(-i), Source = i.ToString()
    }).ToList();
    var bounded = History.Prune(heavy, settings with { MaxItems = 0 }, now);
    Check(bounded.Count == 8 && bounded.All(x => x.Source != "8"), "byte budget evicts oldest non-favorite");
    var fullFavorites = heavy.Take(8).Select(x => x with { Favorite = true }).ToList();
    try { History.Add(fullFavorites, new ClipRecord { Text = "new" }, settings, now); Check(false, "full favorites reports rejected new capture"); }
    catch (InvalidOperationException) { checks++; }
    Check(fullFavorites.Count == 8 && fullFavorites.All(x => x.Favorite), "failed capture never mutates original history");
    Console.WriteLine($"{checks} core checks passed");
}
catch (Exception error) { Console.Error.WriteLine(error.Message); Environment.ExitCode = 1; }
