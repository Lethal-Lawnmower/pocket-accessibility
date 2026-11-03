# Decisions

Append-only log of owner decisions. Never rewrite an entry. When a decision
changes, add a new entry and mark the old one `Superseded by #N`. Agent
recommendations are labelled as such and are not decisions.

Entry format: `## N. Title (YYYY-MM-DD)`, then the decision, the reason, and
its boundaries, in a few lines.

---

## 1. Restart the project (2026-10-31)

Start over in this repository. The old project (parent folder) stays untouched
as a reference archive. Reason: the old project grew far past its scope, with
version intake folders, a large visual launcher and over 1.6 MB of documentation.

## 2. Thin accessibility layer on our own fork (2026-10-31)

Build on our own copy of upstream (the Pokémon Gen 1 Recompilation Project).
Accessibility lives in its own folders. Upstream files get only small, listed
hooks. Reason: upstream updates stay cheap, unlike the old hard fork.
Rejected options: the old hard fork (merge cost), and a pure upstream mod (the
mod sandbox refuses `require("ffi")`, which Prism needs).

## 3. No speech bridge or helper program (2026-10-31)

Never use a separate helper program that speaks on the game's behalf over a
network or local socket. Speech runs in-process through Prism.

## 4. Our own launcher: a small native Windows app (2026-10-31)

Upstream's launcher is proprietary (License Term 2) and cannot be used in a fork.
Ours is a plain Windows application with standard, screen-reader-labelled
controls, also used for setup: game list, Play, Import ROM, Edit save,
Settings, Credits. Agent recommendation: C# Windows Forms on .NET 10. It shows
upstream's required credit (Term 1).
Out of scope unless the owner decides otherwise: cover art, labels, mascots,
themes, animations, online panel, mod browser, update checker, per-generation rooms.

## 5. Save editor carries over from upstream (2026-10-31)

Upstream's save editor (`tools/save-editor/`) is GPL, not part of the
proprietary launcher, so we use it with credit. Our launcher opens it
(upstream's launcher Edit button is proprietary).

## 6. Distribution channel (2026-10-31)

A third-party Accessibility Mod Manager may later distribute our complete build.
It installs, updates and starts the program; our launcher still picks the game.
Using it to patch upstream's official release instead is not possible: the
Windows release is a single fused executable (checked at v0.3.98), and
upstream's updater mounts newer payloads above any loose files. The manager's
source-available license allows publishing plugins but not modifying or reusing it.
Not authorized: publishing to it or contacting anyone about it.

## 7. Pokémon Access redone our own way (2026-10-31)

Recreate the Pokémon Access experience with our own design and improvements,
not a one-to-one port. Pokémon Access declares no license, so its code and
authored data (names, translations, messages) are never copied.

## 8. Bring-your-own Pokémon Access sound pack (2026-10-31)

Players may point the launcher to a Pokémon Access sound folder they already
have, like ROMs. We never ship, host or repackage those sounds. Our own
default sound set must work fully without them.

## 9. First-release defaults (2026-10-31)

Red, Blue and Yellow first; later generations afterwards. Start from a fresh
upstream release tag, not the old fork's history. License: GPLv3 with
upstream's Section 7 terms (required by upstream). Git from day one. Small,
capped documentation (see `README.md`). Old key bindings reviewed, not copied
blindly. Upstream updates taken deliberately (roughly monthly or for a needed
fix), never per release. Prism build and license confirmed before bundling.

## 10. No old game fixes (2026-10-31)

None of the old project's map, battle, save or engine fixes carry over; upstream
is now stable. Accessibility-only behaviour (such as routing to the reachable side
of a Cut tree) is accessibility and is allowed. If an upstream bug blocks
accessibility, record it and ask the owner. No silent local fix.

## 11. Fresh code (2026-10-31)

All accessibility code is written new. Old code is reference only: read it for
behaviour and edge cases, never copy it. Reason: full control, and knowing
exactly what works and what breaks. Reusing an old module needs its own owner
decision. Details: `old-project-inventory.md`.

## 12. Old behaviour is the starting point (2026-10-31)

Rebuild toward the old accessibility behaviour, then adjust from playtesting.
The owner's last full playthrough was in early August 2026, so later old
behaviour is unvalidated. Planned: a new owner playthrough of Red on the new
build. Yellow coverage is not decided; agent recommendation is a targeted pass
over Yellow's differences (Pikachu follower and happiness, the surfing minigame,
gift starters, different trainers and scripts, the intro).

