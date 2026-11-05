package com.pocketaccess.launcher;

import android.content.ContentResolver;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayDeque;
import java.util.Locale;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * Puts Pokémon Access sounds into the save folder, where the game looks for them
 * (src/access/nav/Earcons.lua): from a folder the player has, or, when the player asks,
 * from that project's own GitHub repository.  This project never ships or hosts them
 * (decisions 8 and 51).  Only WAV files in the pack's own folders are kept, and the old
 * pack stays until the new one is complete.
 */
final class SoundPacks {
    /** A problem to read out to the player. */
    static final class SoundPackException extends Exception {
        SoundPackException(String message) {
            super(message);
        }
    }

    interface Progress {
        void percent(int percent);
    }

    private static final String PACK_FOLDER = "pocket-access-sounds";
    private static final String INCOMING_FOLDER = "pocket-access-sounds-incoming";
    private static final long MAX_WAVE_BYTES = 4 * 1024 * 1024; // what the game agrees to load
    private static final long MAX_DOWNLOAD_BYTES = 512L * 1024 * 1024;
    private static final String SOURCE_ZIP = "https://github.com/nuive/pokemon-access/archive/refs/heads/master.zip";
    private static final String BUILT_IN = " You still have the built-in sounds.";

    private SoundPacks() {}

    static boolean isImported(File saveFolder) {
        File pack = new File(saveFolder, PACK_FOLDER);
        return new File(pack, "common").isDirectory() && new File(pack, "gb").isDirectory();
    }

    static void remove(File saveFolder) throws SoundPackException {
        deleteTree(new File(saveFolder, PACK_FOLDER));
        if (new File(saveFolder, PACK_FOLDER).exists()) {
            throw new SoundPackException("The sounds could not be removed.");
        }
    }

    /** Downloads that project's zip and keeps only the sounds from it; returns how many. */
    static int download(File saveFolder, Progress progress) throws SoundPackException {
        saveFolder.mkdirs();
        File zip = new File(saveFolder, "pocket-access-sounds-download.zip");
        try {
            fetch(zip, progress);
            return installFromZip(zip, saveFolder);
        } catch (IOException error) {
            throw new SoundPackException("The download failed: " + error.getMessage() + "." + BUILT_IN);
        } finally {
            zip.delete();
            deleteTree(new File(saveFolder, INCOMING_FOLDER));
        }
    }

    private static void fetch(File zip, Progress progress) throws IOException, SoundPackException {
        HttpURLConnection connection = (HttpURLConnection) new URL(SOURCE_ZIP).openConnection();
        connection.setRequestProperty("User-Agent", "PocketAccessibility-sounds");
        connection.setConnectTimeout(30_000);
        connection.setReadTimeout(60_000);
        try {
            if (connection.getResponseCode() != HttpURLConnection.HTTP_OK) {
                throw new SoundPackException("The sounds aren't at their usual place on GitHub any more ("
                    + connection.getResponseCode() + ")." + BUILT_IN);
            }
            long size = connection.getContentLengthLong();
            try (InputStream body = connection.getInputStream(); OutputStream file = new FileOutputStream(zip)) {
                byte[] buffer = new byte[64 * 1024];
                long total = 0;
                int reported = -1;
                int read;
                while ((read = body.read(buffer)) > 0) {
                    total += read;
                    if (total > MAX_DOWNLOAD_BYTES) {
                        throw new SoundPackException("The download is much larger than expected, so nothing was installed." + BUILT_IN);
                    }
                    file.write(buffer, 0, read);
                    if (size > 0) {
                        int percent = (int) Math.min(99, total * 99 / size);
                        if (percent != reported) progress.percent(reported = percent);
                    }
                }
            }
        } finally {
            connection.disconnect();
        }
    }

    /** Takes only WAV files under the zip's sounds folder; nothing else in it is opened. */
    private static int installFromZip(File zip, File saveFolder) throws IOException, SoundPackException {
        File incoming = new File(saveFolder, INCOMING_FOLDER);
        deleteTree(incoming);
        String root = incoming.getCanonicalPath() + File.separator;
        int copied = 0;
        try (ZipInputStream archive = new ZipInputStream(new FileInputStream(zip))) {
            ZipEntry entry;
            while ((entry = archive.getNextEntry()) != null) {
                String name = entry.getName().replace('\\', '/');
                int marker = name.toLowerCase(Locale.ROOT).indexOf("/sounds/");
                if (marker < 0 || name.indexOf('/') != marker) continue; // <top folder>/sounds/ only
                String relative = name.substring(marker + "/sounds/".length());
                if (!relative.toLowerCase(Locale.ROOT).endsWith(".wav")) continue;
                File destination = new File(root, relative);
                // a name with ".." in it must not land outside the folder
                if (!destination.getCanonicalPath().startsWith(root)) continue;
                if (copyWave(archive, destination)) copied++;
            }
        }
        if (!finish(incoming, copied, saveFolder)) {
            throw new SoundPackException("The download didn't have the sounds in it, so nothing was installed." + BUILT_IN);
        }
        return copied;
    }

