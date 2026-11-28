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
                        [new InboxQuest(789, "Sting of the Scorpid", 0, 1, false), new InboxQuest(4641, "Your Place", 0, 0, true),
                         new InboxQuest(1, "Sting |TInterface:2000|t", 0, 0, false)],
                        DateTimeOffset.FromUnixTimeSeconds(1700000100), [788, 789]),
                ], [new InboxPick(790, "Sarkoth", 5, "Brogg, Ashka", "Hana'zua · Durotar (40.6, 62.6)")],
                new InboxRoute(1411, "Durotar", [
                    new InboxStop(1, 42.9, 69.24, "Zureetha Fargaze", ["Pick up Vile Familiars (Brögg)"]),
                    new InboxStop(2, 45, 56, "Vile Familiar", ["Vile Familiar for Vile Familiars", "Turn in Sarkoth"], 1454, 80.77, 23.7,
                        [[42.9, 69.2, 44.04, 62.5, 45, 56], [1, 2]]),
                ]),
                [new InboxInStep("Player-1-A", "handin", 422, "Arugal's Folly (part 1)", 10, "Deathstalker Faerleia · Silverpine Forest (43.4, 40.9)",
                    "for Arugal's Folly (part 2) with Tawkin")]),
            ],
            [new InboxNext("Player-1-A", 14, 1411, "Durotar", [new InboxSuggestion(792, "Vile Familiars", 4, true, "unlocks 1 more", "Zureetha Fargaze")])],
            [new InboxToonRoute("Player-1-A", new InboxRoute(1411, "Durotar", [
                new InboxStop(1, 51.2, 40.8, "Gornek", ["Turn in Your Place"]),
                new InboxStop(2, 44, 60, "Sarkoth", ["Sarkoth for Sarkoth"]),
            ]))]);
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
            // A crewmate's "|" (the game's escape codes) is written doubled, so the game shows it as text.
            Assert.Contains("Sting ||TInterface:2000||t", File.ReadAllText(path));
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
            var step = journal["instep"].AsTable()![1].AsTable()!;                  // Get in step for my toons
            Assert.Equal("handin", step["kind"].AsString());
            Assert.Equal(422, step["id"].AsInt());
            Assert.Equal("Arugal's Folly (part 1)", step["title"].AsString());
            Assert.StartsWith("Deathstalker Faerleia", step["where"].AsString());
            Assert.Equal("for Arugal's Folly (part 2) with Tawkin", step["goal"].AsString());
            var route = journal["route"].AsTable()!;                                  // the route for the in-game map
            Assert.Equal(1411, route["map"].AsInt());
            var stops = route["stops"].AsTable()!;
            Assert.Equal("Zureetha Fargaze", stops[1].AsTable()!["place"].AsString());
            Assert.Contains("x = 42.9, y = 69.2", File.ReadAllText(path));               // invariant decimals, one place
            Assert.Equal(1454, stops[2].AsTable()!["cityMap"].AsInt());                 // a stop in Orgrimmar, off Durotar's map
            Assert.Contains("cx = 80.8, cy = 23.7", File.ReadAllText(path));
            Assert.True(stops[1].AsTable()!["cityMap"].IsNil);
            var leg = stops[2].AsTable()!["path"].AsTable()!;                            // the way there along the ground
            Assert.Equal(6, leg[1].AsTable()!.Count);
            Assert.True(leg[2].IsNil);                                                    // a broken line is left out
            Assert.Contains("{ 42.9, 69.2, 44, 62.5, 45, 56 }", File.ReadAllText(path));
            Assert.Equal("Turn in Sarkoth", stops[2].AsTable()!["tasks"].AsTable()![2].AsString());
            var own = inbox["routes"].AsTable()!["Player-1-A"].AsTable()!;              // the toon's own route ("Just me")
            Assert.Equal(1411, own["map"].AsInt());
            Assert.Equal("Durotar", own["zone"].AsString());
            Assert.Equal("Sarkoth for Sarkoth", own["stops"].AsTable()![2].AsTable()!["tasks"].AsTable()![1].AsString());
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
    [Fact]
    public void Writes_relay_keys_for_own_toons()
    {
        var crew = new InboxResponse(DateTimeOffset.UtcNow, [], RelayKeys: new Dictionary<string, string>
        {
            ["Player-1-A"] = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
            ["Player-1-B"] = "not hex\" injected",
        });
        var lua = InboxWriter.Render(new Dictionary<string, long>(), null, crew, DateTimeOffset.UtcNow);
        var inbox = SavedVariablesParser.Parse(lua)["Crewlog_Inbox"].AsTable()!;
        Assert.Equal("00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff", inbox["relayKeys"].AsTable()!["Player-1-A"].AsString());
        Assert.Null(inbox["relayKeys"].AsTable()!["Player-1-B"].AsString());
        Assert.DoesNotContain("relayKeys", InboxWriter.Render(new Dictionary<string, long>(), null, new InboxResponse(DateTimeOffset.UtcNow, []), DateTimeOffset.UtcNow));
    }
}
