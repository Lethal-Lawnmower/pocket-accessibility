using System.Text.Json.Nodes;

namespace PocketLauncher;

/// <summary>
/// The save editor window: standard tabs, lists, text boxes and buttons, read by
/// the screen reader like any Windows program.  It holds no save logic; each tab
/// is a PagePanel showing what the backend describes.  Save, Undo and Redo are
/// buttons with the usual Ctrl+S, Ctrl+Z and Ctrl+Y.
/// </summary>
internal sealed class SaveEditorForm : Form
{
    private readonly Game game;
    private readonly SaveBackendClient backend;
    private readonly TabControl tabs = new() { Dock = DockStyle.Fill, AccessibleName = "Pages" };
    private readonly Button saveButton = new();
    private readonly Button undoButton = new();
    private readonly Button redoButton = new();
    private readonly Button reloadButton = new();
    private readonly Button closeButton = new();
    private readonly Label status = new()
    {
        AutoSize = true,
        Dock = DockStyle.Bottom,
        Padding = new Padding(0, 6, 0, 0),
        // read out when it changes, without moving focus
        LiveSetting = System.Windows.Forms.Automation.AutomationLiveSetting.Polite,
    };
    private bool dirty;
    private bool closingConfirmed;

    public SaveEditorForm(GamePaths paths, Game game)
    {
        this.game = game;
        backend = new SaveBackendClient(paths);
        Text = $"Loading the {game.Name} save";
        AutoScaleMode = AutoScaleMode.Dpi;
        StartPosition = FormStartPosition.CenterParent;
        ClientSize = new Size(860, 680);
        MinimumSize = new Size(560, 420);
        Padding = new Padding(10);
        KeyPreview = true;

        ConfigureButton(saveButton, "&Save", SaveAsync);
        ConfigureButton(undoButton, "&Undo", () => HistoryAsync("undo"));
        ConfigureButton(redoButton, "Re&do", () => HistoryAsync("redo"));
        ConfigureButton(reloadButton, "Re&load from disk", ReloadAsync);
        ConfigureButton(closeButton, "&Close", () => { Close(); return Task.CompletedTask; });
        var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, WrapContents = true };
        buttons.Controls.AddRange([saveButton, undoButton, redoButton, reloadButton, closeButton]);

