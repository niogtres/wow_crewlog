namespace Crewlog.Client;

/// <summary>Tiny dialog to change the server address (e.g. a LAN test server before the public site is live).</summary>
internal sealed class ServerPrompt : Form
{
    private readonly TextBox _url = new() { Dock = DockStyle.Top, Font = new Font("Segoe UI", 11f) };

    public string Url => _url.Text.Trim().TrimEnd('/');

    public ServerPrompt(string current)
    {
        Text = "Crewlog server";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(460, 150);
        Padding = new Padding(16);
        _url.Text = current;

        var hint = new Label
        {
            Dock = DockStyle.Top,
            Height = 46,
            Text = "Server address. Normally https://crewlog.dk. For a test on your own network, e.g. http://192.168.0.10:8080.",
        };
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, FlowDirection = FlowDirection.RightToLeft, Height = 40 };
        var ok = new Button { Text = "Save", DialogResult = DialogResult.OK, AutoSize = true };
        var cancel = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel, AutoSize = true };
        buttons.Controls.AddRange([ok, cancel]);
        AcceptButton = ok;
        CancelButton = cancel;
        Controls.AddRange([buttons, _url, hint]);
    }

    /// <summary>https anywhere; plain http only on this PC or the local network (a home server), where nobody on the
    /// way can read the sign-in token or change what the app downloads.</summary>
    public static bool IsValid(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var u) && (u.Scheme == Uri.UriSchemeHttps || (u.Scheme == Uri.UriSchemeHttp && IsLocal(u)));

    private static bool IsLocal(Uri u)
    {
        if (u.IsLoopback || !u.Host.Contains('.')) return true;
        if (!System.Net.IPAddress.TryParse(u.Host, out var ip) || ip.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork) return false;
        var b = ip.GetAddressBytes();
        return b[0] == 10 || (b[0] == 172 && b[1] is >= 16 and <= 31) || (b[0] == 192 && b[1] == 168);
    }

    /// <summary>Whether an address the server sent (a link page, a journal) is on that server: the app opens nothing else.</summary>
    public static bool IsOnServer(string? url, string serverUrl) =>
        Uri.TryCreate(url, UriKind.Absolute, out var u) && Uri.TryCreate(serverUrl, UriKind.Absolute, out var s)
            && (u.Scheme == Uri.UriSchemeHttps || u.Scheme == Uri.UriSchemeHttp)
            && string.Equals(u.Host, s.Host, StringComparison.OrdinalIgnoreCase);
}