## 13. Repository identity and AI references (2026-10-31)

Commits use the owner's GitHub username with the GitHub noreply address. The
local commits made before this entry use the old project pseudonym and will be
re-authored before the first push (safe, because nothing has been pushed).
AI references stay: AI co-author lines and mentions of agent work are acceptable
in the public repository. This replaces the old project's rule against them.

## 14. Working name: Pocket Accessibility (2026-10-31)

Not final. No GitHub project with that name was found (not a trademark
search). It must not use upstream's names or marks (License Term 3).

## 15. GitHub: leaning toward a public fork (2026-10-31)

Not decided and not authorized. Private development would also be allowed,
since GPL obligations apply when builds are shared. A GitHub fork is public and
listed under upstream. A separately created repository is never listed, even when
public. Before any push: owner go-ahead, re-authored commits, reviewed docs.

## 16. Documentation layout (2026-10-31)

A fixed, capped set of files, described in `README.md`. Status is split by
workstream, and each session edits only its own section. Decisions are
append-only. Parallel sessions work on separate git branches so collisions
show up as merge conflicts, not silent overwrites. New sessions start from the
root `CLAUDE.md` or `AGENTS.md`.

## 17. Modular speech that works for mods (2026-10-31)

Keep the layer as modular as possible: menus and text-based mechanics added
by mods should speak without changes to this layer. Implemented by reading
upstream's shared UI classes (which mods receive through `mod.ui`) and an
opt-in `accessibilityText` method any screen can provide. Details:
`menus-and-text.md`.

## 18. Autonomy for Gen 1 screen coverage (2026-10-31)

The owner asked for every Gen 1 screen and all game UI to be covered,
battle included, without checking back after each screen that works.
Agents continue through the screens, verify, document and commit locally.
Still requires the owner: publishing, contacting anyone, product decisions,
and listening tests.

## 19. Publish as a public GitHub fork (2026-10-31)

The owner authorized uploading the project to GitHub as a fork ("I think
this is a good foundation to upload to GitHub under a fork"), after the
first listening session. Done with GitHub's Fork button route (supersedes
the open choice in decision 15), named `pocket-accessibility`, pushing our
`main`. Before pushing: commits re-authored to the owner's GitHub username
and noreply address (decision 13), docs scanned for personal details and
private file names, README given the project section and the credit
required by upstream License Term 1. Still requires the owner: packaged
releases, contacting upstream or anyone else, and any visibility change.

## 20. Reuse the old navigation code (2026-10-31)

Exception to decision 11, granted by the owner: the old project's
navigation code (pathfinding, map and object awareness, terrain and
traversal, puzzle help, earcons, command keys) may be reused rather than
rewritten, "unless I encounter a game breaking bug". Boundaries: decision 10
still applies (no old game fixes come along; anything that patched game
behaviour is dropped), each reused file is reviewed and adapted to v0.3.98,
and its origin is recorded. Menu and battle speech stay the new code.

## 21. Keep Chaos Cut as an optional mod (2026-10-31)

The owner wants the old project's Chaos Cut easter egg kept, as an
optional mod (off unless the player turns it on). It recreates the old
terrain bug that let Cut target people, without the unsafe block mutation.
It is a game-behaviour change, so it lives outside the accessibility layer
as an opt-in mod rather than as a core change (decision 10 still holds for
everything else).

