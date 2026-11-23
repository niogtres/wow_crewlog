using System.IO.Compression;
using System.Net.Http.Json;
using System.Security.Cryptography;
using Crewlog.Client.Core.Server;
using Crewlog.Client.Core.Wow;
using Crewlog.Contracts;

namespace Crewlog.Client.Core.Updates;

public sealed record UpdateStatus(
    ReleaseInfo Release,
    string ClientInstalled,
    string? AddonInstalled,
    bool ClientUpdate,
    bool AddonUpdate)
{
    public bool AddonMissing => AddonInstalled is null;
    public bool Any => ClientUpdate || AddonUpdate;
}

/// <summary>
/// Self-update for the tray client and the addon (DESIGN §7). Everything is downloaded from the configured
/// Crewlog server and checked against the SHA-256 in its release manifest before it is used.
/// </summary>
public sealed class Updater(HttpClient http, ILog log)
{
    public static readonly string[] AddonFolders = ["Crewlog", "Crewlog_Inbox"];

    public static string ClientVersion => typeof(Updater).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";

    public async Task<UpdateStatus?> CheckAsync(string serverUrl, WowFlavorFolder? flavor, CancellationToken ct = default)
    {
        using var resp = await http.GetAsync(serverUrl.TrimEnd('/') + ApiRoutes.ClientLatest, ct);
        if (!resp.IsSuccessStatusCode) return null; // server without a published release
        var release = (await resp.Content.ReadFromJsonAsync<ReleaseInfo>(ServerClient.Json, ct))!;
        var addon = flavor is null ? null : InstalledAddonVersion(flavor);
        return new UpdateStatus(release, ClientVersion, addon,
            IsNewer(release.ClientVersion, ClientVersion),
            flavor is not null && (addon is null || IsNewer(release.AddonVersion, addon)));
    }

    /// <summary>## Version from Interface\AddOns\Crewlog\Crewlog.toc, or null when the addon isn't installed.</summary>
    public static string? InstalledAddonVersion(WowFlavorFolder flavor)
    {
        var toc = Path.Combine(flavor.AddOnsPath, "Crewlog", "Crewlog.toc");
        if (!File.Exists(toc)) return null;
        foreach (var line in File.ReadLines(toc))
            if (line.StartsWith("## Version:", StringComparison.OrdinalIgnoreCase)) return line["## Version:".Length..].Trim();
        return "0.0.0";
    }

    /// <summary>Semantic-ish comparison of "1.2.3" style versions; anything unparsable never counts as newer.</summary>
    public static bool IsNewer(string candidate, string installed) =>
        Version.TryParse(Core(candidate), out var c) && Version.TryParse(Core(installed), out var i) && c > i;

    private static string Core(string v) => v.Split('-', '+')[0].Trim();

    /// <summary>Downloads the addon zip and swaps Crewlog + Crewlog_Inbox into Interface\AddOns.</summary>
    public async Task InstallAddonAsync(ReleaseInfo release, WowFlavorFolder flavor, CancellationToken ct = default)
    {
        var work = Directory.CreateTempSubdirectory("crewlog-addon-");
        try
        {
            var zip = Path.Combine(work.FullName, "addon.zip");
            await DownloadVerifiedAsync(release.AddonUrl, release.AddonSha256, zip, ct);
            var extracted = Path.Combine(work.FullName, "x");
            ZipFile.ExtractToDirectory(zip, extracted);
            InstallFromFolder(extracted, flavor.AddOnsPath);
            log.Info($"Addon {release.AddonVersion} installed in {flavor.AddOnsPath}. Restart WoW or /reload to load it.");
        }
        finally
        {
            try { work.Delete(recursive: true); } catch (IOException) { }
        }
    }

    /// <summary>Installs the addon from a zip already on hand (the copy bundled inside the client exe).</summary>
    public void InstallAddonFromZip(Stream zip, WowFlavorFolder flavor)
    {
        var work = Directory.CreateTempSubdirectory("crewlog-addon-");
        try
        {
            ZipFile.ExtractToDirectory(zip, work.FullName);
            InstallFromFolder(work.FullName, flavor.AddOnsPath);
            log.Info($"Addon {AddonVersionInZip(work.FullName)} installed in {flavor.AddOnsPath}. Restart WoW to load it.");
        }
        finally
        {
            try { work.Delete(recursive: true); } catch (IOException) { }
        }
    }

    /// <summary>## Version of the Crewlog.toc inside an addon zip, without extracting everything.</summary>
    public static string? AddonVersionInZip(Stream zip)
    {
        using var archive = new ZipArchive(zip, ZipArchiveMode.Read, leaveOpen: true);
        var entry = archive.Entries.FirstOrDefault(e => e.FullName.Replace('\\', '/') == "Crewlog/Crewlog.toc");
        if (entry is null) return null;
        using var reader = new StreamReader(entry.Open());
        while (reader.ReadLine() is { } line)
            if (line.StartsWith("## Version:", StringComparison.OrdinalIgnoreCase)) return line["## Version:".Length..].Trim();
        return null;
    }

