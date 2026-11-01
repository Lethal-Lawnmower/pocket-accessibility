namespace PocketLauncher;

/// <summary>One game the launcher can import and start.</summary>
/// <param name="Id">The game's id, as POKEPORT_GAME and POKEPORT_VERSION take it.</param>
/// <param name="Name">The name read to the player.</param>
/// <param name="CacheFolder">Where the game's extracted ROM cache lives in the save folder.</param>
/// <param name="RomSha1">SHA-1 of every accepted cartridge dump (Crystal has two revisions).</param>
internal sealed record Game(string Id, string Name, string CacheFolder, IReadOnlyList<string> RomSha1);

/// <summary>
/// The games this launcher offers.  The ids, cache folders and accepted ROM
/// hashes mirror upstream's src/core/GameVersion.lua; the Lua test
/// tests/access/launcher_catalog_test.lua fails when the two drift apart.
/// </summary>
internal static class GameCatalog
{
    public static readonly IReadOnlyList<Game> All =
    [
        new("red", "Pokémon Red", "red", ["ea9bcae617fdf159b045185467ae58b2e4a48b9a"]),
        new("blue", "Pokémon Blue", "blue", ["d7037c83e1ae5b39bde3c30787637ba1d4c48ce2"]),
        new("yellow", "Pokémon Yellow", "yellow", ["cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1"]),
        new("gold", "Pokémon Gold", "gold", ["d8b8a3600a465308c9953dfa04f0081c05bdcb94"]),
        new("silver", "Pokémon Silver", "silver", ["49b163f7e57702bc939d642a18f591de55d92dae"]),
        new("crystal", "Pokémon Crystal", "crystal",
            ["f4cd194bdee0d04ca4eac29e09b8e4e9d818c133", "f2f52230b536214ef7c9924f483392993e226cfb"]),
    ];

    /// <summary>The game a cartridge dump belongs to, by its SHA-1, or null.</summary>
    public static Game? ForSha1(string sha1) =>
        All.FirstOrDefault(game => game.RomSha1.Contains(sha1, StringComparer.OrdinalIgnoreCase));
}
