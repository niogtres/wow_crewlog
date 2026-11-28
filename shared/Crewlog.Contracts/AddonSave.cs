namespace Crewlog.Contracts;

/// <summary>Schema versions shared by the addon, client and server (DESIGN §10).</summary>
public static class SchemaVersions
{
    /// <summary><c>CrewlogDB.schema</c> the addon writes.</summary>
    public const int SavedVariables = 1;

    /// <summary><c>Crewlog_Inbox.schema</c> the client writes.</summary>
    public const int Inbox = 1;
}

/// <summary>Everything one <c>Crewlog.lua</c> SavedVariables file holds, as read by the client.</summary>
public sealed record AddonSave(
    int Schema,
    string InstallId,
    string? AddonVersion,
    IReadOnlyList<CharacterSnapshot> Characters,
    IReadOnlyList<QuestEvent> Events,
    IReadOnlyList<HarvestedQuest> Harvest,
    long DroppedEvents,
    IReadOnlyList<RelayedSnapshot>? Relayed = null);

/// <summary>
/// A party member's live snapshot that this PC's addon kept for relaying (addon 0.9.0+, "Upload my party's progress";
/// DESIGN §5.4 Party relay). Signed is the text the member's own addon signed:
/// <c>1|guid|unixTime|level|uiMap|x|y|id,ready,have/need:have/need;...|turnedIn,turnedIn</c> (x and y 0–1000, 0 when
/// unknown); Signature is the first 32 hex digits of HMAC-SHA256 over it with that toon's relay key, which only its
/// owner's PC and the server know. The server checks the signature, so a relaying PC can't change what it carries.
/// </summary>
public sealed record RelayedSnapshot(string Guid, string Signed, string Signature, string? Name, DateTimeOffset? KeptAt);

/// <summary>A character's current state. Identity is the player GUID (Forever returns an empty realm name).
/// Pos* (addon 0.8.6+): where the toon stood when the game last saved, zone map id and 0–100 coordinates.
/// Sex (addon 0.8.14+): the game's UnitSex, 2 male and 3 female, for the toon's portrait.</summary>
public sealed record CharacterSnapshot(
    string Guid,
    string? Name,
    int? RealmId,
    string? Class,
    string? Race,
    int? ClassId,
    int? RaceId,
    string? Faction,
    int? Level,
    int? MapId,
    DateTimeOffset? LastSeen,
    long Seq,
    IReadOnlyList<int> Completed,
    string? CompletedHash,
    IReadOnlyList<LogQuest> Log,
    int? PosMapId = null,
    double? PosX = null,
    double? PosY = null,
    int? Sex = null);

public sealed record LogQuest(int QuestId, string? Title, int? Level, IReadOnlyList<ObjectiveState> Objectives);

/// <summary>One objective as the game shows it; Text is the label without the counter ("Mottled Boar slain"), from addon 0.2.2.</summary>
public sealed record ObjectiveState(int Have, int Need, bool Finished, string? Text = null);

public enum QuestEventKind
{
    Unknown = 0,
    Accept,
    TurnIn,
    Abandon,
    Progress,
    Level,
    Zone,
}

/// <summary>One entry of the append-only event log. <c>(CharacterGuid, Seq)</c> is the idempotency key end to end.</summary>
public sealed record QuestEvent(
    string CharacterGuid,
    long Seq,
    DateTimeOffset At,
    QuestEventKind Kind,
    string RawKind,
    int? QuestId = null,
    int? Objective = null,
    int? Have = null,
    int? Need = null,
    bool? Finished = null,
    int? Xp = null,
    int? Level = null,
    int? MapId = null);

/// <summary>Where a quest starts or ends: exactly one of NPC, object or item, plus the player's position when seen.</summary>
public sealed record QuestSource(int? NpcId, int? ObjectId, int? ItemId, int? MapId, double? X, double? Y);

/// <summary>Quest facts observed in-game that may be missing from QuestieDB (DESIGN §8.4).</summary>
public sealed record HarvestedQuest(
    int QuestId,
    DateTimeOffset At,
    string? Title,
    string? ObjectiveText,
    int? Level,
    int? SuggestedGroup,
    bool? Scaling,
    QuestSource? Giver,
    QuestSource? Ender,
    int? After);
