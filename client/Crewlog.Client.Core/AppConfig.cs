using System.Text.Json;
using Crewlog.Client.Core.Wow;

namespace Crewlog.Client.Core;

/// <summary>User settings in <c>%LOCALAPPDATA%\Crewlog\config.json</c>.</summary>
public sealed class AppConfig
{
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    /// <summary>The WoW Forever flavor folder, e.g. <c>D:\Games\World of Warcraft\_forever_</c>.</summary>
    public string? WowFlavorPath { get; set; }

    public bool ShowSyncNotifications { get; set; } = true;

    /// <summary>Crewlog server; the public instance unless overridden (local testing: http://localhost:5180).</summary>
    public string ServerUrl { get; set; } = DefaultServerUrl;

    /// <summary>Display name of the linked account, for the tray menu.</summary>
    public string? LinkedAs { get; set; }

    /// <summary>Last time a portable copy tried to move to the installed app (once a day at most).</summary>
    public DateTimeOffset? InstallerAttemptAt { get; set; }

    /// <summary>The portable exe the installed app replaced; the installed app deletes it on start.</summary>
    public string? LegacyExePath { get; set; }

    /// <summary>Set just before an automatic update restarts the app, so the new version can say it was updated.</summary>
    public string? UpdatedFrom { get; set; }

    public const string DefaultServerUrl = "https://crewlog.dk";

    public static AppConfig Load(string path)
    {
        try
        {
            if (File.Exists(path) && JsonSerializer.Deserialize<AppConfig>(File.ReadAllText(path), Json) is { } config) return config;
        }
        catch (JsonException) { }
        return new AppConfig();
    }

    public void Save(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(this, Json));
    }

    /// <summary>The configured flavor folder if it still exists, otherwise the best auto-detected one.</summary>
    public WowFlavorFolder? ResolveFlavor()
    {
        if (!string.IsNullOrWhiteSpace(WowFlavorPath))
        {
            var configured = WowInstallLocator.FlavorsIn(WowFlavorPath).FirstOrDefault();
            if (configured is not null) return configured;
        }
        return WowInstallLocator.FindAll().FirstOrDefault();
    }
}
