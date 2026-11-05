package com.pocketaccess.launcher;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.system.ErrnoException;
import android.view.ContextMenu;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * The launcher: choose a folder of cartridge dumps once, then a plain list of the
 * games found there.  Selecting a game imports it if needed and starts it.  Only
 * standard Android controls, so TalkBack, touch and a D-pad all work without any
 * speech code here.
 */
public final class MainActivity extends Activity {
    /** Required by License Term 1, visibly, in any launcher. */
    private static final String UPSTREAM_CREDIT =
        "Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC "
            + "(https://github.com/bryanthaboi/gen1recomp)";

    private static final String REFUSAL_FILE = "pocket-access-start-refused.txt";
    private static final String PREFS = "launcher";
    private static final String PREF_FOLDER = "folder";
    private static final String PREF_ROM = "rom.";
    private static final int REQUEST_FOLDER = 1;
    private static final int MENU_REFRESH = 1;
    private static final int MENU_FOLDER = 2;
    private static final int MENU_CREDITS = 3;
    private static final int MENU_EDIT_SAVE = 4;
    private static final int MENU_DOWNLOAD_SOUNDS = 5;
    private static final int MENU_IMPORT_SOUNDS = 6;
    private static final int MENU_REMOVE_SOUNDS = 7;
    private static final int REQUEST_SOUNDS_FOLDER = 2;
    private static final String SOUNDS_NOTICE_FILE = "pocket-access-sounds-notice-shown";
    /** Long enough for TalkBack to say what is about to happen before the game's window opens. */
    private static final long IMPORT_NOTICE_MILLIS = 3000;

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler ui = new Handler(Looper.getMainLooper());
    private SharedPreferences prefs;
    private TextView message;
    private Button chooseFolder;
    private ListView list;
    private ArrayAdapter<GameCatalog.Game> rows;
    private final List<GameCatalog.Game> shown = new ArrayList<>();
    private boolean busy;

    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int margin = (int) (16 * getResources().getDisplayMetrics().density);
        root.setPadding(margin, margin, margin, margin);

        message = new TextView(this);
        message.setTextAppearance(android.R.style.TextAppearance_Medium);
        root.addView(message);

        chooseFolder = new Button(this);
        chooseFolder.setText("Choose ROM folder");
        chooseFolder.setOnClickListener(view -> pickFolder());
        root.addView(chooseFolder);

