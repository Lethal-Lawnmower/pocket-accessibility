package com.pocketaccess.launcher;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.os.Bundle;
import android.system.ErrnoException;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.Spinner;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * The save editor screen, the Android counterpart of the Windows window
 * (SaveEditorForm.cs): only standard controls, and no save logic of its own.  Upstream's
 * editor logic runs in the game's activity, behind this screen (AndroidSaveBackend.lua).
 */
public final class SaveEditorActivity extends Activity implements SaveEditorPage.Host {
    static final String EXTRA_GAME = "game";
    private static final int MENU_SAVE = 1;
    private static final int MENU_UNDO = 2;
    private static final int MENU_REDO = 3;
    private static final int MENU_RELOAD = 4;
    private static final int MENU_CLOSE = 5;

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Map<String, SaveEditorPage> pages = new HashMap<>();
    private final List<String> pageIds = new ArrayList<>();
    private final List<String> pageLabels = new ArrayList<>();
    private BackendClient backend;
    private TextView status;
    private TextView pageLabel;
    private Spinner pagePicker;
    private FrameLayout pageHolder;
    private SaveEditorPage current;
    private String gameId;
    private boolean dirty;
    private boolean opened;
    private boolean closing;

    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        gameId = getIntent().getStringExtra(EXTRA_GAME);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int margin = (int) (8 * getResources().getDisplayMetrics().density);
        root.setPadding(margin, margin, margin, margin);
        status = new TextView(this);
        // read out when it changes, without moving focus
        status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        status.setText("Loading. This can take a few seconds.");
        root.addView(status);
        pagePicker = new Spinner(this);
        pagePicker.setId(View.generateViewId());
        pageLabel = new TextView(this);
        pageLabel.setText("Page");
        pageLabel.setLabelFor(pagePicker.getId());
        pageLabel.setVisibility(View.GONE);
        pagePicker.setVisibility(View.GONE);
        root.addView(pageLabel);
        root.addView(pagePicker);
        pageHolder = new FrameLayout(this);
        root.addView(pageHolder, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
        // A wrapper, because fitting the system bars replaces a view's own padding.
        FrameLayout window = new FrameLayout(this);
        window.setFitsSystemWindows(true);
        window.addView(root);
        setContentView(window);
        BackKey.route(this, this::requestClose);

        startBackend();
    }

