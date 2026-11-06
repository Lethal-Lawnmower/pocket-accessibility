package com.pocketaccess.launcher;

import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.system.ErrnoException;
import android.system.Os;

import org.love2d.android.GameActivity;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Starts the game, the way the Windows launcher's GameRunner does: upstream's
 * main.lua reads POKEPORT_* variables through getenv, and the game's activity
 * runs in this process, so setting them here reaches it.  With a ROM path the
 * game imports first and then boots (docs/access/architecture.md).
 */
final class GameStarter {
    private static final String[] IMPORT_VARIABLES = {
        "POKEPORT_IMPORT_ROM", "POKEPORT_VERSION", "POKEPORT_GAME", "POKEPORT_FORCE_IMPORT",
        "POCKET_EDITOR_PORT", "POCKET_EDITOR_TOKEN",
    };

    private GameStarter() {}

    static File saveFolder(Context context) {
        return new File(context.getExternalFilesDir(null), "save/pokemon-love2d");
    }

    /** Only "imported at some point"; the game runs the full check and refuses a stale import. */
    static boolean isImported(Context context, GameCatalog.Game game) {
        return new File(saveFolder(context), game.id + "/rom-cache.complete").isFile();
    }

    static File importCopy(Context context, GameCatalog.Game game) {
        return new File(context.getCacheDir(), "import-" + game.id + ".rom");
    }

    /** The game can only read plain files, and the chosen folder is a document tree. */
    static void copyForImport(Context context, Uri rom, GameCatalog.Game game) throws IOException {
        ContentResolver resolver = context.getContentResolver();
        try (InputStream input = resolver.openInputStream(rom);
             OutputStream output = new FileOutputStream(importCopy(context, game))) {
            if (input == null) throw new IOException("the ROM could not be opened");
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = input.read(buffer)) > 0) output.write(buffer, 0, read);
        }
    }

    static void deleteImportCopies(Context context) {
        for (GameCatalog.Game game : GameCatalog.ALL) {
            importCopy(context, game).delete();
        }
    }

    /** Starts the game's activity as the save backend instead of the game. */
    static void startSaveBackend(Context context, int port, String token) throws ErrnoException {
        for (String name : IMPORT_VARIABLES) Os.unsetenv(name);
        Os.setenv("POKEPORT_PORTMASTER_MANAGED", "1", true);
        Os.setenv("POCKET_EDITOR_PORT", String.valueOf(port), true);
        Os.setenv("POCKET_EDITOR_TOKEN", token, true);
        context.startActivity(new Intent(context, GameActivity.class));
    }

    /** Starts the game; importing it first when withImport is set. */
    static void start(Context context, GameCatalog.Game game, boolean withImport) throws ErrnoException {
        // The process may outlive an earlier game, with that game's variables still set.
        for (String name : IMPORT_VARIABLES) Os.unsetenv(name);
        // Upstream's self-updater would replace this app with plain upstream.
        Os.setenv("POKEPORT_PORTMASTER_MANAGED", "1", true);
        if (withImport) {
            Os.setenv("POKEPORT_IMPORT_ROM", importCopy(context, game).getAbsolutePath(), true);
            Os.setenv("POKEPORT_VERSION", game.id, true);
            Os.setenv("POKEPORT_FORCE_IMPORT", "1", true);
        }
        Os.setenv("POKEPORT_GAME", game.id, true);
        // Testing period: every spoken line goes to Android's log, so a line the owner
        // did not hear can be compared with what was sent (docs/access/android.md).
        // Decide before a release whether this stays.
        Os.setenv("POKEPORT_ACCESS_TRACE", "1", true);
        // GameActivity hands this extra to love.system.getLaunchGame
        context.startActivity(new Intent(context, GameActivity.class).putExtra("game", game.id));
    }
}
