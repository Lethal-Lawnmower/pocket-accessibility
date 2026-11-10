// Pocket Accessibility's iOS launcher: the games, the ROMs in the app's folder, and sounds.
//
// The catalog mirrors src/core/GameVersion.lua like the Windows and Android launchers;
// tests/access/launcher_catalog_test.lua fails when they drift apart.  ROMs are identified by
// size and SHA-1, as Android's RomFolderScanner does, and the game checks them again on import
// (src/access/PackagedImporter.lua).  The game's save folder on iOS is the app's Documents folder
// (upstream's mobile/ios/patch_love_src.py), which the Files app shows as Pocket Accessibility.

import CryptoKit
import Foundation
import UIKit

struct CatalogGame: Identifiable {
    let id: String
    let name: String
    /// The game's cache folder in the save folder (GameVersion.cachePrefix without the slash).
    let folder: String
    let romSha1: [String]
}

enum GameCatalog {
    static let all: [CatalogGame] = [
        CatalogGame(id: "red", name: "Pokémon Red", folder: "red",
                    romSha1: ["ea9bcae617fdf159b045185467ae58b2e4a48b9a"]),
        CatalogGame(id: "blue", name: "Pokémon Blue", folder: "blue",
                    romSha1: ["d7037c83e1ae5b39bde3c30787637ba1d4c48ce2"]),
        CatalogGame(id: "yellow", name: "Pokémon Yellow", folder: "yellow",
                    romSha1: ["cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1"]),
        CatalogGame(id: "gold", name: "Pokémon Gold", folder: "gold",
                    romSha1: ["d8b8a3600a465308c9953dfa04f0081c05bdcb94"]),
        CatalogGame(id: "silver", name: "Pokémon Silver", folder: "silver",
                    romSha1: ["49b163f7e57702bc939d642a18f591de55d92dae"]),
        CatalogGame(id: "crystal", name: "Pokémon Crystal", folder: "crystal",
                    romSha1: ["f4cd194bdee0d04ca4eac29e09b8e4e9d818c133",
                              "f2f52230b536214ef7c9924f483392993e226cfb"]),
        CatalogGame(id: "firered", name: "Pokémon FireRed", folder: "firered",
                    romSha1: ["41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc",
                              "dd5945db9b930750cb39d00c84da8571feebf417"]),
        CatalogGame(id: "leafgreen", name: "Pokémon LeafGreen", folder: "leafgreen",
                    romSha1: ["574fa542ffebb14be69902d1d36f1ec0a4afd71e",
                              "7862c67bdecbe21d1d69ce082ce34327e1c6ed5e"]),
        CatalogGame(id: "ruby", name: "Pokémon Ruby", folder: "ruby",
                    romSha1: ["f28b6ffc97847e94a6c21a63cacf633ee5c8df1e",
                              "610b96a9c9a7d03d2bafb655e7560ccff1a6d894",
                              "5b64eacf892920518db4ec664e62a086dd5f5bc8"]),
        CatalogGame(id: "sapphire", name: "Pokémon Sapphire", folder: "sapphire",
                    romSha1: ["3ccbbd45f8553c36463f13b938e833f652b793e4",
                              "4722efb8cd45772ca32555b98fd3b9719f8e60a9",
                              "89b45fb172e6b55d51fc0e61989775187f6fe63c"]),
        CatalogGame(id: "emerald", name: "Pokémon Emerald", folder: "emerald",
                    romSha1: ["f3ae088181bf583e55daf962a92bb46f4f1d07b7"]),
    ]

    static func forSha1(_ sha1: String) -> CatalogGame? {
        let wanted = sha1.lowercased()
        return all.first(where: { $0.romSha1.contains(wanted) })
    }
}

/// Where things are.  Everything is in the app's Documents folder, which is also the game's save folder.
enum Storage {
    static let refusalFile = "pocket-access-start-refused.txt"  // src/access/PackagedBuild.lua
    static let cacheMarker = "rom-cache.complete"               // src/import/CacheContract.lua
    static let soundsFolder = "pocket-access-sounds"            // src/access/nav/Earcons.lua
    static let soundsIncoming = "pocket-access-sounds-incoming"

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Where Import ROMs copies to; the player can also drop dumps here (or in Documents itself) in Files.
    static var roms: URL { documents.appendingPathComponent("ROMs", isDirectory: true) }

    /// Only "imported at some point"; the game runs the full check and refuses a stale import.
    static func isImported(_ game: CatalogGame) -> Bool {
        FileManager.default.fileExists(atPath: documents
            .appendingPathComponent(game.folder, isDirectory: true)
            .appendingPathComponent(cacheMarker).path)
    }