    /** The game's activity comes up in front for a moment, then this screen returns on top of it. */
    private void startBackend() {
        try {
            backend = new BackendClient();
            GameStarter.startSaveBackend(this, backend.port(), backend.token());
        } catch (IOException | ErrnoException error) {
            fail("The save editor could not start: " + error.getMessage());
            return;
        }
        worker.execute(() -> {
            try {
                backend.waitForBackend();
                JSONObject request = new JSONObject().put("version", gameId);
                JSONObject answer = backend.send("open", request);
                runOnUiThread(() -> {
                    startActivity(new Intent(this, SaveEditorActivity.class)
                        .addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));
                    onOpened(answer);
                });
            } catch (IOException | JSONException error) {
                runOnUiThread(() -> fail("The save editor could not start: " + error.getMessage()));
            }
        });
    }

    private void onOpened(JSONObject answer) {
        if (!answer.optBoolean("ok")) {
            fail("The save could not be opened: " + firstLine(answer.optString("error")));
            return;
        }
        if (!answer.isNull("missingCache") && answer.has("missingCache")) {
            fail(answer.optString("missingCache"));
            return;
        }
        setTitle(answer.optString("title", "Save editor"));
        if (answer.has("corrupt") && !answer.isNull("corrupt")) {
            showMessage("This save could not be read, so saving is turned off. " + answer.optString("status"));
        }
        JSONArray list = answer.optJSONArray("pages");
        for (int i = 0; list != null && i < list.length(); i++) {
            JSONObject page = list.optJSONObject(i);
            pageIds.add(page.optString("id"));
            pageLabels.add(page.optString("label"));
        }
        pagePicker.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, pageLabels));
        pagePicker.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                showPage(pageIds.get(position));
            }

            @Override
            public void onNothingSelected(AdapterView<?> parent) {}
        });
        pageLabel.setVisibility(View.VISIBLE);
        pagePicker.setVisibility(View.VISIBLE);
        opened = true;
        applyStatus(answer, false);
        status.setText("Editing your " + answer.optString("title", "save") + ".");
        invalidateOptionsMenu();
        pagePicker.requestFocus();
    }

    private void showPage(String id) {
        commitTyping();
        SaveEditorPage page = pages.get(id);
        if (page == null) {
            page = new SaveEditorPage(this, id, this);
            pages.put(id, page);
            pageHolder.addView(page);
        }
        if (current != null) current.setVisibility(View.GONE);
        current = page;
        page.setVisibility(View.VISIBLE);
        page.refresh();
    }

    /** A value still being typed counts; losing focus sends it, ahead of what comes next. */
    private void commitTyping() {
        View focused = getCurrentFocus();
        if (focused != null) focused.clearFocus();
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        menu.add(Menu.NONE, MENU_SAVE, Menu.NONE, "Save").setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM);
        menu.add(Menu.NONE, MENU_UNDO, Menu.NONE, "Undo");
        menu.add(Menu.NONE, MENU_REDO, Menu.NONE, "Redo");
        menu.add(Menu.NONE, MENU_RELOAD, Menu.NONE, "Reload from storage");
        menu.add(Menu.NONE, MENU_CLOSE, Menu.NONE, "Close");
        return true;
    }

    @Override
    public boolean onPrepareOptionsMenu(Menu menu) {
        for (int id : new int[] {MENU_SAVE, MENU_UNDO, MENU_REDO, MENU_RELOAD}) {
            menu.findItem(id).setEnabled(opened);
        }
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        switch (item.getItemId()) {
            case MENU_SAVE:
                commitTyping();
                send("save", null, response -> {});
                return true;
            case MENU_UNDO:
                history("undo");
                return true;
            case MENU_REDO:
                history("redo");
                return true;
            case MENU_RELOAD:
                reload();
                return true;
            case MENU_CLOSE:
                requestClose();
                return true;
            default:
                return super.onOptionsItemSelected(item);
        }
    }

    private void history(String command) {
        commitTyping();
        send(command, null, response -> {
            if (response.optBoolean("changed") && current != null) current.refresh();
        });
    }

    private void reload() {
        Runnable doReload = () -> send("reload", null, response -> {
            pages.clear();
            pageHolder.removeAllViews();
            current = null;
            int position = pagePicker.getSelectedItemPosition();
            if (position >= 0) showPage(pageIds.get(position));
        });
        if (!dirty) {
            doReload.run();
            return;
        }
        new AlertDialog.Builder(this)
            .setMessage("Discard your unsaved changes and reload the save from storage?")
            .setPositiveButton("Discard", (dialog, which) -> doReload.run())
            .setNegativeButton("Keep editing", null)
            .show();
    }

    @Override
    public void onBackPressed() {
        requestClose();
    }

    private void requestClose() {
        commitTyping();
        // through the worker, so anything typed has been answered first
        send("model-free", null, response -> {
            if (!dirty) {
                closeEditor();
                return;
            }
            new AlertDialog.Builder(this)
                .setMessage("Save your changes before closing?")
                .setPositiveButton("Save", (dialog, which) -> send("save", null, saved -> {
                    if (saved.optBoolean("saved")) closeEditor();
                }))
                .setNegativeButton("Don't save", (dialog, which) -> closeEditor())
                .setNeutralButton("Cancel", null)
                .show();
        });
    }

    /** Finishes both activities first: the backend's exit ends this process, and what is left is the launcher. */
    /** However this screen ends, the backend behind it must not stay in front. */
    @Override
    protected void onDestroy() {
        if (isFinishing() && !closing) closeEditor();
        super.onDestroy();
    }

    private void closeEditor() {
        if (closing) return;
        closing = true;
        PocketApplication.finishGameActivity();
        finish();
        worker.execute(() -> {
            if (backend != null) backend.close();
        });
        worker.shutdown();
    }

    @Override
    public void send(String command, JSONObject arguments, SaveEditorPage.Answer answer) {
        if (closing) return;
        if (command.equals("model-free")) {
            worker.execute(() -> runOnUiThread(() -> answer.received(new JSONObject())));
            return;
        }
        worker.execute(() -> {
            try {
                JSONObject response = backend.send(command, arguments);
                runOnUiThread(() -> {
                    if (!response.optBoolean("ok")) {
                        showMessage("That did not work: " + firstLine(response.optString("error", "unknown error")));
                    }
                    applyStatus(response, true);
                    answer.received(response);
                });
            } catch (IOException | JSONException error) {
                runOnUiThread(() -> fail("The save editor stopped: " + error.getMessage()));
            }
        });
    }

    private void applyStatus(JSONObject response, boolean announce) {
        if (response.has("dirty")) dirty = response.optBoolean("dirty");
        String title = getTitle().toString().replaceAll(", unsaved changes$", "");
        setTitle(dirty ? title + ", unsaved changes" : title);
        if (announce && response.has("message") && !response.isNull("message")) {
            String text = response.optString("message");
            status.setText(text);
            if ("error".equals(response.optString("messageKind"))) showMessage(text);
        }
    }

    @Override
    public void showMessage(String text) {
        if (isFinishing()) return;
        new AlertDialog.Builder(this).setMessage(text).setPositiveButton("Close", null).show();
    }

    private void fail(String message) {
        if (isFinishing()) return;
        new AlertDialog.Builder(this)
            .setMessage(message)
            .setCancelable(false)
            .setPositiveButton("Close", (dialog, which) -> closeEditor())
            .show();
    }

    private static String firstLine(String text) {
        int end = text.indexOf('\n');
        return end < 0 ? text : text.substring(0, end);
    }
}
