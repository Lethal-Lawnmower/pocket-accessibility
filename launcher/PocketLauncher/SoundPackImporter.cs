namespace PocketLauncher;

/// <summary>A sound folder that could not be imported; the message is read to the player.</summary>
internal sealed class SoundPackException(string message) : Exception(message);

/// <summary>
/// Copies a Pokémon Access sound folder the player already has into the save folder, where the
/// game looks for it (src/access/nav/Earcons.lua).  The sounds are the player's own files, as
/// ROMs are: this project never ships or hosts them (decision 8).  Only WAV files in the pack's
/// own folders are copied, and the old pack stays until the new one is complete.
/// </summary>
internal static class SoundPackImporter
{
    public const string PackFolder = "pocket-access-sounds";
    private const string IncomingFolder = "pocket-access-sounds-incoming";
    private const long MaxWaveBytes = 4 * 1024 * 1024; // what the game agrees to load
    private static readonly string[] RequiredFolders = ["common", "gb"];

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
            Directory.CreateDirectory(saveDir);
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
