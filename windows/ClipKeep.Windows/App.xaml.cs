using System.ComponentModel;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using ClipKeep.Core;
using Forms = System.Windows.Forms;

namespace ClipKeep.Windows;

public partial class App : Application
{
    internal Snapshot State { get; private set; } = new();
    private EncryptedStore store = null!;
    private ClipboardService monitor = null!;
    private MainWindow panel = null!;
    private Forms.NotifyIcon? tray;
    private HwndSource? source;
    private Mutex? instance;
    private bool ownsMutex;
    private readonly DispatcherTimer purge = new() { Interval = TimeSpan.FromMinutes(10) };
    private SettingsWindow? settingsWindow;
    private bool hotkeyRegistered;
    private long copyGeneration;
    private const int HotkeyId = 0x434B;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (e.Args.Contains("--self-test")) { SelfTest(); return; }
        instance = new Mutex(true, "Local\\ClipKeep.Native", out ownsMutex);
        if (!ownsMutex) { MessageBox.Show("ClipKeep 已在运行，请使用托盘图标。", "ClipKeep"); Shutdown(); return; }
        try
        {
            store = new EncryptedStore(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ClipKeep"));
            State = store.Load();
            panel = new MainWindow(this);
            monitor = new ClipboardService(() => State.Settings, Capture, Notify);
            var handle = new WindowInteropHelper(panel).EnsureHandle();
            source = HwndSource.FromHwnd(handle);
            source.AddHook(WindowMessage);
            hotkeyRegistered = Native.RegisterHotKey(handle, HotkeyId, 0x4000 | 0x0002 | 0x0004, 0x56);
            tray = new Forms.NotifyIcon
            {
                Text = "ClipKeep",
                Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? System.Drawing.SystemIcons.Application,
                Visible = true,
                ContextMenuStrip = new Forms.ContextMenuStrip()
            };
            tray.ContextMenuStrip.Items.Add("打开剪贴历史 (Ctrl+Shift+V)", null, (_, _) => Dispatcher.Invoke(panel.Toggle));
            tray.ContextMenuStrip.Items.Add("暂停／继续记录", null, (_, _) => Dispatcher.Invoke(() => ChangeSettings(State.Settings with { Paused = !State.Settings.Paused })));
            tray.ContextMenuStrip.Items.Add("设置…", null, (_, _) => Dispatcher.Invoke(OpenSettings));
            tray.ContextMenuStrip.Items.Add("清空历史（保留收藏）…", null, (_, _) => Dispatcher.Invoke(ClearHistory));
            tray.ContextMenuStrip.Items.Add("退出", null, (_, _) => Dispatcher.Invoke(Shutdown));
            tray.DoubleClick += (_, _) => Dispatcher.Invoke(panel.Toggle);
            Purge();
            monitor.Start();
            purge.Tick += (_, _) => Purge(); purge.Start();
            if (!hotkeyRegistered) Notify("Ctrl+Shift+V 被其他应用占用，可通过托盘打开面板。");
            else Notify("已在托盘运行，按 Ctrl+Shift+V 打开历史。");
            if (e.Args.Contains("--show")) panel.Toggle();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or Win32Exception
            or System.Text.Json.JsonException or InvalidOperationException)
        {
            MessageBox.Show("ClipKeep 启动失败。原历史文件已保留，不会以空数据覆盖。\n" + ex.Message, "ClipKeep");
            Shutdown(1);
        }
    }

