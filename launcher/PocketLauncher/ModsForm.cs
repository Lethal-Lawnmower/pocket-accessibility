using System.Text;
using System.Text.Json.Nodes;

namespace PocketLauncher;

/// <summary>
/// The Mods window: an Installed tab (a checked list, one game's on and off) and a
/// Find mods tab over upstream's community index.  Only standard controls with
/// explicit accessible names; each list has a read-only details box after it, which
/// a screen reader can read line by line.  The Find mods tab also installs a zip the
/// player chose and manages other indexes.  Listings and enable-state come from
/// launcher/ModBackend; docs/access/launcher.md holds the protocol.
/// </summary>
internal sealed class ModsForm : Form
{
    private const string WarningAcceptedFile = "pocket-access-mods-warning-accepted";

    private readonly GamePaths paths;
    private readonly Game game;
    private readonly BackendClient backend;
    private readonly TabControl tabs = new();
    private readonly CheckedListBox installedList = new();
    private readonly TextBox installedDetails = new();
    private readonly Button removeButton = new();
    private readonly TextBox searchBox = new();
    private readonly CheckBox thisGameOnly = new();
    private readonly ListBox foundList = new();
    private readonly TextBox foundDetails = new();
    private readonly Button installButton = new();
    private readonly Button refreshButton = new();
    private readonly Button zipButton = new();
    private readonly Button indexesButton = new();
    private readonly ToolStripStatusLabel status = new();
    private List<JsonObject> indexRows = [];
    private bool installing;
    private bool closed;
    private bool fillingInstalled;

    /// <summary>
    /// The warning, the first time this profile opens Mods; false if the player backs out.
    /// </summary>
    public static bool ConfirmWarning(IWin32Window owner, GamePaths paths)
    {
        string marker = Path.Combine(paths.SaveDir, WarningAcceptedFile);
        if (File.Exists(marker)) return true;
        DialogResult answer = MessageBox.Show(owner,
            "Mods are not endorsed or tested by Pocket Accessibility. Accessibility may break, " +
            "so use them at your own risk. Mods are other people's code, and they run on your computer.",
            "Mods", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning);
        if (answer != DialogResult.OK) return false;
        Directory.CreateDirectory(paths.SaveDir);
        File.WriteAllText(marker, "");
        return true;
    }

    public ModsForm(GamePaths paths, Game game)
    {
        this.paths = paths;
        this.game = game;
        backend = new BackendClient(paths, paths.ModBackendDir, "mod list");

        Text = $"Mods for {game.Name}";
        AutoScaleMode = AutoScaleMode.Dpi;
        StartPosition = FormStartPosition.CenterParent;
        ClientSize = new Size(760, 560);
        MinimumSize = new Size(520, 480);
        MinimizeBox = false;

        tabs.Dock = DockStyle.Fill;
        tabs.AccessibleName = "Mods";
        tabs.TabPages.Add(BuildInstalledPage());
        tabs.TabPages.Add(BuildFindPage());

        var close = new Button { Text = "&Close", AutoSize = true, Dock = DockStyle.Bottom, DialogResult = DialogResult.Cancel };
        CancelButton = close;

        // Named, or UI Automation names the bar after the control above it.
        var statusStrip = new StatusStrip { SizingGrip = false, AccessibleName = "Status" };
        status.Spring = true;
        status.TextAlign = ContentAlignment.MiddleLeft;
        statusStrip.Items.Add(status);

        Controls.Add(tabs);
        Controls.Add(close);
        Controls.Add(statusStrip);
        ActiveControl = tabs;

        Shown += async (_, _) => await LoadEverythingAsync();
        FormClosing += (_, args) =>
        {
            if (!installing) return;
            args.Cancel = true;
            status.Text = "Please wait for the install to finish.";
        };
        FormClosed += (_, _) =>
        {
            closed = true;
            backend.Dispose();
        };
    }

