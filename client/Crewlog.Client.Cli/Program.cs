using System.Diagnostics;
using Crewlog.Client.Core;
using Crewlog.Client.Core.SavedVariables;
using Crewlog.Client.Core.Server;
using Crewlog.Client.Core.Sync;
using Crewlog.Client.Core.Wow;

// crewlog: developer tool around the client core.
//   crewlog dump <Crewlog.lua>                 print what the addon saved
//   crewlog locate                                list detected WoW flavor folders and Crewlog.lua files
//   crewlog watch [<flavor folder>]               watch like the tray client does (uploads when linked)
//   crewlog link [<server url>]                   link this PC to a Crewlog account (device flow)
//   crewlog push <Crewlog.lua> [<server url>]  upload one save file now

Console.OutputEncoding = System.Text.Encoding.UTF8;
var config = AppConfig.Load(AppPaths.Config);
var tokens = new TokenStore(AppPaths.Token);

return args switch
{
    ["dump", var file] => Dump(file),
    ["locate"] => Locate(),
    ["watch"] => Watch(null),
    ["watch", var folder] => Watch(folder),
    ["link"] => await Link(config.ServerUrl),
    ["link", var url] => await Link(url),
    ["push", var file] => await Push(file, config.ServerUrl),
    ["push", var file, var url] => await Push(file, url),
    _ => Usage(),
};

int Usage()
{
    Console.WriteLine("usage: crewlog dump <file> | crewlog locate | crewlog watch [<folder>] | crewlog link [<server>] | crewlog push <file> [<server>]");
    return 2;
}

async Task<int> Link(string serverUrl)
{
    var client = ServerClient.Create(serverUrl);
    var start = await client.StartDeviceLoginAsync(Environment.MachineName);
    Console.WriteLine($"Open {start.VerifyUrl}");
    Console.WriteLine($"and check the code: {start.UserCode}");
    try { Process.Start(new ProcessStartInfo(start.VerifyUrl) { UseShellExecute = true }); } catch (System.ComponentModel.Win32Exception) { }
    Console.WriteLine("Waiting for approval in the browser…");
    var (token, user) = await client.WaitForApprovalAsync(start);
    tokens.Save(token);
    config.ServerUrl = serverUrl;
    config.LinkedAs = user;
    config.Save(AppPaths.Config);
    Console.WriteLine($"Linked to {user} on {serverUrl}.");
    return 0;
}

async Task<int> Push(string file, string serverUrl)
{
    if (tokens.Load() is not { } token)
    {
        Console.WriteLine("Not linked yet: run `crewlog link` first.");
        return 1;
    }
    var engine = new SyncEngine(new SyncStateStore(AppPaths.State), new ConsoleLog(), () => ServerClient.Create(serverUrl, token));
    var result = await engine.ProcessAsync(file);
    return result.Pushed ? 0 : 1;
}

int Dump(string file)
{
    var save = CrewlogSaveReader.ReadFile(file);
    Console.WriteLine($"schema {save.Schema} · install {save.InstallId} · addon {save.AddonVersion} · dropped {save.DroppedEvents}");
    foreach (var c in save.Characters)
    {
        Console.WriteLine($"\n{c.Name} ({c.Guid}) lvl {c.Level} {c.Race} {c.Class} {c.Faction} · map {c.MapId} · seq {c.Seq} · last seen {c.LastSeen?.ToLocalTime():g}");
        Console.WriteLine($"  completed {c.Completed.Count} (hash {c.CompletedHash}): {string.Join(", ", c.Completed.Take(30))}{(c.Completed.Count > 30 ? ", …" : "")}");
        foreach (var q in c.Log)
            Console.WriteLine($"  log {q.QuestId} \"{q.Title}\" lvl {q.Level}: {string.Join(", ", q.Objectives.Select(o => $"{o.Have}/{o.Need}{(o.Finished ? "✓" : "")}"))}");
    }
    var names = save.Characters.ToDictionary(c => c.Guid, c => c.Name ?? c.Guid);
    Console.WriteLine($"\nevents ({save.Events.Count})");
    foreach (var e in save.Events) Console.WriteLine($"  {names.GetValueOrDefault(e.CharacterGuid, e.CharacterGuid)} {EventText.Describe(e)}");
    Console.WriteLine($"\nharvest ({save.Harvest.Count})");
    foreach (var h in save.Harvest)
        Console.WriteLine($"  {h.QuestId} \"{h.Title}\" lvl {h.Level} giver {Src(h.Giver)} ender {Src(h.Ender)}{(h.After is { } a ? $" after {a}" : "")}");
    return 0;

    static string Src(Crewlog.Contracts.QuestSource? s) => s is null ? "-"
        : FormattableString.Invariant($"{(s.NpcId is { } n ? $"npc {n}" : s.ObjectId is { } o ? $"object {o}" : $"item {s.ItemId}")}@{s.MapId}({s.X:0.###}, {s.Y:0.###})");
}

static int Locate()
{
    var all = WowInstallLocator.FindAll();
    if (all.Count == 0) Console.WriteLine("No WoW installs found.");
    foreach (var f in all)
    {
        Console.WriteLine($"{f.Path}{(f.LooksLikeForever ? "  <- Forever" : "")}");
        foreach (var sv in f.SavedVariablesFiles(SavedVariablesWatcher.FileName))
            Console.WriteLine($"   {sv}{(File.Exists(sv) ? "" : "  (not written yet)")}");
    }
    return 0;
}

int Watch(string? folder)
{
    var flavor = folder is null ? WowInstallLocator.FindAll().FirstOrDefault() : WowInstallLocator.FlavorsIn(folder).FirstOrDefault();
    if (flavor is null)
    {
        Console.WriteLine("No WoW flavor folder found; pass it explicitly: crewlog watch \"D:\\Games\\World of Warcraft\\_forever_\"");
        return 1;
    }
    var token = tokens.Load();
    var engine = new SyncEngine(new SyncStateStore(AppPaths.State), new ConsoleLog(),
        token is null ? null : () => ServerClient.Create(config.ServerUrl, token));
    using var watcher = new SavedVariablesWatcher(flavor);
    watcher.Changed += file => engine.ProcessAsync(file).GetAwaiter().GetResult();
    watcher.Start();
    watcher.RescanAll();
    Console.WriteLine($"Watching {watcher.WtfAccountPath}{(token is null ? " (not linked, local only)" : $" → {config.ServerUrl}")}. Ctrl+C to stop.");
    var quit = new ManualResetEventSlim();
    Console.CancelKeyPress += (_, e) => { e.Cancel = true; quit.Set(); };
    quit.Wait();
    return 0;
}