    private IntPtr WindowMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == Native.HotkeyMessage && wParam.ToInt32() == HotkeyId)
        { panel.Toggle(); handled = true; }
        return IntPtr.Zero;
    }

    private bool Commit(Snapshot candidate)
    {
        try
        {
            store.Save(candidate); State = candidate; panel.Refresh();
            if (tray is not null) tray.Text = State.Settings.Paused ? "ClipKeep — 已暂停记录" : "ClipKeep";
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or Win32Exception or InvalidOperationException)
        { Notify("保存失败，原记录保持不变。" + ex.Message); return false; }
    }
    private void Capture(ClipRecord record)
    {
        try { Commit(State with { Items = History.Add(State.Items, record, State.Settings, DateTimeOffset.UtcNow) }); }
        catch (InvalidOperationException ex) { Notify(ex.Message); }
    }
    private void Purge()
    {
        var items = History.Prune(State.Items, State.Settings, DateTimeOffset.UtcNow);
        if (items.Count != State.Items.Count) Commit(State with { Items = items });
    }
    internal bool ChangeSettings(ClipSettings settings)
    {
        try { return Commit(State with { Settings = settings, Items = History.Prune(State.Items, settings, DateTimeOffset.UtcNow) }); }
        catch (InvalidOperationException ex) { Notify(ex.Message); return false; }
    }
    internal void Favorite(ClipRecord item) => Commit(State with
    { Items = State.Items.Select(x => x.Id == item.Id ? x with { Favorite = !x.Favorite } : x).ToList() });
    internal void Delete(ClipRecord item)
    {
        if (MessageBox.Show("彻底删除这条记录？", "ClipKeep", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes)
            Commit(State with { Items = State.Items.Where(x => x.Id != item.Id).ToList() });
    }
    private void ClearHistory()
    {
        if (MessageBox.Show("清空全部非收藏记录？无法恢复。", "ClipKeep", MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes)
            Commit(State with { Items = State.Items.Where(x => x.Favorite).ToList() });
    }
    internal void OpenSettings()
    {
        panel.Dismiss(false);
        if (settingsWindow is not null) { settingsWindow.Activate(); return; }
        settingsWindow = new SettingsWindow(this);
        settingsWindow.Closed += (_, _) => settingsWindow = null;
        settingsWindow.Show();
    }
    internal async void Copy(ClipRecord item, bool paste, bool plain)
    {
        var generation = ++copyGeneration;
        if (!monitor.Write(item, plain)) return;
        var clipboardSequence = Native.GetClipboardSequenceNumber();
        var target = panel.PreviousWindow;
        var request = new PasteRequest(generation, clipboardSequence, target);
        panel.Dismiss(restoreFocus: true);
        if (!paste || !State.Settings.PasteDirectly || target == IntPtr.Zero) return;
        // Wait for the user's shortcut modifiers to be released; don't paste into a newly focused app.
        await Task.Delay(120);
        for (var i = 0; i < 15 && Keyboard.Modifiers != ModifierKeys.None; i++) await Task.Delay(40);
        if (generation != copyGeneration) return;
        if (Native.GetClipboardSequenceNumber() != clipboardSequence)
        { Notify("剪贴板在等待期间发生变化，已取消自动粘贴。"); return; }
        if (!request.CanSend(copyGeneration, Native.GetClipboardSequenceNumber(), Native.GetForegroundWindow(),
                Keyboard.Modifiers != ModifierKeys.None) || !Native.Paste())
            Notify("内容已复制；未自动粘贴，请在目标应用按 Ctrl+V（管理员应用可能阻止模拟输入）。");
    }
    private void Notify(string message)
    {
        if (panel is not null && panel.IsVisible) panel.Status(message);
        else if (tray is not null) tray.ShowBalloonTip(2500, "ClipKeep", message, Forms.ToolTipIcon.Info);
    }
    protected override void OnExit(ExitEventArgs e)
    {
        purge.Stop(); monitor?.Dispose();
        if (source is not null)
        {
            if (hotkeyRegistered) Native.UnregisterHotKey(source.Handle, HotkeyId);
            source.RemoveHook(WindowMessage);
        }
        settingsWindow?.Close();
        if (panel is not null) panel.CloseForExit();
        if (tray is not null) { tray.Visible = false; tray.Dispose(); }
        if (ownsMutex) instance?.ReleaseMutex();
        instance?.Dispose();
        base.OnExit(e);
    }
    private void SelfTest()
    {
        var directory = Path.Combine(Path.GetTempPath(), "clipkeep-selftest-" + Guid.NewGuid());
        try
        {
            var testStore = new EncryptedStore(directory);
            if (testStore.Load().Items.Count != 0) throw new Exception("Fresh store is not empty.");
            var item = new ClipRecord { Text = "synthetic-clipkeep-secret-2026", Favorite = true };
            var snapshot = new Snapshot { Items = [item] };
            testStore.Save(snapshot);
            if (Encoding.UTF8.GetString(File.ReadAllBytes(testStore.FilePath)).Contains(item.Text))
                throw new Exception("Plaintext found on disk.");
            if (testStore.Load().Items.Single().Text != item.Text) throw new Exception("DPAPI round trip failed.");
            testStore.Save(snapshot with { Settings = new ClipSettings { Paused = true } });
            if (!testStore.Load().Settings.Paused) throw new Exception("Atomic replacement failed.");
            File.WriteAllBytes(testStore.FilePath, [1, 2, 3]);
            try { testStore.Load(); throw new Exception("Corrupt data was accepted."); }
            catch (Win32Exception) { }
            if (!File.ReadAllBytes(testStore.FilePath).SequenceEqual(new byte[] { 1, 2, 3 }))
                throw new Exception("Corrupt data was overwritten.");
            panel = new MainWindow(this); panel.Refresh();
            _ = new WindowInteropHelper(panel).EnsureHandle();
            var settings = new SettingsWindow(this); settings.Close();
            Console.WriteLine("DPAPI, atomic store, corruption handling and WPF construction passed.");
            Shutdown(0);
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); Shutdown(1); }
        finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
    }
}
