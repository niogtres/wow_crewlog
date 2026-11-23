using Crewlog.Client.Core.Inbox;
using Crewlog.Client.Core.Lua;
using Crewlog.Contracts;

namespace Crewlog.Client.Tests;

public class InboxWriterTests
{
    [Fact]
    public void Writes_acks_and_crew_and_merges_with_earlier_acks()
    {
        var flavor = Directory.CreateTempSubdirectory("crewlog-inbox").FullName;
        try
        {
            var save = Path.Combine(flavor, "WTF", "Account", "ACC", "SavedVariables", "Crewlog.lua");
            Assert.Equal(flavor, InboxWriter.FlavorDirFromSaveFile(save));

            var resp = new SyncResponse(new Dictionary<string, long> { ["Player-1-A"] = 11 }, 1700000000, DateTimeOffset.UtcNow, []);
            Assert.Null(InboxWriter.Write(flavor, resp, null)); // addon not installed: nothing written

            Directory.CreateDirectory(Path.Combine(flavor, "Interface", "AddOns", "Crewlog_Inbox"));
            var crew = new InboxResponse(DateTimeOffset.UtcNow,
            [
                new InboxJournal("Tuesday \"crew\"", [
                    new InboxToon("Player-1-B", "Brögg", "Bob", 12, "Warrior", "Durotar", false,
                        [new InboxQuest(789, "Sting of the Scorpid", 0, 1, false), new InboxQuest(4641, "Your Place", 0, 0, true)],
                        DateTimeOffset.FromUnixTimeSeconds(1700000100), [788, 789]),
                ], [new InboxPick(790, "Sarkoth", 5, "Brogg, Ashka", "Hana'zua · Durotar (40.6, 62.6)")]),
            ],
            [new InboxNext("Player-1-A", 14, 1411, "Durotar", [new InboxSuggestion(792, "Vile Familiars", 4, true, "unlocks 1 more", "Zureetha Fargaze")])]);
            var path = InboxWriter.Write(flavor, resp, crew)!;

            // A second account in the same install acks its own toon; the first ack stays.
            InboxWriter.Write(flavor, new SyncResponse(new Dictionary<string, long> { ["Player-1-C"] = 3, ["Player-1-A"] = 9 }, null, DateTimeOffset.UtcNow, []), crew);

            var inbox = SavedVariablesParser.ParseFile(path)["Crewlog_Inbox"].AsTable()!;
            Assert.Equal(1, inbox["schema"].AsInt());
            Assert.Equal(11, inbox["ack"].AsTable()!["Player-1-A"].AsInt()); // never goes backwards
            Assert.Equal(3, inbox["ack"].AsTable()!["Player-1-C"].AsInt());
            Assert.Equal(1700000000, inbox["harvestAck"].AsLong());
            var journal = inbox["journals"].AsTable()![1].AsTable()!;
            Assert.Equal("Tuesday \"crew\"", journal["title"].AsString());
            var toon = journal["toons"].AsTable()![1].AsTable()!;
            Assert.Equal(12, toon["level"].AsInt());
            Assert.Equal(1700000100, toon["updated"].AsLong());
            Assert.True(toon["mine"].IsNil);
            var quests = toon["quests"].AsTable()!;
            Assert.Equal(789, quests[1].AsTable()!["id"].AsInt());
            Assert.True(quests[2].AsTable()!["ready"].AsBoolean());
            Assert.Contains(@"\195\182", File.ReadAllText(path)); // "ö" as UTF-8 bytes, readable by WoW's Lua
            Assert.Equal(789, toon["doneIds"].AsTable()![2].AsInt());              // crewmate has done these of my quests
            Assert.Equal(790, journal["together"].AsTable()![1].AsTable()!["id"].AsInt());
            var next = inbox["next"].AsTable()![1].AsTable()!;
            Assert.Equal(1411, next["uiMap"].AsInt());
            var suggestion = next["quests"].AsTable()![1].AsTable()!;
            Assert.True(suggestion["soon"].AsBoolean());
            Assert.Equal("unlocks 1 more", suggestion["why"].AsString());
        }
        finally
        {
            Directory.Delete(flavor, true);
        }
    }
}
