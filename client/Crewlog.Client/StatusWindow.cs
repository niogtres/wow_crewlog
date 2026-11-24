using System.Reflection;
using Microsoft.Win32;

namespace Crewlog.Client;

/// <summary>What the status window shows; read fresh from the tray app each time it opens or something changes.</summary>
internal sealed record AppStatus(
    string Version,
    string? WowFolder,
    string? AddonVersion,
    bool AddonOffered,
    string? LinkedAs,
    string Watching,
    bool Installed,
    bool StartsWithWindows,
    bool JustInstalled);

/// <summary>
/// The heads-up when Crewlog is started by hand (or after installing): it's running, where to find it, and what's
/// still to do (WoW folder, addon, Discord link), each with a button. Branded, and follows Windows light/dark.
/// </summary>
internal sealed class StatusWindow : Form
{
    private readonly Func<AppStatus> _status;
    private readonly Action _chooseFolder, _installAddon, _link, _openWebsite;
    private readonly Action<bool> _setAutostart;
    private readonly FlowLayoutPanel _rows = new() { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(S(22), S(10), S(22), S(0)) };
    private readonly Label _subtitle = new() { AutoSize = false, Size = new Size(S(410), S(22)), Font = new Font("Segoe UI", 9f) };
    private readonly CheckBox _autostart = new() { Text = "Start with Windows", AutoSize = false, Size = new Size(S(220), S(34)) };
    private readonly bool _dark = IsDarkMode();

    // Sizes are written for 100 % scaling; fonts grow with the display's scaling, so the boxes must too or the text
    // gets clipped (the process is per-monitor DPI aware and WinForms doesn't scale code-built forms by itself).
    private static readonly float DpiScale = ScreenDpi() / 96f;
    private static int S(int px) => (int)Math.Round(px * DpiScale);
    private static float ScreenDpi() { using var g = Graphics.FromHwnd(IntPtr.Zero); return g.DpiX; }
    private Color Bg => _dark ? Color.FromArgb(0x15, 0x22, 0x2A) : Color.White;
    private Color Ink => _dark ? Color.FromArgb(0xE8, 0xEF, 0xEA) : Color.FromArgb(0x17, 0x26, 0x30);
    private Color Muted => _dark ? Color.FromArgb(0x9E, 0xB0, 0xA9) : Color.FromArgb(0x4A, 0x5B, 0x63);
    private static readonly Color Gold = Color.FromArgb(0xE3, 0xA2, 0x1A);
    private static readonly Color Teal = Color.FromArgb(0x2F, 0x96, 0x90);
    private static readonly Color Band = Color.FromArgb(0x07, 0x0E, 0x12);

    public StatusWindow(Func<AppStatus> status, Action chooseFolder, Action installAddon, Action link, Action openWebsite, Action<bool> setAutostart, Icon? icon)
    {
        (_status, _chooseFolder, _installAddon, _link, _openWebsite, _setAutostart) = (status, chooseFolder, installAddon, link, openWebsite, setAutostart);
        Text = "Crewlog";
        Icon = icon;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = true;
        ClientSize = new Size(S(520), S(456));
        Font = new Font("Segoe UI", 10f);
        BackColor = Bg;
        ForeColor = Ink;

        // Header band: emblem + name on the dark band colour of the website.
        var header = new Panel { Dock = DockStyle.Top, Height = S(104), BackColor = Band };
        var emblem = new PictureBox { Size = new Size(S(64), S(64)), Location = new Point(S(22), S(20)), SizeMode = PictureBoxSizeMode.Zoom, BackColor = Band };
        using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("emblem.png"))
            if (s is not null) { using var img = Image.FromStream(s); emblem.Image = new Bitmap(img); } // GDI+ needs its own copy once the stream closes
        var title = new Label { Text = status().JustInstalled ? "Crewlog is installed" : "Crewlog is running", AutoSize = false, Size = new Size(S(400), S(36)), Location = new Point(S(98), S(24)), ForeColor = Color.White, Font = new Font("Segoe UI Semibold", 17f), BackColor = Band };
        _subtitle.Location = new Point(S(100), S(64));
        _subtitle.ForeColor = Color.FromArgb(0xB9, 0xC8, 0xC0);
        _subtitle.BackColor = Band;
        header.Controls.AddRange([emblem, title, _subtitle]);

        var footer = new Panel { Dock = DockStyle.Bottom, Height = S(58), BackColor = Bg, Padding = new Padding(S(22), S(12), S(22), S(12)) };
        var close = Button("Got it", primary: true);
        close.AutoSize = false;
        close.Size = new Size(S(110), S(34));
        close.Dock = DockStyle.Right;
        close.Click += (_, _) => Close();
        _autostart.ForeColor = Ink;
        _autostart.Dock = DockStyle.Left;
        _autostart.CheckedChanged += (_, _) => _setAutostart(_autostart.Checked);
        footer.Controls.AddRange([close, _autostart]);
        AcceptButton = close;
        CancelButton = close;

