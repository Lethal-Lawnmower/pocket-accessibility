namespace PocketLauncher;

/// <summary>
/// Credits in a read-only text box, so a screen reader can read them line by
/// line with the arrow keys.  Holds the upstream credit License Term 1
/// requires in any launcher.
/// </summary>
internal sealed class CreditsForm : Form
{
    private static readonly string[] Lines =
    [
        "Pocket Accessibility: screen reader accessibility for Pokémon Red, Blue, Yellow, Gold, Silver and Crystal.",
        "",
        MainForm.UpstreamCredit + ".",
        "This is an unofficial fork, not affiliated with or endorsed by that project.",
        "",
        "Speech through Prism (https://github.com/ethindp/prism).",
        "Inspired by Pokémon Access and Pokécrystal Access, recreated rather than copied.",
        "",
        "License: GNU General Public License version 3, with the upstream project's Section 7 terms.",
        "Source: https://github.com/Lethal-Lawnmower/pocket-accessibility",
        "",
        "Not affiliated with Nintendo, Game Freak or The Pokémon Company. You supply your own cartridge dumps; no game data is included.",
    ];

    public CreditsForm()
    {
        Text = "Credits";
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
            AccessibleName = "Credits",
            Text = string.Join(Environment.NewLine, Lines),
        };
        var close = new Button { Text = "&Close", AutoSize = true, Dock = DockStyle.Bottom, DialogResult = DialogResult.OK };
        AcceptButton = CancelButton = close;

        Controls.Add(text);
        Controls.Add(close);
        ActiveControl = text;
        Shown += (_, _) => text.Select(0, 0);
    }
}
