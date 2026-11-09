package com.pocketaccess.launcher;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.UUID;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * Downloads a mod's zip and unpacks it into the mods folder, the Android twin of the
 * Windows launcher's ModInstaller.cs.  Written for this launcher: upstream's installer
 * is in its proprietary launcher code (LICENSE.MD).  A zip is someone else's file, so
 * nothing is written outside a scratch folder until the game's own manifest check
 * (the mod backend's "check") has passed, and any path that climbs out is refused.
 */
final class ModInstaller {
    /** A problem to read out to the player. */
    static final class InstallException extends Exception {
        InstallException(String message) {
            super(message);
        }
    }

    interface Progress {
        void stage(String stage, int percent);
    }

    /** Judges an unpacked folder, given relative to the save folder; returns the check's answer. */
    interface Check {
        org.json.JSONObject check(String folder) throws Exception;
    }

    private static final String MANIFEST = "manifest.json";
    private static final String INCOMING = "mods-incoming";
    private static final long MAX_DOWNLOAD_BYTES = 2L * 1024 * 1024 * 1024;
    private static final long MAX_UNPACKED_BYTES = 4L * 1024 * 1024 * 1024;
    private static final Pattern PLAIN_NAME = Pattern.compile("^[A-Za-z0-9_@][A-Za-z0-9_@.\\- ]*$");

    private ModInstaller() {}

    /** Installs a listed mod; the zip must hold the listed id.  Returns the check's answer. */
    static org.json.JSONObject installFromUrl(String url, String expectedId, File saveFolder, Check check,
                                              Progress progress) throws InstallException {
        if (url == null || !url.startsWith("https://")) {
            throw new InstallException("The listing's download address is not a secure web address.");
        }
        String scratchName = UUID.randomUUID().toString().replace("-", "");
        File incoming = new File(saveFolder, INCOMING);
        File scratch = new File(incoming, scratchName);
        File zip = new File(incoming, scratchName + ".zip");
        scratch.mkdirs();
        try {
            download(url, zip, progress);
            unpack(zip, scratch, progress);
            progress.stage("Checking", 96);
            org.json.JSONObject verdict;
            try {
                verdict = check.check(INCOMING + "/" + scratchName);
            } catch (Exception error) {
                throw new InstallException("The mod could not be checked: " + error.getMessage());
            }
            if (!verdict.optBoolean("valid")) {
                throw new InstallException("The game would not load this mod: " + verdict.optString("problem"));
            }
            String foundId = verdict.optString("modId");
            if (expectedId != null && !expectedId.equals(foundId)) {
                throw new InstallException("The download holds a different mod (" + foundId + "), so it was not installed.");
            }
            if (!PLAIN_NAME.matcher(foundId).matches()) {
                throw new InstallException("The mod's name, " + foundId + ", cannot be used as a folder name.");
            }
            progress.stage("Installing", 98);
            File mods = new File(saveFolder, "mods");
            mods.mkdirs();
            replace(scratch, new File(mods, foundId));
            return verdict;
        } catch (IOException error) {
            throw new InstallException("The mod could not be installed: " + error.getMessage());
        } finally {
            zip.delete();
            deleteTree(scratch);
            incoming.delete(); // only when empty
        }
    }

    static void remove(File saveFolder, String folder) throws InstallException {
        if (folder == null || !PLAIN_NAME.matcher(folder).matches()) {
            throw new InstallException(folder + " is not a mod folder.");
        }
        File target = new File(new File(saveFolder, "mods"), folder);
        deleteTree(target);
        if (target.exists()) throw new InstallException("The mod could not be removed.");
    }

    private static void download(String url, File zip, Progress progress) throws IOException, InstallException {
        progress.stage("Downloading", 0);
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setRequestProperty("User-Agent", "PocketAccessibility-mods");
        connection.setConnectTimeout(30_000);
        connection.setReadTimeout(120_000);
        try {
            if (connection.getResponseCode() != HttpURLConnection.HTTP_OK) {
                throw new InstallException("The download failed (" + connection.getResponseCode() + ").");
            }
            long size = connection.getContentLengthLong();
            long total = 0;
            int reported = -1;
            try (InputStream body = connection.getInputStream(); OutputStream out = new FileOutputStream(zip)) {
                byte[] buffer = new byte[64 * 1024];
                int read;
                while ((read = body.read(buffer)) > 0) {
                    total += read;
                    if (total > MAX_DOWNLOAD_BYTES) throw new InstallException("The download is too large to be a mod.");
                    out.write(buffer, 0, read);
                    if (size > 0) {
                        int percent = (int) Math.min(80, total * 80 / size);
                        if (percent != reported) progress.stage("Downloading", reported = percent);
                    }
                }
            }
        } finally {
            connection.disconnect();
        }
    }

    /** The shallowest manifest marks the mod's root; only files under it are unpacked. */
    private static void unpack(File zipFile, File destination, Progress progress) throws IOException, InstallException {
        try (ZipFile zip = new ZipFile(zipFile)) {
            String root = null;
            int depth = Integer.MAX_VALUE;
            int atDepth = 0;
            for (java.util.Enumeration<? extends ZipEntry> e = zip.entries(); e.hasMoreElements(); ) {
                String name = e.nextElement().getName().replace('\\', '/');
                if (!(name.equals(MANIFEST) || name.endsWith("/" + MANIFEST))) continue;
                String candidate = name.substring(0, name.length() - MANIFEST.length());
                int slashes = candidate.length() - candidate.replace("/", "").length();
                if (slashes < depth) {
                    depth = slashes;
                    root = candidate;
                    atDepth = 1;
                } else if (slashes == depth) {
                    atDepth++;
                }
            }
            if (root == null) throw new InstallException("The download has no manifest.json, so it is not a mod.");
            if (atDepth > 1) throw new InstallException("The download holds more than one mod, so it was not installed.");
            String base = destination.getCanonicalPath() + File.separator;
            long total = 0;
            byte[] buffer = new byte[64 * 1024];
            for (java.util.Enumeration<? extends ZipEntry> e = zip.entries(); e.hasMoreElements(); ) {
                ZipEntry entry = e.nextElement();
                String name = entry.getName().replace('\\', '/');
                if (!name.startsWith(root)) continue;
                String relative = name.substring(root.length());
                if (relative.isEmpty()) continue;
                File target = new File(destination, relative);
                if (relative.startsWith("/") || relative.contains(":") || relative.contains("../")
                        || relative.equals("..") || !target.getCanonicalPath().startsWith(base)) {
                    throw new InstallException("The mod's zip has a file that points outside its own folder ("
                        + entry.getName() + "), so it was not installed.");
                }
                if (entry.isDirectory()) {
                    target.mkdirs();
                    continue;
                }
                target.getParentFile().mkdirs();
                try (InputStream in = zip.getInputStream(entry); OutputStream out = new FileOutputStream(target)) {
                    int read;
                    while ((read = in.read(buffer)) > 0) {
                        total += read;
                        if (total > MAX_UNPACKED_BYTES) {
                            throw new InstallException("The mod unpacks to more than 4 gigabytes, so it was not installed.");
                        }
                        out.write(buffer, 0, read);
                    }
                }
            }
            progress.stage("Unpacking", 95);
        }
    }

    /** Swaps the new copy in, keeping the old one until the new one is in place, and its imports. */
    private static void replace(File unpacked, File target) throws IOException {
        File retired = new File(target.getPath() + ".old-" + UUID.randomUUID().toString().replace("-", ""));
        boolean hadOld = target.exists();
        if (hadOld && !target.renameTo(retired)) throw new IOException("the old copy could not be moved aside");
        if (!unpacked.renameTo(target)) {
            if (hadOld) retired.renameTo(target);
            throw new IOException("the new copy could not be put in place");
        }
        if (!hadOld) return;
        File oldImports = new File(retired, "baseroms");
        File newImports = new File(target, "baseroms");
        if (oldImports.isDirectory() && !newImports.exists()) oldImports.renameTo(newImports);
        deleteTree(retired);
    }

    private static void deleteTree(File file) {
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) deleteTree(child);
        }
        file.delete();
    }
}
