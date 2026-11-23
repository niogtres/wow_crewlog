using System.Diagnostics;
using Crewlog.Client.Core.Server;
using Crewlog.Contracts;

namespace Crewlog.Client;

/// <summary>
/// Which of my toons are in which journal (DESIGN §7): one row per toon, one checkbox column per journal.
/// A tick attaches the toon at once; journals are created and joined on the website.
/// </summary>
internal sealed class JournalsWindow : Form
{
    private readonly ServerClient _api;
    private readonly string _site;
    private readonly DataGridView _grid = new()
    {
        Dock = DockStyle.Fill,
        AllowUserToAddRows = false,
        AllowUserToDeleteRows = false,
        AllowUserToResizeRows = false,
        RowHeadersVisible = false,
        SelectionMode = DataGridViewSelectionMode.CellSelect,
        AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.AllCells,
        BackgroundColor = SystemColors.Window,
        BorderStyle = BorderStyle.None,
        EditMode = DataGridViewEditMode.EditOnEnter,
    };
    private readonly Label _status = new() { Dock = DockStyle.Bottom, Height = 28, TextAlign = ContentAlignment.MiddleLeft, Padding = new Padding(8, 0, 0, 0) };
    private JournalsResponse? _data;
    private bool _loading;

    public JournalsWindow(ServerClient api, string site, Icon? icon)
    {
        _api = api;
        _site = site.TrimEnd('/');
        Text = "Crewlog · Journals";
        Icon = icon;
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(460, 300);
        Size = new Size(640, 380);
        Font = SystemFonts.MessageBoxFont ?? Font;

        var intro = new Label
        {
            Dock = DockStyle.Top, Height = 48, Padding = new Padding(8, 8, 8, 0),
            Text = "Tick a box to add a toon to a journal. Everyone in that journal sees what the toon is on. " +
                   "Create or join journals on the website.",
        };
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 44, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(4) };
        var close = new Button { Text = "Close", AutoSize = true, DialogResult = DialogResult.OK };
        var web = new Button { Text = "Open journals on the website", AutoSize = true };
        var refresh = new Button { Text = "Refresh", AutoSize = true };
        close.Click += (_, _) => Close();
        web.Click += (_, _) => Open(_site + "/home#journals-title");
        refresh.Click += async (_, _) => await LoadAsync();
        buttons.Controls.AddRange([close, web, refresh]);
        CancelButton = close;

        _grid.CurrentCellDirtyStateChanged += (_, _) => { if (_grid.IsCurrentCellDirty) _grid.CommitEdit(DataGridViewDataErrorContexts.Commit); };
        _grid.CellValueChanged += async (_, e) => await Toggle(e.RowIndex, e.ColumnIndex);
        _grid.ColumnHeaderMouseClick += (_, e) =>
        {
            if (_grid.Columns[e.ColumnIndex].Tag is JournalInfo j) Open(j.Url);
        };

        Controls.Add(_grid);
        Controls.Add(intro);
        Controls.Add(_status);
        Controls.Add(buttons);
        Shown += async (_, _) => await LoadAsync();
    }

    private async Task LoadAsync()
    {
        _status.Text = "Loading…";
        try
        {
            _data = await _api.JournalsAsync();
        }
        catch (Exception ex) when (ex is ServerException or HttpRequestException or TaskCanceledException)
        {
            _status.Text = ex.Message;
            return;
        }

        _loading = true;
        _grid.Columns.Clear();
        _grid.Rows.Clear();
        _grid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Toon", ReadOnly = true, Frozen = true });
        foreach (var j in _data.Journals)
            _grid.Columns.Add(new DataGridViewCheckBoxColumn
            {
                HeaderText = j.Title + (j.IsOwner ? "" : $"\n({j.OwnerName})"),
                ToolTipText = $"Click the title to open {j.Title} on the website",
                Tag = j,
            });
        foreach (var t in _data.Toons)
        {
            var row = new List<object> { $"{t.Name}  ·  {t.Level} {t.Class}" };
            row.AddRange(_data.Journals.Select(j => (object)j.Attached.Contains(t.Guid)));
            var i = _grid.Rows.Add([.. row]);
            _grid.Rows[i].Tag = t;
        }
        _loading = false;

        _status.Text = (_data.Journals.Count, _data.Toons.Count) switch
        {
            (0, _) => "You're not in any journal yet. Create one or join with a key on the website.",
            (_, 0) => "No toons synced yet. Play a little and click the compass on the minimap.",
            _ => $"{_data.Toons.Count} toon(s), {_data.Journals.Count} journal(s). Changes are saved straight away.",
        };
    }

    private async Task Toggle(int row, int col)
    {
        if (_loading || row < 0 || col < 1) return;
        if (_grid.Rows[row].Tag is not ToonInfo toon || _grid.Columns[col].Tag is not JournalInfo journal) return;
        var on = _grid.Rows[row].Cells[col].Value is true;
        _grid.Enabled = false;
        try
        {
            await _api.SetAttachedAsync(journal.Id, toon.Guid, on);
            _status.Text = on ? $"{toon.Name} added to {journal.Title}." : $"{toon.Name} taken out of {journal.Title}.";
        }
        catch (Exception ex) when (ex is ServerException or HttpRequestException or TaskCanceledException)
        {
            _status.Text = ex.Message;
            _loading = true;
            _grid.Rows[row].Cells[col].Value = !on;
            _loading = false;
        }
        finally
        {
            _grid.Enabled = true;
        }
    }

    private static void Open(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { /* no browser */ }
    }
}