## 22. Camera off by default (2026-10-31)

The owner has never found a use for the Pokémon Access camera ("sonar"),
so it is omitted unless a player wants it. The camera code stays; its keys
(D, G, R, V, F, C, Shift+Y, Shift+F and the through-walls variants) are not
commands and pass through to the game, and F8 help leaves them out, unless
the save option `accessibilityCamera` is true. No menu exposes that option
yet.

## 23. Controller navigation and auto-walk (2026-10-31)

Owner's controller scheme: hold the left trigger as the navigation
modifier; with it held, D-pad up and down cycle object categories and left
and right cycle items within the category. Left stick click starts
auto-walk to the selected object; right stick click starts guided
navigation. Auto-walk is new (the old project had none): it walks the
same route guided navigation describes by holding directions the way a
player would. On the map the left trigger no longer lowers game speed
(upstream's default); the left shoulder still does.

## 24. Wall bumps: keep the game's own sound only (2026-10-31)

The original game already plays its bump sound effect when the player walks
into something, and the owner chose to leave it at that. The old project's
spoken bump descriptions ("Wall ahead.", "Water ahead.", "Map edge.") are
not restored; they depended on a `world.bumped` event the old fork added to
upstream. The reused bump code stays dormant and can be revived later if
wanted.

## 25. Cross-map navigation to Area targets (2026-10-31)

Approved plan: reach targets on other maps without a new system. A new
"Area" category lists item balls still in place on the other maps of the
building or zone the player is in (maps sharing the first two words of
their id). Guided navigation uses the old cross-map planner for them, and
auto-walk follows that planner leg by leg across maps.

## 26. Accessibility page in OPTIONS (2026-10-31)

The owner asked for accessibility settings inside the game's own OPTIONS
menu. First two rows, as requested:

- **AUTO-WALK SPEED:** GAME SPEED (default: the game's own speed setting),
  or any level of the game's speed ladder (NORMAL up to 200X). The chosen
  speed applies only while auto-walk is walking; battles and other screens
  use the player's normal speeds.
- **DIALOGUE SPEECH:** PAGE BY PAGE (default, the chunk-by-chunk pacing the
  owner asked for earlier) or ALL AT ONCE (the whole dialogue box when it
  opens).

More rows can be added to the same page later.

## 27. Gold, Silver and Crystal next, same treatment as Gen 1 (2026-11-01)

The owner moved the project on to Gen 2 ("Let's move on to gold, silver,
crystal. Could you do the same thing with red, blue, and yellow and do a
complete overhaul?"), with the surfing minigame still theirs to pick up.
Scope, as for Gen 1 (decisions 18, 20, 23, 26): every Gen 2 screen and
battle spoken, the navigation, object list and auto-walk working on the
Gen 2 world, the ACCESSIBILITY page available, then an audit of the
differences between Gold, Silver and Crystal. Agents continue without
checking back after each working screen, verify, document and commit
locally. The owner also authorized subagents to split the work ("use sub
agents to spread out if you need to"). Still requires the owner: pushing,
publishing, contacting anyone, product decisions and listening tests.

## 28. Publish Gen 2 as initial groundwork (2026-11-01)

The owner approved pushing the Gold, Silver and Crystal work to the public
fork, labelled as initial groundwork: "push it for now with the label of
this is just initial groundwork. Live user testing will be done
eventually." The README says so. This approval covers that push only;
later pushes still need the owner's go-ahead, and it is not acceptance of
the Gen 2 speech, which nobody has heard yet.

## 29. Third generation next, starting with FireRed and LeafGreen (2026-11-01)

The owner considers Gen 1 and Gen 2 built ("I think first and second gen
are done. I got it."): the remaining work there is the owner's own
playtesting during the week, which will feed fixes back. Next is the
third generation, starting with FireRed and LeafGreen ("Let's start with
fire red / leaf green"); Ruby, Sapphire and Emerald come later. The owner
did no FireRed or LeafGreen work in the old project, so this starts fresh.
Same treatment and the same autonomy as decisions 18 and 27, subagents
allowed. Still requires the owner: pushing, publishing, contacting anyone,
product decisions and listening tests.

## 30. FireRed first; LeafGreen deferred; Pokémon Access as reference (2026-11-01)

The owner deferred LeafGreen ("Leaf green can wait for now") and asked for
FireRed's entire UI now, using the Pokémon Access scripts where useful
("Use the Pokemon access scripts if needed, like you did with Gen 1 and
Gen 2"). Boundaries unchanged: those scripts are a behaviour reference only
(decision 7: no license, so no code or authored text is copied); decision 20
covers only the old project's navigation code. LeafGreen needs a clean dump
from the owner before any game run.

## 31. Publish FireRed as initial groundwork (2026-11-01)

The owner approved pushing the FireRed work, labelled like Gen 2 as
initial groundwork ("Yeah, push it and then open it for me so I can
test"). The README says so. Covers that push only; not acceptance.

## 32. FireRed finishing work stays local; navigation quirks next (2026-11-01)

After the FireRed gap work was merged locally, the owner declined a push
("I don't think it's really worth a GitHub push yet") and asked for the
remaining navigation quirks to be worked out where possible ("Can you
figure out the rest of the navigation quirks? If it's possible?"). The
merged work stays on the local main branch until the owner asks for a push.

## 33. Thin ice stays automatic; push the FireRed finishing work (2026-11-01)

Auto-walk keeps stepping off thin ice and back on to fall through when no
other way exists ("Automatic should be good"). The owner then offered a push
of the FireRed gap and quirk work ("You want to push these to GitHub?"), and
the agent recommended and did it. Covers that push only; decision 32's hold
is over for this work. Not acceptance: the owner plays from 2026-11-02.

## 34. Hide FireRed's scenery from the object list (2026-11-01; now listed under Misc, decision 36)

The owner asked to hide windows, lights and cups ("probably hide them.
Unless they're needed or the original access scripts used them"). Neither
applies: in the game they are flavor lines only, and Pokémon Access's FireRed
tile objects are just switches, thin and cracked ice, and the PC. Pressing A
on them still reads them. A map's own sign event standing on one stays listed.

Extended the same day ("probably hide them as well"): every flavor-only
furniture kind is hidden too (bookshelves, shelves, paintings, kitchens,
computers, cabinets, telephones, tools, food and the like). The PC, wall Town
Map, Battle Records and Questionnaire stay because they do something. Signs
the map itself places stay, including the Vermilion Gym trash cans.

## 35. NPCs get their own category, in every game (2026-11-01)

The owner asked to move NPCs out of the object list into their own section,
for every game ("Should probably move NPCs out of the object list and make a
specific NPCs section", "This goes for every single game"). The order is now
All, Warps, Connections, Signposts, NPCs, Objects, Area. Agent choices, open to
the owner: Pokémon that stand on the map count as NPCs; All still lists
everyone; unknown and mod actors default to NPCs. Items, boulders, trees,
rocks, fossils, gift balls and decorations stay under Objects.

## 36. FireRed's hidden scenery goes under Misc (2026-11-02)

The owner asked for the furniture hidden by decision 34 to go "under a tab
called miscellaneous, or misc for short". This partly replaces decision 34:
flavor furniture is listed again, in its own category, and can be walked to.
The FireRed order is All, Warps, Connections, Signposts, NPCs, Objects, Misc,
Area. Agent choices, open to the owner: All leaves Misc out, because keeping
the noise out of All was the point of decision 34; Gen 1 and 2 get no Misc
stop, because they have no hidden furniture to put there.

## 37. Dark maps need Flash, for navigation too (2026-11-02)

The owner proposed that "Auto, walk, and manual navigation should not work
until the user has applied flash like a sighted person would", across all
games, and chose the option that also limits the object list. On a map still
dark for lack of Flash, auto-walk and guided navigation say "Too dark. Use
Flash."; a journey stops on reaching such a floor; the object list keeps only
what is in sight. Walking by hand still works.

Agent choices, open to the owner, from what each game draws: Gen 1 darkens the
whole screen with silhouettes still in view, so the list keeps the screen; Gen
2 is near black with only the cave entrance blinking, so it keeps warps on
screen; Gen 3 has a circle of light, so it keeps that circle. The camera stays
inside the same limit (in Gen 2 it cannot move). Reading the tiles around the
player and wall sounds stay, as the stand-in for bumping around.

## 38. The save editor comes next (2026-11-02)

Agent choices below superseded by #39; the owner's request stands.

The owner does not plan a full vanilla playthrough and will use the save editor
instead, and asked to work on it next. Agent choices, open to the owner: speech and
keyboard sit over upstream's editor through Kit rather than a separate editor;
Tab moves between controls and the arrows also stop on text; Shift+arrows walk a
cell cursor on the map. Pages work as upstream wrote them, with no extra legality
limits. Does not authorize a push.

## 39. A native save editor; speech over upstream's is scrapped (2026-11-02)

The owner did not want "a whole new vocabulary" to use a save editor, asked whether
the interface was the cause and whether it could be redone like the launcher, then
said: "Yeah, use subagents and handle it. I trust you. I'll test the final result.
Scrap the current method we have." So: a standard Windows Forms window in the launcher
over upstream's save logic, which runs windowless and unedited. Authorizes subagents
for this work. Does not authorize a push. The owner tests the finished result.
Refines #5: the logic carries over, upstream's interface does not face the player.

## 40. Auto-walk chases what runs off, from live state only (2026-11-02)

The owner asked for auto-walk to handle the Ilex Forest Farfetch'd "without any hard-coded
assumptions". `src/access/nav/Chase.lua` knows no map, object or script. After a walk to an
object, if the player stayed put and the object is now at least two cells away, the next
auto-walk tries each side, watches where it goes, remembers each result and stops when no
untried side is left. Game text stays the player's to advance. An object that changes id
(Gold and Silver show one bird per place) is followed by name when exactly one has it.

## 41. Auto-walk pushes boulders, optionally (2026-11-03)

The owner asked for an automatic gym puzzle solver in auto-walk and, after hearing the plan,
said "Yes, build it." When a target has no route, Gen 2 auto-walk searches the floor for pushes
that open one (`Puzzle.planOpening`), walks to each pushing cell, answers the game's Strength
question and pushes (`nav/BoulderWalk.lua`). Nothing names a map. Manual play is unchanged, and
AUTO-WALK PUZZLES in the Accessibility page (default on) turns it off. FireRed has its own
Strength code and is not covered.

Stone-table floors, same day: "auto-pushing, honestly. For those who don't want it, they can turn it
off ... manuals should be able to do it as well, if they have the proper guidance." With the setting
on, auto-walk to a boulder or a hole fills the whole floor (`BoulderWalk.tryStone`); with it off, the
hints work as before.

FireRed, same day ("do a complete kind of search of FireRed"): auto-walk to a boulder, pressure switch or
hole does the floor there too, using its own plan (`Navigation:boulderOpening`), and Secret Switches are
tried like Goldenrod's. Non-adjacent warps to one map stay apart in Gen 2 and 3. Signs with no other name
are "Sign: " and the start of their own text, in Gen 2 and 3.

Same day, the owner on Goldenrod Underground: "I don't mind having the Pathfinder auto do it." So a
target with no route also tries switches (`nav/SwitchWalk.lua`): signs whose text asks to turn them on
or off are flipped, and each result is watched from the map itself, with no switch table. Same
setting, renamed AUTO-WALK PUZZLES.

