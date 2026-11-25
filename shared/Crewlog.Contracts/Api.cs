namespace Crewlog.Contracts;

/// <summary>Routes and JSON shapes of the client ↔ server API (DESIGN §8.2). Version 1 only grows additively.</summary>
public static class ApiRoutes
{
    public const string DeviceStart = "/api/v1/auth/device/start";
    public const string DevicePoll = "/api/v1/auth/device/poll";
    public const string Sync = "/api/v1/sync";
    public const string Me = "/api/v1/me";
    public const string LinkPage = "/link";
    public const string ClientLatest = "/api/v1/client/latest";
    public const string Downloads = "/downloads";
    public const string Journals = "/api/v1/journals";
    /// <summary>PUT attaches, DELETE detaches: /api/v1/journals/{journalId}/characters/{characterGuid}</summary>
    public const string JournalCharacter = "/api/v1/journals/{journalId:guid}/characters/{characterGuid}";
    public const string Inbox = "/api/v1/inbox";

    public static string JournalCharacterPath(Guid journalId, string characterGuid) =>
        $"/api/v1/journals/{journalId}/characters/{Uri.EscapeDataString(characterGuid)}";
}

public sealed record DeviceStartRequest(string DeviceName);

public sealed record DeviceStartResponse(string DeviceCode, string UserCode, string VerifyUrl, int IntervalSeconds, int ExpiresInSeconds);

public sealed record DevicePollRequest(string DeviceCode);

/// <summary>Status: "pending", "approved" (Token set), "expired" or "denied".</summary>
public sealed record DevicePollResponse(string Status, string? Token = null, string? UserName = null);

/// <summary>The client uploads the whole parsed SavedVariables file; the server is idempotent on (character, seq).</summary>
public sealed record SyncRequest(AddonSave Save, string ClientVersion);

/// <summary>
/// Ack: per character, the highest event seq the server has stored. HarvestAck: unix time of the newest
/// harvest entry stored. Both go into the Inbox (M3) so the addon can prune.
/// </summary>
public sealed record SyncResponse(
    IReadOnlyDictionary<string, long> Ack,
    long? HarvestAck,
    DateTimeOffset ServerTime,
    IReadOnlyList<string> Warnings);

public sealed record MeResponse(string UserName, string? AvatarUrl, IReadOnlyList<string> Characters);

/// <summary>
/// The newest client and addon the server offers (DESIGN §7). Hashes are lowercase hex SHA-256. ClientUrl is the
/// portable exe (for copies from before the installer); SetupUrl the installer. Installed apps update through
/// Velopack from {server}/updates instead.
/// </summary>
public sealed record ReleaseInfo(
    string ClientVersion,
    string ClientUrl,
    string ClientSha256,
    string AddonVersion,
    string AddonUrl,
    string AddonSha256,
    DateTimeOffset PublishedAt,
    string? Notes,
    string? SetupUrl = null);

/// <summary>The caller's toons and journals, for the client's Characters window (toons × journals checklist).</summary>
public sealed record JournalsResponse(IReadOnlyList<ToonInfo> Toons, IReadOnlyList<JournalInfo> Journals);

public sealed record ToonInfo(string Guid, string Name, int? Level, string? Class);

public sealed record JournalInfo(Guid Id, string Title, string OwnerName, bool IsOwner, IReadOnlyList<string> Attached, string Url);

/// <summary>
/// What the client writes into the Crewlog_Inbox addon (DESIGN §5): acks so the addon can prune, plus the journal
/// crew's current quests for the in-game crew view.
/// </summary>
public sealed record InboxResponse(DateTimeOffset GeneratedAt, IReadOnlyList<InboxJournal> Journals, IReadOnlyList<InboxNext>? Next = null,
    IReadOnlyList<InboxToonRoute>? Routes = null);

/// <summary>A toon's own route ("Just me" in game): its quests and pick-ups, the website's toon page map.</summary>
public sealed record InboxToonRoute(string Guid, InboxRoute Route);

/// <summary>"Next up" for one of your toons in one zone (the addon shows the zone you're in).</summary>
public sealed record InboxNext(string Guid, int AreaId, int? UiMapId, string Zone, IReadOnlyList<InboxSuggestion> Quests);

/// <summary>Soon = opens within two levels. Why = the reasons, e.g. "unlocks 2 more · 3 quests nearby".</summary>
public sealed record InboxSuggestion(int Id, string Title, int Level, bool Soon, string Why, string? Giver);

/// <summary>A quest two or more toons in the journal can pick up now.</summary>
public sealed record InboxPick(int Id, string Title, int Level, string Who, string? Giver);

public sealed record InboxJournal(string Title, IReadOnlyList<InboxToon> Toons, IReadOnlyList<InboxPick>? Together = null, InboxRoute? Route = null);

/// <summary>The journal's suggested route (the website's route map) for the in-game world map: stops in one zone.</summary>
public sealed record InboxRoute(int UiMapId, string Zone, IReadOnlyList<InboxStop> Stops);

/// <summary>A route stop: number, zone coordinates (0–100), the place, and what to do there (one line per task).
/// A stop in a capital beyond the zone's map edge also carries the city's map and its coordinates there.</summary>
public sealed record InboxStop(int N, double X, double Y, string Place, IReadOnlyList<string> Tasks,
    int? CityMap = null, double? CityX = null, double? CityY = null);

public sealed record InboxToon(string Guid, string Name, string OwnerName, int? Level, string? Class, string? Zone, bool Mine,
    IReadOnlyList<InboxQuest> Quests, DateTimeOffset UpdatedAt, IReadOnlyList<int>? Done = null);

/// <summary>Done/Total count finished objectives.</summary>
public sealed record InboxQuest(int Id, string Title, int Done, int Total, bool Ready);