        Controls.Add(_rows);
        Controls.Add(footer);
        Controls.Add(header);
        Shown += (_, _) => { Refresh(); Activate(); };
        // Right after start Windows may not have registered the tray icon yet; look once more for the hidden-icon row.
        var recheck = new System.Windows.Forms.Timer { Interval = 2500 };
        recheck.Tick += (_, _) => { recheck.Dispose(); if (!IsDisposed) Refresh(); };
        Shown += (_, _) => recheck.Start();
    }

    /// <summary>Re-reads the state; called when opened and after each action.</summary>
    public new void Refresh()
    {
        var s = _status();
        _subtitle.Text = s.JustInstalled
            ? $"Version {s.Version} · look for the compass by the clock (^ shows hidden icons)"
            : $"Version {s.Version} · it lives by the clock (^ shows hidden icons)";
        var trayHidden = TrayVisibility.IsShown() == false;
        _autostart.Visible = s.Installed;
        _autostart.Checked = s.StartsWithWindows;
        _rows.SuspendLayout();
        _rows.Controls.Clear();
        AddRow(s.WowFolder is not null, "WoW Forever", s.WowFolder ?? "Not found yet.", s.WowFolder is null ? ("Choose folder…", _chooseFolder) : null);
        AddRow(s.AddonVersion is not null, "Addon",
            s.AddonVersion is { } v ? $"Version {v} installed. It updates itself." : "Not installed in WoW yet.",
            s.AddonVersion is null && s.WowFolder is not null ? ("Install addon", _installAddon) : null);
        AddRow(s.LinkedAs is not null, "Discord link",
            s.LinkedAs is { } who ? $"Linked as {who}. Your quests sync to the website." : "Link this PC so your quests reach the website.",
            s.LinkedAs is null ? ("Link Discord…", _link) : null);
        AddRow(s.WowFolder is not null, "Syncing", s.WowFolder is null
            ? "Starts once WoW Forever is found."
            : s.Watching + ". In game, click the compass by the minimap to sync any time.", ("Open website", _openWebsite));
        if (trayHidden)
            AddRow(false, "Tray icon", "Windows hid Crewlog's icon. Show it by the clock?", ("Show icon", () => TrayVisibility.Show()));
        _rows.ResumeLayout();
        ClientSize = new Size(S(520), S(104 + 10 + 58 + 12) + _rows.Controls.Count * S(68));
    }

    // Rows use fixed positions: nested auto-sizing layouts in WinForms can loop and freeze the window.
    private void AddRow(bool ok, string title, string detail, (string Label, Action Run)? action)
    {
        var row = new Panel { Width = S(472), Height = S(64), Margin = new Padding(S(0), S(4), S(0), S(0)), BackColor = Bg };
        var mark = new Label { Text = ok ? "✓" : "!", Size = new Size(S(26), S(26)), Location = new Point(S(0), S(12)), TextAlign = ContentAlignment.MiddleCenter,
            Font = new Font("Segoe UI", 11f, FontStyle.Bold), ForeColor = ok ? Color.White : Band, BackColor = ok ? Teal : Gold };
        var textWidth = S(action is null ? 430 : 290);
        var head = new Label { Text = title, AutoSize = false, Size = new Size(textWidth, S(20)), Location = new Point(S(38), S(4)), ForeColor = Ink,
            Font = new Font("Segoe UI Semibold", 10f), UseMnemonic = false };
        var body = new Label { Text = detail, AutoSize = false, Size = new Size(textWidth, S(36)), Location = new Point(S(38), S(24)), ForeColor = Muted,
            Font = new Font("Segoe UI", 9f), UseMnemonic = false, AutoEllipsis = true };
        row.Controls.AddRange([mark, head, body]);
        if (action is { } a)
        {
            var b = Button(a.Label, primary: !ok);
            b.AutoSize = false;
            b.Size = new Size(S(140), S(34));
            b.Location = new Point(row.Width - b.Width, 12);
            b.Click += (_, _) => { a.Run(); Refresh(); };
            row.Controls.Add(b);
        }
        _rows.Controls.Add(row);
    }

    private Button Button(string text, bool primary)
    {
        var b = new Button { Text = text, AutoSize = true, MinimumSize = new Size(0, S(34)), Padding = new Padding(S(10), S(0), S(10), S(0)), FlatStyle = FlatStyle.Flat, Cursor = Cursors.Hand };
        b.FlatAppearance.BorderSize = primary ? 0 : 1;
        b.FlatAppearance.BorderColor = Ink;
        b.BackColor = primary ? Gold : Bg;
        b.ForeColor = primary ? Band : Ink;
        b.Font = new Font("Segoe UI Semibold", 9.5f);
        return b;
    }

    private static bool IsDarkMode()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("AppsUseLightTheme") is int v && v == 0;
    }
}
