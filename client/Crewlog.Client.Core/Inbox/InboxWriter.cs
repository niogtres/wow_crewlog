using System.Globalization;
using System.Text;
using Crewlog.Client.Core.Lua;
using Crewlog.Contracts;

namespace Crewlog.Client.Core.Inbox;

/// <summary>
/// Writes Interface/AddOns/Crewlog_Inbox/Data.lua (DESIGN §5): the server's acks, so the addon can drop events
/// that are safely stored, and the journal crew's current quests for the in-game crew view. The game reads the file
/// on the next /reload or login. Acks are merged with what is already there, so several WoW accounts sharing one
/// install don't undo each other.
/// </summary>
public static class InboxWriter
{
    public const string AddonFolder = "Crewlog_Inbox";
    public const string FileName = "Data.lua";

    /// <summary>WoW flavor folder (…/_anniversary_) from a SavedVariables file (…/WTF/Account/X/SavedVariables/Crewlog.lua).</summary>
    public static string? FlavorDirFromSaveFile(string saveFile)
    {
        var dir = new FileInfo(saveFile).Directory;
        for (var i = 0; i < 4 && dir is not null; i++) dir = dir.Parent;
        return dir?.FullName;
    }

    public static string PathFor(string flavorDir) => Path.Combine(flavorDir, "Interface", "AddOns", AddonFolder, FileName);

