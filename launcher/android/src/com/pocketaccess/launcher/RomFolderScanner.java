package com.pocketaccess.launcher;

import android.content.ContentResolver;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;

import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayDeque;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/** Finds cartridge dumps in the folder the player chose, identifying each by its SHA-1. */
final class RomFolderScanner {
    private static final long[] ROM_SIZES = {1024 * 1024, 2 * 1024 * 1024, 16 * 1024 * 1024};

    private final ContentResolver resolver;

    RomFolderScanner(ContentResolver resolver) {
        this.resolver = resolver;
    }

    /** Game id to the document holding its dump, for every game found in the folder or below it. */
    Map<String, Uri> scan(Uri tree) {
        Map<String, Uri> found = new HashMap<>();
        ArrayDeque<String> folders = new ArrayDeque<>();
        folders.add(DocumentsContract.getTreeDocumentId(tree));
        while (!folders.isEmpty()) {
            Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, folders.remove());
            String[] columns = {
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
            };
            try (Cursor rows = resolver.query(children, columns, null, null, null)) {
                while (rows != null && rows.moveToNext()) {
                    String id = rows.getString(0);
                    if (DocumentsContract.Document.MIME_TYPE_DIR.equals(rows.getString(2))) {
                        folders.add(id);
                    } else if (looksLikeRom(rows.getString(1), rows.getLong(3))) {
                        Uri document = DocumentsContract.buildDocumentUriUsingTree(tree, id);
                        GameCatalog.Game game = identify(document);
                        if (game != null) found.put(game.id, document);
                    }
                }
            }
        }
        return found;
    }

    private static boolean looksLikeRom(String name, long size) {
        String lower = name == null ? "" : name.toLowerCase(Locale.ROOT);
        if (!(lower.endsWith(".gb") || lower.endsWith(".gbc") || lower.endsWith(".gba"))) return false;
        for (long romSize : ROM_SIZES) {
            if (size == romSize) return true;
        }
        return false;
    }

    private GameCatalog.Game identify(Uri document) {
        try (InputStream input = resolver.openInputStream(document)) {
            if (input == null) return null;
            MessageDigest digest = MessageDigest.getInstance("SHA-1");
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = input.read(buffer)) > 0) digest.update(buffer, 0, read);
            StringBuilder hex = new StringBuilder();
            for (byte value : digest.digest()) hex.append(String.format(Locale.ROOT, "%02x", value));
            return GameCatalog.forSha1(hex.toString());
        } catch (IOException | NoSuchAlgorithmException | SecurityException error) {
            return null; // an unreadable file is simply not a game we can offer
        }
    }
}