        list = new ListView(this);
        rows = new ArrayAdapter<GameCatalog.Game>(this, android.R.layout.simple_list_item_2,
            android.R.id.text1, shown) {
            @Override
            public View getView(int position, View reuse, ViewGroup parent) {
                View row = super.getView(position, reuse, parent);
                GameCatalog.Game game = getItem(position);
                ((TextView) row.findViewById(android.R.id.text1)).setText(game.name);
                ((TextView) row.findViewById(android.R.id.text2)).setText(
                    GameStarter.isImported(MainActivity.this, game)
                        ? "Ready" : "Imports the first time you play");
                return row;
            }
        };
        list.setAdapter(rows);
        list.setOnItemClickListener((parent, view, position, id) -> play(shown.get(position), false));
        root.addView(list, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));

        TextView credit = new TextView(this);
        credit.setText(UPSTREAM_CREDIT);
        credit.setTextAppearance(android.R.style.TextAppearance_Small);
        root.addView(credit);

        // A wrapper, because fitting the system bars replaces a view's own padding.
        FrameLayout window = new FrameLayout(this);
        window.setFitsSystemWindows(true);
        window.addView(root);
        setContentView(window);

        // long press, which TalkBack offers too; the menu has the same thing for a controller
        registerForContextMenu(list);

        Uri folder = savedFolder();
        if (folder != null && knownRoms().isEmpty()) scan(folder);
        showSoundsNotice();
    }

    @Override
    public void onCreateContextMenu(ContextMenu menu, View view, ContextMenu.ContextMenuInfo info) {
        menu.add(Menu.NONE, MENU_EDIT_SAVE, Menu.NONE, "Edit save");
    }

    @Override
    public boolean onContextItemSelected(MenuItem item) {
        AdapterView.AdapterContextMenuInfo info = (AdapterView.AdapterContextMenuInfo) item.getMenuInfo();
        if (item.getItemId() != MENU_EDIT_SAVE || info == null) return super.onContextItemSelected(item);
        editSave(shown.get(info.position));
        return true;
    }

    private void editSave(GameCatalog.Game game) {
        if (busy) return;
        if (!GameStarter.isImported(this, game)) {
            say("Play " + game.name + " once first, so its data is imported.");
            return;
        }
        busy = true;
        startActivity(new Intent(this, SaveEditorActivity.class).putExtra(SaveEditorActivity.EXTRA_GAME, game.id));
    }

    private void chooseGameToEdit() {
        List<GameCatalog.Game> imported = new ArrayList<>();
        for (GameCatalog.Game game : GameCatalog.ALL) {
            if (GameStarter.isImported(this, game)) imported.add(game);
        }
        if (imported.isEmpty()) {
            say("Play a game once first, so its data is imported.");
            return;
        }
        String[] names = new String[imported.size()];
        for (int i = 0; i < names.length; i++) names[i] = imported.get(i).name;
        new AlertDialog.Builder(this)
            .setTitle("Edit which save?")
            .setItems(names, (dialog, which) -> editSave(imported.get(which)))
            .setNegativeButton("Cancel", null)
            .show();
    }

    // ------------------------------------------------------------------ sounds

    /** Once only: says the Pokémon Access sounds aren't included, and offers to fetch them. */
    private void showSoundsNotice() {
        File folder = GameStarter.saveFolder(this);
        File marker = new File(folder, SOUNDS_NOTICE_FILE);
        if (marker.exists() || SoundPacks.isImported(folder)) return;
        folder.mkdirs();
        try {
            marker.createNewFile();
        } catch (IOException error) {
            return; // a notice shown on every start would be worse than none
        }
        new AlertDialog.Builder(this)
            .setTitle("Pokémon Access sounds")
            .setMessage("Pocket Accessibility doesn't come with the Pokémon Access sounds. The built-in sounds are "
                + "only meant to hold you over until you get them. Want to download them now?\n\n"
                + "They come straight from the Pokémon Access project on GitHub. You can also do this later "
                + "from this screen's menu: choose Download Pokémon Access sounds.")
            .setPositiveButton("Download sounds", (dialog, which) -> downloadSounds())
            .setNegativeButton("Not now", null)
            .show();
    }

    private void downloadSounds() {
        if (busy) return;
        busy = true;
        File folder = GameStarter.saveFolder(this);
        say("Downloading the Pokémon Access sounds.");
        worker.execute(() -> {
            int[] lastSaid = {0};
            try {
                int count = SoundPacks.download(folder, percent -> {
                    if (percent >= lastSaid[0] + 25) {
                        lastSaid[0] = percent;
                        runOnUiThread(() -> say("Downloading the sounds, " + percent + " percent."));
                    }
                });
                finishSounds("Done. " + count + " sounds are ready, and the game uses them from its next start.");
            } catch (SoundPacks.SoundPackException error) {
                finishSounds(error.getMessage());
            }
        });
    }

    private void finishSounds(String text) {
        runOnUiThread(() -> {
            busy = false;
            say(text);
        });
    }

    private void removeSounds() {
        if (!SoundPacks.isImported(GameStarter.saveFolder(this))) {
            say("No Pokémon Access sounds are installed.");
            return;
        }
        try {
            SoundPacks.remove(GameStarter.saveFolder(this));
            say("Removed. The game goes back to the built-in sounds from its next start.");
        } catch (SoundPacks.SoundPackException error) {
            say(error.getMessage());
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        busy = false;
        GameStarter.deleteImportCopies(this);
        refreshList();
        showRefusal();
    }

    @Override
    protected void onDestroy() {
        worker.shutdown();
        super.onDestroy();
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        menu.add(Menu.NONE, MENU_REFRESH, Menu.NONE, "Refresh game list");
        menu.add(Menu.NONE, MENU_FOLDER, Menu.NONE, "Choose ROM folder");
        menu.add(Menu.NONE, MENU_EDIT_SAVE, Menu.NONE, "Edit a save");
        menu.add(Menu.NONE, MENU_DOWNLOAD_SOUNDS, Menu.NONE, "Download Pokémon Access sounds");
        menu.add(Menu.NONE, MENU_IMPORT_SOUNDS, Menu.NONE, "Import Pokémon Access sounds");
        menu.add(Menu.NONE, MENU_REMOVE_SOUNDS, Menu.NONE, "Remove Pokémon Access sounds");
        menu.add(Menu.NONE, MENU_CREDITS, Menu.NONE, "Credits");
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        switch (item.getItemId()) {
            case MENU_REFRESH:
                Uri folder = savedFolder();
                if (folder != null) scan(folder);
                else pickFolder();
                return true;
            case MENU_FOLDER:
                pickFolder();
                return true;
            case MENU_EDIT_SAVE:
                chooseGameToEdit();
                return true;
            case MENU_DOWNLOAD_SOUNDS:
                downloadSounds();
                return true;
            case MENU_IMPORT_SOUNDS:
                if (!busy) startActivityForResult(new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQUEST_SOUNDS_FOLDER);
                return true;
            case MENU_REMOVE_SOUNDS:
                removeSounds();
                return true;
            case MENU_CREDITS:
                new AlertDialog.Builder(this)
                    .setTitle("Credits")
                    .setMessage("Pocket Accessibility: screen reader accessibility for the "
                        + "Pokémon recompilation games.\n\n" + UPSTREAM_CREDIT
                        + "\n\nSpeech by Prism (MPL-2.0).")
                    .setPositiveButton("Close", null)
                    .show();
                return true;
            default:
                return super.onOptionsItemSelected(item);
        }
    }

    private void pickFolder() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
        startActivityForResult(intent, REQUEST_FOLDER);
    }

    @Override
    protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (result != RESULT_OK || data == null || data.getData() == null) return;
        Uri folder = data.getData();
        if (request == REQUEST_SOUNDS_FOLDER) {
            busy = true;
            say("Importing the sounds.");
            worker.execute(() -> {
                try {
                    int count = SoundPacks.importFolder(getContentResolver(), folder, GameStarter.saveFolder(this));
                    finishSounds("Done. " + count + " sounds are ready, and the game uses them from its next start.");
                } catch (SoundPacks.SoundPackException error) {
                    finishSounds(error.getMessage());
                }
            });
            return;
        }
        if (request != REQUEST_FOLDER) return;
        getContentResolver().takePersistableUriPermission(folder, Intent.FLAG_GRANT_READ_URI_PERMISSION);
        prefs.edit().putString(PREF_FOLDER, folder.toString()).apply();
        scan(folder);
    }

    private Uri savedFolder() {
        String folder = prefs.getString(PREF_FOLDER, null);
        return folder == null ? null : Uri.parse(folder);
    }

    private Uri romFor(GameCatalog.Game game) {
        String rom = prefs.getString(PREF_ROM + game.id, null);
        return rom == null ? null : Uri.parse(rom);
    }

    private List<GameCatalog.Game> knownRoms() {
        List<GameCatalog.Game> known = new ArrayList<>();
        for (GameCatalog.Game game : GameCatalog.ALL) {
            if (romFor(game) != null) known.add(game);
        }
        return known;
    }

    private void scan(Uri folder) {
        say("Looking for games. This can take a moment.");
        chooseFolder.setEnabled(false);
        worker.execute(() -> {
            Map<String, Uri> found;
            try {
                found = new RomFolderScanner(getContentResolver()).scan(folder);
            } catch (RuntimeException error) {
                // the folder may be gone, or its permission revoked
                runOnUiThread(() -> {
                    chooseFolder.setEnabled(true);
                    say("That folder could not be read. Choose it again.");
                });
                return;
            }
            SharedPreferences.Editor edit = prefs.edit();
            for (GameCatalog.Game game : GameCatalog.ALL) {
                Uri rom = found.get(game.id);
                if (rom != null) edit.putString(PREF_ROM + game.id, rom.toString());
                else edit.remove(PREF_ROM + game.id);
            }
            edit.apply();
            runOnUiThread(() -> {
                chooseFolder.setEnabled(true);
                refreshList();
                if (shown.isEmpty()) say("No games found in that folder.");
                else say("Found " + found.size() + (found.size() == 1 ? " game." : " games."));
            });
        });
    }

    /** Games with a known dump, plus any imported earlier whose dump has since moved. */
    private void refreshList() {
        shown.clear();
        for (GameCatalog.Game game : GameCatalog.ALL) {
            if (romFor(game) != null || GameStarter.isImported(this, game)) shown.add(game);
        }
        rows.notifyDataSetChanged();
        boolean noFolder = savedFolder() == null;
        chooseFolder.setVisibility(shown.isEmpty() ? View.VISIBLE : View.GONE);
        if (shown.isEmpty()) {
            message.setText(noFolder
                ? "Choose the folder that holds your cartridge dumps. Games are not included."
                : "No games found. Choose another folder, or add your cartridge dumps and refresh.");
            chooseFolder.requestFocus();
        } else {
            message.setText("Select a game to play.");
            list.requestFocus();
        }
    }

    private void say(String text) {
        message.setText(text);
        message.announceForAccessibility(text);
    }

    private void play(GameCatalog.Game game, boolean forceImport) {
        if (busy) return;
        boolean needImport = forceImport || !GameStarter.isImported(this, game);
        Uri rom = romFor(game);
        if (needImport && rom == null) {
            say(game.name + " needs importing, but its dump was not found. Choose its folder.");
            return;
        }
        busy = true;
        if (!needImport) {
            startGame(game, false);
            return;
        }
        say("Importing " + game.name + ". This can take a minute or two, and the game speaks when it is ready.");
        worker.execute(() -> {
            try {
                GameStarter.copyForImport(this, rom, game);
                ui.postDelayed(() -> startGame(game, true), IMPORT_NOTICE_MILLIS);
            } catch (IOException | SecurityException error) {
                runOnUiThread(() -> {
                    busy = false;
                    say("The dump for " + game.name + " could not be read. Refresh the game list and try again.");
                });
            }
        });
    }

    private void startGame(GameCatalog.Game game, boolean withImport) {
        try {
            GameStarter.start(this, game, withImport);
        } catch (ErrnoException error) {
            busy = false;
            say(game.name + " could not be started: " + error.getMessage());
        }
    }

    /** The game writes why it would not start here (src/access/PackagedBuild.lua). */
    private void showRefusal() {
        File file = new File(GameStarter.saveFolder(this), REFUSAL_FILE);
        if (!file.isFile()) return;
        String reason;
        try {
            reason = new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8);
        } catch (IOException error) {
            reason = "The game did not start, and its reason could not be read.";
        }
        file.delete();
        new AlertDialog.Builder(this)
            .setTitle("The game did not start")
            .setMessage(reason)
            .setPositiveButton("Close", null)
            .show();
    }
}
