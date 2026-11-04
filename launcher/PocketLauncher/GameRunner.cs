using System.Diagnostics;
using System.Security.Cryptography;

namespace PocketLauncher;

/// <summary>
/// Starts the game program.  Everything goes through environment variables
/// upstream's main.lua already reads (docs/access/architecture.md, "Launcher
/// to game interface"), so the game needs no change:
///   POKEPORT_GAME          start this game directly, skipping upstream's launcher
///   POKEPORT_IMPORT_ROM    import this ROM ...
///   POKEPORT_IMPORT_ONLY   ... and quit when done
///   POKEPORT_FORCE_IMPORT  import even over a cache the game accepts (without
///                          it, an import-only run of a ready game boots it)
///   POKEPORT_PORTMASTER_MANAGED=1  keeps upstream's self-updater off; in a
///                          packaged build it would replace ours with plain
///                          upstream
/// The game is never started with --game on the command line: from a source
/// folder that fails before main.lua runs.
/// </summary>
internal sealed class GameRunner(GamePaths paths)
{
    // src/access/PackagedBuild.lua, EXIT_REFUSED: only a packaged build exits with it.
    private const int RefusedExitCode = 40;

    private ProcessStartInfo StartInfo()
    {
        if (paths.LoveExe == null || paths.GameDir == null)
        {
            throw new InvalidOperationException("The game program was not found.");
        }
        var info = new ProcessStartInfo(paths.LoveExe)
        {
            WorkingDirectory = paths.GameDir,
            UseShellExecute = false,
        };
        info.ArgumentList.Add(paths.GameDir);
        info.Environment["POKEPORT_PORTMASTER_MANAGED"] = "1";
        return info;
    }

    /// <summary>Starts a game; the task ends when its window closes.  Returns why
    /// the game refused to start, or null if it ran.</summary>
    public async Task<string?> PlayAsync(Game game)
    {
        File.Delete(paths.RefusalFile);
        var info = StartInfo();
        info.Environment["POKEPORT_GAME"] = game.Id;
        using var process = Process.Start(info)
            ?? throw new InvalidOperationException("The game did not start.");
        await process.WaitForExitAsync();
        if (process.ExitCode != RefusedExitCode) return null;
        string reason = File.Exists(paths.RefusalFile) ? (await File.ReadAllTextAsync(paths.RefusalFile)).Trim() : "";
        File.Delete(paths.RefusalFile);
        return $"{game.Name} did not start. {reason}";
    }

    /// <summary>Imports a cartridge dump for its game; the game program quits when done.</summary>
    public async Task ImportAsync(Game game, string romPath)
    {
        var info = StartInfo();
        info.Environment["POKEPORT_VERSION"] = game.Id;
        info.Environment["POKEPORT_IMPORT_ROM"] = romPath;
        info.Environment["POKEPORT_IMPORT_ONLY"] = "1";
        info.Environment["POKEPORT_FORCE_IMPORT"] = "1";
        using var process = Process.Start(info)
            ?? throw new InvalidOperationException("The importer did not start.");
        await process.WaitForExitAsync();
    }

    public static string Sha1Of(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexStringLower(SHA1.HashData(stream));
    }
}
