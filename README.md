# Pocket Accessibility

I'm not really good at explaining things or writing introductions, but honestly, what this project aims to be is not just a project for me, but a community project that people can modify and contribute to if something doesn't work or isn't up to their standards. QOL features, navigation improvements, etc., etc. This is just a firm baseline to lift us off the ground. VBA itself was old, outdated, and a security and liability risk. We can build our own mods off of this and use existing mods, etc., etc. One thing to keep in mind, though: this supports the base game, and no extra mods are endorsed or guaranteed to work.

This might seem like a lazy, half-assed attempt, which it is not meant to be. I've been working on this project since July, and I did a rewrite of it along the way. Dumping 11 games on this project at once, I get it, can look like I just said "Claude, make me an accessibility mod", when that is far from the case. They're all here to get a firm baseline and then build off of. And to be completely honest, asking me to play through 11 games is not realistic.

Most people don't know how to use GitHub issues, so I created a [Discord server](https://discord.gg/8NNev6PsB6) where you can post your issues. I'm not a fan of everyone having their own server, because that creates fragmentation and it's a lot for people to manage. However, for a fairly large and complex project like this, I feel like it's needed.

Pocket Accessibility aims to cover the gaps and weird issues that the original [Pokémon Access](https://github.com/nuive/pokemon-access) couldn't, with the PC ports from the [Pokémon Gen 1 Recompilation Project](https://github.com/bryanthaboi/gen1recomp) by BOIS CLUB GAMES, LLC as its foundation.

If you don't know Pokémon Access, it's a set of scripts by nuive that make the Pokémon games playable with a screen reader through the VBA-ReRecording emulator. It grew out of the Pokécrystal Access Project, which did the same for Crystal.

**Early days:** expect mild inconveniences to moderate bugs. For feedback, help and bug reports, join the [Discord server](https://discord.gg/8NNev6PsB6).

> [!WARNING]
> **Seizure and flashing warning, in my own words.** This README was generated
> by AI, with human bits added where needed, and this is one of them. Seizures,
> epilepsy and disabilities can range widely. These older games had a lot of
> flashing, weird colors and strobing. I cannot account for all types of
> disabilities or scenarios.
>
> See also Nintendo's
> [information about photosensitivity](https://en-americas-support.nintendo.com/app/answers/detail/a_id/59596).

## Supported Games

Red, Blue, Yellow, Gold, Silver, Crystal, FireRed, LeafGreen, Ruby, Sapphire and Emerald.

Playing through every game myself isn't realistic, so here's how far I've gotten:

- **Crystal:** finished, beat the Elite Four in November 2026.
- **Red:** played through in August 2026.
- **FireRed:** played to about the second gym.
- **Emerald:** only just started. This is very early.
- **Blue, Yellow, Gold and Silver:** not played through, but they share most of their code with the games above.
- **LeafGreen:** not played, but it shares FireRed's code.
- **Ruby and Sapphire:** not played. These are new, so expect more bugs.

All of them have been through automated tests and scripted runs. If you run into a problem, open an issue here or post in the [Discord server](https://discord.gg/8NNev6PsB6).

## What It Does

- **Speech:** menus, dialogue, the Pokémon screens and battles all go through [Prism](https://github.com/ethindp/prism), so it works with your screen reader without any extra setup. Gone are the days of hunting down the right NVDA DLL or `Tolk.dll`. F7 turns on the navigation keys, and F8 is help.
- **Navigation:** a list of what's on the map, like warps, signs, people and objects. You can get spoken directions or auto-walk to whatever you pick, on keyboard or controller. Battles pause the walk, and it carries on afterwards.
- **Other floors:** if there's no route on your floor, auto-walk looks through the other floors. The Area category lists the items and floors of the building or cave you're in. Some places still say there's no route. When an item is what's blocking you, it tells you to pick it up.
- **Launcher:** a standard Windows program that lists the games, imports your ROMs and starts a game.
- **Save editor:** opened from the launcher with Edit save, with tabs for party, boxes, items, trainer, map, Pokédex and events.
- **Mods:** the launcher's Mods window lists the community mod index, installs mods and turns them on or off per game. Mods aren't endorsed or tested by this project and can break accessibility, so use them at your own risk.

### Puzzles

With AUTO-WALK PUZZLES on, which is the default, auto-walk can do these for you. If you'd rather solve them yourself, turn it off in the Accessibility page of the game's options. You still get the hints.

- **Boulders:** auto-walk to a boulder, hole or pressure switch on a floor like Ice Path, Seafoam Islands or Victory Road, or to something only boulders are blocking. You need a Pokémon with Strength. In Seafoam, lower floors' boulders fall from above, so start at the top.
- **Switches:** when a target has no route, it tries the switches, like Goldenrod Underground's and Pokémon Mansion's, and watches what opens. This can take a while. Cinnabar Gym's quiz machines are yours to answer.
- **Lt. Surge's trash cans (Red, Blue, Yellow, FireRed, LeafGreen):** auto-walk to Lt. Surge and it searches the cans until the door opens. The game resets the locks after a wrong second can, so this can take a while.
- **Cut and Surf (Red, Blue, Yellow):** these games only offer them from the party menu, so auto-walk uses them for you when the route needs them. Press A through the game's text.
- **The Farfetch'd in Ilex Forest (Gold, Silver, Crystal):** auto-walk to it, press A once, then auto-walk again without moving, and it keeps after the bird. It learns by trying each side, so this can take a while. Press A through each "Kwaa!" message.
- **Hoenn gyms (Ruby, Sapphire, Emerald):** Mauville and Mossdeep's switches, Fortree's spinning gates and Sootopolis's ice. Auto-walk works these out, but they've only been tested by script.
- **Trick House (Ruby, Sapphire, Emerald):** most rooms work. Room 5 is a quiz, so that's yours. Room 7 doesn't work yet in Ruby or Sapphire.

Not everything is covered. If auto-walk says there's no route, the way may really be closed by the story.

## Getting Started

You supply your own ROMs. No game data is included.

1. Download the zip from this repository's [Releases page](https://github.com/Lethal-Lawnmower/pocket-accessibility/releases) and unzip it anywhere.
2. Open `PocketLauncher.exe`.
3. Choose Import ROM, pick your game's ROM, then Play.

Windows only for now, with Android and Linux on the way. Nothing else needs installing. To update later, choose Check for updates in the launcher. Your saves and imported games are kept outside that folder, so updating doesn't touch them.

### Running from source

1. Install [LÖVE 11.5](https://love2d.org/).
2. Download a [Prism](https://github.com/ethindp/prism/releases) Windows x64 release and copy `prism.dll` into `local-deps/prism/` in this folder.
3. Install the .NET 10 SDK and build the launcher: `dotnet build launcher/PocketLauncher -c Release`.
4. Run `launcher/PocketLauncher/bin/Release/net10.0-windows/PocketLauncher.exe`, use Import ROM for your game, then Play.

## Controls

The game's own controls are arrow keys or WASD to move, Z or Enter for A, X or Backspace for B, Escape for Start and Tab for Select. You can rebind them in the game's options.

**On a keyboard,** press F7 to turn on the navigation keys, and F8 for help:

- **J and L:** previous and next thing on the map.
- **Shift J and Shift L:** change the category, like warps, signs or people.
- **K:** spoken directions to what you picked. Press it again to stop.
- **Shift K:** auto-walk there. Any key stops it.
- **H and Shift H:** enemy health and your health.

The navigation keys only work on the map, so they never get in the way of menus or battles.

**On a controller,** hold the left trigger and use the D-pad: up and down change the category, and left and right move through it. Click the right stick for spoken directions, and the left stick to auto-walk. Click again to stop.

Want another key? Ask, and I'll look at adding it.

## Why I Made This

The original scripts by nuive, which build on Tyler Spivey's Pokécrystal Access Project, rely on VBA, which is built on old, outdated emulator technology. The audio and video quality are poor, and I feel the community deserves better.

## A Note on AI

For full transparency: these accessibility mods are built with AI. I'm blind,
and I don't have the same access to play these games that most sighted people
do. AI has empowered people with disabilities to turn ideas into reality, and
it's what made this project possible.

If you have a problem with that, I'm sorry you feel that way, but it's not
going to change how this project is made. It exists to make these games
playable for people who couldn't play them independently before.

## Where the Navigation Comes From

In my personal opinion, about 80 to 90% of the navigation ideas came from my Red playthrough in August 2026, and the remaining 10 to 20% came from my latest Crystal playthrough. My main interest is Crystal from the second generation and most of the third-generation GBA games.

Things are bound to change, and I'm more than willing to listen to and adapt to community feedback. At the end of the day, this isn't meant to be my project, but something the community can add to and build on. If something doesn't work, please open an issue on this repository or post in the [Discord server](https://discord.gg/8NNev6PsB6).

## Credit

**Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC (https://github.com/bryanthaboi/gen1recomp).** This is an unofficial fork and is not affiliated with or endorsed by that project.

- **[Pokémon Access](https://github.com/nuive/pokemon-access)** by nuive, and Tyler Spivey's Pokécrystal Access Project, for showing what this could be. Their features are recreated, not copied; no code or data from those scripts is included.
- **[Prism](https://github.com/ethindp/prism)** for the speech.
- **[pret](https://github.com/pret)** for the decompilation work the original project is built on.

For the game's own features, like game speed, online play and other platforms, see [the original project](https://github.com/bryanthaboi/gen1recomp).

## Documentation

Start at [docs/access/README.md](docs/access/README.md). Contributors and AI agents begin with [AGENTS.md](AGENTS.md).

## License

GPLv3 with the upstream project's additional terms; see [LICENSE.MD](LICENSE.MD). Upstream's launcher files are proprietary and not part of that license; this project does not use or redistribute them as part of its builds.