    private TabPage BuildInstalledPage()
    {
        installedList.AccessibleName = "Installed mods";
        // Space toggles.  Never on selection: arrowing down the list must not change mods.
        installedList.CheckOnClick = false;
        installedList.Dock = DockStyle.Fill;
        installedList.IntegralHeight = false;
        installedList.SelectedIndexChanged += (_, _) => ShowInstalledDetails();
        installedList.ItemCheck += async (_, args) => await InstalledCheckChangedAsync(args);

        ConfigureDetails(installedDetails, "Details of the selected mod");
        removeButton.Text = "&Remove";
        removeButton.AutoSize = true;
        removeButton.Click += (_, _) => RemoveSelected();

        var page = new TabPage("Installed");
        page.Controls.Add(NewPageLayout(
            (new Label { Text = $"&Installed mods. Checked means on for {game.Name}:", AutoSize = true }, 0),
            (installedList, 60),
            (new Label { Text = "Details:", AutoSize = true }, 0),
            (installedDetails, 40),
            (removeButton, 0)));
        return page;
    }

    private TabPage BuildFindPage()
    {
        searchBox.AccessibleName = "Search mods";
        searchBox.Dock = DockStyle.Fill;
        searchBox.TextChanged += (_, _) => FillFound();

        thisGameOnly.Text = $"&Only mods that could be for {game.Name}";
        thisGameOnly.AutoSize = true;
        thisGameOnly.Checked = true;
        thisGameOnly.CheckedChanged += (_, _) => FillFound();

        foundList.AccessibleName = "Mods in the index";
        foundList.Dock = DockStyle.Fill;
        foundList.IntegralHeight = false;
        foundList.SelectedIndexChanged += (_, _) => ShowFoundDetails();

        ConfigureDetails(foundDetails, "Details of the selected listing");
        installButton.Text = "I&nstall";
        installButton.AutoSize = true;
        installButton.Click += async (_, _) => await InstallSelectedAsync();
        refreshButton.Text = "Re&fresh list";
        refreshButton.AutoSize = true;
        refreshButton.Click += async (_, _) => await LoadIndexAsync(force: true);

        zipButton.Text = "From &zip file...";
        zipButton.AutoSize = true;
        zipButton.Click += async (_, _) => await InstallZipAsync();
        indexesButton.Text = "In&dexes...";
        indexesButton.AutoSize = true;
        indexesButton.Click += async (_, _) => await ManageIndexesAsync();

        var buttons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        buttons.Controls.AddRange([installButton, zipButton, refreshButton, indexesButton]);

        var page = new TabPage("Find mods");
        page.Controls.Add(NewPageLayout(
            (new Label { Text = "&Search:", AutoSize = true }, 0),
            (searchBox, 0),
            (thisGameOnly, 0),
            (new Label { Text = "&Mods in the community index:", AutoSize = true }, 0),
            (foundList, 55),
            (new Label { Text = "Details:", AutoSize = true }, 0),
            (foundDetails, 45),
            (buttons, 0)));
        return page;
    }

