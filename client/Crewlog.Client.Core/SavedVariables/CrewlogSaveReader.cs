using Crewlog.Client.Core.Lua;
using Crewlog.Contracts;

namespace Crewlog.Client.Core.SavedVariables;

public sealed class SaveFormatException(string message) : Exception(message);

/// <summary>Maps the <c>CrewlogDB</c> table (DESIGN §5.3) onto the shared contracts.</summary>
public static class CrewlogSaveReader
{
    public const string GlobalName = "CrewlogDB";

    public static AddonSave ReadFile(string path) => Read(SavedVariablesParser.ParseFile(path));

    public static AddonSave Read(IReadOnlyDictionary<string, LuaValue> globals)
    {
        if (!globals.TryGetValue(GlobalName, out var root) || root.AsTable() is not { } db)
            throw new SaveFormatException($"No {GlobalName} table in file");

        var schema = db["schema"].AsInt() ?? 0;
        if (schema is < 1 or > SchemaVersions.SavedVariables)
            throw new SaveFormatException($"Unsupported {GlobalName} schema {schema} (this client reads up to {SchemaVersions.SavedVariables})");

        var characters = new List<CharacterSnapshot>();
        if (db["chars"].AsTable() is { } chars)
            foreach (var (guid, value) in chars.StringKeyed())
                if (value.AsTable() is { } rec) characters.Add(ReadCharacter(guid, rec));

        var events = new List<QuestEvent>();
        if (db["events"].AsTable() is { } evs)
            foreach (var (_, value) in evs.Pairs())
                if (value.AsTable() is { } ev && ReadEvent(ev) is { } parsed) events.Add(parsed);
        events.Sort((a, b) => a.CharacterGuid == b.CharacterGuid
            ? a.Seq.CompareTo(b.Seq)
            : string.CompareOrdinal(a.CharacterGuid, b.CharacterGuid));

        var harvest = new List<HarvestedQuest>();
        if (db["harvest"].AsTable()?["quests"].AsTable() is { } quests)
            foreach (var (qid, value) in quests.IntKeyed())
                if (value.AsTable() is { } h) harvest.Add(ReadHarvest(qid, h));
        harvest.Sort((a, b) => a.QuestId.CompareTo(b.QuestId));

        var relayed = new List<RelayedSnapshot>();
        if (db["relay"].AsTable() is { } relay)
            foreach (var (guid, value) in relay.StringKeyed())
                if (value.AsTable() is { } r && r["s"].AsString() is { } signed && r["sig"].AsString() is { } sig)
                    relayed.Add(new RelayedSnapshot(guid, signed, sig, r["name"].AsString(), Time(r["at"])));
        relayed.Sort((a, b) => string.CompareOrdinal(a.Guid, b.Guid));

        return new AddonSave(
            schema,
            db["installId"].AsString() ?? "",
            db["addonVersion"].AsString(),
            characters.OrderBy(c => c.Guid, StringComparer.Ordinal).ToList(),
            events,
            harvest,
            db["droppedEvents"].AsLong() ?? 0,
            relayed.Count > 0 ? relayed : null);
    }

    private static CharacterSnapshot ReadCharacter(string guid, LuaTable rec)
    {
        var completed = new List<int>();
        if (rec["completed"].AsTable() is { } c)
            foreach (var (_, v) in c.Pairs())
                if (v.AsInt() is { } id) completed.Add(id);
        completed.Sort();

        var log = new List<LogQuest>();
        if (rec["log"].AsTable() is { } l)
            foreach (var (qid, v) in l.IntKeyed())
                if (v.AsTable() is { } q) log.Add(ReadLogQuest(qid, q));
        log.Sort((a, b) => a.QuestId.CompareTo(b.QuestId));

        return new CharacterSnapshot(
            guid,
            rec["name"].AsString(),
            rec["realmId"].AsInt(),
            rec["class"].AsString(),
            rec["race"].AsString(),
            rec["classId"].AsInt(),
            rec["raceId"].AsInt(),
            rec["faction"].AsString(),
            rec["level"].AsInt(),
            rec["map"].AsInt(),
            Time(rec["lastSeen"]),
            rec["seq"].AsLong() ?? 0,
            completed,
            rec["completedHash"].AsString(),
            log,
            rec["pos"].AsTable()?["map"].AsInt(),
            rec["pos"].AsTable()?["x"].AsNumber(),
            rec["pos"].AsTable()?["y"].AsNumber(),
            rec["sex"].AsInt());
    }

    private static LogQuest ReadLogQuest(int qid, LuaTable q)
    {
        var objectives = new List<ObjectiveState>();
        if (q["o"].AsTable() is { } os)
            foreach (var (_, v) in os.Pairs())
                if (v.AsTable() is { } o)
                    objectives.Add(new ObjectiveState(o["h"].AsInt() ?? 0, o["n"].AsInt() ?? 0, o["f"].AsBoolean() ?? false, o["t"].AsString()));
        return new LogQuest(qid, q["title"].AsString(), q["lvl"].AsInt(), objectives);
    }

    private static QuestEvent? ReadEvent(LuaTable ev)
    {
        var guid = ev["c"].AsString();
        var seq = ev["s"].AsLong();
        if (guid is null || seq is null) return null; // malformed entry: skip, the snapshot still carries the state

        var raw = ev["k"].AsString() ?? "";
        return new QuestEvent(
            guid,
            seq.Value,
            Time(ev["t"]) ?? DateTimeOffset.UnixEpoch,
            KindOf(raw),
            raw,
            QuestId: ev["q"].AsInt(),
            Objective: ev["o"].AsInt(),
            Have: ev["h"].AsInt(),
            Need: ev["n"].AsInt(),
            Finished: ev["f"].AsBoolean(),
            Xp: ev["x"].AsInt(),
            Level: ev["l"].AsInt(),
            MapId: ev["m"].AsInt());
    }

    public static QuestEventKind KindOf(string raw) => raw switch
    {
        "ACCEPT" => QuestEventKind.Accept,
        "TURNIN" => QuestEventKind.TurnIn,
        "ABANDON" => QuestEventKind.Abandon,
        "PROGRESS" => QuestEventKind.Progress,
        "LEVEL" => QuestEventKind.Level,
        "ZONE" => QuestEventKind.Zone,
        _ => QuestEventKind.Unknown,
    };

    private static HarvestedQuest ReadHarvest(int qid, LuaTable h) => new(
        qid,
        Time(h["t"]) ?? DateTimeOffset.UnixEpoch,
        h["title"].AsString(),
        h["obj"].AsString(),
        h["lvl"].AsInt(),
        h["grp"].AsInt(),
        h["scaling"].AsBoolean(),
        ReadSource(h["giver"]),
        ReadSource(h["ender"]),
        h["after"].AsInt());

    private static QuestSource? ReadSource(LuaValue v) => v.AsTable() is { } s
        ? new QuestSource(s["npc"].AsInt(), s["object"].AsInt(), s["item"].AsInt(), s["map"].AsInt(), s["x"].AsNumber(), s["y"].AsNumber())
        : null;

    private static DateTimeOffset? Time(LuaValue v) =>
        v.AsLong() is { } secs and > 0 ? DateTimeOffset.FromUnixTimeSeconds(secs) : null;
}
