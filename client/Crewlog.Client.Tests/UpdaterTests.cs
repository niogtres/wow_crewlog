using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Crewlog.Client.Core.Server;
using Crewlog.Client.Core.Updates;
using Crewlog.Client.Core.Wow;
using Crewlog.Contracts;

namespace Crewlog.Client.Tests;

public class UpdaterTests
{
    [Theory]
    [InlineData("0.2.0", "0.1.0", true)]
    [InlineData("0.1.10", "0.1.9", true)]
    [InlineData("0.1.0", "0.1.0", false)]
    [InlineData("0.1.0", "0.2.0", false)]
    [InlineData("0.2.0-beta", "0.1.0", true)]
    [InlineData("garbage", "0.1.0", false)]
    public void Compares_versions(string candidate, string installed, bool newer) =>
        Assert.Equal(newer, Updater.IsNewer(candidate, installed));

    private static void WriteAddon(string root, string version, string inbox = "Crewlog_Inbox = { schema = 1 }")
    {
        Directory.CreateDirectory(Path.Combine(root, "Crewlog", "media"));
        File.WriteAllText(Path.Combine(root, "Crewlog", "Crewlog.toc"), $"## Interface: 16001\n## Version: {version}\n");
        File.WriteAllText(Path.Combine(root, "Crewlog", "Core.lua"), "-- v" + version);
        Directory.CreateDirectory(Path.Combine(root, "Crewlog_Inbox"));
        File.WriteAllText(Path.Combine(root, "Crewlog_Inbox", "Data.lua"), inbox);
    }

    [Fact]
    public void Installs_addon_and_keeps_the_clients_inbox_data()
    {
        using var tmp = new TempDir();
        var flavor = new WowFlavorFolder(tmp.Combine("_forever_"), "_forever_", true);
        var addOns = flavor.AddOnsPath;
        WriteAddon(addOns, "0.1.0", inbox: "Crewlog_Inbox = { ack = { x = 5 } }");
        File.WriteAllText(Path.Combine(addOns, "Crewlog", "Stale.lua"), "old file");
        var package = tmp.Combine("pkg");
        WriteAddon(package, "0.2.0");

        Updater.InstallFromFolder(package, addOns);

        Assert.Equal("0.2.0", Updater.InstalledAddonVersion(flavor));
        Assert.False(File.Exists(Path.Combine(addOns, "Crewlog", "Stale.lua")));
        Assert.Contains("x = 5", File.ReadAllText(Path.Combine(addOns, "Crewlog_Inbox", "Data.lua")));
        Assert.False(Directory.Exists(Path.Combine(addOns, "Crewlog.crewlog-old")));
    }

    [Fact]
    public void Refuses_an_incomplete_package_and_leaves_the_install_alone()
    {
        using var tmp = new TempDir();
        var addOns = tmp.Combine("AddOns");
        WriteAddon(addOns, "0.1.0");
        var package = tmp.Combine("pkg");
        Directory.CreateDirectory(Path.Combine(package, "Crewlog"));

        Assert.Throws<InvalidDataException>(() => Updater.InstallFromFolder(package, addOns));
        Assert.Contains("v0.1.0", File.ReadAllText(Path.Combine(addOns, "Crewlog", "Core.lua")));
    }

    [Fact]
    public void Swaps_the_executable_and_keeps_an_old_copy_to_clean_up()
    {
        using var tmp = new TempDir();
        var current = tmp.Combine("Crewlog.exe");
        var staged = tmp.Combine("new.exe");
        File.WriteAllText(current, "v1");
        File.WriteAllText(staged, "v2");

        Updater.SwapExecutable(staged, current);
        Assert.Equal("v2", File.ReadAllText(current));
        Assert.Equal("v1", File.ReadAllText(current + ".old"));
        Updater.CleanupAfterUpdate(current);
        Assert.False(File.Exists(current + ".old"));
    }

    [Fact]
    public async Task Check_and_install_addon_from_a_server_verifies_the_hash()
    {
        using var tmp = new TempDir();
        var package = tmp.Combine("pkg");
        WriteAddon(package, "0.2.0");
        var zipPath = tmp.Combine("addon.zip");
        ZipFile.CreateFromDirectory(package, zipPath);
        var zipBytes = File.ReadAllBytes(zipPath);
        var flavorRoot = tmp.Combine("_forever_");
        WriteAddon(Path.Combine(flavorRoot, "Interface", "AddOns"), "0.1.0");
        var flavor = new WowFlavorFolder(flavorRoot, "_forever_", true);

        var release = new ReleaseInfo("0.1.0", "http://crewlog.test/downloads/Crewlog.exe", "00",
            "0.2.0", "http://crewlog.test/downloads/Crewlog-addon.zip", Convert.ToHexStringLower(SHA256.HashData(zipBytes)), DateTimeOffset.UtcNow, null);
        var http = new HttpClient(new FakeServer(release, zipBytes));
        var updater = new Updater(http, new ListLog());

        var status = await updater.CheckAsync("http://crewlog.test", flavor);
        Assert.NotNull(status);
        Assert.True(status.AddonUpdate);
        Assert.Equal("0.1.0", status.AddonInstalled);

        await updater.InstallAddonAsync(status.Release, flavor);
        Assert.Equal("0.2.0", Updater.InstalledAddonVersion(flavor));

        var tampered = release with { AddonSha256 = new string('0', 64) };
        await Assert.ThrowsAsync<InvalidDataException>(() => updater.InstallAddonAsync(tampered, flavor));
    }

    private sealed class FakeServer(ReleaseInfo release, byte[] zip) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var path = request.RequestUri!.AbsolutePath;
            if (path == ApiRoutes.ClientLatest)
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(JsonSerializer.Serialize(release, ServerClient.Json), Encoding.UTF8, "application/json"),
                });
            if (path.EndsWith("Crewlog-addon.zip", StringComparison.Ordinal))
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(zip) });
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
        }
    }
}