        Controls.Add(tabs);
        Controls.Add(status);
        Controls.Add(buttons);
        tabs.SelectedIndexChanged += async (_, _) => await ShowCurrentPageAsync();
        KeyDown += OnKeyDown;
        Shown += async (_, _) => await OpenAsync();
        FormClosing += OnFormClosing;
        FormClosed += (_, _) => backend.Dispose();
        SetButtonsEnabled(false);
        status.Text = "Loading. This can take a few seconds.";
    }

    private void ConfigureButton(Button button, string text, Func<Task> action)
    {
        button.Text = text;
        button.AutoSize = true;
        button.Click += async (_, _) => await action();
    }

    private void SetButtonsEnabled(bool enabled)
    {
        saveButton.Enabled = undoButton.Enabled = redoButton.Enabled = reloadButton.Enabled = enabled;
    }

    private async Task OpenAsync()
    {
        JsonObject opened;
        try
        {
            await backend.StartAsync();
            opened = await backend.SendAsync("open", new JsonObject { ["version"] = game.Id });
        }
        catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception or IOException)
        {
            Fail($"The save editor could not start: {error.Message}");
            return;
        }
        if (opened["ok"]?.GetValue<bool>() != true)
        {
            Fail($"The save could not be opened: {opened["error"]}");
            return;
        }
        if (opened["missingCache"] is JsonNode missing)
        {
            Fail(missing.ToString());
            return;
        }
        Text = opened["title"]?.ToString() ?? game.Name;
        if (opened["corrupt"] != null)
        {
            ShowMessage($"This save could not be read, so saving is turned off. {opened["status"]}", MessageBoxIcon.Warning);
        }
        foreach (var page in opened["pages"]?.AsArray() ?? [])
        {
            string id = page!["id"]!.ToString();
            var tab = new TabPage(page["label"]!.ToString()) { Name = id, AccessibleName = page["label"]!.ToString() };
            tab.Controls.Add(new PagePanel(id, RunAsync, ShowMessage) { Dock = DockStyle.Fill });
            tabs.TabPages.Add(tab);
        }
        ApplyStatus(opened, announce: false);
        status.Text = $"Editing {opened["path"]}";
        await ShowCurrentPageAsync();
        tabs.Focus();
    }

    private void Fail(string message)
    {
        ShowMessage(message, MessageBoxIcon.Error);
        closingConfirmed = true;
        Close();
    }

    private PagePanel? CurrentPanel => tabs.SelectedTab?.Controls.OfType<PagePanel>().FirstOrDefault();

    private async Task ShowCurrentPageAsync()
    {
        if (CurrentPanel is PagePanel panel) await panel.RefreshAsync();
    }

    /// <summary>Every command goes through here: it sends, then reports what came back.</summary>
    private async Task<JsonObject> RunAsync(string command, JsonObject? arguments)
    {
        JsonObject response;
        try
        {
            response = await backend.SendAsync(command, arguments);
        }
        catch (Exception error) when (error is InvalidOperationException or IOException or ObjectDisposedException)
        {
            if (!IsDisposed) ShowMessage($"The save editor stopped: {error.Message}", MessageBoxIcon.Error);
            return new JsonObject { ["ok"] = false };
        }
        if (IsDisposed) return response;
        if (response["ok"]?.GetValue<bool>() != true)
        {
            ShowMessage($"That did not work: {FirstLine(response["error"]?.ToString())}", MessageBoxIcon.Error);
        }
        ApplyStatus(response, announce: true);
        return response;
    }

    private static string FirstLine(string? text) => (text ?? "unknown error").Split('\n')[0];

    private void ApplyStatus(JsonObject response, bool announce)
    {
        if (response["dirty"] is JsonNode isDirty) dirty = isDirty.GetValue<bool>();
        // A disabled focused button would drop the keyboard focus, so these stay
        // enabled and simply answer "nothing to do".
        SetButtonsEnabled(true);
        string title = Text.TrimEnd(' ', '*');
        Text = dirty ? title + " *" : title;
        if (announce && response["message"] is JsonNode message)
        {
            string text = message.ToString();
            status.Text = text;
            if (response["messageKind"]?.ToString() == "error") ShowMessage(text, MessageBoxIcon.Warning);
        }
    }

    private async Task SaveAsync()
    {
        await RunAsync("save", null);
    }

    private async Task HistoryAsync(string command)
    {
        var response = await RunAsync(command, null);
        if (response["changed"]?.GetValue<bool>() == true) await ShowCurrentPageAsync();
    }

    private async Task ReloadAsync()
    {
        if (dirty && MessageBox.Show(this, "Discard your unsaved changes and reload the save from disk?",
                "Reload", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
        {
            return;
        }
        await RunAsync("reload", null);
        await ShowCurrentPageAsync();
    }

    private async void OnKeyDown(object? sender, KeyEventArgs e)
    {
        Func<Task>? action = (e.Control, e.Shift, e.KeyCode) switch
        {
            (true, false, Keys.S) => SaveAsync,
            (true, false, Keys.Z) => () => HistoryAsync("undo"),
            (true, false, Keys.Y) => () => HistoryAsync("redo"),
            (true, true, Keys.Z) => () => HistoryAsync("redo"),
            _ => null,
        };
        if (action == null) return;
        e.Handled = e.SuppressKeyPress = true;
        // a value still being typed counts
        if (CurrentPanel is PagePanel panel) await panel.CommitPendingAsync();
        await action();
    }

    private async void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        if (closingConfirmed) return;
        // Asking the backend takes a moment, so hold the close, then finish it.
        e.Cancel = true;
        if (CurrentPanel is PagePanel panel) await panel.CommitPendingAsync();
        if (dirty)
        {
            var answer = MessageBox.Show(this, "Save your changes before closing?", Text.TrimEnd(' ', '*'),
                MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
            if (answer == DialogResult.Cancel) return;
            if (answer == DialogResult.Yes)
            {
                var saved = await RunAsync("save", null);
                if (saved["saved"]?.GetValue<bool>() != true) return;
            }
        }
        closingConfirmed = true;
        Close();
    }

    private void ShowMessage(string text, MessageBoxIcon icon) =>
        MessageBox.Show(this, text, "Save editor", MessageBoxButtons.OK, icon);
}
