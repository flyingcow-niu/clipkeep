using System.Collections.Specialized;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using ClipKeep.Core;

namespace ClipKeep.Windows;

internal sealed class ClipboardService(Func<ClipSettings> settings, Action<ClipRecord> captured, Action<string> error) : IDisposable
{
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(500) };
    private uint last = Native.GetClipboardSequenceNumber();
    internal void Start() { timer.Tick += Poll; timer.Start(); }
    internal void SkipCurrent() => last = Native.GetClipboardSequenceNumber();
    public void Dispose() { timer.Stop(); timer.Tick -= Poll; }

    private void Poll(object? sender, EventArgs args)
    {
        var sequence = Native.GetClipboardSequenceNumber();
        if (sequence == last) return;
        var config = settings();
        var source = Native.ClipboardOwnerProcess();
        if (config.Paused || source.Length == 0 || source.Equals("ClipKeep", StringComparison.OrdinalIgnoreCase)
            || config.ExcludedProcesses.Contains(source, StringComparer.OrdinalIgnoreCase)) { last = sequence; return; }
        try
        {
            var data = Clipboard.GetDataObject();
            if (data is null) { last = sequence; return; }
            // Treat presence of any privacy opt-out marker conservatively as do-not-record.
            string[] sensitive = ["ExcludeClipboardContentFromMonitorProcessing", "CanIncludeInClipboardHistory",
                "CanUploadToCloudClipboard", "Clipboard Viewer Ignore", "org.nspasteboard.ConcealedType",
                "org.nspasteboard.TransientType"];
            if (sensitive.Any(format => data.GetDataPresent(format, false))) { last = sequence; return; }
            ClipRecord? record = null;
            if (data.GetDataPresent(DataFormats.FileDrop))
            {
                if (data.GetData(DataFormats.FileDrop) is string[] paths && paths.Length > 0)
                    record = new() { Kind = "files", Files = paths, Text = string.Join("\n", paths), Source = source };
            }
            else if (data.GetDataPresent(DataFormats.UnicodeText))
            {
                var text = data.GetData(DataFormats.UnicodeText) as string ?? "";
                if (Encoding.UTF8.GetByteCount(text) > History.MaxItemBytes) { last = sequence; error("文本超过 8 MiB，未记录。"); return; }
                if (!string.IsNullOrWhiteSpace(text)) record = new()
                {
                    Text = text, Source = source,
                    Html = data.GetDataPresent(DataFormats.Html, false) ? data.GetData(DataFormats.Html, false) as string : null,
                    Rtf = data.GetDataPresent(DataFormats.Rtf, false) ? data.GetData(DataFormats.Rtf, false) as string : null
                };
            }
            else if (data.GetDataPresent(DataFormats.Bitmap) && data.GetData(DataFormats.Bitmap) is BitmapSource image)
            {
                if ((long)image.PixelWidth * image.PixelHeight > 16_000_000) { last = sequence; error("图片像素过大，未记录。"); return; }
                var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image));
                using var stream = new MemoryStream(); encoder.Save(stream);
                record = new() { Kind = "image", ImagePng = stream.ToArray(), Source = source };
            }
            if (Native.GetClipboardSequenceNumber() != sequence) return;
            last = sequence;
            if (record is not null)
            {
                if (record.PayloadBytes > History.MaxItemBytes) { error("内容超过 8 MiB，未记录。"); return; }
                captured(record);
            }
        }
        catch (ExternalException) { /* Clipboard held by another application: retry next tick. */ }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or ArgumentException or NotSupportedException)
        { last = sequence; error("无法读取这条剪贴板内容。"); }
    }

    internal bool Write(ClipRecord record, bool plain)
    {
        try
        {
            var data = new DataObject();
            if (record.Kind == "image" && !plain && record.ImagePng is { } bytes)
            {
                using var stream = new MemoryStream(bytes);
                var image = new BitmapImage(); image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad;
                image.StreamSource = stream; image.EndInit(); image.Freeze();
                data.SetData(DataFormats.Bitmap, image);
            }
            else if (record.Kind == "files" && !plain)
            {
                if (record.Files.Any(path => !File.Exists(path) && !Directory.Exists(path)))
                { error("原文件已移动或删除，无法复制。"); return false; }
                var files = new StringCollection(); files.AddRange(record.Files); data.SetFileDropList(files);
            }
            else
            {
                if (record.Kind == "image") { error("图片没有纯文本内容。"); return false; }
                data.SetText(record.Text, TextDataFormat.UnicodeText);
                if (!plain)
                {
                    if (record.Html is not null) data.SetData(DataFormats.Html, record.Html);
                    if (record.Rtf is not null) data.SetData(DataFormats.Rtf, record.Rtf);
                }
            }
            // Avoid duplicating app-managed copies into Windows cloud/history services.
            data.SetData("ExcludeClipboardContentFromMonitorProcessing", new MemoryStream([0]));
            Clipboard.SetDataObject(data, true);
            SkipCurrent(); return true;
        }
        catch (Exception ex) when (ex is ExternalException or IOException or InvalidOperationException or ArgumentException or NotSupportedException)
        { error("复制失败，剪贴板可能被其他程序占用，请重试。"); return false; }
    }
}
