using Microsoft.Win32;

namespace Crewlog.Client;

/// <summary>
/// Windows 11 hides a new tray icon by default, and with the taskbar's "Hidden icon menu" switched off there's no ^
/// to find it under: the app runs with no visible icon. Windows keeps one key per tray icon under
/// HKCU\Control Panel\NotifyIconSettings (what Settings → Taskbar → Other system tray icons edits); IsPromoted = 1
/// shows it by the clock. We only write it when the player asks to.
/// </summary>
internal static class TrayVisibility
{
    private const string Root = @"Control Panel\NotifyIconSettings";

    /// <summary>True when the icon sits by the clock, false when Windows tucks it away, null when Windows has no
    /// entry for it (older Windows, or the icon hasn't registered yet).</summary>
    public static bool? IsShown()
    {
        using var key = FindKey(writable: false);
        return key is null ? null : key.GetValue("IsPromoted") is int v && v == 1;
    }

    /// <summary>Asks Windows to show the icon by the clock. Explorer picks the change up right away.</summary>
    public static bool Show()
    {
        try
        {
            using var key = FindKey(writable: true);
            if (key is null) return false;
            key.SetValue("IsPromoted", 1, RegistryValueKind.DWord);
            return true;
        }
        catch (Exception) { return false; }
    }

    // ExecutablePath is stored either in full or with the known folder as a GUID prefix
    // ("{F1B32785-...}\Crewlog\Crewlog.exe" for LocalAppData), so compare with those prefixes expanded.
    private static RegistryKey? FindKey(bool writable)
    {
        var exe = Environment.ProcessPath;
        if (exe is null) return null;
        try
        {
            using var root = Registry.CurrentUser.OpenSubKey(Root);
            if (root is null) return null;
            foreach (var name in root.GetSubKeyNames())
            {
                var sub = root.OpenSubKey(name, writable);
                if (sub?.GetValue("ExecutablePath") is string path && string.Equals(Expand(path), exe, StringComparison.OrdinalIgnoreCase))
                    return sub;
                sub?.Dispose();
            }
        }
        catch (Exception) { }
        return null;
    }

    private static readonly (string Guid, Environment.SpecialFolder Folder)[] KnownFolders =
    [
        ("{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}", Environment.SpecialFolder.LocalApplicationData),
        ("{3EB685DB-65F9-4CF6-A03A-E3EF65729F3D}", Environment.SpecialFolder.ApplicationData),
        ("{905E63B6-C1BF-494E-B29C-65B732D3D21A}", Environment.SpecialFolder.ProgramFiles),
        ("{7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E}", Environment.SpecialFolder.ProgramFilesX86),
        ("{6D809377-6AF0-444B-8957-A3773F02200E}", Environment.SpecialFolder.ProgramFiles),
        ("{F38BF404-1D43-42F2-9305-67DE0B28FC23}", Environment.SpecialFolder.Windows),
        ("{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}", Environment.SpecialFolder.Desktop),
    ];

    private static string Expand(string path)
    {
        foreach (var (guid, folder) in KnownFolders)
            if (path.StartsWith(guid, StringComparison.OrdinalIgnoreCase))
                return Environment.GetFolderPath(folder) + path[guid.Length..];
        return path;
    }
}
