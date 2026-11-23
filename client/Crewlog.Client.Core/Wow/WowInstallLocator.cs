using Microsoft.Win32;

namespace Crewlog.Client.Core.Wow;

/// <summary>A game flavor folder such as <c>…\World of Warcraft\_forever_</c>.</summary>
public sealed record WowFlavorFolder(string Path, string Name, bool LooksLikeForever)
{
    public string AddOnsPath => System.IO.Path.Combine(Path, "Interface", "AddOns");
    public string WtfAccountPath => System.IO.Path.Combine(Path, "WTF", "Account");

    /// <summary><c>WTF\Account\&lt;ACCOUNT&gt;\SavedVariables\&lt;file&gt;</c> for every account folder, existing or not.</summary>
    public IEnumerable<string> SavedVariablesFiles(string fileName)
    {
        if (!Directory.Exists(WtfAccountPath)) yield break;
        foreach (var account in Directory.EnumerateDirectories(WtfAccountPath))
            yield return System.IO.Path.Combine(account, "SavedVariables", fileName);
    }
}

/// <summary>
/// Finds WoW installs (DESIGN §7): registry, Battle.net default folders, then common locations on every fixed drive.
/// Flavor folders are the <c>_name_</c> subfolders that contain <c>WTF</c> or <c>Interface</c>.
/// </summary>
public static class WowInstallLocator
{
    private static readonly string[] CommonRoots =
    [
        "World of Warcraft",
        @"Program Files (x86)\World of Warcraft",
        @"Program Files\World of Warcraft",
        @"Games\World of Warcraft",
        @"Blizzard\World of Warcraft",
        @"Battle.net\World of Warcraft",
    ];

    public static IReadOnlyList<WowFlavorFolder> FindAll()
    {
        var roots = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var r in RegistryRoots()) roots.Add(r);
        foreach (var drive in DriveInfo.GetDrives())
        {
            if (drive.DriveType != DriveType.Fixed || !drive.IsReady) continue;
            foreach (var rel in CommonRoots) roots.Add(Path.Combine(drive.RootDirectory.FullName, rel));
        }
        return roots.Where(Directory.Exists).SelectMany(FlavorsIn)
            .DistinctBy(f => f.Path, StringComparer.OrdinalIgnoreCase)
            .OrderByDescending(f => f.LooksLikeForever).ThenBy(f => f.Path, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    /// <summary>Flavor folders under a WoW root. Also accepts being pointed at a flavor folder directly.</summary>
    public static IEnumerable<WowFlavorFolder> FlavorsIn(string root)
    {
        if (!Directory.Exists(root)) yield break;
        if (IsFlavor(root))
        {
            yield return Make(root);
            yield break;
        }
        foreach (var dir in Directory.EnumerateDirectories(root))
        {
            var name = Path.GetFileName(dir);
            if (name.Length > 2 && name.StartsWith('_') && name.EndsWith('_') && IsFlavor(dir)) yield return Make(dir);
        }
    }

    private static bool IsFlavor(string dir) =>
        Directory.Exists(Path.Combine(dir, "WTF")) || Directory.Exists(Path.Combine(dir, "Interface"));

    private static WowFlavorFolder Make(string dir)
    {
        var name = Path.GetFileName(dir.TrimEnd('\\', '/'));
        return new WowFlavorFolder(dir, name, name.Contains("forever", StringComparison.OrdinalIgnoreCase));
    }

    private static IEnumerable<string> RegistryRoots()
    {
        if (!OperatingSystem.IsWindows()) yield break;
        foreach (var key in new[] { @"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft", @"SOFTWARE\Blizzard Entertainment\World of Warcraft" })
        {
            string? install = null;
            try
            {
                using var k = Registry.LocalMachine.OpenSubKey(key);
                install = k?.GetValue("InstallPath") as string;
            }
            catch (System.Security.SecurityException) { }
            catch (UnauthorizedAccessException) { }
            if (string.IsNullOrWhiteSpace(install)) continue;
            // InstallPath usually points at a flavor folder (…\_retail_\); its parent is the WoW root.
            var trimmed = install.TrimEnd('\\', '/');
            yield return trimmed;
            if (Path.GetDirectoryName(trimmed) is { } parent) yield return parent;
        }
    }
}