    /** Imports from a folder chosen in Android's picker; returns how many sounds. */
    static int importFolder(ContentResolver resolver, Uri tree, File saveFolder) throws SoundPackException {
        saveFolder.mkdirs();
        File incoming = new File(saveFolder, INCOMING_FOLDER);
        deleteTree(incoming);
        try {
            String top = DocumentsContract.getTreeDocumentId(tree);
            String root = hasRequiredFolders(resolver, tree, top) ? top : childFolder(resolver, tree, top, "sounds");
            if (root == null || !hasRequiredFolders(resolver, tree, root)) {
                throw new SoundPackException("This folder doesn't look like Pokémon Access sounds. "
                    + "Choose the sounds folder, the one with the common and gb folders in it.");
            }
            int copied = copyTree(resolver, tree, root, incoming);
            if (!finish(incoming, copied, saveFolder)) {
                throw new SoundPackException("That folder has no usable sound files, so nothing was imported.");
            }
            return copied;
        } catch (IOException | RuntimeException error) {
            throw new SoundPackException("The sounds could not be imported: " + error.getMessage());
        } finally {
            deleteTree(incoming);
        }
    }

    private static int copyTree(ContentResolver resolver, Uri tree, String root, File incoming) throws IOException {
        int copied = 0;
        ArrayDeque<String> folders = new ArrayDeque<>();
        ArrayDeque<File> targets = new ArrayDeque<>();
        folders.add(root);
        targets.add(incoming);
        while (!folders.isEmpty()) {
            String folder = folders.remove();
            File target = targets.remove();
            try (Cursor rows = children(resolver, tree, folder)) {
                while (rows != null && rows.moveToNext()) {
                    String name = rows.getString(1);
                    // Names come from a document provider, so they are checked like a zip's.
                    if (name == null || name.contains("/") || name.equals("..")) continue;
                    if (DocumentsContract.Document.MIME_TYPE_DIR.equals(rows.getString(2))) {
                        folders.add(rows.getString(0));
                        targets.add(new File(target, name));
                    } else if (name.toLowerCase(Locale.ROOT).endsWith(".wav")) {
                        Uri document = DocumentsContract.buildDocumentUriUsingTree(tree, rows.getString(0));
                        try (InputStream input = resolver.openInputStream(document)) {
                            if (input != null && copyWave(input, new File(target, name))) copied++;
                        }
                    }
                }
            }
        }
        return copied;
    }

    private static Cursor children(ContentResolver resolver, Uri tree, String folder) {
        String[] columns = {
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        };
        return resolver.query(DocumentsContract.buildChildDocumentsUriUsingTree(tree, folder), columns, null, null, null);
    }

    private static String childFolder(ContentResolver resolver, Uri tree, String folder, String wanted) {
        try (Cursor rows = children(resolver, tree, folder)) {
            while (rows != null && rows.moveToNext()) {
                if (wanted.equalsIgnoreCase(rows.getString(1))
                    && DocumentsContract.Document.MIME_TYPE_DIR.equals(rows.getString(2))) {
                    return rows.getString(0);
                }
            }
        }
        return null;
    }

    private static boolean hasRequiredFolders(ContentResolver resolver, Uri tree, String folder) {
        return childFolder(resolver, tree, folder, "common") != null
            && childFolder(resolver, tree, folder, "gb") != null;
    }

    /** Copies one sound, refusing anything too large or not really a WAV file. */
    private static boolean copyWave(InputStream input, File destination) throws IOException {
        destination.getParentFile().mkdirs();
        byte[] buffer = new byte[64 * 1024];
        long total = 0;
        byte[] header = new byte[12];
        int headerBytes = 0;
        boolean keep = true;
        try (OutputStream output = new FileOutputStream(destination)) {
            int read;
            while ((read = input.read(buffer)) > 0) {
                total += read;
                if (total > MAX_WAVE_BYTES) {
                    keep = false;
                    break;
                }
                int forHeader = Math.min(read, header.length - headerBytes);
                System.arraycopy(buffer, 0, header, headerBytes, forHeader);
                headerBytes += forHeader;
                output.write(buffer, 0, read);
            }
        }
        keep = keep && headerBytes == header.length
            && header[0] == 'R' && header[1] == 'I' && header[2] == 'F' && header[3] == 'F'
            && header[8] == 'W' && header[9] == 'A' && header[10] == 'V' && header[11] == 'E';
        if (!keep) destination.delete();
        return keep;
    }

    /** Swaps in a complete pack, putting the old one back if that fails. */
    private static boolean finish(File incoming, int copied, File saveFolder) throws SoundPackException {
        if (copied == 0 || !new File(incoming, "common").isDirectory() || !new File(incoming, "gb").isDirectory()) {
            return false;
        }
        File target = new File(saveFolder, PACK_FOLDER);
        File retired = new File(saveFolder, PACK_FOLDER + "-old");
        deleteTree(retired);
        if (target.exists() && !target.renameTo(retired)) {
            throw new SoundPackException("The sounds could not be installed." + BUILT_IN);
        }
        if (!incoming.renameTo(target)) {
            retired.renameTo(target);
            throw new SoundPackException("The sounds could not be installed." + BUILT_IN);
        }
        deleteTree(retired);
        return true;
    }

    private static void deleteTree(File file) {
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) deleteTree(child);
        }
        file.delete();
    }
}
