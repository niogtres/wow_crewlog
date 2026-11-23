using System.Text;

namespace Crewlog.Client.Core;

public interface ILog
{
    void Info(string message);
    void Warn(string message);
    void Error(string message, Exception? ex = null);
}

/// <summary>Daily rolling text log in <c>%LOCALAPPDATA%\Crewlog\logs</c>, 14 days kept (DESIGN §7).</summary>
public sealed class FileLog : ILog
{
    private readonly string _dir;
    private readonly Lock _gate = new();
    public event Action<string>? Line;

    public FileLog(string dir)
    {
        _dir = dir;
        Directory.CreateDirectory(dir);
        foreach (var old in Directory.EnumerateFiles(dir, "crewlog-*.log")
                     .Where(f => File.GetLastWriteTimeUtc(f) < DateTime.UtcNow.AddDays(-14)))
        {
            try { File.Delete(old); } catch (IOException) { }
        }
    }

    public string CurrentFile => Path.Combine(_dir, $"crewlog-{DateTime.Now:yyyy-MM-dd}.log");

    public void Info(string message) => Write("INFO", message);
    public void Warn(string message) => Write("WARN", message);
    public void Error(string message, Exception? ex = null) => Write("ERROR", ex is null ? message : $"{message}: {ex}");

    private void Write(string level, string message)
    {
        var line = $"{DateTime.Now:HH:mm:ss} {level,-5} {message}";
        lock (_gate)
        {
            try { File.AppendAllText(CurrentFile, line + Environment.NewLine, Encoding.UTF8); }
            catch (IOException) { } // logging must never take the client down
        }
        Line?.Invoke(line);
    }
}

public sealed class ConsoleLog : ILog
{
    public void Info(string message) => Console.WriteLine(message);
    public void Warn(string message) => Console.WriteLine("WARN  " + message);
    public void Error(string message, Exception? ex = null) => Console.Error.WriteLine("ERROR " + message + (ex is null ? "" : ": " + ex.Message));
}

public static class AppPaths
{
    public static string Root => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Crewlog");
    public static string Logs => Path.Combine(Root, "logs");
    public static string State => Path.Combine(Root, "state.json");
    public static string Config => Path.Combine(Root, "config.json");
    public static string Token => Path.Combine(Root, "device.token");
}
