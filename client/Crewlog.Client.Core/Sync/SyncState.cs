using System.Text.Json;

namespace Crewlog.Client.Core.Sync;

/// <summary>
/// What the client has already handled, per install + character: the highest event seq seen.
/// M1 uses it to log only new events; from M2 on it tracks what the server has acknowledged.
/// </summary>
public sealed class SyncState
{
    public Dictionary<string, long> LastSeq { get; set; } = new(StringComparer.Ordinal);

    public static string Key(string installId, string characterGuid) => $"{installId}/{characterGuid}";

    public long Get(string installId, string guid) => LastSeq.TryGetValue(Key(installId, guid), out var s) ? s : 0;

    public void Set(string installId, string guid, long seq) => LastSeq[Key(installId, guid)] = seq;
}

public sealed class SyncStateStore(string path)
{
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    public string Path { get; } = path;

    public SyncState Load()
    {
        try
        {
            if (File.Exists(Path))
                return JsonSerializer.Deserialize<SyncState>(File.ReadAllText(Path), Json) ?? new SyncState();
        }
        catch (JsonException) { } // corrupt state: start over, the addon still has every unacked event
        return new SyncState();
    }

    /// <summary>Write to a temp file and swap it in, so a crash never leaves half a file.</summary>
    public void Save(SyncState state)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
        var tmp = Path + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(state, Json));
        File.Move(tmp, Path, overwrite: true);
    }
}
