namespace Crewlog.Client;

internal static class Program
{
    public const string ShowEventName = @"Local\Crewlog.Client.ShowStatus";

    [STAThread]
    private static void Main(string[] args)
    {
        // Velopack: install/update/uninstall hooks run (and exit) here, before anything else.
        AppInstall.Bootstrap();

        // After a self-update the old process is still exiting; wait for it before taking the single-instance lock.
        if (args is ["--after-update", var pidText] && int.TryParse(pidText, out var pid))
        {
            try { System.Diagnostics.Process.GetProcessById(pid).WaitForExit(15_000); }
            catch (ArgumentException) { } // already gone
        }


        // A portable copy from before the installer moves itself to the installed app, then steps aside.
        var config = Core.AppConfig.Load(Core.AppPaths.Config);
        if (AppInstall.MoveToInstaller(config, new Core.FileLog(Core.AppPaths.Logs))) return;

        // One tray icon per Windows user. Starting it again shows the running copy's status window instead.
        using var single = new Mutex(initiallyOwned: true, @"Local\Crewlog.Client", out var isFirst);
        using var show = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
        if (!isFirst)
        {
            show.Set();
            return;
        }

        ApplicationConfiguration.Initialize();
        // Started at Windows login (the Run entry adds --autostart): stay quiet in the tray. Started by hand or right
        // after installing: open the status window so it's clear Crewlog is running and what's left to do.
        var autostart = args.Contains("--autostart", StringComparer.OrdinalIgnoreCase);
        Application.Run(new TrayApp(showStatus: !autostart || AppInstall.FirstRun, show));
    }
}
