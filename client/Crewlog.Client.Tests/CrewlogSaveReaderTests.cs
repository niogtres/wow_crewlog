using Crewlog.Client.Core.Lua;
using Crewlog.Client.Core.SavedVariables;
using Crewlog.Contracts;

namespace Crewlog.Client.Tests;

/// <summary>Reads the files produced by addon/tests/collector_test.lua, so addon and client agree on the schema.</summary>
public class CrewlogSaveReaderTests
{
    public static TheoryData<string> Fixtures => new() { "CrewlogDB.lua", "CrewlogDB.indexcomments.lua" };

    private static AddonSave Load(string name) =>
        CrewlogSaveReader.ReadFile(Path.Combine(AppContext.BaseDirectory, "Fixtures", name));

    [Theory]
    [MemberData(nameof(Fixtures))]
    public void Reads_the_session_the_addon_test_recorded(string fixture)
    {
        var save = Load(fixture);

        Assert.Equal(1, save.Schema);
        Assert.Equal("abc", save.InstallId);
        Assert.Equal("0.1.0-test", save.AddonVersion);

        var c = Assert.Single(save.Characters);
        Assert.Equal("Player-6949-0A1B2C3D", c.Guid);
        Assert.Equal("Zarnokk", c.Name);
        Assert.Equal(6949, c.RealmId);
        Assert.Equal("ROGUE", c.Class);
        Assert.Equal((8, 4), (c.RaceId, c.ClassId));
        Assert.Equal(2, c.Level);
        Assert.Equal(1412, c.MapId);
        Assert.Equal((1411, 43.2, 68.7), (c.PosMapId, c.PosX, c.PosY)); // where the toon stood at the last save (route map)
        Assert.Equal(11, c.Seq);
        Assert.Equal([788, 3911, 4641], c.Completed);
        Assert.Empty(c.Log);

        Assert.Equal(9, save.Events.Count);
        Assert.Equal(Enumerable.Range(3, 9).Select(i => (long)i), save.Events.Select(e => e.Seq));
        Assert.Equal(
            [QuestEventKind.Accept, QuestEventKind.Accept, QuestEventKind.Progress, QuestEventKind.Progress, QuestEventKind.Progress,
             QuestEventKind.TurnIn, QuestEventKind.Abandon, QuestEventKind.Level, QuestEventKind.Zone],
            save.Events.Select(e => e.Kind));

        var finalProgress = save.Events.Last(e => e.Kind == QuestEventKind.Progress);
        Assert.Equal((788, 1, 10, 10, true), (finalProgress.QuestId!.Value, finalProgress.Objective!.Value, finalProgress.Have!.Value, finalProgress.Need!.Value, finalProgress.Finished!.Value));
        Assert.Equal(450, save.Events.Single(e => e.Kind == QuestEventKind.TurnIn).Xp);

        var giver = save.Harvest.Single(h => h.QuestId == 97279);
        Assert.Equal("Wayward Weapons", giver.Title);
        Assert.Equal(3143, giver.Giver!.NpcId);
        Assert.Equal(1411, giver.Giver.MapId);
        Assert.Equal(0.4323, giver.Giver.X!.Value, 4);
        Assert.Equal(788, save.Harvest.Single(h => h.QuestId == 790).After);
        Assert.Equal(3143, save.Harvest.Single(h => h.QuestId == 788).Ender!.NpcId);
    }

    [Fact]
    public void Both_serializer_styles_read_identically()
    {
        var a = Load("CrewlogDB.lua");
        var b = Load("CrewlogDB.indexcomments.lua");
        Assert.Equal(a.Events, b.Events);
        Assert.Equal(a.Characters.Single().Completed, b.Characters.Single().Completed);
    }

    [Fact]
    public void Rejects_unknown_schema_and_missing_root()
    {
        Assert.Throws<SaveFormatException>(() => CrewlogSaveReader.Read(SavedVariablesParser.Parse("CrewlogDB = { schema = 99 }")));
        Assert.Throws<SaveFormatException>(() => CrewlogSaveReader.Read(SavedVariablesParser.Parse("Other = {}")));
    }

    [Fact]
    public void Skips_malformed_events_and_keeps_unknown_kinds()
    {
        var save = CrewlogSaveReader.Read(SavedVariablesParser.Parse("""
            CrewlogDB = { schema = 1, installId = "x", events = {
              { c = "Player-1-A", s = 1, t = 100, k = "SOMETHING_NEW" },
              { k = "ACCEPT", q = 5 },
            } }
            """));
        var e = Assert.Single(save.Events);
        Assert.Equal(QuestEventKind.Unknown, e.Kind);
        Assert.Equal("SOMETHING_NEW", e.RawKind);
    }
}
