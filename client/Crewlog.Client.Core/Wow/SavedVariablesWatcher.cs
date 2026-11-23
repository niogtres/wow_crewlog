namespace Crewlog.Client.Core.Wow;

/// <summary>
/// Watches <c>WTF\Account\*\SavedVariables\Crewlog.lua</c> under one flavor folder. WoW writes the file in
/// several passes on /reload and logout, so changes are debounced (DESIGN §7: 2 s) before <see cref="Changed"/> fires.
/// </summary>
public sealed class SavedVariablesWatcher : IDisposable
{
    public const string FileName = "Crewlog.lua";

    private readonly FileSystemWatcher _fsw;
    private readonly TimeSpan _debounce;
    private readonly Lock _gate = new();
    private readonly Dictionary<string, Timer> _pending = new(StringComparer.OrdinalIgnoreCase);
    private bool _disposed;

    /// <summary>Fires on a thread-pool thread with the full path of the settled file.</summary>
    public event Action<string>? Changed;

    public string WtfAccountPath { get; }

    public SavedVariablesWatcher(WowFlavorFolder flavor, TimeSpan? debounce = null)
    {
        WtfAccountPath = flavor.WtfAccountPath;
        Directory.CreateDirectory(WtfAccountPath);
        _debounce = debounce ?? TimeSpan.FromSeconds(2);
        _fsw = new FileSystemWatcher(WtfAccountPath, FileName)
        {
            IncludeSubdirectories = true,
            NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.Size,
            InternalBufferSize = 64 * 1024,
        };
        _fsw.Changed += (_, e) => Schedule(e.FullPath);
        _fsw.Created += (_, e) => Schedule(e.FullPath);
        _fsw.Renamed += (_, e) => Schedule(e.FullPath);
        _fsw.Error += (_, _) => RescanAll();
    }

    public void Start() => _fsw.EnableRaisingEvents = true;

    /// <summary>Raise <see cref="Changed"/> for every existing file, e.g. at startup or after a watcher overflow.</summary>
    public void RescanAll()
    {
        if (!Directory.Exists(WtfAccountPath)) return;
        foreach (var account in Directory.EnumerateDirectories(WtfAccountPath))
        {
            var file = Path.Combine(account, "SavedVariables", FileName);
            if (File.Exists(file)) Schedule(file);
        }
    }

    private void Schedule(string path)
    {
        // Exactly Crewlog.lua: WoW renames the previous save to Crewlog.lua.bak, which also raises events.
        if (!string.Equals(Path.GetFileName(path), FileName, StringComparison.OrdinalIgnoreCase)) return;
        // Only the account-wide SavedVariables folder counts; WoW also keeps per-character copies elsewhere.
        if (!string.Equals(Path.GetFileName(Path.GetDirectoryName(path)), "SavedVariables", StringComparison.OrdinalIgnoreCase)) return;
        lock (_gate)
        {
            if (_disposed) return;
            if (_pending.TryGetValue(path, out var t))
            {
                t.Change(_debounce, Timeout.InfiniteTimeSpan);
                return;
            }
            _pending[path] = new Timer(_ => Fire(path), null, _debounce, Timeout.InfiniteTimeSpan);
        }
    }

    private void Fire(string path)
    {
        lock (_gate)
        {
            if (_pending.Remove(path, out var t)) t.Dispose();
            if (_disposed) return;
        }
        if (File.Exists(path)) Changed?.Invoke(path);
    }

    public void Dispose()
    {
        lock (_gate)
        {
            _disposed = true;
            foreach (var t in _pending.Values) t.Dispose();
            _pending.Clear();
        }
        _fsw.Dispose();
    }
}
