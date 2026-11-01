namespace PocketLauncher;

/// <summary>
/// Where LÖVE, the game folder and the save folder are.  For now the
/// launcher runs from a source checkout: the game folder is the first folder
/// above the launcher that holds main.lua and src/access, and LÖVE is the
/// standard install.  Packaged builds will bundle both (docs/access/launcher.md).
/// Environment overrides: POCKET_LOVE (the LÖVE executable), POCKET_GAME_DIR
/// (the game folder) and POKEPORT_IDENTITY (the save folder name, which the
/// game reads too; test runs use a disposable one).
/// </summary>
internal sealed record GamePaths(string? LoveExe, string? GameDir, string SaveDir)
{
    public const string DefaultIdentity = "pokemon-love2d";

    public static GamePaths Discover()
    {
        string identity = Environment.GetEnvironmentVariable("POKEPORT_IDENTITY") is { Length: > 0 } id
            ? id : DefaultIdentity;
        // An unfused LÖVE game keeps its save folder under %APPDATA%\LOVE.
        string saveDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "LOVE", identity);
        return new GamePaths(FindLove(), FindGameDir(), saveDir);
    }

    private static string? FindLove()
    {
        string? forced = Environment.GetEnvironmentVariable("POCKET_LOVE");
        if (!string.IsNullOrEmpty(forced)) return File.Exists(forced) ? forced : null;
        string[] candidates =
        [
            Path.Combine(AppContext.BaseDirectory, "love", "love.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "LOVE", "love.exe"),
        ];
        return candidates.FirstOrDefault(File.Exists);
    }

    private static string? FindGameDir()
    {
        string? forced = Environment.GetEnvironmentVariable("POCKET_GAME_DIR");
        if (!string.IsNullOrEmpty(forced)) return IsGameDir(forced) ? Path.GetFullPath(forced) : null;
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
        {
            if (IsGameDir(dir.FullName)) return dir.FullName;
        }
        return null;
    }

    private static bool IsGameDir(string dir) =>
        File.Exists(Path.Combine(dir, "main.lua"))
        && File.Exists(Path.Combine(dir, "src", "access", "init.lua"));

    /// <summary>Prism's DLL, without which the game runs but cannot speak.</summary>
    public bool HasPrism => GameDir != null
        && File.Exists(Path.Combine(GameDir, "local-deps", "prism", "prism.dll"));

    /// <summary>
    /// Whether a game's ROM cache is imported: the cache's completion marker
    /// exists and names one of the game's accepted ROMs.  The game itself also
    /// checks the cache format and every required file
    /// (src/import/CacheContract.lua); this is the cheap part of that check.
    /// </summary>
    public bool IsImported(Game game)
    {
        string marker = Path.Combine(SaveDir, game.CacheFolder, "rom-cache.complete");
        if (!File.Exists(marker)) return false;
        string text = File.ReadAllText(marker).Trim();
        return game.RomSha1.Any(sha1 => text.EndsWith(":" + sha1, StringComparison.OrdinalIgnoreCase));
    }
}
