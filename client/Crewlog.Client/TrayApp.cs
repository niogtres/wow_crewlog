using System.Diagnostics;
using System.Reflection;
using Crewlog.Client.Core;
using Crewlog.Client.Core.Server;
using Crewlog.Client.Core.Sync;
using Crewlog.Client.Core.Updates;
using Crewlog.Client.Core.Wow;

namespace Crewlog.Client;

/// <summary>
/// The tray daemon (DESIGN §7): find WoW Forever, watch Crewlog.lua, parse it on every /reload or logout,
/// log new events and upload them to the Crewlog server once this PC is linked, then write acks and journal
/// crew data into the Crewlog_Inbox addon.
/// </summary>
internal sealed class TrayApp : ApplicationContext
{
    private static readonly string Version =
        Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0] ?? "0.0.0";

    private readonly SynchronizationContext _ui;
    private readonly NotifyIcon _tray;
    private readonly ToolStripMenuItem _status;
    private readonly FileLog _log;
    private readonly SyncEngine _engine;
    private readonly AppConfig _config;
    private readonly TokenStore _tokens = new(AppPaths.Token);
    private readonly ToolStripMenuItem _link;
    private readonly ToolStripMenuItem _updateItem = new() { Visible = false, Font = new Font(SystemFonts.MenuFont ?? Control.DefaultFont, FontStyle.Bold) };
    private readonly Updater _updater;
    private readonly System.Windows.Forms.Timer _updateTimer = new() { Interval = 20_000 };
    private readonly System.Windows.Forms.Timer _crewTimer = new() { Interval = 60_000 };
    private readonly Core.Inbox.InboxRefresher _crew;
    private bool _updating;
    private bool _bundledAddonPending;
    private string? _token;
    private bool _linking;
    private SavedVariablesWatcher? _watcher;
    private WowFlavorFolder? _flavor;

    private readonly bool _showStatusOnStart;
    private StatusWindow? _statusWindow;

    public TrayApp(bool showStatus, EventWaitHandle showRequests)
    {
        _showStatusOnStart = showStatus;
        // Work posted from background threads (sync results, a second start asking to show the status window) must
        // run on this UI thread. Whatever context happens to be current here may be a plain thread-pool one, so
        // install WinForms' own explicitly.
        _ui = new WindowsFormsSynchronizationContext();
        SynchronizationContext.SetSynchronizationContext(_ui);
        _log = new FileLog(AppPaths.Logs);
        _config = AppConfig.Load(AppPaths.Config);
        _token = _tokens.Load();
        _engine = new SyncEngine(new SyncStateStore(AppPaths.State), _log,
            () => _token is null ? null : ServerClient.Create(_config.ServerUrl, _token, InstalledAddon()));
        _link = new ToolStripMenuItem("", null, (_, _) => LinkOrUnlink());
        _updater = new Updater(new HttpClient { Timeout = TimeSpan.FromMinutes(5) }, _log);
        Updater.CleanupAfterUpdate(Environment.ProcessPath);
        AppInstall.CleanUpLegacyCopy(_config, _log);
        _updateItem.Click += (_, _) => { if (_bundledAddonPending) InstallBundledAddon(); };
        _updateTimer.Tick += async (_, _) =>
        {
            _updateTimer.Interval = (int)TimeSpan.FromMinutes(30).TotalMilliseconds; // first check soon after start, then every 30 min
            await CheckForUpdates(manual: false);
        };
        _updateTimer.Start();

        // Crew data for the in-game view, between your own syncs: every 2 min while WoW runs, else every 15 min.
        _crew = new Core.Inbox.InboxRefresher(_log, () => _token is null ? null : ServerClient.Create(_config.ServerUrl, _token, InstalledAddon()));
        _crewTimer.Tick += (_, _) =>
        {
            if (_flavor is not { } flavor || _token is null) return;
            var playing = Core.Inbox.InboxRefresher.WowRunning();
            if (_crew.Due(playing, DateTimeOffset.UtcNow)) _ = Task.Run(() => _crew.RefreshAsync(flavor.Path));
        };
        _crewTimer.Start();
        UpdateLinkItem();

        _status = new ToolStripMenuItem("Starting…") { Enabled = false };
        var notify = new ToolStripMenuItem("Sync notifications") { Checked = _config.ShowSyncNotifications, CheckOnClick = true };
        notify.CheckedChanged += (_, _) => { _config.ShowSyncNotifications = notify.Checked; _config.Save(AppPaths.Config); };

        var menu = new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem($"Crewlog {Version}") { Enabled = false, Font = new Font(SystemFonts.MenuFont ?? Control.DefaultFont, FontStyle.Bold) });
        menu.Items.Add(_status);
        menu.Items.Add("Status…", null, (_, _) => ShowStatus());
        menu.Items.Add(_updateItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_link);
        menu.Items.Add("Open Crewlog website", null, (_, _) => Open(_config.ServerUrl.TrimEnd('/') + "/home"));
        menu.Items.Add("Journals…", null, (_, _) => ShowJournals());
        menu.Items.Add("Sync now", null, (_, _) => SyncNow());
        menu.Items.Add("Open today's log", null, (_, _) => Open(_log.CurrentFile));
        menu.Items.Add("Open log folder", null, (_, _) => Open(AppPaths.Logs));
        menu.Items.Add("Choose WoW folder…", null, (_, _) => ChooseFolder());
        menu.Items.Add("Server address…", null, (_, _) => ChangeServer());
        menu.Items.Add(notify);
        if (AppInstall.IsInstalled)
        {
            var autostart = new ToolStripMenuItem("Start with Windows") { Checked = AppInstall.StartsWithWindows, CheckOnClick = true };
            autostart.CheckedChanged += (_, _) => AppInstall.SetAutostart(autostart.Checked);
            menu.Items.Add(autostart);
        }
        menu.Items.Add("Check for updates", null, async (_, _) => await CheckForUpdates(manual: true));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => ExitThread());

        _tray = new NotifyIcon
        {
            Icon = LoadIcon(),
            Text = $"Crewlog {Version}",
            ContextMenuStrip = menu,
            Visible = true,
        };
        _tray.DoubleClick += (_, _) => ShowStatus();
        // Another start of Crewlog while this one runs: show this one's status window.
        ThreadPool.RegisterWaitForSingleObject(showRequests, (_, _) => _ui.Post(_ => ShowStatus(), null), null, Timeout.Infinite, executeOnlyOnce: false);
        _tray.BalloonTipClicked += (_, _) => { if (_bundledAddonPending) InstallBundledAddon(); };

        _log.Info($"Crewlog client {Version} started ({(AppInstall.IsInstalled ? "installed" : "portable")})");
        AnnounceUpdate();
        if (AppInstall.IsInstalled) AppInstall.RefreshAutostartEntry();
        StartWatching(_config.ResolveFlavor(), announce: false);
        if (_showStatusOnStart) _ui.Post(_ => ShowStatus(), null);
    }

    /// <summary>The status window: running, where to find it, what's left to do. One at a time.</summary>
    private void ShowStatus()
    {
        if (_statusWindow is { IsDisposed: false })
        {
            _statusWindow.Refresh();
            if (_statusWindow.WindowState == FormWindowState.Minimized) _statusWindow.WindowState = FormWindowState.Normal;
            _statusWindow.Activate();
            return;
        }
        _statusWindow = new StatusWindow(CurrentStatus, ChooseFolder, InstallBundledAddon, LinkOrUnlink,
            () => Open(_config.ServerUrl.TrimEnd('/') + "/home"), AppInstall.SetAutostart, WindowIcon());
        _statusWindow.Show();
    }

    private AppStatus CurrentStatus() => new(
        Version,
        _flavor?.Path,
        _flavor is { } f ? Updater.InstalledAddonVersion(f) : null,
        _bundledAddonPending,
        _token is null ? null : _config.LinkedAs ?? "you",
        _status.Text ?? "",
        AppInstall.IsInstalled,
        AppInstall.IsInstalled && AppInstall.StartsWithWindows,
        AppInstall.FirstRun);

    // The tray gets its own simplified compass (docs/brand/icons/crewlog-tray.ico), loaded at the exact size the
    // taskbar uses (16 px at 100 %, 20 at 125 %, …): the detailed emblem scaled down turns into a blur.
    /// <summary>Title bars and the taskbar button of Crewlog's windows: the full emblem.</summary>
    private static Icon? WindowIcon()
    {
        using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("crewlog.ico");
        return s is null ? null : new Icon(s);
    }

    private static Icon LoadIcon()
    {
        using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("tray.ico");
        return s is null ? SystemIcons.Application : new Icon(s, SystemInformation.SmallIconSize);
    }

    private void StartWatching(WowFlavorFolder? flavor, bool announce)
    {
        _watcher?.Dispose();
        _watcher = null;
        _flavor = flavor;

        if (flavor is null)
        {
            SetStatus("WoW Forever not found");
            _log.Warn("No WoW install found. Choose the folder from the tray menu.");
            _tray.ShowBalloonTip(8000, "Crewlog", "Couldn't find WoW Forever. Right-click the tray icon → Choose WoW folder…", ToolTipIcon.Warning);
            return;
        }

        _watcher = new SavedVariablesWatcher(flavor);
        _watcher.Changed += file => ThreadPool.QueueUserWorkItem(_ => HandleChange(file));
        _watcher.Start();
        _log.Info($"Watching {_watcher.WtfAccountPath}");
        OfferBundledAddonIfMissing();
        SetStatus($"Watching {flavor.Name} · waiting for /reload");
        if (announce) _tray.ShowBalloonTip(4000, "Crewlog", $"Watching {flavor.Path}", ToolTipIcon.Info);
        _watcher.RescanAll();
    }

    private void HandleChange(string file)
    {
        SyncResult result;
        try
        {
            result = _engine.ProcessAsync(file).GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            _log.Error("Sync failed", ex);
            _ui.Post(_ => SetStatus("Sync failed · see log"), null);
            return;
        }

        _ui.Post(_ =>
        {
            if (!result.Ok)
            {
                SetStatus("Could not read Crewlog.lua · see log");
                return;
            }
            var where = result.Pushed ? "synced" : _token is null ? "read (not linked)" : "read · upload failed";
            SetStatus($"{char.ToUpper(where[0])}{where[1..]} {DateTime.Now:HH:mm} · {result.NewEvents.Count} new");
            if (result.NewEvents.Count > 0 && _config.ShowSyncNotifications && result.Save is { } save)
            {
                var names = save.Characters.ToDictionary(c => c.Guid, c => c.Name ?? "?");
                var who = string.Join(", ", result.NewEvents.Select(e => names.GetValueOrDefault(e.CharacterGuid, "?")).Distinct());
                _tray.ShowBalloonTip(4000, $"{who} synced", $"{result.NewEvents.Count} new quest event(s) recorded.", ToolTipIcon.Info);
            }
        }, null);
    }

    private void UpdateLinkItem() =>
        _link.Text = _token is null ? "Link with Discord…" : $"Linked as {_config.LinkedAs ?? "you"} · Unlink";

    private async void LinkOrUnlink()
    {
        if (_token is not null)
        {
            if (MessageBox.Show($"Unlink this PC from {_config.LinkedAs}? Quests stay saved on the server.", "Crewlog",
                    MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK) return;
            _tokens.Clear();
            _token = null;
            _config.LinkedAs = null;
            _config.Save(AppPaths.Config);
            UpdateLinkItem();
            _log.Info("Unlinked this PC");
            return;
        }
        if (_linking) return;
        _linking = true;
        try
        {
            var client = ServerClient.Create(_config.ServerUrl);
            var start = await client.StartDeviceLoginAsync(Environment.MachineName);
            _log.Info($"Linking: open {start.VerifyUrl} and confirm code {start.UserCode}");
            _tray.ShowBalloonTip(10000, $"Code {start.UserCode}", "Log in with Discord in your browser and check that it shows this code.", ToolTipIcon.Info);
            Open(start.VerifyUrl);
            var (token, user) = await client.WaitForApprovalAsync(start);
            _tokens.Save(token);
            _token = token;
            _config.LinkedAs = user;
            _config.Save(AppPaths.Config);
            UpdateLinkItem();
            _log.Info($"Linked to {user} on {_config.ServerUrl}");
            _tray.ShowBalloonTip(4000, "Crewlog", $"Linked to {user}. Syncing now.", ToolTipIcon.Info);
            _watcher?.RescanAll();
        }
        catch (Exception ex) when (ex is ServerException or HttpRequestException or TaskCanceledException)
        {
            _log.Warn("Linking failed: " + ex.Message);
            _tray.ShowBalloonTip(6000, "Crewlog", "Linking failed: " + ex.Message, ToolTipIcon.Warning);
        }
        finally
        {
            _linking = false;
        }
    }

    private void ChangeServer()
    {
        using var dlg = new ServerPrompt(_config.ServerUrl);
        if (dlg.ShowDialog() != DialogResult.OK || dlg.Url == _config.ServerUrl) return;
        if (!ServerPrompt.IsValid(dlg.Url))
        {
            MessageBox.Show("That isn't a web address (it should start with https:// or http://).", "Crewlog", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        // A token belongs to one server: changing servers means linking again.
        _config.ServerUrl = dlg.Url;
        _config.LinkedAs = null;
        _config.Save(AppPaths.Config);
        _tokens.Clear();
        _token = null;
        UpdateLinkItem();
        _log.Info($"Server changed to {dlg.Url}; link this PC again");
        _tray.ShowBalloonTip(5000, "Crewlog", $"Server set to {dlg.Url}. Choose Link with Discord… to connect.", ToolTipIcon.Info);
    }

    /// <summary>Fresh install: the addon isn't in WoW yet, so offer the copy bundled in this exe right away (works offline).</summary>
    private void OfferBundledAddonIfMissing()
    {
        if (_flavor is not { } flavor || Updater.InstalledAddonVersion(flavor) is not null) return;
        using var zip = BundledAddon();
        if (zip is null) return;
        var version = Updater.AddonVersionInZip(zip) ?? "?";
        _updateItem.Text = "Install the Crewlog addon…";
        _updateItem.Visible = true;
        _bundledAddonPending = true;
        _tray.ShowBalloonTip(10000, "Install the Crewlog addon",
            $"The addon isn't in WoW Forever yet. Click to install version {version} into {flavor.Name}\\Interface\\AddOns.", ToolTipIcon.Info);
        _log.Info($"Addon not installed in {flavor.AddOnsPath}; offering bundled {version}");
    }

    private static Stream? BundledAddon() => Assembly.GetExecutingAssembly().GetManifestResourceStream("addon.zip");

    private void InstallBundledAddon()
    {
        if (_flavor is not { } flavor) return;
        using var zip = BundledAddon();
        if (zip is null) return;
        try
        {
            _updater.InstallAddonFromZip(zip, flavor);
            _bundledAddonPending = false;
            _updateItem.Visible = false;
            _tray.ShowBalloonTip(8000, "Crewlog addon installed",
                "Restart WoW Forever (or start it) and the addon is ready. Type /cl in-game to check.", ToolTipIcon.Info);
        }
        catch (Exception ex) when (ex is IOException or InvalidDataException or UnauthorizedAccessException)
        {
            _log.Error("Addon install failed", ex);
            MessageBox.Show("Couldn't install the addon:" + Environment.NewLine + ex.Message + Environment.NewLine +
                "If WoW is installed under Program Files, try running Crewlog as administrator once.", "Crewlog", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    /// <summary>
    /// Updates install themselves (DESIGN §7):
    /// - the addon: downloaded and swapped in, a balloon says to /reload (a fresh install still asks first);
    /// - the app (installed through Crewlog-Setup.exe): Velopack downloads the new version (only what changed) and
    ///   restarts into it. Portable development copies don't update.
    /// </summary>
    /// <summary>The addon version installed in WoW's folder (read from its .toc), sent with every call.</summary>
    private string? InstalledAddon() => _flavor is { } f ? Updater.InstalledAddonVersion(f) : null;

    private async Task CheckForUpdates(bool manual)
    {
        if (_updating) return;
        _updating = true;
        try
        {
            await UpdateAddon(manual);
            await UpdateApp(manual);
        }
        finally
        {
            _updating = false;
        }
    }

    private async Task UpdateAddon(bool manual)
    {
        UpdateStatus? status;
        try
        {
            status = await _updater.CheckAsync(_config.ServerUrl, _flavor);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException)
        {
            _log.Warn("Update check failed: " + ex.Message);
            if (manual) MessageBox.Show("Couldn't reach the Crewlog server to check for updates.", "Crewlog", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        // A missing addon is offered (it touches the WoW folder for the first time); an installed one just updates.
        if (status is not { AddonUpdate: true } || status.AddonMissing || _flavor is not { } flavor) return;
        try
        {
            await _updater.InstallAddonAsync(status.Release, flavor);
            _tray.ShowBalloonTip(6000, "Crewlog addon updated",
                $"Addon {status.Release.AddonVersion} is in place. /reload in WoW (or restart it) to load it.", ToolTipIcon.Info);
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException or InvalidDataException or UnauthorizedAccessException or TaskCanceledException)
        {
            _log.Error("Addon update failed", ex);
            if (manual) MessageBox.Show("The addon update failed and nothing was changed:" + Environment.NewLine + ex.Message, "Crewlog", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private async Task UpdateApp(bool manual)
    {
        if (!AppInstall.IsInstalled)
        {
            if (manual) MessageBox.Show($"This is a portable copy of Crewlog {Version}; it doesn't update itself. Get the installer from the website for automatic updates.",
                "Crewlog", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        try
        {
            var mgr = AppInstall.Updates(_config.ServerUrl);
            var update = await mgr.CheckForUpdatesAsync();
            if (update is null)
            {
                if (manual) MessageBox.Show($"Crewlog {Version} is up to date.", "Crewlog", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            var to = update.TargetFullRelease.Version.ToString();
            _log.Info($"Updating Crewlog {Version} → {to}");
            await mgr.DownloadUpdatesAsync(update);
            _config.UpdatedFrom = Version;
            _config.Save(AppPaths.Config);
            _log.Info($"Restarting into {to}");
            mgr.ApplyUpdatesAndRestart(update, ["--autostart"]); // exits this process; the restart stays quiet (just the "updated" balloon)
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException or TaskCanceledException or InvalidOperationException or UnauthorizedAccessException)
        {
            _log.Warn("App update failed, trying again later: " + ex.Message);
            if (manual) MessageBox.Show("The update failed and nothing was changed:" + Environment.NewLine + ex.Message, "Crewlog", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    /// <summary>After an automatic update: say so once.</summary>
    private void AnnounceUpdate()
    {
        if (_config.UpdatedFrom is not { } from || from == Version) return;
        _config.UpdatedFrom = null;
        _config.Save(AppPaths.Config);
        _tray.ShowBalloonTip(5000, $"Crewlog updated to {Version}", "See what's new in the download window on the website.", ToolTipIcon.Info);
    }

    private JournalsWindow? _journals;

    private void ShowJournals()
    {
        if (_token is null)
        {
            MessageBox.Show("Link this PC with Discord first (tray menu → Link with Discord…).", "Crewlog", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        if (_journals is { IsDisposed: false }) { _journals.Activate(); return; }
        _journals = new JournalsWindow(ServerClient.Create(_config.ServerUrl, _token, InstalledAddon()), _config.ServerUrl, WindowIcon());
        _journals.Show();
    }

    private void SyncNow()
    {
        if (_watcher is null) { ChooseFolder(); return; }
        _watcher.RescanAll();
    }

    private void ChooseFolder()
    {
        using var dlg = new FolderBrowserDialog
        {
            Description = "Choose your World of Warcraft folder (or its _forever_ folder)",
            UseDescriptionForTitle = true,
            InitialDirectory = _flavor?.Path ?? Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
        };
        if (dlg.ShowDialog() != DialogResult.OK) return;

        var flavors = WowInstallLocator.FlavorsIn(dlg.SelectedPath).OrderByDescending(f => f.LooksLikeForever).ToList();
        if (flavors.Count == 0)
        {
            MessageBox.Show("That folder doesn't look like a WoW install (no WTF or Interface folder inside).", "Crewlog", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        _config.WowFlavorPath = flavors[0].Path;
        _config.Save(AppPaths.Config);
        StartWatching(flavors[0], announce: true);
    }

    private void SetStatus(string text)
    {
        _status.Text = text;
        // Hover text: name + version, then the status. Windows allows 127 characters.
        var tip = $"Crewlog {Version}\n{text}";
        _tray.Text = tip.Length > 127 ? tip[..127] : tip;
    }

    private void Open(string path)
    {
        try
        {
            if (!File.Exists(path) && !Directory.Exists(path)) _log.Info("(log created)");
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or FileNotFoundException)
        {
            _log.Warn($"Could not open {path}: {ex.Message}");
        }
    }

    protected override void ExitThreadCore()
    {
        _log.Info("Crewlog client stopped");
        _watcher?.Dispose();
        _updateTimer.Dispose();
        _crewTimer.Dispose();
        _tray.Visible = false;
        _tray.Dispose();
        base.ExitThreadCore();
    }
}
