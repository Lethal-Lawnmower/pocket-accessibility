package com.pocketaccess.launcher;

import android.app.AlertDialog;
import android.content.Context;
import android.content.res.Configuration;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;

/**
 * One page of the save editor, drawn from the backend's description, as on Windows
 * (launcher/PocketLauncher/PagePanel.cs): the list on one side; pickers, summary,
 * fields and buttons on the other, so the list's recycling never nests in a scroll
 * view.  Controls are kept and updated in place between answers, so focus and
 * TalkBack's position do not jump.  A typed value is sent when focus leaves its box
 * or on the keyboard's Done; a choice as soon as it is made.
 */
final class SaveEditorPage extends LinearLayout {
    /** How a page talks to the editor screen. */
    interface Host {
        void send(String command, JSONObject arguments, Answer answer);

        void showMessage(String text);
    }

    interface Answer {
        void received(JSONObject response);
    }

    private static final class Row {
        final String id;
        final String text;
        final boolean checked;

        Row(String id, String text, boolean checked) {
            this.id = id;
            this.text = text;
            this.checked = checked;
        }

        @Override
        public String toString() {
            return text;
        }
    }

    private static final class Choice {
        final Object value;
        final String label;

        Choice(Object value, String label) {
            this.value = value;
            this.label = label;
        }

        @Override
        public String toString() {
            return label;
        }
    }

    /** A dropdown; `known` is the value the backend last gave, so setting it sends nothing. */
    private final class ChoiceBox {
        final Spinner spinner = new Spinner(getContext());
        final List<Choice> choices = new ArrayList<>();
        final ArrayAdapter<Choice> adapter = new ArrayAdapter<>(getContext(),
            android.R.layout.simple_spinner_dropdown_item, choices);
        String known = "";

        ChoiceBox(ChoiceSent onChosen) {
            spinner.setAdapter(adapter);
            spinner.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
                @Override
                public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                    if (position >= choices.size()) return;
                    Choice choice = choices.get(position);
                    if (!valueText(choice.value).equals(known)) {
                        known = valueText(choice.value);
                        onChosen.chosen(choice.value);
                    }
                }