    private static string AddonVersionInZip(string extractedDir)
    {
        var toc = Path.Combine(extractedDir, "Crewlog", "Crewlog.toc");
        return File.Exists(toc)
            ? File.ReadLines(toc).FirstOrDefault(l => l.StartsWith("## Version:", StringComparison.OrdinalIgnoreCase))?["## Version:".Length..].Trim() ?? "?"
            : "?";
    }

    /// <summary>
    /// Replaces each addon folder from <paramref name="source"/>. The Inbox's Data.lua is written by this client,
    /// so the current one is kept instead of the shipped stub.
    /// </summary>
    public static void InstallFromFolder(string source, string addOnsPath)
    {
        Directory.CreateDirectory(addOnsPath);
        foreach (var name in AddonFolders)
        {
            var from = Path.Combine(source, name);
            if (!Directory.Exists(from)) throw new InvalidDataException($"The addon package has no {name} folder");
        }
        foreach (var name in AddonFolders)
        {
            var from = Path.Combine(source, name);
            var to = Path.Combine(addOnsPath, name);
            string? keepInbox = null;
            if (name == "Crewlog_Inbox" && File.Exists(Path.Combine(to, "Data.lua")))
                keepInbox = File.ReadAllText(Path.Combine(to, "Data.lua"));

            var old = to + ".crewlog-old";
            if (Directory.Exists(old)) Directory.Delete(old, recursive: true);
            if (Directory.Exists(to)) Directory.Move(to, old);
            try
            {
                CopyDirectory(from, to);
                if (keepInbox is not null) File.WriteAllText(Path.Combine(to, "Data.lua"), keepInbox);
                if (Directory.Exists(old)) Directory.Delete(old, recursive: true);
            }
            catch
            {
                // put the previous version back rather than leave a half-installed addon
                if (Directory.Exists(to)) Directory.Delete(to, recursive: true);
                if (Directory.Exists(old)) Directory.Move(old, to);
                throw;
            }
        }
    }

    /// <summary>Downloads the new client exe next to the state folder; returns its path once the hash matches.</summary>
    public async Task<string> StageClientAsync(ReleaseInfo release, CancellationToken ct = default)
    {
        var dir = Path.Combine(AppPaths.Root, "update");
        Directory.CreateDirectory(dir);
        var target = Path.Combine(dir, $"Crewlog-{release.ClientVersion}.exe");
        await DownloadVerifiedAsync(release.ClientUrl, release.ClientSha256, target, ct);
        return target;
    }

    /// <summary>
    /// Swap the running exe for the staged one: Windows lets a running exe be renamed but not overwritten,
    /// so the current file becomes *.old (deleted on next start) and the new one takes its name.
    /// </summary>
    public static string SwapExecutable(string staged, string current)
    {
        var old = current + ".old";
        if (File.Exists(old)) File.Delete(old);
        File.Move(current, old);
        try
        {
            File.Copy(staged, current);
        }
        catch
        {
            File.Move(old, current);
            throw;
        }
        try { File.Delete(staged); } catch (IOException) { }
        return current;
    }

    public static void CleanupAfterUpdate(string? current)
    {
        if (current is null) return;
        try { if (File.Exists(current + ".old")) File.Delete(current + ".old"); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    private async Task DownloadVerifiedAsync(string url, string sha256, string target, CancellationToken ct)
    {
        var tmp = target + ".part";
        using (var resp = await http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct))
        {
            resp.EnsureSuccessStatusCode();
            await using var fs = File.Create(tmp);
            await resp.Content.CopyToAsync(fs, ct);
        }
        string actual;
        await using (var fs = File.OpenRead(tmp)) actual = Convert.ToHexStringLower(await SHA256.HashDataAsync(fs, ct));
        if (!string.Equals(actual, sha256, StringComparison.OrdinalIgnoreCase))
        {
            File.Delete(tmp);
            throw new InvalidDataException($"Download of {Path.GetFileName(url)} failed its checksum; nothing was changed.");
        }
        File.Move(tmp, target, overwrite: true);
    }

    private static void CopyDirectory(string from, string to)
    {
        Directory.CreateDirectory(to);
        foreach (var dir in Directory.EnumerateDirectories(from, "*", SearchOption.AllDirectories))
            Directory.CreateDirectory(Path.Combine(to, Path.GetRelativePath(from, dir)));
        foreach (var file in Directory.EnumerateFiles(from, "*", SearchOption.AllDirectories))
            File.Copy(file, Path.Combine(to, Path.GetRelativePath(from, file)), overwrite: true);
    }
}
