using Crewlog.Client.Core;
using Crewlog.Client.Core.Sync;
using Crewlog.Client.Core.Wow;

namespace Crewlog.Client.Tests;

internal sealed class ListLog : ILog
{
    public List<string> Lines { get; } = [];
    public void Info(string message) => Lines.Add(message);
    public void Warn(string message) => Lines.Add("WARN " + message);
    public void Error(string message, Exception? ex = null) => Lines.Add("ERROR " + message);
}

public sealed class TempDir : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "crewlog-tests-" + Guid.NewGuid().ToString("N"));
    public TempDir() => Directory.CreateDirectory(Path);
    public string Combine(params string[] parts) => System.IO.Path.Combine([Path, .. parts]);
    public void Dispose() { try { Directory.Delete(Path, true); } catch (IOException) { } }
}

public class SyncEngineTests
{
    private static string Fixture => Path.Combine(AppContext.BaseDirectory, "Fixtures", "CrewlogDB.lua");

    [Fact]
    public void Logs_new_events_once_and_remembers_them()
    {
        using var tmp = new TempDir();
        var store = new SyncStateStore(tmp.Combine("state.json"));
        var log = new ListLog();
        var engine = new SyncEngine(store, log);

        var first = engine.Process(Fixture);
        Assert.True(first.Ok);
        Assert.Equal(9, first.NewEvents.Count);
        Assert.Contains(log.Lines, l => l.Contains("Zarnokk turned in quest 788 (+450 xp)"));

        var second = engine.Process(Fixture);
        Assert.Empty(second.NewEvents);
        Assert.Equal(11, store.Load().Get("abc", "Player-6949-0A1B2C3D"));
    }

    [Fact]
    public void Reports_unreadable_files_without_throwing()
    {
        using var tmp = new TempDir();
        var bad = tmp.Combine("Crewlog.lua");
        File.WriteAllText(bad, "CrewlogDB = { broken");
        var log = new ListLog();
        var result = new SyncEngine(new SyncStateStore(tmp.Combine("state.json")), log).Process(bad);
        Assert.False(result.Ok);
        Assert.Contains(log.Lines, l => l.StartsWith("WARN Could not read"));
    }
}

public class WowInstallLocatorTests
{
    [Fact]
    public void Finds_flavor_folders_and_prefers_forever()
    {
        using var tmp = new TempDir();
        Directory.CreateDirectory(tmp.Combine("_retail_", "WTF"));
        Directory.CreateDirectory(tmp.Combine("_forever_", "Interface", "AddOns"));
        Directory.CreateDirectory(tmp.Combine("_forever_", "WTF", "Account", "ACC1", "SavedVariables"));
        Directory.CreateDirectory(tmp.Combine("Data"));

        var flavors = WowInstallLocator.FlavorsIn(tmp.Path).OrderByDescending(f => f.LooksLikeForever).ToList();
        Assert.Equal(["_forever_", "_retail_"], flavors.Select(f => f.Name));
        Assert.True(flavors[0].LooksLikeForever);
        Assert.Equal(tmp.Combine("_forever_", "WTF", "Account", "ACC1", "SavedVariables", "Crewlog.lua"),
            Assert.Single(flavors[0].SavedVariablesFiles("Crewlog.lua")));
    }

    [Fact]
    public void Accepts_a_flavor_folder_directly()
    {
        using var tmp = new TempDir();
        Directory.CreateDirectory(tmp.Combine("WTF"));
        Assert.Single(WowInstallLocator.FlavorsIn(tmp.Path));
    }
}

public class SavedVariablesWatcherTests
{
    [Fact]
    public async Task Debounces_bursts_of_writes_into_one_change()
    {
        using var tmp = new TempDir();
        var sv = tmp.Combine("WTF", "Account", "ACC1", "SavedVariables");
        Directory.CreateDirectory(sv);
        var file = Path.Combine(sv, "Crewlog.lua");
        File.WriteAllText(file, "CrewlogDB = {}");

        using var watcher = new SavedVariablesWatcher(new WowFlavorFolder(tmp.Path, "_forever_", true), TimeSpan.FromMilliseconds(300));
        var hits = 0;
        var done = new TaskCompletionSource();
        watcher.Changed += p => { if (p == file && Interlocked.Increment(ref hits) == 1) done.TrySetResult(); };
        watcher.Start();

        for (var i = 0; i < 5; i++)
        {
            File.WriteAllText(file, $"CrewlogDB = {{ n = {i} }}");
            await Task.Delay(50);
        }
        await done.Task.WaitAsync(TimeSpan.FromSeconds(10));
        await Task.Delay(700);
        Assert.Equal(1, hits);
    }

    [Fact]
    public async Task Ignores_the_bak_file_wow_rotates_on_save()
    {
        using var tmp = new TempDir();
        var sv = tmp.Combine("WTF", "Account", "ACC1", "SavedVariables");
        Directory.CreateDirectory(sv);
        var file = Path.Combine(sv, "Crewlog.lua");
        File.WriteAllText(file, "CrewlogDB = {}");

        using var watcher = new SavedVariablesWatcher(new WowFlavorFolder(tmp.Path, "_forever_", true), TimeSpan.FromMilliseconds(200));
        var seen = new List<string>();
        watcher.Changed += p => { lock (seen) seen.Add(p); };
        watcher.Start();

        // What WoW does on /reload: old file -> .bak, then a fresh Crewlog.lua.
        File.Move(file, file + ".bak");
        File.WriteAllText(file, "CrewlogDB = { n = 1 }");
        await Task.Delay(1200);

        lock (seen) Assert.Equal([file], seen);
    }

    [Fact]
    public async Task Rescan_reports_existing_files_and_ignores_other_folders()
    {
        using var tmp = new TempDir();
        var sv = tmp.Combine("WTF", "Account", "ACC1", "SavedVariables");
        Directory.CreateDirectory(sv);
        File.WriteAllText(Path.Combine(sv, "Crewlog.lua"), "CrewlogDB = {}");
        var perChar = tmp.Combine("WTF", "Account", "ACC1", "Realm", "Char", "SavedVariables");
        Directory.CreateDirectory(perChar);

        using var watcher = new SavedVariablesWatcher(new WowFlavorFolder(tmp.Path, "_forever_", true), TimeSpan.FromMilliseconds(100));
        var seen = new List<string>();
        watcher.Changed += p => { lock (seen) seen.Add(p); };
        watcher.RescanAll();
        // Wait for the debounced report (a busy CI runner can take well over the 100 ms), then a little longer so a
        // stray second report would show.
        for (var waited = 0; waited < 5000 && seen.Count == 0; waited += 50) await Task.Delay(50);
        await Task.Delay(300);
        lock (seen) Assert.Equal([Path.Combine(sv, "Crewlog.lua")], seen);
    }
}