                @Override
                public void onNothingSelected(AdapterView<?> parent) {}
            });
        }

        void update(JSONArray options, Object value) throws JSONException {
            List<Choice> fresh = new ArrayList<>();
            for (int i = 0; options != null && i < options.length(); i++) {
                JSONObject option = options.getJSONObject(i);
                fresh.add(new Choice(option.opt("value"), option.getString("label")));
            }
            boolean same = fresh.size() == choices.size();
            for (int i = 0; same && i < fresh.size(); i++) {
                same = fresh.get(i).label.equals(choices.get(i).label);
            }
            if (!same) {
                choices.clear();
                choices.addAll(fresh);
                adapter.notifyDataSetChanged();
            }
            known = valueText(value);
            for (int i = 0; i < fresh.size(); i++) {
                if (valueText(fresh.get(i).value).equals(known)) {
                    if (spinner.getSelectedItemPosition() != i) spinner.setSelection(i);
                    break;
                }
            }
        }
    }

    private interface ChoiceSent {
        void chosen(Object value);
    }

    private final class Field {
        final String id;
        final String kind;
        final TextView label = new TextView(getContext());
        final TextView note = new TextView(getContext());
        View control;
        ChoiceBox box;
        String name = "";
        boolean edited;

        Field(String id, String kind) {
            this.id = id;
            this.kind = kind;
        }
    }

    private final String pageId;
    private final Host host;
    private final TextView listLabel = new TextView(getContext());
    private final EditText filter = new EditText(getContext());
    private final ListView list = new ListView(getContext());
    private final LinearLayout listSide = new LinearLayout(getContext());
    private final LinearLayout topPickers = column();
    private final TextView summary = new TextView(getContext());
    private final LinearLayout lowerPickers = column();
    private final LinearLayout fieldsBox = column();
    private final LinearLayout actionsBox = column();

    private final List<Row> shownRows = new ArrayList<>();
    private List<Row> allRows = new ArrayList<>();
    private ArrayAdapter<Row> rowsAdapter;
    private boolean checksMode;
    private String selectedRow;
    private String filterOwner = "";
    private boolean updating;
    private final Map<String, ChoiceBox> pickers = new HashMap<>();
    private final Map<String, TextView> pickerLabels = new HashMap<>();
    private final Map<String, Field> fields = new HashMap<>();
    private final Map<String, Button> actions = new HashMap<>();
    private String pickerSignature = "";
    private String fieldSignature = "";
    private String actionSignature = "";

    SaveEditorPage(Context context, String pageId, Host host) {
        super(context);
        this.pageId = pageId;
        this.host = host;
        boolean wide = context.getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE;
        setOrientation(wide ? HORIZONTAL : VERTICAL);

        listSide.setOrientation(VERTICAL);
        listLabel.setTextAppearance(android.R.style.TextAppearance_Medium);
        listSide.addView(listLabel);
        filter.setHint("Filter");
        filter.setSingleLine(true);
        filter.setImeOptions(EditorInfo.IME_ACTION_DONE);
        filter.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence text, int start, int count, int after) {}

            @Override
            public void onTextChanged(CharSequence text, int start, int before, int count) {}

            @Override
            public void afterTextChanged(Editable text) {
                if (!updating) showRows();
            }
        });
        listSide.addView(filter);
        listSide.addView(list, new LayoutParams(LayoutParams.MATCH_PARENT, 0, 1));
        list.setOnItemClickListener((parent, view, position, id) -> onRowClicked(position));
        addView(listSide, wide
            ? new LayoutParams(0, LayoutParams.MATCH_PARENT, 1)
            : new LayoutParams(LayoutParams.MATCH_PARENT, 0, 1));

        LinearLayout details = column();
        details.addView(topPickers);
        summary.setTextAppearance(android.R.style.TextAppearance_Small);
        // focusable so TalkBack and a D-pad can both stop on it
        summary.setFocusable(true);
        details.addView(summary);
        details.addView(lowerPickers);
        details.addView(fieldsBox);
        details.addView(actionsBox);
        ScrollView scroll = new ScrollView(context);
        scroll.addView(details);
        addView(scroll, wide
            ? new LayoutParams(0, LayoutParams.MATCH_PARENT, 1)
            : new LayoutParams(LayoutParams.MATCH_PARENT, 0, 1));
    }

    private LinearLayout column() {
        LinearLayout layout = new LinearLayout(getContext());
        layout.setOrientation(VERTICAL);
        return layout;
    }

    void refresh() {
        send("model", new JSONObject());
    }

    private void send(String command, JSONObject arguments) {
        try {
            arguments.put("page", pageId);
        } catch (JSONException impossible) {
            throw new IllegalStateException(impossible);
        }
        host.send(command, arguments, response -> {
            JSONObject model = response.optJSONObject("model");
            if (model != null) apply(model);
        });
    }

    private void sendWith(String command, String key, Object value, String key2, Object value2) {
        JSONObject arguments = new JSONObject();
        try {
            arguments.put(key, value == null ? JSONObject.NULL : value);
            if (key2 != null) arguments.put(key2, value2);
        } catch (JSONException impossible) {
            throw new IllegalStateException(impossible);
        }
        send(command, arguments);
    }

    private void apply(JSONObject model) {
        updating = true;
        try {
            applyPickers(model.optJSONArray("pickers"));
            String text = model.optString("summary", "");
            summary.setVisibility(model.has("summary") ? VISIBLE : GONE);
            if (!summary.getText().toString().equals(text)) summary.setText(text);
            applyList(model.optJSONObject("list"));
            applyFields(model.optJSONArray("fields"));
            applyActions(model.optJSONArray("actions"));
        } catch (JSONException error) {
            host.showMessage("The save editor could not read that page: " + error.getMessage());
        } finally {
            updating = false;
        }
    }

    // ---------------------------------------------------------------- pickers

    private void applyPickers(JSONArray entries) throws JSONException {
        StringBuilder signature = new StringBuilder();
        for (int i = 0; entries != null && i < entries.length(); i++) {
            JSONObject entry = entries.getJSONObject(i);
            signature.append(entry.getString("id")).append('/').append(entry.has("below")).append('|');
        }
        if (!signature.toString().equals(pickerSignature)) {
            pickerSignature = signature.toString();
            topPickers.removeAllViews();
            lowerPickers.removeAllViews();
            pickers.clear();
            pickerLabels.clear();
            for (int i = 0; entries != null && i < entries.length(); i++) {
                JSONObject entry = entries.getJSONObject(i);
                String id = entry.getString("id");
                ChoiceBox box = new ChoiceBox(value -> sendWith("pick", "picker", id, "value", orNull(value)));
                box.spinner.setId(View.generateViewId());
                TextView label = new TextView(getContext());
                label.setLabelFor(box.spinner.getId());
                LinearLayout target = entry.optBoolean("below") ? lowerPickers : topPickers;
                target.addView(label);
                target.addView(box.spinner);
                pickers.put(id, box);
                pickerLabels.put(id, label);
            }
        }
        for (int i = 0; entries != null && i < entries.length(); i++) {
            JSONObject entry = entries.getJSONObject(i);
            String id = entry.getString("id");
            pickerLabels.get(id).setText(entry.getString("label"));
            pickers.get(id).update(entry.optJSONArray("options"), entry.opt("value"));
        }
    }

    // ------------------------------------------------------------------- list

    private void applyList(JSONObject model) throws JSONException {
        if (model == null) {
            listSide.setVisibility(GONE);
            allRows = new ArrayList<>();
            return;
        }
        listSide.setVisibility(VISIBLE);
        String label = model.optString("label", "");
        listLabel.setText(label);
        boolean filtered = model.optBoolean("filter");
        filter.setVisibility(filtered ? VISIBLE : GONE);
        // a filter from another view, or one with no box to clear it, must not hide rows
        if ((!filtered || !label.equals(filterOwner)) && filter.getText().length() > 0) filter.setText("");
        filterOwner = label;
        boolean checks = model.optBoolean("checks");
        if (rowsAdapter == null || checks != checksMode) {
            checksMode = checks;
            shownRows.clear();
            rowsAdapter = new ArrayAdapter<>(getContext(), checks
                ? android.R.layout.simple_list_item_multiple_choice
                : android.R.layout.simple_list_item_activated_1, shownRows);
            list.setChoiceMode(checks ? ListView.CHOICE_MODE_MULTIPLE : ListView.CHOICE_MODE_SINGLE);
            list.setAdapter(rowsAdapter);
        }
        allRows = new ArrayList<>();
        JSONArray rows = model.optJSONArray("rows");
        for (int i = 0; rows != null && i < rows.length(); i++) {
            JSONObject row = rows.getJSONObject(i);
            allRows.add(new Row(row.get("id").toString(), row.getString("text"), row.optBoolean("checked")));
        }
        selectedRow = model.has("selected") && !model.isNull("selected") ? model.get("selected").toString() : null;
        showRows();
    }

    private void showRows() {
        String query = filter.getText().toString().trim().toLowerCase(Locale.ROOT);
        List<Row> rows = new ArrayList<>();
        for (Row row : allRows) {
            if (query.isEmpty() || row.text.toLowerCase(Locale.ROOT).contains(query)) rows.add(row);
        }
        boolean same = rows.size() == shownRows.size();
        for (int i = 0; same && i < rows.size(); i++) {
            same = rows.get(i).id.equals(shownRows.get(i).id) && rows.get(i).text.equals(shownRows.get(i).text);
        }
        shownRows.clear();
        shownRows.addAll(rows);
        // Rebuilding a long list unchanged would make TalkBack lose its place.
        if (!same) rowsAdapter.notifyDataSetChanged();
        for (int i = 0; i < rows.size(); i++) {
            boolean on = checksMode ? rows.get(i).checked : rows.get(i).id.equals(selectedRow);
            if (list.isItemChecked(i) != on) list.setItemChecked(i, on);
        }
    }

    private void onRowClicked(int position) {
        if (position >= shownRows.size()) return;
        Row row = shownRows.get(position);
        if (checksMode) {
            sendWith("toggle", "row", row.id, "checked", list.isItemChecked(position));
        } else {
            selectedRow = row.id;
            sendWith("select", "row", row.id, null, null);
        }
    }

    // ----------------------------------------------------------------- fields

    private void applyFields(JSONArray entries) throws JSONException {
        StringBuilder signature = new StringBuilder();
        for (int i = 0; entries != null && i < entries.length(); i++) {
            JSONObject entry = entries.getJSONObject(i);
            signature.append(entry.getString("id")).append('/').append(entry.optString("kind", "info")).append('|');
        }
        if (!signature.toString().equals(fieldSignature)) {
            fieldSignature = signature.toString();
            fieldsBox.removeAllViews();
            fields.clear();
            for (int i = 0; entries != null && i < entries.length(); i++) {
                JSONObject entry = entries.getJSONObject(i);
                Field field = newField(entry.getString("id"), entry.optString("kind", "info"));
                fields.put(field.id, field);
                if (!(field.control instanceof CheckBox) && !field.kind.equals("info")) fieldsBox.addView(field.label);
                fieldsBox.addView(field.control);
                fieldsBox.addView(field.note);
            }
        }
        for (int i = 0; entries != null && i < entries.length(); i++) {
            JSONObject entry = entries.getJSONObject(i);
            updateField(fields.get(entry.getString("id")), entry);
        }
    }

    private Field newField(String id, String kind) {
        Field field = new Field(id, kind);
        field.note.setTextAppearance(android.R.style.TextAppearance_Small);
        field.note.setVisibility(GONE);
        switch (kind) {
            case "choice":
                field.box = new ChoiceBox(value -> sendWith("set", "field", id, "value", orNull(value)));
                field.control = field.box.spinner;
                break;
            case "check":
                CheckBox check = new CheckBox(getContext());
                check.setOnClickListener(view -> sendWith("set", "field", id, "value", check.isChecked()));
                field.control = check;
                break;
            case "info":
                TextView info = new TextView(getContext());
                info.setFocusable(true);
                field.control = info;
                break;
            default:
                EditText text = new EditText(getContext());
                text.setSingleLine(true);
                text.setImeOptions(EditorInfo.IME_ACTION_DONE);
                if (kind.equals("number")) {
                    text.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_SIGNED);
                }
                text.addTextChangedListener(new TextWatcher() {
                    @Override
                    public void beforeTextChanged(CharSequence value, int start, int count, int after) {}

                    @Override
                    public void onTextChanged(CharSequence value, int start, int before, int count) {}

                    @Override
                    public void afterTextChanged(Editable value) {
                        if (!updating) field.edited = true;
                    }
                });
                text.setOnFocusChangeListener((view, focused) -> {
                    if (!focused) commit(field);
                });
                text.setOnEditorActionListener((view, action, event) -> {
                    commit(field);
                    return false;
                });
                field.control = text;
        }
        field.control.setId(View.generateViewId());
        field.label.setLabelFor(field.control.getId());
        return field;
    }

    private void updateField(Field field, JSONObject entry) throws JSONException {
        field.name = entry.optString("label", field.id);
        String range = entry.has("lo") && entry.has("hi")
            ? ", " + formatValue(entry.get("lo")) + " to " + formatValue(entry.get("hi")) : "";
        field.label.setText(field.name + range);
        field.control.setEnabled(entry.optBoolean("enabled", true));
        String issue = entry.optString("issue", "");
        String help = entry.optString("help", "");
        String note = (issue.isEmpty() ? "" : "Problem: " + issue + ". ") + help;
        field.note.setText(note);
        field.note.setVisibility(note.isEmpty() ? GONE : VISIBLE);
        // A value still being typed is the player's, not the backend's.
        if (field.edited && field.control.hasFocus()) return;
        field.edited = false;
        Object value = entry.opt("value");
        if (field.box != null) {
            field.box.update(entry.optJSONArray("options"), value);
        } else if (field.control instanceof CheckBox) {
            CheckBox check = (CheckBox) field.control;
            check.setText(field.name);
            check.setChecked(Boolean.TRUE.equals(value));
        } else if (field.control instanceof EditText) {
            EditText text = (EditText) field.control;
            String shown = formatValue(value);
            if (!text.getText().toString().equals(shown)) text.setText(shown);
        } else {
            ((TextView) field.control).setText(field.name + ": " + formatValue(value));
        }
    }

    private void commit(Field field) {
        if (!field.edited) return;
        String typed = ((EditText) field.control).getText().toString().trim();
        Object value = typed;
        if (field.kind.equals("number")) {
            try {
                value = Long.parseLong(typed);
            } catch (NumberFormatException error) {
                host.showMessage(field.name + ": enter a whole number.");
                return;
            }
        }
        field.edited = false;
        sendWith("set", "field", field.id, "value", value);
    }

    // ---------------------------------------------------------------- actions

    private void applyActions(JSONArray entries) throws JSONException {
        StringBuilder signature = new StringBuilder();
        for (int i = 0; entries != null && i < entries.length(); i++) {
            signature.append(entries.getJSONObject(i).getString("id")).append('|');
        }
        if (!signature.toString().equals(actionSignature)) {
            actionSignature = signature.toString();
            actionsBox.removeAllViews();
            actions.clear();
            for (int i = 0; entries != null && i < entries.length(); i++) {
                String id = entries.getJSONObject(i).getString("id");
                Button button = new Button(getContext());
                button.setAllCaps(false);
                button.setOnClickListener(view -> onAction(id, button));
                actions.put(id, button);
                actionsBox.addView(button);
            }
        }
        for (int i = 0; entries != null && i < entries.length(); i++) {
            JSONObject entry = entries.getJSONObject(i);
            Button button = actions.get(entry.getString("id"));
            button.setText(entry.getString("label"));
            button.setEnabled(entry.optBoolean("enabled", true));
            button.setTag(entry.isNull("confirm") ? null : entry.optString("confirm", null));
        }
    }

    private void onAction(String id, Button button) {
        View focused = findFocus();
        if (focused != null) focused.clearFocus(); // a value still being typed counts
        Object question = button.getTag();
        if (question == null) {
            sendWith("action", "action", id, null, null);
            return;
        }
        new AlertDialog.Builder(getContext())
            .setMessage(question.toString())
            .setPositiveButton("Yes", (dialog, which) -> sendWith("action", "action", id, null, null))
            .setNegativeButton("No", null)
            .show();
    }

    // ------------------------------------------------------------------ values

    private static Object orNull(Object value) {
        return value == null ? JSONObject.NULL : value;
    }

    /** Numbers compare and read without exponents or a trailing .0, however they were written. */
    private static String valueText(Object value) {
        if (value == null || value == JSONObject.NULL) return "";
        return formatValue(value);
    }

    private static String formatValue(Object value) {
        if (value == null || value == JSONObject.NULL) return "";
        if (value instanceof Number) {
            double number = ((Number) value).doubleValue();
            if (number == Math.rint(number) && !Double.isInfinite(number)) {
                return String.format(Locale.ROOT, "%.0f", number);
            }
            return String.valueOf(number);
        }
        return Objects.toString(value);
    }
}
