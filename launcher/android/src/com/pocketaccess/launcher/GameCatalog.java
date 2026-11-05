package com.pocketaccess.launcher;

import java.util.Arrays;
import java.util.List;
import java.util.Locale;

/**
 * The games this launcher offers.  The ids and accepted ROM hashes mirror
 * upstream's src/core/GameVersion.lua; tests/access/launcher_catalog_test.lua
 * fails when the two drift apart.
 */
final class GameCatalog {
    static final class Game {
        final String id;
        final String name;
        final List<String> romSha1;

        Game(String id, String name, String... romSha1) {
            this.id = id;
            this.name = name;
            this.romSha1 = Arrays.asList(romSha1);
        }
    }

    static final List<Game> ALL = Arrays.asList(
        new Game("red", "Pokémon Red", "ea9bcae617fdf159b045185467ae58b2e4a48b9a"),
        new Game("blue", "Pokémon Blue", "d7037c83e1ae5b39bde3c30787637ba1d4c48ce2"),
        new Game("yellow", "Pokémon Yellow", "cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1"),
        new Game("gold", "Pokémon Gold", "d8b8a3600a465308c9953dfa04f0081c05bdcb94"),
        new Game("silver", "Pokémon Silver", "49b163f7e57702bc939d642a18f591de55d92dae"),
        new Game("crystal", "Pokémon Crystal",
            "f4cd194bdee0d04ca4eac29e09b8e4e9d818c133", "f2f52230b536214ef7c9924f483392993e226cfb"),
        new Game("firered", "Pokémon FireRed",
            "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc", "dd5945db9b930750cb39d00c84da8571feebf417"),
        new Game("leafgreen", "Pokémon LeafGreen",
            "574fa542ffebb14be69902d1d36f1ec0a4afd71e", "7862c67bdecbe21d1d69ce082ce34327e1c6ed5e"),
        new Game("ruby", "Pokémon Ruby",
            "f28b6ffc97847e94a6c21a63cacf633ee5c8df1e", "610b96a9c9a7d03d2bafb655e7560ccff1a6d894",
            "5b64eacf892920518db4ec664e62a086dd5f5bc8"),
        new Game("sapphire", "Pokémon Sapphire",
            "3ccbbd45f8553c36463f13b938e833f652b793e4", "4722efb8cd45772ca32555b98fd3b9719f8e60a9",
            "89b45fb172e6b55d51fc0e61989775187f6fe63c"),
        new Game("emerald", "Pokémon Emerald", "f3ae088181bf583e55daf962a92bb46f4f1d07b7"));

    private GameCatalog() {}

    /** The game a cartridge dump belongs to, by its SHA-1, or null. */
    static Game forSha1(String sha1) {
        String wanted = sha1.toLowerCase(Locale.ROOT);
        for (Game game : ALL) {
            if (game.romSha1.contains(wanted)) return game;
        }
        return null;
    }
}
