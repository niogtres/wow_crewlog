using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Crewlog.Client.Core.Server;
using Crewlog.Contracts;

namespace Crewlog.Client.Core.Inbox;

/// <summary>
/// Keeps the in-game crew data fresh between your own syncs (DESIGN §7, sync loop step 5): pulls the journal crew
/// from the server every 2 minutes while WoW is running and every 15 minutes otherwise, and rewrites the Inbox only
/// when something changed. WoW reads it on the next /reload or login. Acks already in the Inbox are kept.
/// </summary>
public sealed class InboxRefresher(ILog log, Func<ServerClient?> server)
{
    public static readonly TimeSpan WhilePlaying = TimeSpan.FromMinutes(2);
    public static readonly TimeSpan Otherwise = TimeSpan.FromMinutes(15);

    private string? _lastHash;
    private DateTimeOffset _lastPull = DateTimeOffset.MinValue;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public bool Due(bool wowRunning, DateTimeOffset now) => now - _lastPull >= (wowRunning ? WhilePlaying : Otherwise);

    /// <summary>Returns true when the Inbox was rewritten with new crew data.</summary>
    public async Task<bool> RefreshAsync(string flavorDir, DateTimeOffset? now = null, CancellationToken ct = default)
    {
        if (!await _gate.WaitAsync(0, ct)) return false; // one pull at a time
        try
        {
            _lastPull = now ?? DateTimeOffset.UtcNow;
            if (server() is not { } client) return false;
            InboxResponse crew;
            try
            {
                crew = await client.InboxAsync(ct);
            }
            catch (Exception ex) when (ex is ServerException or HttpRequestException or TaskCanceledException)
            {
                log.Warn("Crew refresh failed: " + ex.Message);
                return false;
            }

            var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(crew.Journals))));
            if (hash == _lastHash) return false;
            var path = InboxWriter.Write(flavorDir, new SyncResponse(new Dictionary<string, long>(), null, DateTimeOffset.UtcNow, []), crew);
            if (path is null) return false; // the Inbox addon isn't installed
            _lastHash = hash;
            log.Info($"Crew data refreshed ({crew.Journals.Count} journal(s)); /reload in game to see it");
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            log.Warn("Could not write the crew data: " + ex.Message);
            return false;
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>A WoW client is running (Wow.exe, WowClassic.exe, …). Cheap: process names only.</summary>
    public static bool WowRunning()
    {
        foreach (var p in Process.GetProcesses())
        {
            using (p)
                if (p.ProcessName.StartsWith("Wow", StringComparison.OrdinalIgnoreCase)) return true;
        }
        return false;
    }
}
