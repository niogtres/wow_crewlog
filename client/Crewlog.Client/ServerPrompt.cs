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

    public static bool IsValid(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var u) && (u.Scheme == Uri.UriSchemeHttps || u.Scheme == Uri.UriSchemeHttp);
}
