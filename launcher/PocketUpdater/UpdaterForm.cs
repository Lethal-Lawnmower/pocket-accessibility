using System.Diagnostics;
using System.Windows.Forms.Automation;

namespace PocketUpdater;

/// <summary>
/// The updater's one window: says which version is installed and which is newest, with that
/// release's notes, and installs it when asked.  It starts the launcher when it closes if the
/// launcher opened it, so the player is never left with nothing open.
/// </summary>
internal sealed class UpdaterForm : Form
{
    private const string UpstreamCredit =
        "Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC (https://github.com/bryanthaboi/gen1recomp).";

    private readonly string programDir;
    private readonly bool reopenLauncher;
    private readonly Label summary = new() { AutoSize = true, MaximumSize = new Size(560, 0) };
    private readonly TextBox notes = new()
    {
        Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill,
        AccessibleName = "What's new in this release", TabStop = true,
    };
    private readonly Button updateButton = new() { Text = "&Update now", AutoSize = true, Enabled = false };
    private readonly Button closeButton = new() { Text = "&Close", AutoSize = true };
    private readonly ProgressBar bar = new() { AccessibleName = "Update progress", Dock = DockStyle.Bottom, Height = 22, Visible = false };
    private readonly ToolStripStatusLabel status = new();
    private ReleaseInfo? available;
    private bool updating;
    private string? stage;
    private int quarter;

    public UpdaterForm(string programDir, bool reopenLauncher)
    {
        this.programDir = programDir;
        this.reopenLauncher = reopenLauncher;
        Text = "Pocket Accessibility updates";
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(600, 400);
        MinimumSize = new Size(480, 340);
        StartPosition = FormStartPosition.CenterScreen;

        var buttons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = true, Dock = DockStyle.Fill };
        buttons.Controls.AddRange([updateButton, closeButton]);
        var layout = new TableLayoutPanel { ColumnCount = 1, RowCount = 5, Dock = DockStyle.Fill, Padding = new Padding(12) };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.Controls.Add(summary);
        layout.Controls.Add(new Label { Text = "&What's new:", AutoSize = true });
        layout.Controls.Add(notes);
        layout.Controls.Add(buttons);
        layout.Controls.Add(new Label { Text = UpstreamCredit, AutoSize = true, MaximumSize = new Size(560, 0) });

        // Named, or UI Automation names the bar after the control above it.
        var statusStrip = new StatusStrip { SizingGrip = false, AccessibleName = "Status" };
        status.Spring = true;
        status.TextAlign = ContentAlignment.MiddleLeft;
        statusStrip.Items.Add(status);

        Controls.Add(layout);
        Controls.Add(bar);
        Controls.Add(statusStrip);
        CancelButton = closeButton;
        ActiveControl = closeButton;

        closeButton.Click += (_, _) => Close();
        updateButton.Click += async (_, _) => await UpdateAsync();
        Shown += async (_, _) => await CheckAsync();
        FormClosing += (_, args) =>
        {
            if (!updating) return;
            args.Cancel = true;
            status.Text = "Please wait for the update to finish.";
        };
        FormClosed += (_, _) =>
        {
            if (reopenLauncher) StartLauncher();
        };
    }

    private void SetSummary(string text)
    {
        summary.Text = text;
        status.Text = text;
        Announce(text);
    }

    /// <summary>A screen reader does not read a label that changes away from focus, so say so
    /// through an automation notification, the standard way a window reports a change.</summary>
    private void Announce(string text)
    {
        if (!summary.IsHandleCreated) return;
        summary.AccessibilityObject.RaiseAutomationNotification(
            AutomationNotificationKind.ActionCompleted, AutomationNotificationProcessing.ImportantMostRecent, text);
    }

    private async Task CheckAsync()
    {
        UpdateEngine.RemoveLeftovers(programDir);
        if (!UpdateEngine.IsPackagedFolder(programDir))
        {
            SetSummary("Updates are for the packaged download. This copy runs from source, so use git instead.");
            return;
        }
        Version installed = UpdateEngine.InstalledVersion(programDir)!;
        SetSummary($"You have version {Short(installed)}. Checking for a newer one.");
        try
        {
            ReleaseInfo? latest = await UpdateEngine.LatestReleaseAsync();
            if (latest == null)
            {
                SetSummary($"You have version {Short(installed)}. No releases are available yet.");
            }
            else if (latest.Version <= installed)
            {
                SetSummary($"You have version {Short(installed)}, which is the latest.");
                notes.Text = latest.Notes.ReplaceLineEndings();
            }
            else
            {
                available = latest;
                notes.Text = latest.Notes.ReplaceLineEndings();
                updateButton.Enabled = true;
                SetSummary($"Version {Short(latest.Version)} is available. You have {Short(installed)}.");
                updateButton.Focus();
            }
        }
        catch (UpdateException error)
        {
            SetSummary($"You have version {Short(installed)}. {error.Message}");
        }
    }

    private async Task UpdateAsync()
    {
        if (available == null || updating) return;
        updating = true;
        updateButton.Enabled = closeButton.Enabled = false;
        bar.Value = 0;
        bar.Visible = true;
        stage = null;
        quarter = 0;
        var progress = new Progress<UpdateProgress>(ShowProgress);
        try
        {
            await UpdateEngine.InstallAsync(available, programDir, progress);
            bar.Style = ProgressBarStyle.Blocks;
            bar.Value = 100;
            updating = false;
            string done = $"Updated to version {Short(available.Version)}. Your saves and imported games are untouched.";
            SetSummary(done);
            MessageBox.Show(this, done + " The launcher will open now.", "Pocket Accessibility updates", MessageBoxButtons.OK, MessageBoxIcon.Information);
            if (!reopenLauncher) StartLauncher();
            Close();
        }
        catch (UpdateException error)
        {
            updating = false;
            SetSummary($"Not updated. {error.Message}");
            MessageBox.Show(this, $"Not updated. {error.Message}", "Pocket Accessibility updates", MessageBoxButtons.OK, MessageBoxIcon.Error);
            updateButton.Enabled = true;
            updateButton.Focus();
        }
        finally
        {
            closeButton.Enabled = true;
            bar.Visible = false;
        }
    }

    private void ShowProgress(UpdateProgress update)
    {
        bar.Style = update.Percent == null ? ProgressBarStyle.Marquee : ProgressBarStyle.Blocks;
        if (update.Percent is int percent) bar.Value = Math.Clamp(percent, 0, 100);
        string line = update.Percent is int shown ? $"{update.Stage}, {shown} percent." : $"{update.Stage}.";
        status.Text = line;
        int nowQuarter = (update.Percent ?? 0) / 25;
        if (update.Stage == stage && nowQuarter <= quarter) return;
        stage = update.Stage;
        quarter = nowQuarter;
        Announce(line);
    }

    private void StartLauncher()
    {
        string launcher = Path.Combine(programDir, "PocketLauncher.exe");
        if (!File.Exists(launcher)) return;
        Process.Start(new ProcessStartInfo(launcher) { UseShellExecute = false, WorkingDirectory = programDir })?.Dispose();
    }

    private static string Short(Version version) => version.ToString(Math.Min(version.Build >= 0 ? 3 : 2, 3));
}
