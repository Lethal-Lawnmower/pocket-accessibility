using System.Globalization;
using System.Text.Json.Nodes;

namespace PocketLauncher;

/// <summary>
/// One page of the save editor, drawn from the backend's description: dropdowns,
/// a read-only summary, a list with an optional filter, more dropdowns, fields and
/// buttons, in that tab order.  Controls are kept and updated in place between
/// answers, so focus and the screen reader's position never jump.  A typed value
/// is sent when focus leaves its box or on Enter; a dropdown when focus leaves it
/// or its list closes, so arrowing through choices does not make an edit per choice.
/// </summary>
internal sealed class PagePanel : UserControl
{
    private readonly string pageId;
    private readonly Func<string, JsonObject?, Task<JsonObject>> run;
    private readonly Action<string, MessageBoxIcon> showMessage;

    private readonly FlowLayoutPanel topPickers = NewFlow();
    private readonly TextBox summary = new()
    {
        Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, AccessibleName = "Summary", Width = 780, Height = 72,
    };
    private readonly Label filterLabel = new() { Text = "&Filter:", AutoSize = true };
    private readonly TextBox filter = new() { AccessibleName = "Filter", Width = 300 };
    private readonly Label listLabel = new() { AutoSize = true };
    private readonly ListBox list = new() { Width = 780, Height = 190, IntegralHeight = false };
    private readonly CheckedListBox checkList = new() { Width = 780, Height = 190, IntegralHeight = false, CheckOnClick = false };
    private readonly FlowLayoutPanel lowerPickers = NewFlow();
    private readonly TableLayoutPanel fieldTable = new() { AutoSize = true, ColumnCount = 2 };
    private readonly FlowLayoutPanel actions = NewFlow();

    private readonly Dictionary<string, FieldRow> fieldRows = [];
    private readonly Dictionary<string, Button> actionButtons = [];
    private readonly Dictionary<string, PickerRow> pickerRows = [];
    private string fieldSignature = "", actionSignature = "", pickerSignature = "";
    private List<Row> allRows = [];
    private List<Row> shownRows = [];
    private bool updating;
    private int requestCount;

    private sealed record Row(string Id, string Text, bool Checked)
    {
        public override string ToString() => Text;
    }

    private sealed record Choice(JsonNode? Value, string Label)
    {
        public override string ToString() => Label;
    }

    private sealed class FieldRow(string id, string kind, Label label, Control control)
    {
        public string Id => id;
        public string Kind => kind;
        public Label Label => label;
        public Control Control => control;
        public bool Edited;
    }

    private sealed record PickerRow(string Id, Label Label, ComboBox Box);

    public PagePanel(string pageId, Func<string, JsonObject?, Task<JsonObject>> run, Action<string, MessageBoxIcon> showMessage)
    {
        this.pageId = pageId;
        this.run = run;
        this.showMessage = showMessage;
        AutoScroll = true;

        var filterRow = NewFlow();
        filterRow.Controls.AddRange([filterLabel, filter]);
        var layout = new TableLayoutPanel { AutoSize = true, ColumnCount = 1, Dock = DockStyle.Top };
        foreach (Control control in new Control[] { topPickers, summary, filterRow, listLabel, list, checkList, lowerPickers, fieldTable, actions })
        {
            layout.Controls.Add(control);
        }
        Controls.Add(layout);
        summary.Visible = filterRow.Visible = listLabel.Visible = list.Visible = checkList.Visible = false;
        filterVisibility = visible => filterRow.Visible = visible;

        filter.TextChanged += (_, _) => { if (!updating) ShowRows(); };
        list.SelectedIndexChanged += async (_, _) => await OnRowSelectedAsync(list);
        checkList.SelectedIndexChanged += async (_, _) => await OnRowSelectedAsync(checkList);
        checkList.ItemCheck += async (_, e) => await OnRowCheckedAsync(e);
        list.KeyDown += OnListKeyDown;
        checkList.KeyDown += OnListKeyDown;
    }

    private readonly Action<bool> filterVisibility;

    private static FlowLayoutPanel NewFlow() => new() { AutoSize = true, WrapContents = true, Margin = new Padding(0, 4, 0, 4) };

    public async Task RefreshAsync() => Apply(await SendAsync("model", null));

    private async Task<JsonObject> SendAsync(string command, JsonObject? arguments)
    {
        arguments ??= [];
        arguments["page"] = pageId;
        requestCount++;
        return await run(command, arguments);
    }

    private async Task SendAndApplyAsync(string command, JsonObject arguments) => Apply(await SendAsync(command, arguments));

