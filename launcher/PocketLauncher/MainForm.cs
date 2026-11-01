namespace PocketLauncher;

/// <summary>
/// The launcher window: a list of the six games with whether each is
/// imported, and Play, Import ROM, Credits and Exit.  Only standard controls
/// with explicit accessible names, laid out in a table so the tab order is
/// the reading order: games list, buttons, the required upstream credit.
/// Results the player must hear (import done, errors) come as message boxes,
/// which screen readers announce; the status bar holds the current state.
/// </summary>
internal sealed class MainForm : Form
{
    // License Term 1 requires this credit, visibly, in any launcher.
    public const string UpstreamCredit =
        "Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC " +
        "(https://github.com/bryanthaboi/gen1recomp)";

    private readonly GamePaths paths;
    private readonly GameRunner runner;
    private readonly ListBox gamesList = new();
    private readonly Button playButton = new();
    private readonly Button importButton = new();
    private readonly Button creditsButton = new();
    private readonly Button exitButton = new();
    private readonly ToolStripStatusLabel status = new();
    private bool busy;

    private readonly string? romToImport;

    /// <param name="romToImport">A cartridge dump to import once the window
    /// is up: a ROM dropped on the launcher's icon, or opened with it.</param>
    public MainForm(GamePaths paths, string? romToImport = null)
    {
        this.paths = paths;
        this.romToImport = romToImport;
        runner = new GameRunner(paths);

        Text = "Pocket Accessibility";
        AutoScaleMode = AutoScaleMode.Dpi;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        StartPosition = FormStartPosition.CenterScreen;
        Padding = new Padding(12);

        var gamesLabel = new Label { Text = "&Games:", AutoSize = true };
        gamesList.AccessibleName = "Games";
        gamesList.IntegralHeight = true;
        gamesList.Height = gamesList.ItemHeight * GameCatalog.All.Count + 8;
        gamesList.Width = 320;
        gamesList.DoubleClick += async (_, _) => await PlaySelectedAsync();

        ConfigureButton(playButton, "&Play", async () => await PlaySelectedAsync());
        ConfigureButton(importButton, "&Import ROM...", async () => await ImportAsync());
        ConfigureButton(creditsButton, "&Credits", () => { using var credits = new CreditsForm(); credits.ShowDialog(this); return Task.CompletedTask; });
        ConfigureButton(exitButton, "E&xit", () => { Close(); return Task.CompletedTask; });
        AcceptButton = playButton; // Enter on the list plays the selected game

        var buttons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        buttons.Controls.AddRange([playButton, importButton, creditsButton, exitButton]);

        var credit = new Label { Text = UpstreamCredit, AutoSize = true, MaximumSize = new Size(480, 0) };

        var layout = new TableLayoutPanel { AutoSize = true, ColumnCount = 1, Dock = DockStyle.Fill };
        layout.Controls.Add(gamesLabel);
        layout.Controls.Add(gamesList);
        layout.Controls.Add(buttons);
        layout.Controls.Add(credit);

        // Named, or UI Automation names the bar after the label above it.
        var statusStrip = new StatusStrip { SizingGrip = false, AccessibleName = "Status" };
        status.Spring = true;
        status.TextAlign = ContentAlignment.MiddleLeft;
        statusStrip.Items.Add(status);

        Controls.Add(layout);
        Controls.Add(statusStrip);
        ActiveControl = gamesList;
        Shown += async (_, _) =>
        {
            if (!await OnFirstShownAsync()) return;
            if (romToImport != null) await ImportFileAsync(romToImport);
        };
    }

    private void ConfigureButton(Button button, string text, Func<Task> action)
    {
        button.Text = text;
        button.AutoSize = true;
        button.Click += async (_, _) => await action();
    }

    private Game? SelectedGame => gamesList.SelectedItem is GameRow row ? row.Game : null;

    /// <summary>A list row: the game's name and whether it can be played.</summary>
    private sealed record GameRow(Game Game, ImportState State)
    {
        public override string ToString() => State switch
        {
            ImportState.Ready => $"{Game.Name}, imported{Silent}",
            ImportState.NeedsReimport => $"{Game.Name}, needs importing again{Silent}",
            _ => $"{Game.Name}, not imported{Silent}",
        };

        // Games the layer does not cover yet run, but their screens are silent.
        private string Silent => Game.Speaks ? "" : ", no speech yet";
    }

    private ImportState StateOf(Game game) =>
        gamesList.Items.Cast<GameRow>().FirstOrDefault(row => row.Game == game)?.State ?? ImportState.NotImported;

