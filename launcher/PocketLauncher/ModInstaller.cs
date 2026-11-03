using System.IO.Compression;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace PocketLauncher;

/// <summary>A mod that could not be installed; the message is read to the player.</summary>
internal sealed class ModInstallException(string message) : Exception(message);

/// <summary>
/// Downloads a mod's zip and unpacks it into the mods folder.  Written for this
/// launcher: upstream's installer is in its proprietary launcher code (LICENSE.MD),
/// which we may not use.  A zip is someone else's file, so nothing is written
/// outside a scratch folder until the game's own manifest check has passed, and
/// any path that climbs out of that folder is refused.
/// </summary>
internal static partial class ModInstaller
{
    private const string ManifestName = "manifest.json";
    private const string IncomingFolder = "mods-incoming";
    private const long MaxDownloadBytes = 2L * 1024 * 1024 * 1024;
    private const long MaxUnpackedBytes = 4L * 1024 * 1024 * 1024;

    private static readonly HttpClient Http = CreateHttpClient();

    private static HttpClient CreateHttpClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(15) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("PocketAccessibility-mods");
        return client;
    }

    /// <summary>A mod id or folder that is one plain name, never a path.</summary>
    [GeneratedRegex(@"^[A-Za-z0-9_@][A-Za-z0-9_@.\- ]*$")]
    private static partial Regex PlainName();

    /// <summary>Downloads a listed mod and installs it; the zip must hold the listed id.</summary>
    /// <returns>The check's answer about the installed mod.</returns>
    public static Task<JsonObject> InstallFromUrlAsync(string url, string expectedId, string saveDir,
                                                       Func<string, string?> existingFolderFor,
                                                       Func<string, Task<JsonObject>> check)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out Uri? uri) || uri.Scheme != Uri.UriSchemeHttps)
        {
            throw new ModInstallException("The listing's download address is not a secure web address.");
        }
        return InstallAsync(zipPath => DownloadAsync(uri, zipPath), expectedId, saveDir, existingFolderFor, check);
    }

    /// <summary>Installs a zip the player chose; whatever id its manifest names.</summary>
    /// <returns>The check's answer about the installed mod.</returns>
    public static Task<JsonObject> InstallFromFileAsync(string zipFile, string saveDir,
                                                        Func<string, string?> existingFolderFor,
                                                        Func<string, Task<JsonObject>> check) =>
        InstallAsync(zipPath => Task.Run(() => File.Copy(zipFile, zipPath)), null, saveDir, existingFolderFor, check);

    /// <summary>
    /// Fetches the zip, unpacks and checks it, then replaces the mod's folder, if it has one.
    /// <paramref name="check"/> asks the mod backend to judge a folder given relative to the
    /// save folder.  Files the player imported for the mod (baseroms) are carried over.
    /// </summary>
    private static async Task<JsonObject> InstallAsync(Func<string, Task> fetchZip, string? expectedId, string saveDir,
                                                       Func<string, string?> existingFolderFor,
                                                       Func<string, Task<JsonObject>> check)
    {
        string scratchName = Guid.NewGuid().ToString("N");
        string incoming = Path.Combine(saveDir, IncomingFolder);
        string scratch = Path.Combine(incoming, scratchName);
        string zipPath = scratch + ".zip";
        Directory.CreateDirectory(scratch);
        try
        {
            await fetchZip(zipPath);
            await Task.Run(() => Unpack(zipPath, scratch));

            JsonObject verdict = await check($"{IncomingFolder}/{scratchName}");
            if (verdict["valid"]?.GetValue<bool>() != true)
            {
                throw new ModInstallException($"The game would not load this mod: {verdict["problem"]}");
            }
            string foundId = verdict["modId"]?.GetValue<string>() ?? "";
            if (expectedId != null && foundId != expectedId)
            {
                throw new ModInstallException($"The download holds a different mod ({foundId}), so it was not installed.");
            }
            string folderName = existingFolderFor(foundId) ?? foundId;
            if (!PlainName().IsMatch(folderName))
            {
                throw new ModInstallException($"The mod's name, {foundId}, cannot be used as a folder name.");
            }

            string modsDir = Path.Combine(saveDir, "mods");
            Directory.CreateDirectory(modsDir);
            await Task.Run(() => Replace(scratch, Path.Combine(modsDir, folderName)));
            return verdict;
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException)
        {
            throw new ModInstallException($"The download failed: {error.Message}");
        }
        catch (Exception error) when (error is InvalidDataException or IOException or UnauthorizedAccessException)
        {
            throw new ModInstallException($"The mod could not be unpacked: {error.Message}");
        }
        finally
        {
            TryDelete(() => File.Delete(zipPath));
            TryDelete(() => Directory.Delete(scratch, true));
            TryDelete(() => Directory.Delete(incoming)); // only succeeds when empty
        }
    }

    private static async Task DownloadAsync(Uri uri, string zipPath)
    {
        using HttpResponseMessage response = await Http.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();
        await using Stream body = await response.Content.ReadAsStreamAsync();
        await using FileStream file = File.Create(zipPath);
        var buffer = new byte[81920];
        long total = 0;
        int read;
        while ((read = await body.ReadAsync(buffer)) > 0)
        {
            total += read;
            if (total > MaxDownloadBytes) throw new ModInstallException("The download is too large to be a mod.");
            await file.WriteAsync(buffer.AsMemory(0, read));
        }
    }

    /// <summary>
    /// Mods are zipped with the manifest at the top or one folder down, so the shallowest
    /// manifest marks the mod's root, and only files under that root are unpacked.
    /// </summary>
    private static void Unpack(string zipPath, string destination)
    {
        using ZipArchive archive = ZipFile.OpenRead(zipPath);
        string root = FindModRoot(archive);
        string destinationRoot = Path.GetFullPath(destination) + Path.DirectorySeparatorChar;
        long total = 0;
        var buffer = new byte[81920];
        foreach (ZipArchiveEntry entry in archive.Entries)
        {
            string name = entry.FullName.Replace('\\', '/');
            if (!name.StartsWith(root, StringComparison.Ordinal)) continue;
            string relative = name[root.Length..];
            if (relative.Length == 0) continue;
            string target = Path.GetFullPath(Path.Combine(destinationRoot, relative));
            if (!IsSafeRelative(relative) || !target.StartsWith(destinationRoot, StringComparison.OrdinalIgnoreCase))
            {
                throw new ModInstallException($"The mod's zip has a file that points outside its own folder ({entry.FullName}), so it was not installed.");
            }
            if (relative.EndsWith('/'))
            {
                Directory.CreateDirectory(target);
                continue;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            using Stream input = entry.Open();
            using FileStream output = File.Create(target);
            int read;
            while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
            {
                total += read;
                if (total > MaxUnpackedBytes) throw new ModInstallException("The mod unpacks to more than 4 gigabytes, so it was not installed.");
                output.Write(buffer, 0, read);
            }
        }
    }

    private static string FindModRoot(ZipArchive archive)
    {
        var manifests = archive.Entries
            .Select(entry => entry.FullName.Replace('\\', '/'))
            .Where(name => name == ManifestName || name.EndsWith("/" + ManifestName, StringComparison.Ordinal))
            .Select(name => name[..^ManifestName.Length])
            .ToList();
        if (manifests.Count == 0) throw new ModInstallException("The download has no manifest.json, so it is not a mod.");
        int shallowest = manifests.Min(root => root.Count(c => c == '/'));
        var candidates = manifests.Where(root => root.Count(c => c == '/') == shallowest).ToList();
        if (candidates.Count > 1) throw new ModInstallException("The download holds more than one mod, so it was not installed.");
        return candidates[0];
    }

    private static bool IsSafeRelative(string relative)
    {
        if (relative.StartsWith('/') || relative.Contains(':')) return false;
        return relative.Split('/').All(segment => segment != "..");
    }

    /// <summary>Swaps the new copy in, keeping the old one until the new one is in place.</summary>
    private static void Replace(string unpacked, string target)
    {
        string retired = target + ".old-" + Guid.NewGuid().ToString("N");
        bool hadOld = Directory.Exists(target);
        if (hadOld) Directory.Move(target, retired);
        try
        {
            Directory.Move(unpacked, target);
        }
        catch
        {
            if (hadOld) Directory.Move(retired, target);
            throw;
        }
        if (!hadOld) return;
        string oldImports = Path.Combine(retired, "baseroms");
        string newImports = Path.Combine(target, "baseroms");
        if (Directory.Exists(oldImports) && !Directory.Exists(newImports)) Directory.Move(oldImports, newImports);
        TryDelete(() => Directory.Delete(retired, true));
    }

    /// <summary>Deletes a mod from the save folder's mods folder.</summary>
    public static void Remove(string saveDir, string folder)
    {
        if (!PlainName().IsMatch(folder)) throw new ModInstallException($"{folder} is not a mod folder.");
        Directory.Delete(Path.Combine(saveDir, "mods", folder), true);
    }

    private static void TryDelete(Action delete)
    {
        try
        {
            delete();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // scratch files only; a leftover is harmless
        }
    }
}