    /// <summary>
    /// One column, in tab order.  A row with a share takes that percent of the space left
    /// over and the others keep their own height, so the buttons stay on the page at any size.
    /// </summary>
    private static TableLayoutPanel NewPageLayout(params (Control Control, int Share)[] rows)
    {
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = rows.Length, Padding = new Padding(8) };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        foreach (var (control, share) in rows)
        {
            layout.RowStyles.Add(share > 0 ? new RowStyle(SizeType.Percent, share) : new RowStyle(SizeType.AutoSize));
            layout.Controls.Add(control);
        }
        return layout;
    }

    private static void ConfigureDetails(TextBox box, string name)
    {
        box.Multiline = true;
        box.ReadOnly = true;
        box.ScrollBars = ScrollBars.Vertical;
        box.Dock = DockStyle.Fill;
        box.AccessibleName = name;
    }

    private static string? TextOf(JsonObject row, string key) => row[key] is JsonValue value ? value.ToString() : null;

    private static bool Flag(JsonObject row, string key) =>
        row[key] is JsonValue value && value.TryGetValue(out bool flag) && flag;

    private static IEnumerable<string> Strings(JsonObject row, string key) =>
        row[key] is JsonArray list ? list.Select(item => item?.ToString() ?? "") : [];

    private static List<JsonObject> Rows(JsonObject response, string key) =>
        response[key] is JsonArray list ? list.OfType<JsonObject>().ToList() : [];

    private async Task<JsonObject> AskAsync(string command, JsonObject? arguments = null)
    {
        JsonObject response = await backend.SendAsync(command, arguments);
        if (!Flag(response, "ok")) throw new InvalidOperationException(TextOf(response, "error") ?? "The mod list did not answer.");
        return response;
    }

    private async Task LoadEverythingAsync()
    {
        try
        {
            status.Text = "Loading.";
            await backend.StartAsync();
            await LoadInstalledAsync();
            await LoadIndexAsync(force: false);
        }
        catch (Exception error) when (error is InvalidOperationException or IOException)
        {
            if (!closed) ShowMessage(error.Message, MessageBoxIcon.Error);
        }
    }

    private async Task LoadInstalledAsync()
    {
        JsonObject response = await AskAsync("installed", new JsonObject { ["version"] = game.Id });
        if (closed) return;
        string? selected = (installedList.SelectedItem as InstalledRow)?.Folder;
        fillingInstalled = true;
        installedList.BeginUpdate();
        installedList.Items.Clear();
        foreach (JsonObject row in Rows(response, "mods"))
        {
            installedList.Items.Add(new InstalledRow(row, game.Name), Flag(row, "enabled"));
        }
        installedList.EndUpdate();
        int index = installedList.Items.Cast<InstalledRow>().ToList().FindIndex(row => row.Folder == selected);
        if (installedList.Items.Count > 0) installedList.SelectedIndex = Math.Max(0, index);
        fillingInstalled = false;
        ShowInstalledDetails();
    }

    private async Task LoadIndexAsync(bool force)
    {
        status.Text = "Getting the community mod list.";
        refreshButton.Enabled = false;
        try
        {
            JsonObject response = await AskAsync("index", new JsonObject { ["version"] = game.Id, ["force"] = force });
            if (closed) return;
            indexRows = Rows(response, "mods");
            FillFound();
            string problems = string.Join(" ", Strings(response, "problems"));
            status.Text = indexRows.Count == 0 ? $"The community mod list could not be read. {problems}"
                : Flag(response, "stale") ? $"{indexRows.Count} mods, from a saved copy: the list could not be refreshed."
                : $"{indexRows.Count} mods in the community list. {problems}".TrimEnd();
        }
        catch (Exception error) when (error is InvalidOperationException or IOException)
        {
            if (!closed) status.Text = $"The community mod list could not be read. {error.Message}";
        }
        finally
        {
            if (!closed) refreshButton.Enabled = true;
        }
    }

    private void ShowInstalledDetails()
    {
        if (installedList.SelectedItem is not InstalledRow selected)
        {
            installedDetails.Text = "";
            removeButton.Enabled = false;
            return;
        }
        JsonObject row = selected.Row;
        var text = new StringBuilder();
        if (TextOf(row, "problem") is string problem) text.AppendLine($"The game will not load this mod: {problem}");
        if (TextOf(row, "version") is string version) text.AppendLine($"Version {version}");
        if (TextOf(row, "author") is string author) text.AppendLine($"By {author}");
        if (TextOf(row, "games") is string games) text.AppendLine($"For: {games}");
        if (TextOf(row, "description") is string description) text.AppendLine(description);
        string permissions = string.Join(", ", Strings(row, "permissions"));
        if (permissions != "") text.AppendLine($"Permissions: {permissions}");
        if (!Flag(row, "removable")) text.AppendLine("Comes with the game, so it cannot be removed here.");
        installedDetails.Text = text.ToString().TrimEnd();
        removeButton.Enabled = Flag(row, "removable") && !installing;
    }

    /// <summary>ItemCheck fires before the box changes; a refused answer puts it back.</summary>
    private async Task InstalledCheckChangedAsync(ItemCheckEventArgs args)
    {
        if (fillingInstalled || installedList.Items[args.Index] is not InstalledRow row) return;
        bool on = args.NewValue == CheckState.Checked;
        if (row.Id == null)
        {
            args.NewValue = args.CurrentValue;
            status.Text = $"{row.Name} cannot be turned on: the game will not load it.";
            return;
        }
        try
        {
            await AskAsync("setEnabled", new JsonObject { ["version"] = game.Id, ["modId"] = row.Id, ["enabled"] = on });
            if (closed) return;
            status.Text = $"{row.Name} {(on ? "on" : "off")} for {game.Name}.";
        }
        catch (Exception error) when (error is InvalidOperationException or IOException)
        {
            if (closed) return;
            fillingInstalled = true;
            installedList.SetItemChecked(args.Index, !on);
            fillingInstalled = false;
            ShowMessage($"{row.Name} could not be changed: {error.Message}", MessageBoxIcon.Error);
        }
    }

    private void RemoveSelected()
    {
        if (installing || installedList.SelectedItem is not InstalledRow row || !Flag(row.Row, "removable")) return;
        DialogResult answer = MessageBox.Show(this,
            $"Remove {row.Name} from every game? Its folder is deleted. Your saves are left alone.",
            "Remove mod", MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2);
        if (answer != DialogResult.Yes) return;
        _ = RemoveAsync(row);
    }

    private async Task RemoveAsync(InstalledRow row)
    {
        try
        {
            ModInstaller.Remove(paths.SaveDir, row.Folder);
            status.Text = $"{row.Name} removed.";
            await LoadInstalledAsync();
            await LoadIndexAsync(force: false);
            installedList.Focus();
        }
        catch (Exception error) when (error is ModInstallException or InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            if (!closed) ShowMessage($"{row.Name} could not be removed: {error.Message}", MessageBoxIcon.Error);
        }
    }

    private void FillFound()
    {
        string? selected = (foundList.SelectedItem as FoundRow)?.Id;
        string[] terms = searchBox.Text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        foundList.BeginUpdate();
        foundList.Items.Clear();
        // Listed for this game first; then those whose listing names no game, which may be.
        foreach (JsonObject row in indexRows.OrderBy(row => Flag(row, "forThisGame") ? 0 : 1))
        {
            if (thisGameOnly.Checked && !Flag(row, "forThisGame") && Flag(row, "gamesListed")) continue;
            string searched = $"{TextOf(row, "title")} {TextOf(row, "author")} {TextOf(row, "summary")} {TextOf(row, "id")}";
            if (terms.All(term => searched.Contains(term, StringComparison.OrdinalIgnoreCase)))
            {
                foundList.Items.Add(new FoundRow(row));
            }
        }
        foundList.EndUpdate();
        int index = foundList.Items.Cast<FoundRow>().ToList().FindIndex(row => row.Id == selected);
        if (foundList.Items.Count > 0) foundList.SelectedIndex = Math.Max(0, index);
        ShowFoundDetails();
    }

    private void ShowFoundDetails()
    {
        if (foundList.SelectedItem is not FoundRow selected)
        {
            foundDetails.Text = "";
            installButton.Enabled = false;
            return;
        }
        JsonObject row = selected.Row;
        var text = new StringBuilder();
        if (TextOf(row, "summary") is string summary) text.AppendLine(summary);
        text.AppendLine($"Version {TextOf(row, "version")}, by {TextOf(row, "author") ?? "an unnamed author"}");
        text.AppendLine(Flag(row, "gamesListed") ? $"For: {TextOf(row, "games")}"
            : "The listing does not say which games it is for. Its own manifest decides, once installed.");
        if (TextOf(row, "source") is string source) text.AppendLine($"Listed by another index: {source}");
        string categories = string.Join(", ", Strings(row, "categories"));
        if (categories != "") text.AppendLine($"Categories: {categories}");
        if (TextOf(row, "license") is string license) text.AppendLine($"License: {license}");
        if (TextOf(row, "installedVersion") is string installed) text.AppendLine($"Installed version: {installed}");
        foreach (string warning in Strings(row, "warnings")) text.AppendLine($"Warning: {warning}");
        if (TextOf(row, "unavailable") is string unavailable) text.AppendLine($"Cannot be installed: {unavailable}");
        if (TextOf(row, "repo") is string repo) text.AppendLine($"Project page: {repo}");
        foundDetails.Text = text.ToString().TrimEnd();
        installButton.Enabled = TextOf(row, "url") != null && !installing;
    }

    private async Task InstallSelectedAsync()
    {
        if (installing || foundList.SelectedItem is not FoundRow selected) return;
        JsonObject row = selected.Row;
        if (TextOf(row, "url") is not string url) return;

        var question = new StringBuilder($"Install {selected.Title}, version {TextOf(row, "version")}?");
        if (!Flag(row, "gamesListed")) question.Append("\n\nThe listing does not say which games it is for.");
        else if (!Flag(row, "forThisGame")) question.Append($"\n\nIt does not list {game.Name}; it is for: {TextOf(row, "games")}.");
        if (TextOf(row, "source") is string source) question.Append($"\n\nListed by another index, {source}, not the official one.");
        var warnings = Strings(row, "warnings").ToList();
        if (warnings.Count > 0) question.Append("\n\n").Append(string.Join("\n", warnings));
        if (MessageBox.Show(this, question.ToString(), "Install mod", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
        {
            return;
        }

        await RunInstallAsync(selected.Title, () => ModInstaller.InstallFromUrlAsync(url, selected.Id, paths.SaveDir, FolderOfInstalled, CheckFolderAsync));
    }

    private async Task InstallZipAsync()
    {
        if (installing) return;
        using var dialog = new OpenFileDialog { Title = "Choose a mod's zip file", Filter = "Zip files (*.zip)|*.zip|All files (*.*)|*.*" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        string name = Path.GetFileName(dialog.FileName);
        DialogResult answer = MessageBox.Show(this,
            $"Install {name}? This file is not from an index, so nothing has checked it. Only install it if you trust where it came from.",
            "Install mod", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
        if (answer != DialogResult.Yes) return;
        await RunInstallAsync(name, () => ModInstaller.InstallFromFileAsync(dialog.FileName, paths.SaveDir, FolderOfInstalled, CheckFolderAsync));
    }

    private string? FolderOfInstalled(string modId) =>
        installedList.Items.Cast<InstalledRow>().FirstOrDefault(item => item.Id == modId)?.Folder;

    private Task<JsonObject> CheckFolderAsync(string folder) =>
        AskAsync("check", new JsonObject { ["folder"] = folder, ["version"] = game.Id });

    private async Task RunInstallAsync(string name, Func<Task<JsonObject>> install)
    {
        installing = true;
        installButton.Enabled = removeButton.Enabled = zipButton.Enabled = false;
        status.Text = $"Installing {name}.";
        try
        {
            JsonObject installed = await install();
            await LoadInstalledAsync();
            await LoadIndexAsync(force: false);
            string title = TextOf(installed, "name") ?? name;
            status.Text = $"{title} installed.";
            string where = !Flag(installed, "forThisGame")
                ? $"It will not run on {game.Name}: its manifest says it is for {TextOf(installed, "games")}."
                : Flag(installed, "enabled")
                    ? $"It is on for {game.Name}; turn it off in the Installed tab."
                    : $"It is off for {game.Name}, as its author marks it experimental or you turned it off before; turn it on in the Installed tab.";
            ShowMessage($"{title} installed. {where} Mods load when a game starts.", MessageBoxIcon.Information);
        }
        catch (Exception error) when (error is ModInstallException or InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            status.Text = $"{name} was not installed.";
            ShowMessage($"{name} was not installed. {error.Message}", MessageBoxIcon.Error);
        }
        finally
        {
            installing = false;
            zipButton.Enabled = true;
            ShowFoundDetails();
            ShowInstalledDetails();
            foundList.Focus();
        }
    }

    private async Task ManageIndexesAsync()
    {
        using var sources = new ModSourcesForm(AskAsync);
        sources.ShowDialog(this);
        if (sources.Changed) await LoadIndexAsync(force: false);
        foundList.Focus();
    }

    private void ShowMessage(string text, MessageBoxIcon icon) =>
        MessageBox.Show(this, text, "Mods", MessageBoxButtons.OK, icon);

    /// <summary>An installed mod's row: its name and what the check box cannot say.</summary>
    private sealed record InstalledRow(JsonObject Row, string GameName)
    {
        public string? Id => TextOf(Row, "id");
        public string Folder => TextOf(Row, "folder") ?? "";
        public string Name => TextOf(Row, "name") ?? Folder;

        public override string ToString()
        {
            if (TextOf(Row, "problem") != null) return $"{Name}, will not load";
            string note = Flag(Row, "forThisGame") ? "" : $", not for {GameName}";
            return $"{Name} {TextOf(Row, "version")}{note}";
        }
    }

    /// <summary>A listing's row: its title, author, and whether it is already installed.</summary>
    private sealed record FoundRow(JsonObject Row)
    {
        public string Id => TextOf(Row, "id") ?? "";
        public string Title => TextOf(Row, "title") ?? Id;

        public override string ToString()
        {
            string by = TextOf(Row, "author") is string author ? $", by {author}" : "";
            string version = TextOf(Row, "version") ?? "";
            string note = TextOf(Row, "installedVersion") is string installed
                ? installed == version ? ", installed" : $", installed {installed}, version {version} available"
                : "";
            string games = Flag(Row, "gamesListed") ? "" : ", games not listed";
            return $"{Title}{by}{games}{note}";
        }
    }
}
