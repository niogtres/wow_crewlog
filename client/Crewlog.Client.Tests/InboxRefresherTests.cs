using System.Net;
using System.Text;
using Crewlog.Client.Core;
using Crewlog.Client.Core.Inbox;
using Crewlog.Client.Core.Lua;
using Crewlog.Client.Core.Server;

namespace Crewlog.Client.Tests;

public class InboxRefresherTests
{
    private sealed class FakeServer : HttpMessageHandler
    {
        public string Body = "";
        public int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            Calls++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(Body, Encoding.UTF8, "application/json") });
        }
    }

    private sealed class NullLog : ILog
    {
        public void Info(string message) { }
        public void Warn(string message) { }
        public void Error(string message, Exception? ex = null) { }
    }

    private static string Crew(int done) => $$"""
        {"generatedAt":"2026-11-23T22:00:00Z","journals":[{"title":"Tuesday crew","toons":[
          {"guid":"Player-1-B","name":"Brogg","ownerName":"Bob","level":12,"class":"Warrior","zone":"Durotar","mine":false,
           "quests":[{"id":789,"title":"Sting of the Scorpid","done":{{done}},"total":1,"ready":false}],"updatedAt":"2026-11-23T21:59:00Z"}]}]}
        """;

    private const string RouteJson = """
        ,"routes":[{"guid":"Player-1-A","route":{"uiMapId":1411,"zone":"Durotar","stops":[
          {"n":1,"x":50,"y":50,"place":"Gornek","tasks":["Turn in Your Place"]}]}}]}
        """;

    [Fact]
    public async Task Pulls_on_schedule_writes_only_changes_and_keeps_acks()
    {
        var flavor = Directory.CreateTempSubdirectory("crewlog-refresh").FullName;
        try
        {
            var inboxDir = Path.Combine(flavor, "Interface", "AddOns", "Crewlog_Inbox");
            Directory.CreateDirectory(inboxDir);
            File.WriteAllText(Path.Combine(inboxDir, "Data.lua"), "Crewlog_Inbox = { schema = 1, ack = { [\"Player-1-A\"] = 7 }, harvestAck = 99 }");

            var fake = new FakeServer { Body = Crew(0) };
            var refresher = new InboxRefresher(new NullLog(), () => new ServerClient(new HttpClient(fake) { BaseAddress = new Uri("http://test/") }));
            var t0 = DateTimeOffset.Parse("2026-11-23T22:00:00Z");

            Assert.True(refresher.Due(wowRunning: false, t0));
            Assert.True(await refresher.RefreshAsync(flavor, t0));
            Assert.False(refresher.Due(wowRunning: true, t0.AddMinutes(1)));   // every 2 min while playing
            Assert.True(refresher.Due(wowRunning: true, t0.AddMinutes(2)));
            Assert.False(refresher.Due(wowRunning: false, t0.AddMinutes(10))); // every 15 min otherwise
            Assert.True(refresher.Due(wowRunning: false, t0.AddMinutes(15)));

            Assert.False(await refresher.RefreshAsync(flavor, t0.AddMinutes(2))); // nothing new: no rewrite
            fake.Body = Crew(1);
            Assert.True(await refresher.RefreshAsync(flavor, t0.AddMinutes(4)));  // a crewmate progressed
            fake.Body = Crew(1).TrimEnd()[..^1] + RouteJson;
            Assert.True(await refresher.RefreshAsync(flavor, t0.AddMinutes(6)));  // only your own route changed
            Assert.False(await refresher.RefreshAsync(flavor, t0.AddMinutes(8)));
            Assert.True(await refresher.RefreshAsync(flavor, t0.AddMinutes(16))); // the same, but the copy there is 10 min old
            Assert.Equal(6, fake.Calls);

            var inbox = SavedVariablesParser.ParseFile(Path.Combine(inboxDir, "Data.lua"))["Crewlog_Inbox"].AsTable()!;
            Assert.Equal(7, inbox["ack"].AsTable()!["Player-1-A"].AsInt());      // acks survive
            Assert.Equal(99, inbox["harvestAck"].AsLong());
            var quest = inbox["journals"].AsTable()![1].AsTable()!["toons"].AsTable()![1].AsTable()!["quests"].AsTable()![1].AsTable()!;
            Assert.Equal(1, quest["done"].AsInt());

            var unlinked = new InboxRefresher(new NullLog(), () => null);
            Assert.False(await unlinked.RefreshAsync(flavor));
        }
        finally
        {
            Directory.Delete(flavor, true);
        }
    }
}
