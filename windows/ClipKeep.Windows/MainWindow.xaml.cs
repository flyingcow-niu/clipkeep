using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using ClipKeep.Core;

namespace ClipKeep.Windows;

internal sealed class CardView(ClipRecord record) : INotifyPropertyChanged
{
    public ClipRecord Record { get; } = record;
    public string KindLabel => Record.Kind switch { "image" => "图片", "files" => "文件", _ => Record.Html is not null || Record.Rtf is not null ? "富文本" : "文本" };
    public string Star => Record.Favorite ? "★" : "";
    private string badge = "";
    public string Badge { get => badge; set { if (badge == value) return; badge = value; PropertyChanged?.Invoke(this, new(nameof(Badge))); } }
    private BitmapImage? thumbnail;
    public BitmapImage? Thumbnail
    {
        get
        {
            if (thumbnail is not null || Record.ImagePng is null) return thumbnail;
            try
            {
                using var stream = new MemoryStream(Record.ImagePng);
                var image = new BitmapImage(); image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad;
                image.DecodePixelWidth = 320; image.StreamSource = stream; image.EndInit(); image.Freeze();
                return thumbnail = image;
            }
            catch (Exception ex) when (ex is IOException or NotSupportedException or ArgumentException) { return null; }
        }
    }
    public event PropertyChangedEventHandler? PropertyChanged;
}

public partial class MainWindow : Window
{
    private readonly App owner;
    private bool allowClose;
    internal IntPtr PreviousWindow { get; private set; }
    internal MainWindow(App owner)
    {
        this.owner = owner;
        InitializeComponent();
        Closing += (_, e) => { if (!allowClose) { e.Cancel = true; Hide(); } };
    }
    internal void CloseForExit() { allowClose = true; Close(); }
    internal void Toggle()
    {
        if (IsVisible) { Dismiss(true); return; }
        PreviousWindow = Native.GetForegroundWindow();
        SearchBox.Clear(); FavoritesOnly.IsChecked = false;
        var work = SystemParameters.WorkArea;
        Width = Math.Min(1120, work.Width); Height = Math.Min(370, work.Height);
        Left = work.Left + (work.Width - Width) / 2; Top = work.Bottom - Height;
        Refresh(); Show(); Activate(); SearchBox.Focus();
        Dispatcher.BeginInvoke(UpdateBadges, DispatcherPriority.Loaded);
    }
    internal void Dismiss(bool restoreFocus)
    {
        Hide();
        if (restoreFocus && PreviousWindow != IntPtr.Zero) Native.SetForegroundWindow(PreviousWindow);
    }
    internal void Refresh()
    {
        if (Cards is null) return;
        var selected = (Cards.SelectedItem as CardView)?.Record.Id;
        Cards.ItemsSource = History.Search(owner.State.Items, SearchBox.Text, FavoritesOnly.IsChecked == true)
            .Select(item => new CardView(item)).ToList();
        Cards.SelectedItem = Cards.Items.Cast<CardView>().FirstOrDefault(x => x.Record.Id == selected)
            ?? Cards.Items.Cast<CardView>().FirstOrDefault();
        CountLabel.Text = $"{Cards.Items.Count} 条";
        if (Cards.Items.Count == 0) StatusLabel.Text = SearchBox.Text.Length > 0 ? "没有匹配的记录" : "复制一些内容开始使用";
        Dispatcher.BeginInvoke(UpdateBadges, DispatcherPriority.Loaded);
    }
    internal void Status(string text) => StatusLabel.Text = text;
    private void SearchChanged(object sender, TextChangedEventArgs e) => Refresh();
    private void FilterChanged(object sender, RoutedEventArgs e) => Refresh();
    private void OpenSettings(object sender, RoutedEventArgs e) => owner.OpenSettings();
    private void OnDeactivated(object? sender, EventArgs e) => Hide();
    private void CardsScrolled(object sender, ScrollChangedEventArgs e) => UpdateBadges();
    private void SelectionChanged(object sender, SelectionChangedEventArgs e) { StatusLabel.Text = ""; }
    private void DoubleClickCard(object sender, MouseButtonEventArgs e)
    { if (Cards.SelectedItem is CardView card) owner.Copy(card.Record, paste: true, plain: false); }

    private void UpdateBadges()
    {
        var number = 0;
        foreach (CardView card in Cards.Items)
        {
            card.Badge = "";
            if (Cards.ItemContainerGenerator.ContainerFromItem(card) is not ListBoxItem container || !container.IsVisible) continue;
            var point = container.TranslatePoint(new Point(), Cards);
            if (point.X >= 0 && point.X + container.ActualWidth <= Cards.ActualWidth + 1 && number < 9)
                card.Badge = "Ctrl+" + (++number);
        }
    }
    private void HandleKey(object sender, KeyEventArgs e)
    {
        var control = Keyboard.Modifiers == ModifierKeys.Control;
        var card = Cards.SelectedItem as CardView;
        if (control && e.Key == Key.C)
        {
            if (Keyboard.FocusedElement is TextBox box && box.SelectionLength > 0) return;
            if (card is not null) owner.Copy(card.Record, paste: false, plain: false);
        }
        else if (e.Key == Key.Escape) Dismiss(true);
        else if (e.Key is Key.Left or Key.Right && Keyboard.Modifiers == ModifierKeys.None)
        {
            if (Cards.Items.Count > 0)
            {
                Cards.SelectedIndex = Math.Clamp(Cards.SelectedIndex + (e.Key == Key.Right ? 1 : -1), 0, Cards.Items.Count - 1);
                Cards.ScrollIntoView(Cards.SelectedItem);
            }
        }
        else if (e.Key == Key.Enter && card is not null)
            owner.Copy(card.Record, paste: true, plain: Keyboard.Modifiers.HasFlag(ModifierKeys.Shift));
        else if (control && e.Key == Key.D && card is not null) owner.Favorite(card.Record);
        else if (control && e.Key == Key.Delete && card is not null) owner.Delete(card.Record);
        else if (control && e.Key >= Key.D1 && e.Key <= Key.D9)
        {
            var badge = "Ctrl+" + ((int)e.Key - (int)Key.D1 + 1);
            var target = Cards.Items.Cast<CardView>().FirstOrDefault(x => x.Badge == badge);
            if (target is not null) owner.Copy(target.Record, paste: true, plain: false);
        }
        else return;
        e.Handled = true;
    }
}
