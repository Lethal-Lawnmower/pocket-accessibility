package com.pocketaccess.launcher;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.os.Bundle;
import android.system.ErrnoException;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.Spinner;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * The Mods screen, the Android counterpart of the Windows Mods window (ModsForm.cs):
 * installed mods with on/off per game, and the community mod index to install from.
 * Only standard controls.  The index, manifest checks and enable-state are upstream's
 * own code, run as the mod backend in the game's activity behind this screen
 * (launcher/ModBackend/modservice.lua through src/access/AndroidSaveBackend.lua);
 * downloading and unpacking are ModInstaller's.
 */
public final class ModsActivity extends Activity {
    static final String EXTRA_GAME = "game";
    private static final String WARNING_ACCEPTED = "pocket-access-mods-warning-accepted";
    private static final String[] VIEWS = { "Installed mods", "Browse the mod index" };

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final List<JSONObject> rows = new ArrayList<>();
    private BackendClient backend;
    private TextView status;
    private Spinner gamePicker;
    private Spinner viewPicker;
    private ListView list;
    private ArrayAdapter<JSONObject> adapter;
    private final List<GameCatalog.Game> games = new ArrayList<>();
    private boolean closing;
    private boolean busy;

    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        setTitle("Mods");
        for (GameCatalog.Game game : GameCatalog.ALL) {
            if (GameStarter.isImported(this, game)) games.add(game);
        }

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int margin = (int) (8 * getResources().getDisplayMetrics().density);
        root.setPadding(margin, margin, margin, margin);
        status = new TextView(this);
        status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        status.setText("Loading the mods. This can take a few seconds.");
        root.addView(status);