    /// <summary>Writes the inbox when the Inbox addon is installed. Returns the path, or null when it isn't.</summary>
    public static string? Write(string flavorDir, SyncResponse sync, InboxResponse? crew, DateTimeOffset? now = null)
    {
        var path = PathFor(flavorDir);
        if (!Directory.Exists(Path.GetDirectoryName(path))) return null;

        var ack = ReadAck(path, out var harvestAck);
        foreach (var (guid, seq) in sync.Ack) ack[guid] = Math.Max(seq, ack.GetValueOrDefault(guid));
        if (sync.HarvestAck is { } h) harvestAck = Math.Max(h, harvestAck ?? 0);

        var text = Render(ack, harvestAck, crew, now ?? DateTimeOffset.UtcNow);
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, text, new UTF8Encoding(false));
        File.Move(tmp, path, overwrite: true);
        return path;
    }

    internal static Dictionary<string, long> ReadAck(string path, out long? harvestAck)
    {
        harvestAck = null;
        var ack = new Dictionary<string, long>(StringComparer.Ordinal);
        try
        {
            if (!File.Exists(path)) return ack;
            if (SavedVariablesParser.ParseFile(path).GetValueOrDefault("Crewlog_Inbox")?.AsTable() is not { } inbox) return ack;
            harvestAck = inbox["harvestAck"].AsLong();
            if (inbox["ack"].AsTable() is { } t)
                foreach (var (k, v) in t.StringKeyed())
                    if (v.AsLong() is { } seq) ack[k] = seq;
        }
        catch (Exception ex) when (ex is LuaParseException or IOException)
        {
            // A broken or locked file is simply rewritten from the server's numbers.
        }
        return ack;
    }

    public static string Render(IReadOnlyDictionary<string, long> ack, long? harvestAck, InboxResponse? crew, DateTimeOffset now)
    {
        var sb = new StringBuilder();
        sb.AppendLine("-- Written by the Crewlog Windows client on every sync. Do not edit.");
        sb.AppendLine("Crewlog_Inbox = {");
        sb.AppendLine("  schema = 1,");
        sb.Append("  generatedAt = ").Append(now.ToUnixTimeSeconds()).AppendLine(",");
        if (harvestAck is { } h) sb.Append("  harvestAck = ").Append(h).AppendLine(",");
        sb.AppendLine("  ack = {");
        foreach (var (guid, seq) in ack.OrderBy(a => a.Key, StringComparer.Ordinal))
            sb.Append("    [").Append(Str(guid)).Append("] = ").Append(seq).AppendLine(",");
        sb.AppendLine("  },");
        if (crew is not null)
        {
            sb.AppendLine("  journals = {");
            foreach (var j in crew.Journals)
            {
                sb.Append("    { title = ").Append(Str(j.Title)).AppendLine(", toons = {");
                foreach (var t in j.Toons)
                {
                    sb.Append("      { guid = ").Append(Str(t.Guid))
                      .Append(", name = ").Append(Str(t.Name))
                      .Append(", owner = ").Append(Str(t.OwnerName));
                    if (t.Level is { } lv) sb.Append(", level = ").Append(lv);
                    if (t.Class is { } c) sb.Append(", class = ").Append(Str(c));
                    if (t.Zone is { } z) sb.Append(", zone = ").Append(Str(z));
                    if (t.Mine) sb.Append(", mine = true");
                    if (t.Done is { Count: > 0 } doneIds) sb.Append(", doneIds = { ").Append(string.Join(", ", doneIds)).Append(" }");
                    sb.Append(", updated = ").Append(t.UpdatedAt.ToUnixTimeSeconds()).AppendLine(", quests = {");
                    foreach (var q in t.Quests)
                        sb.Append("        { id = ").Append(q.Id)
                          .Append(", title = ").Append(Str(q.Title))
                          .Append(", done = ").Append(q.Done)
                          .Append(", total = ").Append(q.Total)
                          .Append(q.Ready ? ", ready = true" : "").AppendLine(" },");
                    sb.AppendLine("      } },");
                }
                sb.Append("    }");
                if (j.Together is { Count: > 0 } together)
                {
                    sb.AppendLine(", together = {");
                    foreach (var p in together)
                    {
                        sb.Append("      { id = ").Append(p.Id).Append(", title = ").Append(Str(p.Title)).Append(", level = ").Append(p.Level)
                          .Append(", who = ").Append(Str(p.Who));
                        if (p.Giver is { } g) sb.Append(", giver = ").Append(Str(g));
                        sb.AppendLine(" },");
                    }
                    sb.Append("    }");
                }
                sb.AppendLine(" },");
            }
            sb.AppendLine("  },");
            if (crew.Next is { Count: > 0 } next)
            {
                // "Next up" per own toon and zone; the addon shows the zone the player is in.
                sb.AppendLine("  next = {");
                foreach (var n in next)
                {
                    sb.Append("    { guid = ").Append(Str(n.Guid)).Append(", area = ").Append(n.AreaId);
                    if (n.UiMapId is { } ui) sb.Append(", uiMap = ").Append(ui);
                    sb.Append(", zone = ").Append(Str(n.Zone)).AppendLine(", quests = {");
                    foreach (var q in n.Quests)
                    {
                        sb.Append("      { id = ").Append(q.Id).Append(", title = ").Append(Str(q.Title)).Append(", level = ").Append(q.Level);
                        if (q.Soon) sb.Append(", soon = true");
                        if (q.Why.Length > 0) sb.Append(", why = ").Append(Str(q.Why));
                        if (q.Giver is { } g) sb.Append(", giver = ").Append(Str(g));
                        sb.AppendLine(" },");
                    }
                    sb.AppendLine("    } },");
                }
                sb.AppendLine("  },");
            }
        }
        sb.AppendLine("}");
        return sb.ToString();
    }

    /// <summary>A Lua string literal; anything outside printable ASCII is escaped as decimal bytes (UTF-8).</summary>
    internal static string Str(string s)
    {
        var sb = new StringBuilder("\"");
        foreach (var b in Encoding.UTF8.GetBytes(s))
        {
            switch (b)
            {
                case (byte)'"': sb.Append("\\\""); break;
                case (byte)'\\': sb.Append("\\\\"); break;
                case (byte)'\n': sb.Append("\\n"); break;
                case < 32 or >= 127: sb.Append('\\').Append(b.ToString("000", CultureInfo.InvariantCulture)); break;
                default: sb.Append((char)b); break;
            }
        }
        return sb.Append('"').ToString();
    }
}
