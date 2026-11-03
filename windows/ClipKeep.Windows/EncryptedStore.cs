using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using ClipKeep.Core;

namespace ClipKeep.Windows;

internal sealed record Snapshot
{
    public int Version { get; init; } = 1;
    public List<ClipRecord> Items { get; init; } = [];
    public ClipSettings Settings { get; init; } = new();
}

internal sealed class EncryptedStore(string directory)
{
    internal string FilePath => Path.Combine(directory, "history.dat");
    private const long MaxFileBytes = 100L * 1024 * 1024;

    internal Snapshot Load()
    {
        if (!File.Exists(FilePath)) return new();
        if (new FileInfo(FilePath).Length > MaxFileBytes) throw new InvalidDataException("历史文件过大，已停止读取。");
        var plain = Dpapi.Transform(File.ReadAllBytes(FilePath), protect: false);
        try
        {
            var snapshot = JsonSerializer.Deserialize<Snapshot>(plain)
                ?? throw new InvalidDataException("历史文件内容无效。");
            if (snapshot.Version != 1 || snapshot.Items is null || snapshot.Settings is null
                || snapshot.Settings.ExcludedProcesses is null || snapshot.Items.Any(x => x is null
                    || x.Text is null || x.Files is null || x.Source is null || x.Files.Any(path => path is null)))
                throw new InvalidDataException("无法读取此版本的历史文件。");
            if (snapshot.Settings.RetentionDays < 0 || snapshot.Settings.RetentionDays > 3650 || snapshot.Settings.MaxItems < 0)
                throw new InvalidDataException("历史文件设置无效。");
            return snapshot;
        }
        finally { CryptographicOperations.ZeroMemory(plain); }
    }

    internal void Save(Snapshot snapshot)
    {
        if (snapshot.Items.Sum(x => x.PayloadBytes) > History.MaxTotalBytes)
            throw new InvalidOperationException("历史内容超过 64 MiB，请删除部分记录或收藏后重试。");
        Directory.CreateDirectory(directory);
        var plain = JsonSerializer.SerializeToUtf8Bytes(snapshot);
        byte[] encrypted;
        try { encrypted = Dpapi.Transform(plain, protect: true); }
        finally { CryptographicOperations.ZeroMemory(plain); }
        if (encrypted.LongLength > MaxFileBytes) throw new InvalidOperationException("历史文件超过存储上限。");
        var temp = Path.Combine(directory, Guid.NewGuid() + ".tmp");
        try
        {
            using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { stream.Write(encrypted); stream.Flush(flushToDisk: true); }
            // Both paths are on the same volume. Replace only after encryption and durable write succeed.
            if (File.Exists(FilePath)) File.Replace(temp, FilePath, null);
            else File.Move(temp, FilePath);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}

internal static class Dpapi
{
    [StructLayout(LayoutKind.Sequential)]
    private struct Blob { public int Length; public IntPtr Data; }
    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptProtectData(ref Blob input, string? description, IntPtr entropy,
        IntPtr reserved, IntPtr prompt, uint flags, out Blob output);
    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptUnprotectData(ref Blob input, IntPtr description, IntPtr entropy,
        IntPtr reserved, IntPtr prompt, uint flags, out Blob output);
    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr memory);

    internal static byte[] Transform(byte[] bytes, bool protect)
    {
        var input = new Blob { Length = bytes.Length, Data = Marshal.AllocHGlobal(bytes.Length) };
        Blob output = default;
        try
        {
            Marshal.Copy(bytes, 0, input.Data, bytes.Length);
            // CRYPTPROTECT_UI_FORBIDDEN, no LOCAL_MACHINE flag: current Windows user only.
            var success = protect
                ? CryptProtectData(ref input, null, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output)
                : CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output);
            if (!success) throw new Win32Exception(Marshal.GetLastWin32Error(), "无法加密或解密历史；请使用原 Windows 用户，不要覆盖原文件。");
            var result = new byte[output.Length];
            Marshal.Copy(output.Data, result, 0, result.Length);
            return result;
        }
        finally
        {
            for (var i = 0; i < input.Length; i++) Marshal.WriteByte(input.Data, i, 0);
            Marshal.FreeHGlobal(input.Data);
            if (output.Data != IntPtr.Zero)
            {
                for (var i = 0; i < output.Length; i++) Marshal.WriteByte(output.Data, i, 0);
                LocalFree(output.Data);
            }
        }
    }
}
