using System.IO.Compression;

namespace PocketLauncher;

/// <summary>A sound folder that could not be imported; the message is read to the player.</summary>
internal sealed class SoundPackException(string message) : Exception(message);

/// <summary>
/// Puts Pokémon Access sounds into the save folder, where the game looks for them
/// (src/access/nav/Earcons.lua): from a folder the player has, or, when the player asks, from
/// that project's own GitHub repository.  This project never ships or hosts them (decisions 8
/// and 51).  Only WAV files in the pack's own folders are kept, and the old pack stays until the
/// new one is complete.
/// </summary>
internal static class SoundPackImporter
{
    public const string PackFolder = "pocket-access-sounds";
    private const string IncomingFolder = "pocket-access-sounds-incoming";
    private const long MaxWaveBytes = 4 * 1024 * 1024; // what the game agrees to load
    private const long MaxDownloadBytes = 512L * 1024 * 1024;
    private const string SourceZip = "https://github.com/nuive/pokemon-access/archive/refs/heads/master.zip";
    private static readonly string[] RequiredFolders = ["common", "gb"];
    private static readonly HttpClient Http = CreateHttpClient();

    private static HttpClient CreateHttpClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("PocketAccessibility-sounds");
        return client;
    }

    public static bool IsImported(string saveDir) =>
        RequiredFolders.All(folder => Directory.Exists(Path.Combine(saveDir, PackFolder, folder)));

    /// <summary>The folder that holds the sounds: the one chosen, or its "sounds" folder.</summary>
    private static string? FindSoundsRoot(string chosen)
    {
        foreach (string candidate in new[] { chosen, Path.Combine(chosen, "sounds") })
        {
            if (RequiredFolders.All(folder => Directory.Exists(Path.Combine(candidate, folder)))) return candidate;
        }
        return null;
    }

    /// <returns>How many sounds were imported.</returns>
    public static int Import(string chosenFolder, string saveDir)
    {
        string root = FindSoundsRoot(chosenFolder)
            ?? throw new SoundPackException("This folder doesn't look like Pokémon Access sounds. Choose the sounds folder, the one with the common and gb folders in it.");
        string incoming = Path.Combine(saveDir, IncomingFolder);
        string target = Path.Combine(saveDir, PackFolder);
        try
        {
            if (Directory.Exists(incoming)) Directory.Delete(incoming, true);
            int copied = 0;
            foreach (string file in Directory.EnumerateFiles(root, "*.wav", SearchOption.AllDirectories))
            {
                if (new FileInfo(file).Length > MaxWaveBytes || !IsWave(file)) continue;
                string destination = Path.Combine(incoming, Path.GetRelativePath(root, file));
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                File.Copy(file, destination);
                copied++;
            }
            if (copied == 0 || !RequiredFolders.All(folder => Directory.Exists(Path.Combine(incoming, folder))))
            {
                throw new SoundPackException("That folder has no usable sound files, so nothing was imported.");
            }
            PutInPlace(incoming, target);
            return copied;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new SoundPackException($"The sounds could not be imported: {error.Message}");
        }
        finally
        {
            try
            {
                if (Directory.Exists(incoming)) Directory.Delete(incoming, true);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                // scratch only; the next import clears it
            }
        }
    }

    private static void PutInPlace(string incoming, string target)
    {
        string retired = target + "-old";
        if (Directory.Exists(retired)) Directory.Delete(retired, true);
        if (Directory.Exists(target)) Directory.Move(target, retired);
        try
        {
            Directory.Move(incoming, target);
        }
        catch
        {
            if (Directory.Exists(retired)) Directory.Move(retired, target);
            throw;
        }
        if (Directory.Exists(retired)) Directory.Delete(retired, true);
    }

    /// <summary>Downloads that project's zip and keeps only the sounds from it.</summary>
    /// <param name="progress">A percent, or null while the size is unknown.</param>
    /// <returns>How many sounds were installed.</returns>
    public static async Task<int> DownloadAsync(string saveDir, IProgress<int?>? progress = null, string sourceUrl = SourceZip)
    {
        string zipPath = Path.Combine(saveDir, "pocket-access-sounds-download.zip");
        string incoming = Path.Combine(saveDir, IncomingFolder);
        Directory.CreateDirectory(saveDir);
        try
        {
            progress?.Report(null);
            using (HttpResponseMessage response = await Http.GetAsync(sourceUrl, HttpCompletionOption.ResponseHeadersRead))
            {
                if (!response.IsSuccessStatusCode)
                {
                    throw new SoundPackException($"The sounds aren't at their usual place on GitHub any more ({(int)response.StatusCode}). You still have the built-in sounds.");
                }
                long? size = response.Content.Headers.ContentLength;
                await using Stream body = await response.Content.ReadAsStreamAsync();
                await using FileStream file = File.Create(zipPath);
                var buffer = new byte[81920];
                long total = 0;
                int reported = -1, read;
                while ((read = await body.ReadAsync(buffer)) > 0)
                {
                    total += read;
                    if (total > MaxDownloadBytes) throw new SoundPackException("The download is much larger than expected, so nothing was installed.");
                    await file.WriteAsync(buffer.AsMemory(0, read));
                    if (size is > 0)
                    {
                        int percent = (int)Math.Min(99, total * 99 / size.Value);
                        if (percent != reported) progress?.Report(reported = percent);
                    }
                }
            }
            return await Task.Run(() => InstallFromZip(zipPath, incoming, Path.Combine(saveDir, PackFolder)));
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException)
        {
            throw new SoundPackException($"The download failed: {error.Message} You still have the built-in sounds.");
        }
        catch (Exception error) when (error is InvalidDataException or IOException or UnauthorizedAccessException)
        {
            throw new SoundPackException($"The sounds could not be installed: {error.Message} You still have the built-in sounds.");
        }
        finally
        {
            try
            {
                if (File.Exists(zipPath)) File.Delete(zipPath);
                if (Directory.Exists(incoming)) Directory.Delete(incoming, true);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                // scratch only; the next run overwrites it
            }
        }
    }

    /// <summary>Takes only WAV files under the zip's sounds folder; nothing else in it is opened.</summary>
    public static int InstallFromZip(string zipPath, string incoming, string target)
    {
        if (Directory.Exists(incoming)) Directory.Delete(incoming, true);
        string root = Path.GetFullPath(incoming) + Path.DirectorySeparatorChar;
        int copied = 0;
        using (ZipArchive archive = ZipFile.OpenRead(zipPath))
        {
            foreach (ZipArchiveEntry entry in archive.Entries)
            {
                string name = entry.FullName.Replace('\\', '/');
                int marker = name.IndexOf("/sounds/", StringComparison.OrdinalIgnoreCase);
                if (marker < 0 || name.IndexOf('/') != marker) continue; // <top folder>/sounds/ only
                string relative = name[(marker + "/sounds/".Length)..];
                if (!relative.EndsWith(".wav", StringComparison.OrdinalIgnoreCase) || entry.Length > MaxWaveBytes) continue;
                string destination = Path.GetFullPath(Path.Combine(root, relative));
                if (relative.Contains(':') || !destination.StartsWith(root, StringComparison.OrdinalIgnoreCase)) continue;
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                entry.ExtractToFile(destination);
                if (IsWave(destination)) copied++;
                else File.Delete(destination);
            }
        }
        if (copied == 0 || !RequiredFolders.All(folder => Directory.Exists(Path.Combine(incoming, folder))))
        {
            throw new SoundPackException("The download didn't have the sounds in it, so nothing was installed. You still have the built-in sounds.");
        }
        PutInPlace(incoming, target);
        return copied;
    }

    /// <summary>Back to the built-in sounds.</summary>
    public static void Remove(string saveDir)
    {
        string target = Path.Combine(saveDir, PackFolder);
        try
        {
            if (Directory.Exists(target)) Directory.Delete(target, true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new SoundPackException($"The sounds could not be removed: {error.Message}");
        }
    }

    private static bool IsWave(string path)
    {
        var header = new byte[12];
        using FileStream stream = File.OpenRead(path);
        return stream.Read(header, 0, 12) == 12
            && header[0] == 'R' && header[1] == 'I' && header[2] == 'F' && header[3] == 'F'
            && header[8] == 'W' && header[9] == 'A' && header[10] == 'V' && header[11] == 'E';
    }
}
