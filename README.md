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
- **Launcher:** a standard Windows program that lists the games, imports your ROMs and starts a game. Press Alt for the Tools menu, with Check for updates and getting the Pokémon Access sounds.
- **Sounds:** built-in sound cues work out of the box. They're only meant to hold you over until you get the Pokémon Access sounds, which the launcher can download for you from that project's GitHub page. If you already have them, you can import them instead. They aren't included in this download.
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

You supply your own ROMs. No game data is included. Downloads are on this repository's [Releases page](https://github.com/Lethal-Lawnmower/pocket-accessibility/releases).

### Windows

1. Download the Windows zip and unzip it anywhere.
2. Open `PocketLauncher.exe`.
3. Choose Import ROM, pick your game's ROM, then Play.

Nothing else needs installing. To update later, press Alt in the launcher and choose Check for updates under Tools. Your saves and imported games are kept outside that folder, so updating doesn't touch them.

### Android

Android is new and has had much less testing. It's played with touch gestures or a controller, using the controls below. It needs Android 8 or later on a 64-bit device, and speaks through TalkBack. Touch gestures need Android 11 or later and a small service that comes with the app: open Touch controls in the launcher's menu to switch it on and read what it does.

1. Download the APK on your device and install it. Android will ask you to allow installing apps from your browser or file manager.
2. Put your ROMs in a folder on the device, such as one inside Downloads.
3. Open Pocket Accessibility, choose Choose ROM folder, and pick that folder. Your games appear in a list.
4. Select a game. The first time, it's imported, then it starts.

The launcher's menu also has the Pokémon Access sounds, the save editor and the licenses. A long press on a game opens its save editor. To update, install the newer APK over the old one; your saves are kept.

### iPhone

iPhone support is new. The app speaks through VoiceOver and is played with touch gestures, using the controls below; open Touch controls in the launcher to read how the game screen takes them.

The iPhone download is an unsigned `.ipa`, not an App Store app. How you put it on your device is up to you. We used Sideloadly on a computer. With a free Apple account, an app installed this way has to be signed again every 7 days.

Games aren't included. Put your ROMs on the iPhone either way:

- From your computer: drag them into the app's files, as Pocket Accessibility, with file sharing in Finder on a Mac or the Apple Devices app (or iTunes) on Windows.
- Already on your iPhone: in the launcher, choose Import ROMs and pick them in Files.

Then choose Refresh game list if they don't show, and select a game. The first time, it's imported, then it starts.

The launcher also has the save editor, Mods, and the Pokémon Access sounds. To update, install the newer `.ipa` over the old app; your saves are kept as long as you don't delete the app first.

Linux is on the way.

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

**On a controller,** including on Android, hold the left trigger and use the D-pad: up and down change the category, and left and right move through it. Click the right stick for spoken directions, and the left stick to auto-walk. Click again to stop.

**On a touchscreen,** TalkBack stays on, and the game screen takes gestures. They work anywhere on the screen, held either way up; what matters is how many fingers you use, not where you touch.

- **Swipe:** walk on the map. In menus, battles and dialogue, it moves the cursor.
- **Two-finger swipe left and right:** previous and next thing on the map.
- **Two-finger swipe up and down:** change the category. Your two fingers can sit side by side or one above the other.
- **Tap:** spoken directions to what you picked, which keep coming as you walk. Tap again to stop them. In Auto walking, a tap walks you there instead, and another tap stops.
- **Double tap:** A. **Two-finger double tap:** B.
- **Three-finger double tap:** Start. **Three-finger tap:** Select.
- **Two-finger triple tap on the title screen:** back to the launcher. Save first; leaving doesn't save.
- **Any gesture** stops a walk.

How a swipe walks is up to you, under TOUCH WALKING in the game's options, in the ACCESSIBILITY section:

- **Manual:** each swipe is one step.
- **Hybrid:** the game tells you the next straight stretch, like "18 up". Swipe that way to walk all of it, then it tells you the next one.
- **Auto:** a tap walks you all the way to what you picked, and another tap stops. Swipes are single steps, so once you're there you can turn and step up to it.

On devices that can vibrate, you feel a light tick with each step and a firmer one when you walk into something. HAPTICS in the same options turns that off. Touch is the newest part of all this and still changing, so tell me what feels wrong.

Want another key? Ask, and I'll look at adding it.

## Why I Made This

The original scripts by nuive, which build on Tyler Spivey's Pokécrystal Access Project, rely on VBA, which is built on old, outdated emulator technology. The audio and video quality are poor, and I feel the community deserves better.

## Why Isn't This a Mod?

For now, this has to be a fork. The original project has a good mod system, and a mod would be the better option if it could work. I tested what a mod can do, and most of what this project needs is possible, but a few things stand in the way:

- **Speech:** this is the hard block. Speech goes through Prism, which is a native library, and loading one takes LuaJIT's FFI. The mod sandbox doesn't allow FFI, and for good reason, since it would let a mod run any native code. So a mod can read what's on screen but has no way to pass it to your screen reader.
- **The launcher:** mods load inside the game, but the original launcher comes first, and it draws its own screens, which screen readers can't read. A blind player couldn't reliably get through importing a game and starting it, and a mod can't change that. The original launcher is also proprietary, so this project has its own.
- **How deep it goes:** this reads a lot of the game's internal screens directly. Mods can do that in my testing, but only with a permission that's shown as patching engine code, and through hooks marked as deprecated. Moving over would be a big job, and it could break more easily.

If mods get a built-in way to speak and there's an accessible way to start a game, I'd happily look at this again.

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