    static func soundsInstalled() -> Bool {
        let pack = documents.appendingPathComponent(soundsFolder, isDirectory: true)
        return isDirectory(pack.appendingPathComponent("common")) && isDirectory(pack.appendingPathComponent("gb"))
    }

    static func isDirectory(_ url: URL) -> Bool {
        var directory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }
}

/// Finds cartridge dumps by extension, size and SHA-1, like Android's RomFolderScanner.
enum RomScanner {
    static let extensions: Set<String> = ["gb", "gbc", "gba"]
    static let sizes: Set<Int> = [1024 * 1024, 2 * 1024 * 1024, 16 * 1024 * 1024]

    static func looksLikeRom(_ url: URL, size: Int) -> Bool {
        extensions.contains(url.pathExtension.lowercased()) && sizes.contains(size)
    }

    /// Game id to the file holding its dump.  `cache` maps "path|size|modified" to a SHA-1, so a
    /// return to the launcher does not hash every dump again.
    static func scan(folders: [URL], cache: [String: String]) -> (found: [String: URL], cache: [String: String]) {
        var found: [String: URL] = [:]
        var known = cache
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        for folder in folders {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let values = try? item.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true, let size = values.fileSize,
                      looksLikeRom(item, size: size) else { continue }
                let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
                let key = "\(item.path)|\(size)|\(modified)"
                var sha1 = known[key]
                if sha1 == nil, let data = try? Data(contentsOf: item, options: .mappedIfSafe) {
                    sha1 = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    known[key] = sha1
                }
                if let sha1 = sha1, let game = GameCatalog.forSha1(sha1), found[game.id] == nil {
                    found[game.id] = item
                }
            }
        }
        return (found, known)
    }
}

final class LauncherModel: ObservableObject {
    struct Row: Identifiable {
        let game: CatalogGame
        let rom: URL?
        let imported: Bool
        var id: String { game.id }
        var status: String { imported ? "Ready" : "Imports the first time you play" }
    }

    @Published var rows: [Row] = []
    @Published var message = "Looking for games."
    @Published var refusal: String?
    @Published var soundsInstalled = false
    @Published var busy = false

    /// Set by PocketLauncherBridge; called once with the game to start.
    var onStart: ((GameStart) -> Void)?
    /// Set by PocketLauncherBridge; called once when a screen needs the game's backend ("save" or "mods").
    var onOpenBackend: ((String) -> Void)?
    /// The game whose save editor is open (PocketSaveEditor.swift).
    @Published var editing: CatalogGame?

    /// Kept for the life of the process, across returns to the launcher.
    private static var hashCache: [String: String] = [:]

    /// Before the launcher shows: the ROMs folder (so Files shows it), the game's refusal, the list.
    func prepare() {
        try? FileManager.default.createDirectory(at: Storage.roms, withIntermediateDirectories: true)
        let refusalURL = Storage.documents.appendingPathComponent(Storage.refusalFile)
        if FileManager.default.fileExists(atPath: refusalURL.path) {
            let text = (try? String(contentsOf: refusalURL, encoding: .utf8))
                ?? "The game did not start, and its reason could not be read."
            try? FileManager.default.removeItem(at: refusalURL)
            refusal = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        soundsInstalled = Storage.soundsInstalled()
        refresh(announce: false)
    }

    func refresh(announce: Bool) {
        busy = true
        if announce { say("Looking for games.") }
        let cache = LauncherModel.hashCache
        DispatchQueue.global(qos: .userInitiated).async {
            let result = RomScanner.scan(folders: [Storage.roms, Storage.documents], cache: cache)
            DispatchQueue.main.async {
                LauncherModel.hashCache = result.cache
                self.show(found: result.found, announce: announce)
            }
        }
    }

    private func show(found: [String: URL], announce: Bool) {
        rows = GameCatalog.all.compactMap { game -> Row? in
            let rom = found[game.id]
            let imported = Storage.isImported(game)
            guard rom != nil || imported else { return nil }
            return Row(game: game, rom: rom, imported: imported)
        }
        busy = false
        if rows.isEmpty {
            message = "No games yet. Games are not included. Choose Import ROMs and pick your cartridge dumps, "
                + "or put them in the ROMs folder of Pocket Accessibility in the Files app and choose Refresh game list."
        } else {
            message = "Choose a game to play."
        }
        PocketLauncherBridge.log("games listed: \(rows.map { $0.game.id }.joined(separator: ","))")
        if announce {
            say(found.isEmpty ? "No games found." : "Found \(found.count) " + (found.count == 1 ? "game." : "games."))
        }
    }

    func play(_ row: Row) {
        guard !busy else { return }
        if row.imported {
            busy = true
            onStart?(GameStart(gameId: row.game.id, romPath: nil))
            return
        }
        guard let rom = row.rom else {
            say("\(row.game.name) needs importing, but its dump was not found. Import it again.")
            return
        }
        busy = true
        say("Importing \(row.game.name). This can take a minute or two, and the game speaks when it is ready.")
        // long enough for VoiceOver to say that before the game's own speech starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.onStart?(GameStart(gameId: row.game.id, romPath: rom.path))
        }
    }