    /// <summary>Sends whatever is typed but not yet sent.</summary>
    public async Task CommitPendingAsync()
    {
        foreach (var row in fieldRows.Values.Where(row => row.Edited).ToList()) await CommitFieldAsync(row);
        foreach (var picker in pickerRows.Values.Where(picker => picker.Box.Tag is true).ToList()) await CommitPickerAsync(picker);
    }

    private void Apply(JsonObject response)
    {
        if (IsDisposed || response["model"] is not JsonObject model) return;
        updating = true;
        try
        {
            ApplyPickers(model["pickers"]?.AsArray());
            summary.Visible = model["summary"] != null;
            string summaryText = model["summary"]?.ToString()?.ReplaceLineEndings("\r\n") ?? "";
            if (summary.Text != summaryText) summary.Text = summaryText;
            ApplyList(model["list"]?.AsObject());
            ApplyFields(model["fields"]?.AsArray());
            ApplyActions(model["actions"]?.AsArray());
        }
        finally
        {
            updating = false;
        }
    }

    // ---------------------------------------------------------------- pickers

    private void ApplyPickers(JsonArray? pickers)
    {
        var entries = pickers?.Select(node => node!.AsObject()).ToList() ?? [];
        string signature = string.Join("|", entries.Select(p => p["id"] + "/" + (p["below"] != null)));
        if (signature != pickerSignature)
        {
            pickerSignature = signature;
            topPickers.Controls.Clear();
            lowerPickers.Controls.Clear();
            pickerRows.Clear();
            foreach (var entry in entries)
            {
                string id = entry["id"]!.ToString();
                var label = new Label { AutoSize = true, Margin = new Padding(0, 6, 4, 0) };
                var box = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 280 };
                var row = new PickerRow(id, label, box);
                pickerRows[id] = row;
                HookPicker(row);
                var target = entry["below"]?.GetValue<bool>() == true ? lowerPickers : topPickers;
                target.Controls.AddRange([label, box]);
            }
        }
        foreach (var entry in entries)
        {
            var row = pickerRows[entry["id"]!.ToString()];
            row.Label.Text = entry["label"]!.ToString() + ":";
            row.Box.AccessibleName = entry["label"]!.ToString();
            FillChoices(row.Box, entry["options"]?.AsArray(), entry["value"]);
            row.Box.Tag = false;
        }
    }

    private void HookPicker(PickerRow row)
    {
        row.Box.SelectedIndexChanged += (_, _) => { if (!updating) row.Box.Tag = true; };
        row.Box.Leave += async (_, _) => await CommitPickerAsync(row);
        row.Box.DropDownClosed += async (_, _) => await CommitPickerAsync(row);
        row.Box.KeyDown += async (_, e) =>
        {
            if (e.KeyCode != Keys.Enter) return;
            e.Handled = e.SuppressKeyPress = true;
            await CommitPickerAsync(row);
        };
    }

    private async Task CommitPickerAsync(PickerRow row)
    {
        if (row.Box.Tag is not true || row.Box.SelectedItem is not Choice choice) return;
        row.Box.Tag = false;
        await SendAndApplyAsync("pick", new JsonObject { ["picker"] = row.Id, ["value"] = choice.Value?.DeepClone() });
    }

    private static void FillChoices(ComboBox box, JsonArray? options, JsonNode? value)
    {
        var choices = options?.Select(o => new Choice(o!["value"], o["label"]!.ToString())).ToList() ?? [];
        bool same = box.Items.Count == choices.Count
            && box.Items.Cast<Choice>().Zip(choices).All(pair => pair.First.Label == pair.Second.Label);
        if (!same)
        {
            box.BeginUpdate();
            box.Items.Clear();
            box.Items.AddRange([.. choices]);
            box.EndUpdate();
        }
        int index = choices.FindIndex(choice => JsonNode.DeepEquals(choice.Value, value));
        if (box.SelectedIndex != index) box.SelectedIndex = index;
    }

    // ------------------------------------------------------------------- list

    private void ApplyList(JsonObject? model)
    {
        if (model == null)
        {
            list.Visible = checkList.Visible = listLabel.Visible = false;
            filterVisibility(false);
            allRows = shownRows = [];
            return;
        }
        bool checks = model["checks"]?.GetValue<bool>() == true;
        list.Visible = !checks;
        checkList.Visible = checks;
        listLabel.Visible = true;
        listLabel.Text = model["label"]?.ToString() + ":";
        ActiveList.AccessibleName = model["label"]?.ToString();
        filterVisibility(model["filter"]?.GetValue<bool>() == true);
        allRows = model["rows"]?.AsArray().Select(row => new Row(
            row!["id"]!.ToString(), row["text"]!.ToString(), row["checked"]?.GetValue<bool>() == true)).ToList() ?? [];
        ShowRows(model["selected"]?.ToString());
    }

    private ListBox ActiveList => checkList.Visible ? checkList : list;

    private void ShowRows(string? selectId = null)
    {
        var box = ActiveList;
        selectId ??= (box.SelectedItem as Row)?.Id;
        string query = filter.Text.Trim();
        var rows = query.Length == 0 ? allRows
            : allRows.Where(row => row.Text.Contains(query, StringComparison.OrdinalIgnoreCase)).ToList();
        bool wasUpdating = updating;
        updating = true;
        if (!rows.SequenceEqual(shownRows) || box.Items.Count != rows.Count)
        {
            shownRows = rows;
            int top = box.TopIndex;
            box.BeginUpdate();
            box.Items.Clear();
            foreach (var row in rows)
            {
                if (box is CheckedListBox checkedBox) checkedBox.Items.Add(row, row.Checked);
                else box.Items.Add(row);
            }
            if (top < box.Items.Count) box.TopIndex = top;
            box.EndUpdate();
        }
        int index = rows.FindIndex(row => row.Id == selectId);
        if (box.SelectedIndex != index) box.SelectedIndex = index;
        updating = wasUpdating;
    }

    private async Task OnRowSelectedAsync(ListBox box)
    {
        if (updating || box.SelectedItem is not Row row) return;
        await SendAndApplyAsync("select", new JsonObject { ["row"] = row.Id });
    }

    private async Task OnRowCheckedAsync(ItemCheckEventArgs e)
    {
        if (updating || e.Index >= shownRows.Count) return;
        await SendAndApplyAsync("toggle", new JsonObject
        {
            ["row"] = shownRows[e.Index].Id,
            ["checked"] = e.NewValue == CheckState.Checked,
        });
    }

    /// <summary>Delete on a row runs the page's "delete" action when it has one.</summary>
    private async void OnListKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Delete && actionButtons.TryGetValue("delete", out var button) && button.Enabled)
        {
            e.Handled = true;
            button.PerformClick();
            await Task.CompletedTask;
        }
    }

    // ----------------------------------------------------------------- fields

    private void ApplyFields(JsonArray? fields)
    {
        var entries = fields?.Select(node => node!.AsObject()).ToList() ?? [];
        string signature = string.Join("|", entries.Select(f => f["id"] + "/" + f["kind"]));
        if (signature != fieldSignature)
        {
            string? focused = fieldRows.Values.FirstOrDefault(row => row.Control.ContainsFocus)?.Id;
            fieldSignature = signature;
            fieldTable.SuspendLayout();
            fieldTable.Controls.Clear();
            foreach (var row in fieldRows.Values) { row.Label.Dispose(); row.Control.Dispose(); }
            fieldRows.Clear();
            foreach (var entry in entries)
            {
                var row = NewFieldRow(entry);
                fieldRows[row.Id] = row;
                fieldTable.Controls.Add(row.Label);
                fieldTable.Controls.Add(row.Control);
            }
            fieldTable.ResumeLayout();
            if (focused != null)
            {
                if (fieldRows.TryGetValue(focused, out var again)) again.Control.Focus();
                else if (ActiveList.Visible) ActiveList.Focus();
            }
        }
        foreach (var entry in entries) UpdateField(fieldRows[entry["id"]!.ToString()], entry);
    }

    private FieldRow NewFieldRow(JsonObject entry)
    {
        string kind = entry["kind"]?.ToString() ?? "info";
        var label = new Label { AutoSize = true, Margin = new Padding(0, 7, 8, 0) };
        Control control = kind switch
        {
            "choice" => new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 340 },
            "check" => new CheckBox { AutoSize = true },
            "info" => new TextBox { ReadOnly = true, Width = 440 },
            _ => new TextBox { Width = kind == "number" ? 160 : 300 },
        };
        var row = new FieldRow(entry["id"]!.ToString(), kind, label, control);
        switch (control)
        {
            case ComboBox box:
                box.SelectedIndexChanged += (_, _) => { if (!updating) row.Edited = true; };
                box.DropDownClosed += async (_, _) => await CommitFieldAsync(row);
                box.Leave += async (_, _) => await CommitFieldAsync(row);
                box.KeyDown += (_, e) => OnFieldEnter(row, e);
                break;
            case CheckBox check:
                check.CheckedChanged += async (_, _) =>
                {
                    if (updating) return;
                    row.Edited = true;
                    await CommitFieldAsync(row);
                };
                break;
            case TextBox text when kind != "info":
                text.TextChanged += (_, _) => { if (!updating) row.Edited = true; };
                text.Leave += async (_, _) => await CommitFieldAsync(row);
                text.KeyDown += (_, e) => OnFieldEnter(row, e);
                break;
        }
        return row;
    }

    private async void OnFieldEnter(FieldRow row, KeyEventArgs e)
    {
        if (e.KeyCode != Keys.Enter) return;
        e.Handled = e.SuppressKeyPress = true;
        await CommitFieldAsync(row);
    }

    private void UpdateField(FieldRow row, JsonObject entry)
    {
        string name = entry["label"]?.ToString() ?? row.Id;
        string? issue = entry["issue"]?.ToString();
        string range = entry["lo"] != null && entry["hi"] != null
            ? $", {entry["lo"]} to {entry["hi"]}" : "";
        row.Label.Text = name + ":";
        row.Control.AccessibleName = name + range;
        string? help = entry["help"]?.ToString();
        row.Control.AccessibleDescription = issue != null ? $"Problem: {issue}. {help}" : help;
        row.Control.Enabled = entry["enabled"]?.GetValue<bool>() != false;
        // A value still being typed is the player's, not the backend's.
        if (row.Edited && row.Control.ContainsFocus) return;
        row.Edited = false;
        switch (row.Control)
        {
            case ComboBox box:
                FillChoices(box, entry["options"]?.AsArray(), entry["value"]);
                break;
            case CheckBox check:
                check.Text = name;
                check.Checked = entry["value"]?.GetValue<bool>() == true;
                break;
            case TextBox text:
                string value = FormatValue(entry["value"]);
                if (text.Text != value) text.Text = value;
                break;
        }
    }

    /// <summary>Whole numbers without exponents, however the backend wrote them.</summary>
    private static string FormatValue(JsonNode? value)
    {
        if (value is JsonValue number && number.TryGetValue<double>(out double d))
        {
            return d.ToString("0.##", CultureInfo.InvariantCulture);
        }
        return value?.ToString() ?? "";
    }

    private async Task CommitFieldAsync(FieldRow row)
    {
        if (!row.Edited) return;
        JsonNode? value;
        switch (row.Control)
        {
            case ComboBox box:
                if (box.SelectedItem is not Choice choice) { row.Edited = false; return; }
                value = choice.Value?.DeepClone();
                break;
            case CheckBox check:
                value = check.Checked;
                break;
            case TextBox text when row.Kind == "number":
                if (!double.TryParse(text.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out double number))
                {
                    showMessage($"{row.Control.AccessibleName}: enter a whole number.", MessageBoxIcon.Warning);
                    row.Control.Focus();
                    return;
                }
                value = number;
                break;
            default:
                value = row.Control.Text;
                break;
        }
        row.Edited = false;
        await SendAndApplyAsync("set", new JsonObject { ["field"] = row.Id, ["value"] = value });
    }

    // ---------------------------------------------------------------- actions

    private void ApplyActions(JsonArray? entries)
    {
        var list = entries?.Select(node => node!.AsObject()).ToList() ?? [];
        string signature = string.Join("|", list.Select(a => a["id"]!.ToString()));
        if (signature != actionSignature)
        {
            string? focused = actionButtons.FirstOrDefault(pair => pair.Value.Focused).Key;
            actionSignature = signature;
            actions.Controls.Clear();
            foreach (var button in actionButtons.Values) button.Dispose();
            actionButtons.Clear();
            foreach (var entry in list)
            {
                string id = entry["id"]!.ToString();
                var button = new Button { AutoSize = true };
                button.Click += async (_, _) => await OnActionAsync(id, button);
                actionButtons[id] = button;
                actions.Controls.Add(button);
            }
            if (focused != null && actionButtons.TryGetValue(focused, out var again)) again.Focus();
        }
        foreach (var entry in list)
        {
            var button = actionButtons[entry["id"]!.ToString()];
            button.Text = entry["label"]!.ToString();
            button.Enabled = entry["enabled"]?.GetValue<bool>() != false;
            button.Tag = entry["confirm"]?.ToString();
        }
    }

    private async Task OnActionAsync(string id, Button button)
    {
        await CommitPendingAsync();
        if (button.Tag is string question && MessageBox.Show(this, question, "Save editor",
                MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
        {
            return;
        }
        await SendAndApplyAsync("action", new JsonObject { ["action"] = id });
    }
}
