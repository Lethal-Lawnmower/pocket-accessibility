using System.Diagnostics;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace PocketUpdater;

/// <summary>A problem to read to the player; the installed folder is as it was.</summary>
internal sealed class UpdateException(string message) : Exception(message);

/// <summary>How far an update has got: a stage, and a percent of the whole, or null when unknown.</summary>
internal readonly record struct UpdateProgress(string Stage, int? Percent);

/// <summary>The newest release this updater may install.</summary>
internal sealed record ReleaseInfo(Version Version, string Tag, string Notes, Uri ZipUrl, string Sha256);

/// <summary>
/// Finds, checks and installs a release.  Only this repository's releases over https, and only a
/// zip whose SHA-256 matches what GitHub reports for it.  Nothing in the program folder changes
/// until the new copy is unpacked and checked, and the old copy is kept until the new one is in
/// place.  Saves, imported games and mods are in the save folder, so they are not involved.
/// </summary>
internal static partial class UpdateEngine
{
    public const string ReleasesApi = "https://api.github.com/repos/Lethal-Lawnmower/pocket-accessibility/releases/latest";
    private const string VersionFile = "version.txt";
    private const string IncomingFolder = "update-incoming";
    private const string RetiredFolder = "update-old";
    private const string UpdaterFile = "PocketUpdater.exe";
    private const long MaxDownloadBytes = 1024L * 1024 * 1024;
    private const long MaxUnpackedBytes = 2L * 1024 * 1024 * 1024;
    private const int DownloadEndsAt = 70, UnpackEndsAt = 95, InstallAt = 97;

    // What makes a folder a Pocket Accessibility package, in a download and when installed.
    private static readonly string[] RequiredFiles =
        ["PocketLauncher.exe", "PocketUpdater.exe", VersionFile, "game/main.lua", "game/pocket-access-package.txt", "love/love.exe"];

    private static readonly HttpClient Http = CreateHttpClient();

