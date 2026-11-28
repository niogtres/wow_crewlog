using Crewlog.Client.Core.Lua;
using Crewlog.Client.Core.SavedVariables;
using Crewlog.Client.Core.Server;
using Crewlog.Contracts;

namespace Crewlog.Client.Core.Sync;

public sealed record SyncResult(
    string File,
    AddonSave? Save,
    IReadOnlyList<QuestEvent> NewEvents,
    string? Error,
    SyncResponse? Server = null,
    string? PushError = null,
    string? InboxPath = null)
{
    public bool Ok => Error is null;
    public bool Pushed => Server is not null;
}

/// <summary>
/// One sync pass for one SavedVariables file: parse, log what's new, and (when linked) upload to the server.
/// The upload is the whole save every time; the server dedupes on (character, seq). After an upload the server's
/// acks and the journal crew's quests go into the Crewlog_Inbox addon.
/// </summary>
public sealed class SyncEngine(SyncStateStore store, ILog log, Func<ServerClient?>? server = null)
{
    public static readonly string ClientVersion = typeof(SyncEngine).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";
    private readonly SemaphoreSlim _gate = new(1, 1);

    public SyncResult Process(string file) => ProcessAsync(file).GetAwaiter().GetResult();

    public async Task<SyncResult> ProcessAsync(string file, CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            AddonSave save;
            try
            {
                save = ReadWithRetry(file);
            }
            catch (Exception ex) when (ex is LuaParseException or SaveFormatException or IOException or UnauthorizedAccessException)
            {
                log.Warn($"Could not read {file}: {ex.Message}");
                return new SyncResult(file, null, [], ex.Message);
            }

            var state = store.Load();
            var fresh = new List<QuestEvent>();
            foreach (var group in save.Events.GroupBy(e => e.CharacterGuid))
            {
                var last = state.Get(save.InstallId, group.Key);
                var news = group.Where(e => e.Seq > last).OrderBy(e => e.Seq).ToList();
                if (news.Count == 0) continue;
                fresh.AddRange(news);
                state.Set(save.InstallId, group.Key, news[^1].Seq);
            }

            var names = save.Characters.ToDictionary(c => c.Guid, c => c.Name ?? c.Guid, StringComparer.Ordinal);
            log.Info($"Read {Path.GetFileName(Path.GetDirectoryName(Path.GetDirectoryName(file)))}: " +
                     $"{save.Characters.Count} toon(s), {save.Events.Count} pending event(s), {save.Harvest.Count} harvested quest(s), {fresh.Count} new");
            foreach (var c in save.Characters)
                log.Info($"  {c.Name} lvl {c.Level} {c.Race} {c.Class} · map {c.MapId} · {c.Completed.Count} completed · {c.Log.Count} in log · seq {c.Seq}");
            foreach (var e in fresh)
                log.Info($"  + {names.GetValueOrDefault(e.CharacterGuid, e.CharacterGuid)} {EventText.Describe(e)}");
            if (save.Relayed is { Count: > 0 } relayed)
                log.Info($"  carrying party progress for {string.Join(", ", relayed.Select(r => r.Name ?? r.Guid))}");
            if (save.DroppedEvents > 0)
                log.Warn($"  the addon dropped {save.DroppedEvents} old event(s) because the client was away too long");

            if (fresh.Count > 0) store.Save(state);

            if (server?.Invoke() is not { } client) return new SyncResult(file, save, fresh, null);
            try
            {
                var resp = await client.SyncAsync(save, ClientVersion, ct);
                foreach (var w in resp.Warnings) log.Warn("  server: " + w);
                if (resp.Relayed > 0) log.Info($"  the website took party progress for {resp.Relayed} crewmate(s)");
                log.Info($"  uploaded · server has events up to {string.Join(", ", resp.Ack.Select(a => $"{names.GetValueOrDefault(a.Key, a.Key)} #{a.Value}"))}");
                return new SyncResult(file, save, fresh, null, resp, InboxPath: await WriteInbox(file, client, resp, ct));
            }
            catch (Exception ex) when (ex is ServerException or HttpRequestException or TaskCanceledException)
            {
                // Nothing is lost: the addon keeps every event until the server's ack reaches it (M3 Inbox).
                log.Warn($"  upload failed, will retry on the next sync: {ex.Message}");
                return new SyncResult(file, save, fresh, null, null, ex.Message);
            }
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>Acks + journal crew into the Inbox addon; the game picks it up on the next /reload.</summary>
    private async Task<string?> WriteInbox(string file, ServerClient client, SyncResponse resp, CancellationToken ct)
    {
        if (Inbox.InboxWriter.FlavorDirFromSaveFile(file) is not { } flavor) return null;
        InboxResponse? crew = null;
        try { crew = await client.InboxAsync(ct); }
        catch (Exception ex) when (ex is ServerException or HttpRequestException or TaskCanceledException)
        {
            log.Warn($"  journal data not fetched: {ex.Message}");
        }
        try
        {
            var path = Inbox.InboxWriter.Write(flavor, resp, crew);
            if (path is null) log.Warn("  the Crewlog_Inbox addon is missing; reinstall the addon from the tray menu");
            else log.Info($"  inbox written ({crew?.Journals.Count ?? 0} journal(s))");
            return path;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            log.Warn($"  could not write the inbox: {ex.Message}");
            return null;
        }
    }

    // WoW may still be writing: retry a parse failure a few times before giving up.
    private static AddonSave ReadWithRetry(string file)
    {
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                return CrewlogSaveReader.ReadFile(file);
            }
            catch (Exception ex) when (attempt < 4 && ex is LuaParseException or IOException)
            {
                Thread.Sleep(250 * attempt);
            }
        }
    }
}

public static class EventText
{
    public static string Describe(QuestEvent e) => e.Kind switch
    {
        QuestEventKind.Accept => $"accepted quest {e.QuestId}",
        QuestEventKind.TurnIn => $"turned in quest {e.QuestId}" + (e.Xp is { } xp ? $" (+{xp} xp)" : ""),
        QuestEventKind.Abandon => $"abandoned quest {e.QuestId}",
        QuestEventKind.Progress => $"quest {e.QuestId} objective {e.Objective}: {e.Have}/{e.Need}" + (e.Finished == true ? " ✓" : ""),
        QuestEventKind.Level => $"reached level {e.Level}",
        QuestEventKind.Zone => $"entered map {e.MapId}",
        _ => e.RawKind,
    } + $" · #{e.Seq} @ {e.At.ToLocalTime():yyyy-MM-dd HH:mm:ss}";
}