    /// Opens the save editor for a game that has been imported (its data is needed to read the save).
    /// The backend runs in the game program, which then starts again on this launcher.
    func editSave(_ game: CatalogGame) {
        guard !busy, editing == nil else { return }
        guard Storage.isImported(game) else {
            say("\(game.name) has not been imported yet. Play it once first, then edit its save.")
            return
        }
        busy = true
        PocketLauncherBridge.log("save editor for \(game.id)")
        onOpenBackend?("save")
        editing = game
    }

    /// The editor closed: the game program starts again and shows a fresh launcher.
    func editorClosed() {
        BackendChannel.close()
        say("Closing the save editor.")
    }

    var importedGames: [CatalogGame] { rows.filter { $0.imported }.map { $0.game } }

    /// Copies what the player picked into Documents/ROMs, then lists the games again.
    func importRoms(_ urls: [URL]) {
        var copied = 0
        var skipped: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard RomScanner.extensions.contains(url.pathExtension.lowercased()) else {
                skipped.append(url.lastPathComponent)
                continue
            }
            let target = Storage.roms.appendingPathComponent(url.lastPathComponent)
            if target.standardizedFileURL == url.standardizedFileURL {
                copied += 1
                continue
            }
            do {
                try FileManager.default.createDirectory(at: Storage.roms, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: url, to: target)
                copied += 1
            } catch {
                skipped.append(url.lastPathComponent)
            }
        }
        PocketLauncherBridge.log("imported \(copied) file(s), skipped \(skipped.count)")
        if !skipped.isEmpty {
            say("Not copied, not a Game Boy or Game Boy Advance dump, or unreadable: " + skipped.joined(separator: ", "))
        }
        refresh(announce: true)
    }

    // ------------------------------------------------------------ sounds

    /// Copies the Pokémon Access sounds from a folder the player picked: the sounds folder itself
    /// (with common and gb in it) or the folder above it.  Only WAV files of at most 4 MiB, as on
    /// Android; the old pack stays until the new one is complete.
    func importSounds(from folder: URL) {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        var root = folder
        if !Storage.isDirectory(root.appendingPathComponent("common")) {
            root = folder.appendingPathComponent("sounds", isDirectory: true)
        }
        guard Storage.isDirectory(root.appendingPathComponent("common")),
              Storage.isDirectory(root.appendingPathComponent("gb")) else {
            say("This folder doesn't look like Pokémon Access sounds. Choose the sounds folder, "
                + "the one with the common and gb folders in it.")
            return
        }
        let incoming = Storage.documents.appendingPathComponent(Storage.soundsIncoming, isDirectory: true)
        try? fm.removeItem(at: incoming)
        var copied = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        if let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys) {
            for case let file as URL in walker {
                guard file.pathExtension.lowercased() == "wav",
                      let values = try? file.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true, (values.fileSize ?? 0) <= 4 * 1024 * 1024 else { continue }
                let rootPath = root.standardizedFileURL.path
                let filePath = file.standardizedFileURL.path
                guard filePath.hasPrefix(rootPath + "/") else { continue }
                let relative = String(filePath.dropFirst(rootPath.count + 1))
                let target = incoming.appendingPathComponent(relative)
                do {
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: file, to: target)
                    copied += 1
                } catch {
                    continue
                }
            }
        }
        let pack = Storage.documents.appendingPathComponent(Storage.soundsFolder, isDirectory: true)
        if copied == 0 {
            try? fm.removeItem(at: incoming)
            say("That folder has no usable sound files, so nothing was imported.")
            return
        }
        try? fm.removeItem(at: pack)
        do {
            try fm.moveItem(at: incoming, to: pack)
        } catch {
            try? fm.removeItem(at: incoming)
            say("The sounds could not be put in place: \(error.localizedDescription)")
            return
        }
        soundsInstalled = Storage.soundsInstalled()
        PocketLauncherBridge.log("sounds imported: \(copied)")
        say("Done. \(copied) sounds are ready, and the game uses them from its next start.")
    }

    func removeSounds() {
        let pack = Storage.documents.appendingPathComponent(Storage.soundsFolder, isDirectory: true)
        try? FileManager.default.removeItem(at: pack)
        soundsInstalled = Storage.soundsInstalled()
        say(soundsInstalled ? "The sounds could not be removed."
            : "Removed. The game goes back to the built-in sounds from its next start.")
    }

    /// Shown on screen and spoken by VoiceOver.
    func say(_ text: String) {
        message = text
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
