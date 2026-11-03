using System.Windows;
using System.Windows.Controls;
using ClipKeep.Core;

namespace ClipKeep.Windows;

internal sealed class SettingsWindow : Window
{
    internal SettingsWindow(App app)
    {
        Title = "ClipKeep 设置"; Width = 490; Height = 490; ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var panel = new StackPanel { Margin = new Thickness(22) };
        var current = app.State.Settings;
        var paused = new CheckBox { Content = "暂停记录", IsChecked = current.Paused, Margin = new Thickness(4, 10, 4, 10) };
        var paste = new CheckBox { Content = "Enter 后自动粘贴到原应用", IsChecked = current.PasteDirectly, Margin = new Thickness(4, 10, 4, 10) };
        panel.Children.Add(paused); panel.Children.Add(paste);
        panel.Children.Add(new TextBlock { Text = "保留天数（0 = 不按时间清理，收藏不自动删除）" });
        var days = new TextBox { Text = current.RetentionDays.ToString() }; panel.Children.Add(days);
        panel.Children.Add(new TextBlock { Text = "最多保留非收藏条数（0 = 不限条数，仍有 64 MiB 总上限）" });
        var count = new TextBox { Text = current.MaxItems.ToString() }; panel.Children.Add(count);
        panel.Children.Add(new TextBlock { Text = "排除的应用进程名（逗号分隔，不含 .exe）" });
        var excluded = new TextBox { Text = string.Join(", ", current.ExcludedProcesses) }; panel.Children.Add(excluded);
        panel.Children.Add(new TextBlock { Text = "呼出面板：Ctrl+Shift+V\n数据使用当前 Windows 用户 DPAPI 加密。\n历史文件：%LOCALAPPDATA%\\ClipKeep\\history.dat",
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(4, 12, 4, 4) });
        var message = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var save = new Button { Content = "保存并应用" };
        save.Click += (_, _) =>
        {
            if (!int.TryParse(days.Text, out var retention) || retention < 0 || retention > 3650
                || !int.TryParse(count.Text, out var max) || max < 0 || max > 100000)
            { message.Text = "天数需为 0–3650，条数需为 0–100000 的整数。"; return; }
            var settings = current with { Paused = paused.IsChecked == true, PasteDirectly = paste.IsChecked == true,
                RetentionDays = retention, MaxItems = max,
                ExcludedProcesses = excluded.Text.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries) };
            if (app.ChangeSettings(settings)) Close(); else message.Text = "保存失败，原设置未变更。";
        };
        panel.Children.Add(save); panel.Children.Add(message); Content = panel;
    }
}