    /// <summary>Asks the game which games are ready and rebuilds the list.</summary>
    private async Task RefreshGamesAsync(Game? select = null)
    {
        select ??= SelectedGame;
        var checkedStates = await ReadyCheck.RunAsync(paths);
        if (checkedStates == null)
        {
            status.Text = "Could not ask the game which games are imported; showing what the save folder suggests.";
        }
        gamesList.BeginUpdate();
        gamesList.Items.Clear();
        foreach (var game in GameCatalog.All)
        {
            bool marker = paths.HasImportMarker(game);
            ImportState state;
            if (checkedStates != null && checkedStates.TryGetValue(game.Id, out var verdict))
            {
                state = verdict == ImportState.Ready ? ImportState.Ready
                    : marker ? ImportState.NeedsReimport : ImportState.NotImported;
            }
            else
            {
                state = marker ? ImportState.Ready : ImportState.NotImported;
            }
            gamesList.Items.Add(new GameRow(game, state));
        }
        int index = select == null ? -1 : GameCatalog.All.ToList().IndexOf(select);
        if (index < 0)
        {
            // Start on the first playable game, or the first game.
            index = Math.Max(0, gamesList.Items.Cast<GameRow>().ToList().FindIndex(row => row.State == ImportState.Ready));
        }
        gamesList.SelectedIndex = index;
        gamesList.EndUpdate();
    }

    /// <summary>Checks the setup and the games; false when no game can be started at all.</summary>
    private async Task<bool> OnFirstShownAsync()
    {
        if (paths.GameDir == null || paths.LoveExe == null)
        {
            string missing = paths.GameDir == null
                ? "The game folder was not found. Start the launcher from inside the Pocket Accessibility folder, or set POCKET_GAME_DIR."
                : "LÖVE 11.5 was not found. Install it from love2d.org, or set POCKET_LOVE to love.exe.";
            status.Text = missing;
            playButton.Enabled = importButton.Enabled = false;
            ShowMessage(missing, MessageBoxIcon.Error);
            return false;
        }
        status.Text = "Ready.";
        await RefreshGamesAsync();
        if (!paths.HasPrism)
        {
            ShowMessage("The speech library was not found (local-deps\\prism\\prism.dll in the game folder). " +
                        "The games will start, but nothing will be spoken until Prism is installed.",
                        MessageBoxIcon.Warning);
        }
        return true;
    }

    private async Task PlaySelectedAsync()
    {
        if (busy || SelectedGame is not Game game) return;
        ImportState state = StateOf(game);
        if (state != ImportState.Ready)
        {
            ShowMessage(state == ImportState.NeedsReimport
                ? $"{game.Name} was imported by an older version and needs importing again. Choose Import ROM and pick your {game.Name} cartridge dump."
                : $"{game.Name} is not imported yet. Choose Import ROM and pick your {game.Name} cartridge dump first.",
                MessageBoxIcon.Information);
            importButton.Focus();
            return;
        }
        await RunBusyAsync($"Playing {game.Name}.", async () =>
        {
            // Out of the way while the game runs; back with focus on the list after.
            WindowState = FormWindowState.Minimized;
            try
            {
                await runner.PlayAsync(game);
            }
            finally
            {
                WindowState = FormWindowState.Normal;
                Activate();
            }
        });
        status.Text = "Ready.";
        await RefreshGamesAsync(game);
        gamesList.Focus();
    }

    private async Task ImportAsync()
    {
        if (busy) return;
        using var dialog = new OpenFileDialog
        {
            Title = "Choose a cartridge dump",
            Filter = "Game Boy ROMs (*.gb, *.gbc, *.gba)|*.gb;*.gbc;*.gba|All files (*.*)|*.*",
        };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        await ImportFileAsync(dialog.FileName);
    }

    private async Task ImportFileAsync(string romPath)
    {
        if (busy) return;
        string sha1;
        try
        {
            sha1 = await Task.Run(() => GameRunner.Sha1Of(romPath));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            ShowMessage($"The file could not be read: {error.Message}", MessageBoxIcon.Error);
            return;
        }
        Game? game = GameCatalog.ForSha1(sha1);
        if (game == null)
        {
            ShowMessage("This file is not one of the supported cartridge dumps: the USA or Europe releases of " +
                        "Red, Blue, Yellow, Gold, Silver, Crystal, FireRed, LeafGreen, Ruby, Sapphire and Emerald.",
                        MessageBoxIcon.Warning);
            return;
        }
        await RunBusyAsync($"Importing {game.Name}. This can take a minute.",
                           () => runner.ImportAsync(game, romPath));
        await RefreshGamesAsync(game);
        if (StateOf(game) == ImportState.Ready)
        {
            status.Text = $"{game.Name} imported.";
            ShowMessage($"{game.Name} imported. Press Play to start.", MessageBoxIcon.Information);
        }
        else
        {
            status.Text = $"{game.Name} was not imported.";
            ShowMessage($"The import of {game.Name} did not finish. Try again, or check that the file is a clean dump.",
                        MessageBoxIcon.Error);
        }
        gamesList.Focus();
    }

    /// <summary>Runs one game-program task with the buttons disabled.</summary>
    private async Task RunBusyAsync(string message, Func<Task> work)
    {
        busy = true;
        status.Text = message;
        playButton.Enabled = importButton.Enabled = false;
        try
        {
            await work();
        }
        catch (Exception error)
        {
            ShowMessage(error.Message, MessageBoxIcon.Error);
        }
        finally
        {
            busy = false;
            playButton.Enabled = importButton.Enabled = true;
        }
    }

    private void ShowMessage(string text, MessageBoxIcon icon) =>
        MessageBox.Show(this, text, "Pocket Accessibility", MessageBoxButtons.OK, icon);
}