        gamePicker = labelled(root, "Game");
        String[] names = new String[games.size()];
        int chosen = 0;
        String wanted = getIntent().getStringExtra(EXTRA_GAME);
        for (int i = 0; i < names.length; i++) {
            names[i] = games.get(i).name;
            if (games.get(i).id.equals(wanted)) chosen = i;
        }
        gamePicker.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, names));
        gamePicker.setSelection(chosen);
        viewPicker = labelled(root, "Show");
        viewPicker.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, VIEWS));

        list = new ListView(this);
        adapter = new ArrayAdapter<JSONObject>(this, android.R.layout.simple_list_item_2, android.R.id.text1, rows) {
            @Override
            public View getView(int position, View reuse, ViewGroup parent) {
                View row = super.getView(position, reuse, parent);
                JSONObject mod = getItem(position);
                ((TextView) row.findViewById(android.R.id.text1)).setText(title(mod));
                ((TextView) row.findViewById(android.R.id.text2)).setText(subtitle(mod));
                return row;
            }
        };
        list.setAdapter(adapter);
        list.setOnItemClickListener((parent, view, position, id) -> choose(rows.get(position)));
        root.addView(list, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));

        FrameLayout window = new FrameLayout(this);
        window.setFitsSystemWindows(true);
        window.addView(root);
        setContentView(window);
        BackKey.route(this, this::onBackPressed);

        if (games.isEmpty()) {
            fail("Play a game once first, so its data is imported; mods are turned on per game.");
            return;
        }
        if (!new File(GameStarter.saveFolder(this), WARNING_ACCEPTED).exists()) {
            new AlertDialog.Builder(this)
                .setTitle("Mods")
                .setMessage("Mods are not endorsed or tested by Pocket Accessibility. Accessibility may break, "
                    + "so use them at your own risk. Mods are other people's code, and they run on your device.")
                .setCancelable(false)
                .setPositiveButton("OK", (dialog, which) -> {
                    File folder = GameStarter.saveFolder(this);
                    folder.mkdirs();
                    try {
                        new File(folder, WARNING_ACCEPTED).createNewFile();
                    } catch (IOException ignored) {
                        // asked again next time
                    }
                    startBackend();
                })
                .setNegativeButton("Cancel", (dialog, which) -> finish())
                .show();
        } else {
            startBackend();
        }
    }

    private Spinner labelled(LinearLayout root, String text) {
        Spinner spinner = new Spinner(this);
        spinner.setId(View.generateViewId());
        TextView label = new TextView(this);
        label.setText(text);
        label.setLabelFor(spinner.getId());
        root.addView(label);
        root.addView(spinner);
        return spinner;
    }

    private GameCatalog.Game game() {
        int position = gamePicker.getSelectedItemPosition();
        return games.get(Math.max(0, Math.min(games.size() - 1, position)));
    }

    private boolean browsing() {
        return viewPicker.getSelectedItemPosition() == 1;
    }

    /** The game's activity comes up in front for a moment, then this screen returns on top of it. */
    private void startBackend() {
        try {
            backend = new BackendClient();
            GameStarter.startBackend(this, "mods", backend.port(), backend.token());
        } catch (IOException | ErrnoException error) {
            fail("The Mods screen could not start: " + error.getMessage());
            return;
        }
        worker.execute(() -> {
            try {
                backend.waitForBackend();
                runOnUiThread(() -> {
                    startActivity(new Intent(this, ModsActivity.class).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));
                    AdapterView.OnItemSelectedListener reload = new AdapterView.OnItemSelectedListener() {
                        @Override
                        public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                            refresh(false);
                        }

                        @Override
                        public void onNothingSelected(AdapterView<?> parent) {}
                    };
                    gamePicker.setOnItemSelectedListener(reload);
                    viewPicker.setOnItemSelectedListener(reload);
                    refresh(false);
                });
            } catch (IOException error) {
                runOnUiThread(() -> fail("The Mods screen could not start: " + error.getMessage()));
            }
        });
    }

    private void refresh(boolean force) {
        if (closing || busy) return;
        boolean index = browsing();
        String gameId = game().id;
        say(index ? "Fetching the mod index." : "Reading your mods.");
        worker.execute(() -> {
            try {
                JSONObject request = new JSONObject().put("version", gameId).put("force", force);
                JSONObject answer = backend.send(index ? "index" : "installed", request);
                runOnUiThread(() -> show(answer, index));
            } catch (IOException | JSONException error) {
                runOnUiThread(() -> fail("The mod backend stopped: " + error.getMessage()));
            }
        });
    }

    private void show(JSONObject answer, boolean index) {
        if (!answer.optBoolean("ok")) {
            say("That did not work: " + answer.optString("error"));
            return;
        }
        rows.clear();
        JSONArray mods = answer.optJSONArray("mods");
        for (int i = 0; mods != null && i < mods.length(); i++) rows.add(mods.optJSONObject(i));
        adapter.notifyDataSetChanged();
        String count = rows.size() + (rows.size() == 1 ? " mod" : " mods");
        if (index) {
            StringBuilder text = new StringBuilder(count + " in the index.");
            if (answer.optBoolean("stale")) text.append(" The list could not be refreshed, so it may be out of date.");
            say(text.toString());
        } else {
            say(rows.isEmpty() ? "No mods installed. Choose Browse the mod index to find some." : count + " installed.");
        }
    }

    private static String title(JSONObject mod) {
        String name = mod.optString("title", mod.optString("name", mod.optString("folder", "?")));
        String version = mod.optString("version", "");
        return version.isEmpty() ? name : name + ", version " + version;
    }

    private String subtitle(JSONObject mod) {
        List<String> parts = new ArrayList<>();
        if (mod.has("problem")) parts.add("The game cannot load it: " + mod.optString("problem"));
        if (mod.has("enabled")) parts.add(mod.optBoolean("enabled") ? "On" : "Off");
        if (mod.has("installedVersion")) parts.add("installed " + mod.optString("installedVersion"));
        if (mod.has("forThisGame") && !mod.optBoolean("forThisGame") && (mod.has("enabled") || mod.optBoolean("gamesListed"))) {
            parts.add("not for " + game().name);
        }
        if (mod.has("unavailable")) parts.add("cannot be installed: " + mod.optString("unavailable"));
        String about = mod.optString("summary", mod.optString("description", ""));
        if (!about.isEmpty()) parts.add(about);
        return String.join(". ", parts);
    }

    private void choose(JSONObject mod) {
        if (busy) return;
        List<String> actions = new ArrayList<>();
        List<Runnable> runs = new ArrayList<>();
        if (browsing()) {
            if (mod.has("url") && !mod.isNull("url")) {
                boolean installed = mod.has("installedVersion");
                actions.add(installed ? "Install again or update" : "Install");
                runs.add(() -> confirmInstall(mod));
            }
        } else if (mod.has("id")) {
            boolean on = mod.optBoolean("enabled");
            actions.add(on ? "Turn off for " + game().name : "Turn on for " + game().name);
            runs.add(() -> setEnabled(mod, !on));
        }
        if (!browsing() && mod.optBoolean("removable")) {
            actions.add("Remove");
            runs.add(() -> confirmRemove(mod));
        }
        actions.add("Details");
        runs.add(() -> details(mod));
        new AlertDialog.Builder(this)
            .setTitle(title(mod))
            .setItems(actions.toArray(new String[0]), (dialog, which) -> runs.get(which).run())
            .setNegativeButton("Cancel", null)
            .show();
    }

    private void details(JSONObject mod) {
        StringBuilder text = new StringBuilder(subtitle(mod));
        if (mod.has("author")) text.append("\n\nBy ").append(mod.optString("author"));
        if (mod.has("games")) text.append("\n\nGames: ").append(mod.optString("games"));
        JSONArray permissions = mod.optJSONArray("permissions");
        if (permissions != null && permissions.length() > 0) {
            List<String> asked = new ArrayList<>();
            for (int i = 0; i < permissions.length(); i++) asked.add(permissions.optString(i));
            text.append("\n\nIt asks for: ").append(String.join(", ", asked));
        }
        JSONArray warnings = mod.optJSONArray("warnings");
        for (int i = 0; warnings != null && i < warnings.length(); i++) {
            text.append("\n\nWarning: ").append(warnings.optString(i));
        }
        if (mod.has("license")) text.append("\n\nLicense: ").append(mod.optString("license"));
        new AlertDialog.Builder(this).setTitle(title(mod)).setMessage(text.toString())
            .setPositiveButton("Close", null).show();
    }

    private void confirmInstall(JSONObject mod) {
        JSONArray warnings = mod.optJSONArray("warnings");
        StringBuilder text = new StringBuilder("Download and install " + title(mod) + "?");
        for (int i = 0; warnings != null && i < warnings.length(); i++) {
            text.append("\n\nWarning: ").append(warnings.optString(i));
        }
        new AlertDialog.Builder(this).setMessage(text.toString())
            .setPositiveButton("Install", (dialog, which) -> install(mod))
            .setNegativeButton("Cancel", null).show();
    }

    private void install(JSONObject mod) {
        busy = true;
        String gameId = game().id;
        File saveFolder = GameStarter.saveFolder(this);
        say("Installing " + title(mod) + ".");
        worker.execute(() -> {
            int[] lastSaid = {-25};
            try {
                JSONObject verdict = ModInstaller.installFromUrl(mod.optString("url"), mod.optString("id"), saveFolder,
                    folder -> backend.send("check", new JSONObject().put("folder", folder).put("version", gameId)),
                    (stage, percent) -> {
                        if (percent >= lastSaid[0] + 25) {
                            lastSaid[0] = percent;
                            runOnUiThread(() -> say(stage + ", " + percent + " percent."));
                        }
                    });
                String done = "Installed " + verdict.optString("name") + ".";
                if (!verdict.optBoolean("forThisGame", true)) done += " It does not list " + game().name + ".";
                else if (!verdict.optBoolean("enabled", true)) done += " It is off; turn it on in Installed mods.";
                String message = done;
                runOnUiThread(() -> {
                    busy = false;
                    say(message + " It takes effect the next time you start the game.");
                    refresh(false);
                });
            } catch (ModInstaller.InstallException error) {
                runOnUiThread(() -> {
                    busy = false;
                    say(error.getMessage());
                });
            }
        });
    }

    private void setEnabled(JSONObject mod, boolean on) {
        String gameId = game().id;
        worker.execute(() -> {
            try {
                JSONObject answer = backend.send("setEnabled", new JSONObject()
                    .put("modId", mod.optString("id")).put("enabled", on).put("version", gameId));
                runOnUiThread(() -> {
                    if (!answer.optBoolean("ok")) {
                        say("That did not work: " + answer.optString("error"));
                        return;
                    }
                    say(title(mod) + (on ? " is on" : " is off") + " for " + game().name + ".");
                    refresh(false);
                });
            } catch (IOException | JSONException error) {
                runOnUiThread(() -> fail("The mod backend stopped: " + error.getMessage()));
            }
        });
    }

    private void confirmRemove(JSONObject mod) {
        new AlertDialog.Builder(this).setMessage("Remove " + title(mod) + "? Its files are deleted.")
            .setPositiveButton("Remove", (dialog, which) -> {
                try {
                    ModInstaller.remove(GameStarter.saveFolder(this), mod.optString("folder"));
                    say("Removed " + title(mod) + ".");
                    refresh(false);
                } catch (ModInstaller.InstallException error) {
                    say(error.getMessage());
                }
            })
            .setNegativeButton("Cancel", null).show();
    }

    private void say(String text) {
        status.setText(text);
        status.announceForAccessibility(text);
    }

    @Override
    public void onBackPressed() {
        if (busy) {
            say("Please wait for the install to finish.");
            return;
        }
        closeScreen();
    }

    /** Finishes both activities first: the backend's exit ends this process, and what is left is the launcher. */
    private void closeScreen() {
        if (closing) return;
        closing = true;
        PocketApplication.finishGameActivity();
        finish();
        worker.execute(() -> {
            if (backend != null) backend.close();
        });
        worker.shutdown();
    }

    /** However this screen ends, the backend behind it must not stay in front. */
    @Override
    protected void onDestroy() {
        if (isFinishing() && !closing) closeScreen();
        super.onDestroy();
    }

    private void fail(String message) {
        if (isFinishing()) return;
        new AlertDialog.Builder(this).setMessage(message).setCancelable(false)
            .setPositiveButton("Close", (dialog, which) -> closeScreen()).show();
    }
}
