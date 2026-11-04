namespace PocketLauncher;

/// <summary>
/// Credits in a read-only text box, so a screen reader can read them line by
/// line with the arrow keys.  Holds the upstream credit License Term 1
/// requires in any launcher, the GPL's copyright and no-warranty notices, and
/// the way to read the license and third-party notices (GPL section 5d).
/// </summary>
internal sealed class CreditsForm : Form
{
    private static readonly string[] Lines =
    [
        "Pocket Accessibility: screen reader accessibility for Pokémon Red, Blue, Yellow, Gold, Silver, Crystal and FireRed.",
        "Copyright (C) 2026 BOIS CLUB GAMES, LLC. Accessibility additions copyright (C) 2026 the Pocket Accessibility contributors.",
        "",
        MainForm.UpstreamCredit + ".",
        "This is an unofficial fork, not affiliated with or endorsed by that project.",
        "",
        "Speech through Prism (https://github.com/ethindp/prism).",
        "Inspired by Pokémon Access and Pokécrystal Access, recreated rather than copied.",
        "",
        "License: GNU General Public License version 3, with the upstream project's Section 7 terms. Choose License to read it.",
        "This program comes with ABSOLUTELY NO WARRANTY. It is free software, and you may redistribute it under those terms.",
        "Other software included is listed under Third-party notices.",
        "Source: https://github.com/Lethal-Lawnmower/pocket-accessibility",
        "",
        "Not affiliated with Nintendo, Game Freak or The Pokémon Company. You supply your own cartridge dumps; no game data is included.",
    ];

    public CreditsForm(GamePaths paths) : this("Credits", string.Join(Environment.NewLine, Lines))
    {
        var licenseButton = new Button { Text = "&License", AutoSize = true, Dock = DockStyle.Bottom };
        licenseButton.Click += (_, _) => ShowFile("License", paths.GameDir, "LICENSE.MD");
        var noticesButton = new Button { Text = "&Third-party notices", AutoSize = true, Dock = DockStyle.Bottom };
        noticesButton.Click += (_, _) => ShowFile("Third-party notices", paths.GameDir, "launcher", "THIRD-PARTY-NOTICES.txt");
        Controls.Add(noticesButton);
        Controls.Add(licenseButton);
    }

    private void ShowFile(string title, string? gameDir, params string[] parts)
    {
        string path = Path.Combine([gameDir ?? "", .. parts]);
        string text;
        try
        {
            text = File.ReadAllText(path);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            text = $"{path} could not be read: {error.Message}";
        }
        using var viewer = new CreditsForm(title, text);
        viewer.ShowDialog(this);
    }

    private CreditsForm(string title, string body)
    {
        Text = title;
        AutoScaleMode = AutoScaleMode.Dpi;
        StartPosition = FormStartPosition.CenterParent;
        ClientSize = new Size(560, 300);
        MinimizeBox = MaximizeBox = false;
        Padding = new Padding(12);

        var text = new TextBox
        {
            Multiline = true,
            ReadOnly = true,
            ScrollBars = ScrollBars.Vertical,
            Dock = DockStyle.Fill,
            AccessibleName = title,
            Text = body.ReplaceLineEndings(Environment.NewLine),
        };
        var close = new Button { Text = "&Close", AutoSize = true, Dock = DockStyle.Bottom, DialogResult = DialogResult.OK };
        AcceptButton = CancelButton = close;

        Controls.Add(text);
        Controls.Add(close);
        ActiveControl = text;
        Shown += (_, _) => text.Select(0, 0);
    }
}
