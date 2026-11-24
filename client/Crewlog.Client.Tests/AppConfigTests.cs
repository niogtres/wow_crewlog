using Crewlog.Client.Core;

namespace Crewlog.Client.Tests;

public class AppConfigTests
{
    [Theory]
    [InlineData("https://crewlog.dk")]
    [InlineData("https://crewlog.dk/")]
    [InlineData("HTTPS://crewlog.dk")]
    [InlineData("https://www.crewlog.dk")]
    public void A_saved_former_server_address_moves_to_the_current_one_and_is_saved(string former)
    {
        var dir = Directory.CreateTempSubdirectory("crewlog-config").FullName;
        try
        {
            var path = Path.Combine(dir, "config.json");
            new AppConfig { ServerUrl = former, LinkedAs = "Mossbeard" }.Save(path);

            var loaded = AppConfig.Load(path);
            Assert.Equal("https://crewlog.dk", loaded.ServerUrl);
            Assert.Equal("Mossbeard", loaded.LinkedAs);
            Assert.Contains("https://crewlog.dk", File.ReadAllText(path)); // written back, so it happens once
        }
        finally { Directory.Delete(dir, recursive: true); }
    }

    [Theory]
    [InlineData("http://192.168.0.10:8080")]
    [InlineData("http://localhost:5180")]
    [InlineData("https://crewlog.dk")]
    public void Any_other_server_address_is_left_alone(string url)
    {
        var config = new AppConfig { ServerUrl = url };
        Assert.False(config.MoveFromFormerServer());
        Assert.Equal(url, config.ServerUrl);
    }
}
