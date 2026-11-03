using System.Text.Json.Nodes;

namespace PocketLauncher;

/// <summary>
/// The list of mod indexes the Find mods tab reads: upstream's built-in one, which
/// cannot be removed, and any the player adds by GitHub owner/repo or web address.
/// Other people's indexes do not get the official one's release scan or blocklist, so
/// adding one says so first.
/// </summary>
internal sealed class ModSourcesForm : Form
{
    private readonly Func<string, JsonObject?, Task<JsonObject>> ask;
    private readonly ListBox sourcesList = new();
    private readonly TextBox addressBox = new();
    private readonly Button addButton = new();
    private readonly Button removeButton = new();
    private readonly Label status = new();

    /// <summary>True once the list of indexes has changed.</summary>
    public bool Changed { get; private set; }

    /// <param name="ask">Sends one mod backend command; throws if the backend refuses.</param>
    public ModSourcesForm(Func<string, JsonObject?, Task<JsonObject>> ask)
    {
        this.ask = ask;
        Text = "Mod indexes";
        AutoScaleMode = AutoScaleMode.Dpi;
        StartPosition = FormStartPosition.CenterParent;
        ClientSize = new Size(620, 340);
        MinimumSize = new Size(440, 300);
        MinimizeBox = MaximizeBox = false;

        sourcesList.AccessibleName = "Mod indexes";
        sourcesList.Dock = DockStyle.Fill;
        sourcesList.IntegralHeight = false;
        sourcesList.SelectedIndexChanged += (_, _) => UpdateRemoveButton();

        addressBox.AccessibleName = "Address of an index to add";
        addressBox.Dock = DockStyle.Fill;
        addressBox.TextChanged += (_, _) => addButton.Enabled = addressBox.Text.Trim() != "";

        addButton.Text = "&Add";
        addButton.AutoSize = true;
        addButton.Enabled = false;
        addButton.Click += async (_, _) => await AddAsync();
        removeButton.Text = "&Remove selected";
        removeButton.AutoSize = true;
        removeButton.Enabled = false;
        removeButton.Click += async (_, _) => await RemoveAsync();
        var close = new Button { Text = "&Close", AutoSize = true, DialogResult = DialogResult.Cancel };
        CancelButton = close;
        AcceptButton = addButton;

        var buttons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        buttons.Controls.AddRange([addButton, removeButton, close]);

        status.AutoSize = true;
        status.AccessibleName = "Status";

        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 6, Padding = new Padding(12) };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        var rows = new (Control Control, bool Stretch)[]
        {
            (new Label { Text = "&Indexes:", AutoSize = true }, false),
            (sourcesList, true),
            (new Label { Text = "A&ddress to add, as owner/repo or a web address:", AutoSize = true }, false),
            (addressBox, false),
            (buttons, false),
            (status, false),
        };
        foreach (var (control, stretch) in rows)
        {
            layout.RowStyles.Add(stretch ? new RowStyle(SizeType.Percent, 100) : new RowStyle(SizeType.AutoSize));
            layout.Controls.Add(control);
        }
        Controls.Add(layout);
        ActiveControl = sourcesList;
        Shown += async (_, _) => await RefreshAsync();
    }

    private sealed record SourceRow(string Label, string Feed, bool BuiltIn)
    {
        public override string ToString() => BuiltIn ? $"{Label}, official" : Label;
    }

    private void UpdateRemoveButton() =>
        removeButton.Enabled = sourcesList.SelectedItem is SourceRow { BuiltIn: false };

    private async Task RefreshAsync()
    {
        try
        {
            JsonObject response = await ask("sources", null);
            sourcesList.Items.Clear();
            foreach (JsonObject row in (response["sources"] as JsonArray ?? []).OfType<JsonObject>())
            {
                sourcesList.Items.Add(new SourceRow(row["label"]?.ToString() ?? "", row["feed"]?.ToString() ?? "",
                                                    row["builtIn"]?.GetValue<bool>() == true));
            }
            if (sourcesList.Items.Count > 0) sourcesList.SelectedIndex = 0;
            UpdateRemoveButton();
        }
        catch (Exception error) when (error is InvalidOperationException or IOException)
        {
            status.Text = error.Message;
        }
    }

    private async Task AddAsync()
    {
        string address = addressBox.Text.Trim();
        if (address == "") return;
        DialogResult answer = MessageBox.Show(this,
            "Other indexes are run by other people. The official index scans releases and blocks some mods and " +
            "authors; another index may not. Only add one you trust. Add it?",
            "Add index", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
        if (answer != DialogResult.Yes) return;
        try
        {
            JsonObject response = await ask("addSource", new JsonObject { ["input"] = address });
            Changed = true;
            addressBox.Clear();
            await RefreshAsync();
            status.Text = $"{response["label"]} added.";
            sourcesList.Focus();
        }
        catch (Exception error) when (error is InvalidOperationException or IOException)
        {
            status.Text = "Not added.";
            MessageBox.Show(this, error.Message, "Add index", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private async Task RemoveAsync()
    {
        if (sourcesList.SelectedItem is not SourceRow { BuiltIn: false } row) return;
        try
        {
            await ask("removeSource", new JsonObject { ["feed"] = row.Feed });
            Changed = true;
            await RefreshAsync();
            status.Text = $"{row.Label} removed. Mods you installed from it stay installed.";
            sourcesList.Focus();
        }
        catch (Exception error) when (error is InvalidOperationException or IOException)
        {
            MessageBox.Show(this, error.Message, "Remove index", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