    private static HttpClient CreateHttpClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(20) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("PocketAccessibility-updater");
        return client;
    }

    [GeneratedRegex(@"^PocketAccessibility-.+-windows-x64\.zip$", RegexOptions.IgnoreCase)]
    private static partial Regex ZipName();

    [GeneratedRegex(@"^[0-9a-f]{64}$")]
    private static partial Regex Sha256Text();

    /// <summary>A version from a tag or file ("v0.0.1", "0.0.1"), or null.</summary>
    public static Version? ParseVersion(string? text)
    {
        string trimmed = (text ?? "").Trim().TrimStart('v', 'V');
        return Version.TryParse(trimmed, out Version? version) ? version : null;
    }

    /// <summary>The version in a program folder, or null when it does not say.</summary>
    public static Version? InstalledVersion(string programDir)
    {
        string file = Path.Combine(programDir, VersionFile);
        return File.Exists(file) ? ParseVersion(File.ReadAllText(file)) : null;
    }

    /// <summary>Whether this folder is a package; a source checkout has no version file.</summary>
    public static bool IsPackagedFolder(string programDir) =>
        RequiredFiles.All(file => File.Exists(Path.Combine(programDir, file)));

    /// <summary>The newest release, or null when the repository has none yet.</summary>
    public static async Task<ReleaseInfo?> LatestReleaseAsync()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, ReleasesApi);
        request.Headers.Accept.ParseAdd("application/vnd.github+json");
        try
        {
            using HttpResponseMessage response = await Http.SendAsync(request);
            if (response.StatusCode == System.Net.HttpStatusCode.NotFound) return null;
            response.EnsureSuccessStatusCode();
            return ParseRelease(await response.Content.ReadAsStringAsync());
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException)
        {
            throw new UpdateException($"Could not reach GitHub: {error.Message}");
        }
    }

    /// <summary>Reads GitHub's answer about a release; refuses one it cannot trust.</summary>
    public static ReleaseInfo ParseRelease(string json)
    {
        JsonNode root;
        try
        {
            root = JsonNode.Parse(json) ?? throw new UpdateException("GitHub's answer was empty.");
        }
        catch (System.Text.Json.JsonException)
        {
            throw new UpdateException("GitHub's answer could not be read.");
        }
        string tag = root["tag_name"]?.GetValue<string>() ?? "";
        Version version = ParseVersion(tag) ?? throw new UpdateException($"The release's version, {tag}, could not be read.");
        JsonNode? asset = root["assets"]?.AsArray().FirstOrDefault(item =>
            item?["name"]?.GetValue<string>() is string name && ZipName().IsMatch(name));
        if (asset == null) throw new UpdateException($"Release {tag} has no Windows download.");
        string url = asset["browser_download_url"]?.GetValue<string>() ?? "";
        const string Allowed = "https://github.com/Lethal-Lawnmower/pocket-accessibility/releases/download/";
        if (!url.StartsWith(Allowed, StringComparison.Ordinal) || !Uri.TryCreate(url, UriKind.Absolute, out Uri? uri))
        {
            throw new UpdateException($"Release {tag}'s download is not on this project's releases.");
        }
        string digest = asset["digest"]?.GetValue<string>() ?? "";
        string sha = digest.StartsWith("sha256:", StringComparison.Ordinal) ? digest["sha256:".Length..].ToLowerInvariant() : "";
        if (!Sha256Text().IsMatch(sha)) throw new UpdateException($"GitHub gave no checksum for release {tag}, so it was not installed.");
        return new ReleaseInfo(version, tag, root["body"]?.GetValue<string>() ?? "", uri, sha);
    }

    /// <summary>The whole update: download, check, unpack, swap.</summary>
    public static async Task InstallAsync(ReleaseInfo release, string programDir, IProgress<UpdateProgress>? progress = null)
    {
        EnsureNothingRunning(programDir);
        string incoming = Path.Combine(programDir, IncomingFolder);
        RemoveLeftovers(programDir);
        Directory.CreateDirectory(incoming);
        string zipPath = Path.Combine(incoming, "download.zip");
        try
        {
            await DownloadAsync(release.ZipUrl, zipPath, progress);
            await Task.Run(() => InstallZip(zipPath, release.Sha256, release.Version, programDir, progress));
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException)
        {
            throw new UpdateException($"The download failed: {error.Message}");
        }
        finally
        {
            RemoveLeftovers(programDir);
        }
    }

    /// <summary>Checks a downloaded zip, unpacks it, and swaps it in.</summary>
    public static void InstallZip(string zipPath, string expectedSha256, Version expectedVersion, string programDir, IProgress<UpdateProgress>? progress = null)
    {
        progress?.Report(new UpdateProgress("Checking the download", DownloadEndsAt));
        string actual;
        using (FileStream stream = File.OpenRead(zipPath)) actual = Convert.ToHexStringLower(SHA256.HashData(stream));
        if (actual != expectedSha256) throw new UpdateException("The download does not match GitHub's checksum, so it was not installed.");

        string unpacked = Path.Combine(programDir, IncomingFolder, "unpacked");
        try
        {
            string root = Unpack(zipPath, unpacked, progress);
            foreach (string file in RequiredFiles)
            {
                if (!File.Exists(Path.Combine(root, file))) throw new UpdateException($"The download is missing {file}, so it was not installed.");
            }
            if (InstalledVersion(root) != expectedVersion)
            {
                throw new UpdateException($"The download says it is a different version from release {expectedVersion}, so it was not installed.");
            }
            progress?.Report(new UpdateProgress("Installing", InstallAt));
            Swap(root, programDir);
        }
        catch (Exception error) when (error is InvalidDataException or IOException or UnauthorizedAccessException)
        {
            throw new UpdateException($"The update could not be installed, and your copy was left as it was: {error.Message}");
        }
    }

    /// <summary>Refuses while the launcher or a game from this folder is running.</summary>
    public static void EnsureNothingRunning(string programDir)
    {
        string prefix = Path.GetFullPath(programDir).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        foreach (string name in new[] { "PocketLauncher", "love", "lovec" })
        {
            foreach (Process process in Process.GetProcessesByName(name))
            {
                using (process)
                {
                    string? path = null;
                    try
                    {
                        path = process.MainModule?.FileName;
                    }
                    catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException)
                    {
                        // gone already, or not ours to read
                    }
                    if (path != null && path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    {
                        throw new UpdateException("Close the launcher and any game first, then try again.");
                    }
                }
            }
        }
    }

    private static async Task DownloadAsync(Uri uri, string zipPath, IProgress<UpdateProgress>? progress)
    {
        progress?.Report(new UpdateProgress("Downloading", null));
        using HttpResponseMessage response = await Http.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();
        long? size = response.Content.Headers.ContentLength;
        await using Stream body = await response.Content.ReadAsStreamAsync();
        await using FileStream file = File.Create(zipPath);
        var buffer = new byte[81920];
        long total = 0;
        int reported = -1, read;
        while ((read = await body.ReadAsync(buffer)) > 0)
        {
            total += read;
            if (total > MaxDownloadBytes) throw new UpdateException("The download is too large to be this program.");
            await file.WriteAsync(buffer.AsMemory(0, read));
            if (size is > 0)
            {
                int percent = (int)Math.Min(DownloadEndsAt, total * DownloadEndsAt / size.Value);
                if (percent != reported) progress?.Report(new UpdateProgress("Downloading", reported = percent));
            }
        }
    }

    /// <summary>Unpacks into a scratch folder; returns the folder that holds the package.</summary>
    private static string Unpack(string zipPath, string destination, IProgress<UpdateProgress>? progress)
    {
        Directory.CreateDirectory(destination);
        string destinationRoot = Path.GetFullPath(destination) + Path.DirectorySeparatorChar;
        using ZipArchive archive = ZipFile.OpenRead(zipPath);
        long size = archive.Entries.Sum(entry => entry.Length);
        if (size > MaxUnpackedBytes) throw new UpdateException("The download unpacks to more than this program should.");
        long total = 0;
        int reported = -1;
        var buffer = new byte[81920];
        foreach (ZipArchiveEntry entry in archive.Entries)
        {
            string target = Path.GetFullPath(Path.Combine(destinationRoot, entry.FullName.Replace('\\', '/')));
            if (entry.FullName.Contains(':') || !target.StartsWith(destinationRoot, StringComparison.OrdinalIgnoreCase))
            {
                throw new UpdateException($"The download has a file that points outside its own folder ({entry.FullName}), so it was not installed.");
            }
            if (entry.FullName.EndsWith('/') || entry.FullName.EndsWith('\\'))
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
                output.Write(buffer, 0, read);
                total += read;
                if (total > MaxUnpackedBytes) throw new UpdateException("The download unpacks to more than this program should.");
                if (size > 0)
                {
                    int percent = DownloadEndsAt + (int)Math.Min(UnpackEndsAt - DownloadEndsAt, total * (UnpackEndsAt - DownloadEndsAt) / size);
                    if (percent != reported) progress?.Report(new UpdateProgress("Unpacking", reported = percent));
                }
            }
        }
        // the package's one top folder, or the zip's root
        string[] folders = Directory.GetDirectories(destination);
        return File.Exists(Path.Combine(destination, VersionFile)) || folders.Length != 1 ? destination : folders[0];
    }

    /// <summary>
    /// Moves each item the package holds out of the way and the new one in; on any failure, puts
    /// everything back.  The updater itself stays: it is what is running, and it has one simple
    /// job.  A fixed updater reaches players through a fresh download of the zip.  Anything else
    /// in the folder is left alone.
    /// </summary>
    private static void Swap(string newRoot, string programDir)
    {
        string retired = Path.Combine(programDir, RetiredFolder);
        Directory.CreateDirectory(retired);
        var retiredItems = new List<(string From, string To)>();
        var placed = new List<string>();
        try
        {
            foreach (string source in Directory.GetFileSystemEntries(newRoot))
            {
                string name = Path.GetFileName(source);
                if (name.Equals(UpdaterFile, StringComparison.OrdinalIgnoreCase)) continue;
                string target = Path.Combine(programDir, name);
                if (Exists(target))
                {
                    string kept = Path.Combine(retired, name);
                    MoveEntry(target, kept);
                    retiredItems.Add((target, kept));
                }
                MoveEntry(source, target);
                placed.Add(target);
            }
        }
        catch
        {
            foreach (string target in placed) DeleteEntry(target);
            foreach ((string from, string to) in retiredItems) MoveEntry(to, from);
            throw;
        }
    }

    private static bool Exists(string path) => File.Exists(path) || Directory.Exists(path);

    private static void MoveEntry(string from, string to)
    {
        if (Directory.Exists(from)) Directory.Move(from, to);
        else File.Move(from, to);
    }

    private static void DeleteEntry(string path)
    {
        if (Directory.Exists(path)) Directory.Delete(path, true);
        else if (File.Exists(path)) File.Delete(path);
    }

    /// <summary>Clears scratch folders and the old copy.</summary>
    public static void RemoveLeftovers(string programDir)
    {
        foreach (string folder in new[] { IncomingFolder, RetiredFolder })
        {
            try
            {
                string path = Path.Combine(programDir, folder);
                if (Directory.Exists(path)) Directory.Delete(path, true);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                // something still has a file open; the next run removes it
            }
        }
    }
}
