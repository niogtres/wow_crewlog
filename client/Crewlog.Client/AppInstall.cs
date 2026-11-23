using System.Diagnostics;
using Crewlog.Client.Core;
using Microsoft.Win32;
using System.Net.Http.Json;
using Velopack;

namespace Crewlog.Client;

/// <summary>
/// The installed app (DESIGN §7): Crewlog-Setup.exe (Velopack) installs per user into %LOCALAPPDATA%\CrewlogApp
/// with Start menu + desktop shortcuts and an uninstaller, and the app updates itself from {server}/updates.
/// Settings stay in %LOCALAPPDATA%\Crewlog, so uninstalling the app keeps them only if the user wants to reinstall.
/// Copies from before the installer (a portable Crewlog.exe) move themselves over once.
/// </summary>
internal static class AppInstall
{
    public const string PackId = "CrewlogApp";
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValue = "Crewlog";

    /// <summary>Velopack's entry point: handles install/update/uninstall hooks (and exits for them) before the app starts.</summary>
    public static void Bootstrap()
    {
        VelopackApp.Build()
            .OnFirstRun(_ => FirstRun = true)
            .OnAfterInstallFastCallback(_ => SetAutostart(true))
            .OnBeforeUninstallFastCallback(_ => SetAutostart(false))
            .Run();
    }

    /// <summary>True on the first start right after installing.</summary>
    public static bool FirstRun { get; private set; }

    public static UpdateManager Updates(string serverUrl) => new(serverUrl.TrimEnd('/') + "/updates");

    public static bool IsInstalled
    {
        get
        {
            try { return new UpdateManager("https://localhost/").IsInstalled; }
            catch (Exception) { return false; }
        }
    }

    /// <summary>The launcher Velopack keeps at the install root; stays the same across updates.</summary>
    public static string StubPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), PackId, "Crewlog.exe");

    public static bool StartsWithWindows
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(RunValue) is string;
        }
    }

    /// <summary>The Run entry: the stable launcher plus --autostart, so a login start stays quiet.</summary>
    private static string AutostartCommand => $"\"{StubPath}\" --autostart";

    /// <summary>0.6.0 wrote the Run entry without --autostart; bring it up to date.</summary>
    public static void RefreshAutostartEntry()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
        if (key?.GetValue(RunValue) is string v && v != AutostartCommand) key.SetValue(RunValue, AutostartCommand);
    }

    public static void SetAutostart(bool on)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (on) key.SetValue(RunValue, AutostartCommand);
        else key.DeleteValue(RunValue, throwOnMissingValue: false);
    }

    /// <summary>
    /// A portable copy (from before 0.6.0) moves to the installer: download Crewlog-Setup.exe, install silently,
    /// start the installed app, and exit. Runs before the single-instance lock is taken. Returns true when this
    /// process should exit. Tried at most once a day; never for development builds (anything under a bin folder).
    /// </summary>
    public static bool MoveToInstaller(AppConfig config, ILog log)
    {
        var exe = Environment.ProcessPath;
        if (exe is null || IsInstalled) return false;
        if (exe.Contains(@"\bin\", StringComparison.OrdinalIgnoreCase) || Debugger.IsAttached) return false;
        if (config.InstallerAttemptAt is { } last && DateTimeOffset.UtcNow - last < TimeSpan.FromDays(1)) return false;
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
            var latest = http.GetFromJsonAsync<Crewlog.Contracts.ReleaseInfo>(config.ServerUrl.TrimEnd('/') + Crewlog.Contracts.ApiRoutes.ClientLatest)
                .GetAwaiter().GetResult();
            if (latest?.SetupUrl is not { } setupUrl) return false;
            config.InstallerAttemptAt = DateTimeOffset.UtcNow;
            config.LegacyExePath = exe;
            config.Save(AppPaths.Config);

            var setup = Path.Combine(Path.GetTempPath(), "Crewlog-Setup.exe");
            using (var fs = File.Create(setup))
                http.GetStreamAsync(setupUrl).GetAwaiter().GetResult().CopyTo(fs);
            log.Info($"Moving from the portable copy {exe} to the installed app ({setup} --silent)");
            using (var p = Process.Start(new ProcessStartInfo(setup, "--silent") { UseShellExecute = false }))
            {
                if (p is null || !p.WaitForExit(TimeSpan.FromMinutes(5)) || p.ExitCode != 0)
                {
                    log.Warn($"The installer didn't finish (exit {(p is { HasExited: true } ? p.ExitCode : -1)}); staying portable for now");
                    return false;
                }
            }
            // Velopack normally starts the app after installing; start it ourselves if it didn't.
            if (File.Exists(StubPath) && !InstalledAppRunning()) Process.Start(new ProcessStartInfo(StubPath) { UseShellExecute = true });
            return true;
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException or TaskCanceledException
            or System.Text.Json.JsonException or System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            log.Warn("Moving to the installer failed, trying again tomorrow: " + ex.Message);
            return false;
        }
    }

    private static bool InstalledAppRunning()
    {
        var root = Path.GetDirectoryName(StubPath)!;
        foreach (var p in Process.GetProcessesByName("Crewlog"))
        {
            try { if (p.MainModule?.FileName.StartsWith(root, StringComparison.OrdinalIgnoreCase) == true) return true; }
            catch (Exception) { /* another user's process or access denied */ }
            finally { p.Dispose(); }
        }
        return false;
    }

    /// <summary>In the installed app: remove the portable exe this install replaced (and its leftovers).</summary>
    public static void CleanUpLegacyCopy(AppConfig config, ILog log)
    {
        if (!IsInstalled || config.LegacyExePath is not { } old) return;
        foreach (var f in new[] { old, old + ".old" })
        {
            try { if (File.Exists(f)) { File.Delete(f); log.Info($"Removed the old portable copy {f}"); } }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { log.Warn($"Could not remove {f}: {ex.Message}"); return; }
        }
        config.LegacyExePath = null;
        config.Save(AppPaths.Config);
    }
}
