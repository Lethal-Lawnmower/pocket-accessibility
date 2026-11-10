// The Mods screen on iPhone (docs/access/ios.md, "Save editor and mods"), after Android's
// ModsActivity.java: the same mod backend (launcher/ModBackend/modservice.lua) through
// BackendChannel, standard SwiftUI controls.  Installed mods can be turned on or off per game,
// removed and read about; the mod index can be browsed and a listed mod installed.
//
// Installing: the zip is downloaded here (https only, at most 2 GiB) into mods-incoming, the
// backend unpacks it there ("unpack": iOS has no zip reader of its own) and runs the game's own
// manifest check ("check"); only then does the new copy replace mods/<id>, keeping the old copy's
// imported base ROMs (baseroms), as ModInstaller.java does.

import SwiftUI
import UIKit

struct ModEntry: Identifiable {
    let raw: [String: Any]
    let id: String

    init(_ raw: [String: Any], index: Int) {
        self.raw = raw
        id = (raw["id"] as? String) ?? (raw["folder"] as? String) ?? "row\(index)"
    }

    func string(_ key: String) -> String? {
        guard let value = raw[key] as? String, !value.isEmpty else { return nil }
        return value
    }
    func flag(_ key: String) -> Bool { (raw[key] as? Bool) == true }
    func has(_ key: String) -> Bool { raw[key] != nil && !(raw[key] is NSNull) }
    func list(_ key: String) -> [String] { raw[key] as? [String] ?? [] }

    var title: String {
        let name = string("title") ?? string("name") ?? string("folder") ?? "?"
        guard let version = string("version") else { return name }
        return "\(name), version \(version)"
    }
}

enum ModFiles {
    static let warningAccepted = "pocket-access-mods-warning-accepted"
    static let incoming = "mods-incoming"
    static let maxDownloadBytes: Int64 = 2 * 1024 * 1024 * 1024

    static var mods: URL { Storage.documents.appendingPathComponent("mods", isDirectory: true) }

    /// The same test as ModInstaller.java's PLAIN_NAME.
    static func isPlainName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z0-9_@][A-Za-z0-9_@.\\- ]*$", options: .regularExpression) != nil
    }

    static func remove(folder: String) throws {
        guard isPlainName(folder) else { throw ModProblem("\(folder) is not a mod folder.") }
        let target = mods.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.removeItem(at: target)
        if FileManager.default.fileExists(atPath: target.path) { throw ModProblem("The mod could not be removed.") }
    }

    /// Swaps the new copy in, keeping the old one until the new one is in place, and its imports.
    static func replace(_ unpacked: URL, into target: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: mods, withIntermediateDirectories: true)
        let retired = target.deletingLastPathComponent()
            .appendingPathComponent(target.lastPathComponent + ".old-" + UUID().uuidString, isDirectory: true)
        let hadOld = fm.fileExists(atPath: target.path)
        if hadOld { try fm.moveItem(at: target, to: retired) }
        do {
            try fm.moveItem(at: unpacked, to: target)
        } catch {
            if hadOld { try? fm.moveItem(at: retired, to: target) }
            throw ModProblem("The new copy could not be put in place.")
        }
        guard hadOld else { return }
        let oldImports = retired.appendingPathComponent("baseroms", isDirectory: true)
        let newImports = target.appendingPathComponent("baseroms", isDirectory: true)
        if Storage.isDirectory(oldImports), !fm.fileExists(atPath: newImports.path) {
            try? fm.moveItem(at: oldImports, to: newImports)
        }
        try? fm.removeItem(at: retired)
    }
}

struct ModProblem: LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}

@MainActor
final class ModsModel: ObservableObject {
    enum Listing: String, CaseIterable, Identifiable {
        case installed = "Installed mods"
        case index = "Browse the mod index"
        var id: String { rawValue }
    }

    let games: [CatalogGame]
    @Published var gameId: String
    @Published var view: Listing = .installed
    @Published var rows: [ModEntry] = []
    @Published var status = "Loading the mods. This can take a few seconds."
    @Published var busy = false
    @Published var failure: String?
    @Published var alert: String?
    @Published var warningAccepted: Bool

    init(games: [CatalogGame]) {
        self.games = games
        gameId = games.first?.id ?? "red"
        warningAccepted = FileManager.default.fileExists(
            atPath: Storage.documents.appendingPathComponent(ModFiles.warningAccepted).path)
        if games.isEmpty {
            failure = "Play a game once first, so its data is imported; mods are turned on per game."
        }
    }

    var gameName: String { games.first(where: { $0.id == gameId })?.name ?? gameId }

    func say(_ text: String) {
        status = text
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    func acceptWarning() {
        let marker = Storage.documents.appendingPathComponent(ModFiles.warningAccepted)
        FileManager.default.createFile(atPath: marker.path, contents: Data())
        warningAccepted = true
        load()
    }

    private func send(_ command: String, _ arguments: [String: Any] = [:]) async -> [String: Any]? {
        do {
            return try await BackendChannel.send(command, arguments)
        } catch {
            if let backendError = error as? BackendError, case .closed = backendError { return nil }
            failure = "The mod backend stopped: \(error.localizedDescription)"
            return nil
        }
    }

    func load(force: Bool = false) {
        guard warningAccepted, failure == nil else { return }
        let index = view == .index
        busy = true
        say(index ? "Fetching the mod index." : "Reading your mods.")
        Task {
            var arguments: [String: Any] = ["version": gameId]
            if force { arguments["force"] = true }
            let answer = await send(index ? "index" : "installed", arguments)
            busy = false
            guard let answer = answer else { return }
            if (answer["ok"] as? Bool) != true {
                say("That did not work: " + (answer["error"] as? String ?? "unknown error"))
                return
            }
            let list = answer["mods"] as? [[String: Any]] ?? []
            rows = list.enumerated().map { ModEntry($0.element, index: $0.offset) }
            if index {
                var text = "\(rows.count) mods listed."
                if (answer["stale"] as? Bool) == true { text += " The index could not be reached; this is the saved copy." }
                if let problems = answer["problems"] as? [String], !problems.isEmpty {
                    text += " " + problems.joined(separator: ". ")
                }
                say(text)
            } else {
                say(rows.isEmpty ? "No mods installed. Choose Browse the mod index to find some."
                    : "\(rows.count) installed.")
            }
        }
    }

    func subtitle(_ mod: ModEntry) -> String {
        var parts: [String] = []
        if let problem = mod.string("problem") { parts.append("The game cannot load it: \(problem)") }
        if mod.has("enabled") { parts.append(mod.flag("enabled") ? "On" : "Off") }
        if let installed = mod.string("installedVersion") { parts.append("Installed \(installed)") }
        if mod.has("forThisGame"), !mod.flag("forThisGame"), mod.has("enabled") || mod.flag("gamesListed") {
            parts.append("Not for \(gameName)")
        }
        if let unavailable = mod.string("unavailable") { parts.append("Cannot be installed: \(unavailable)") }
        if let about = mod.string("summary") ?? mod.string("description") { parts.append(about) }
        return parts.joined(separator: ". ")
    }

    func details(_ mod: ModEntry) -> String {
        var text = subtitle(mod)
        if let author = mod.string("author") { text += "\n\nBy \(author)" }
        if let games = mod.string("games") { text += "\n\nGames: \(games)" }
        let permissions = mod.list("permissions")
        if !permissions.isEmpty { text += "\n\nIt asks for: " + permissions.joined(separator: ", ") }
        for warning in mod.list("warnings") { text += "\n\nWarning: \(warning)" }
        if let license = mod.string("license") { text += "\n\nLicense: \(license)" }
        return text
    }

    func setEnabled(_ mod: ModEntry, _ on: Bool) {
        guard let id = mod.string("id") else { return }
        Task {
            guard let answer = await send("setEnabled", ["modId": id, "enabled": on, "version": gameId]) else { return }
            if (answer["ok"] as? Bool) == true {
                say("\(mod.title) is \(on ? "on" : "off") for \(gameName). It takes effect the next time you start the game.")
                load()
            } else {
                say("That did not work: " + (answer["error"] as? String ?? "unknown error"))
            }
        }
    }

    func remove(_ mod: ModEntry) {
        guard let folder = mod.string("folder") else { return }
        do {
            try ModFiles.remove(folder: folder)
            say("Removed \(mod.title).")
            load()
        } catch {
            say(error.localizedDescription)
        }
    }

    func install(_ mod: ModEntry) {
        guard !busy, let url = mod.string("url") else { return }
        busy = true
        say("Installing \(mod.title).")
        let expectedId = mod.string("id")
        let game = gameId
        Task {
            let scratch = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let incoming = Storage.documents.appendingPathComponent(ModFiles.incoming, isDirectory: true)
            let zip = incoming.appendingPathComponent(scratch + ".zip")
            let unpacked = incoming.appendingPathComponent(scratch, isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: zip)
                try? FileManager.default.removeItem(at: unpacked)
                // the scratch folder itself, only when nothing else is in it
                if (try? FileManager.default.contentsOfDirectory(atPath: incoming.path))?.isEmpty == true {
                    try? FileManager.default.removeItem(at: incoming)
                }
            }
            do {
                try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
                try await download(url, to: zip)
                say("Unpacking.")
                guard let unpack = await send("unpack", ["zip": "\(ModFiles.incoming)/\(scratch).zip",
                                                         "into": "\(ModFiles.incoming)/\(scratch)"]) else {
                    busy = false
                    return
                }
                if (unpack["ok"] as? Bool) != true {
                    throw ModProblem(unpack["error"] as? String ?? "The mod could not be unpacked.")
                }
                say("Checking.")
                guard let verdict = await send("check", ["folder": "\(ModFiles.incoming)/\(scratch)",
                                                         "version": game]) else {
                    busy = false
                    return
                }
                if (verdict["ok"] as? Bool) != true {
                    throw ModProblem("The mod could not be checked: " + (verdict["error"] as? String ?? "unknown error"))
                }
                if (verdict["valid"] as? Bool) != true {
                    throw ModProblem("The game would not load this mod: " + (verdict["problem"] as? String ?? "?"))
                }
                let foundId = verdict["modId"] as? String ?? ""
                if let expected = expectedId, expected != foundId {
                    throw ModProblem("The download holds a different mod (\(foundId)), so it was not installed.")
                }
                guard ModFiles.isPlainName(foundId) else {
                    throw ModProblem("The mod's name, \(foundId), cannot be used as a folder name.")
                }
                try ModFiles.replace(unpacked, into: ModFiles.mods.appendingPathComponent(foundId, isDirectory: true))
                var done = "Installed \(verdict["name"] as? String ?? foundId)."
                if (verdict["forThisGame"] as? Bool) == false {
                    done += " It does not list \(gameName)."
                } else if (verdict["enabled"] as? Bool) == false {
                    done += " It is off; turn it on in Installed mods."
                }
                busy = false
                say(done + " It takes effect the next time you start the game.")
                load()
            } catch {
                busy = false
                say(error.localizedDescription)
            }
        }
    }

    /// https only, at most 2 GiB.  Stages are announced; there is no percentage here.
    private func download(_ address: String, to file: URL) async throws {
        guard address.hasPrefix("https://"), let url = URL(string: address) else {
            throw ModProblem("The listing's download address is not a secure web address.")
        }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.setValue("PocketAccessibility-mods", forHTTPHeaderField: "User-Agent")
        say("Downloading.")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ModProblem("The download failed (\(http.statusCode)).")
        }
        let size = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if Int64(size) > ModFiles.maxDownloadBytes { throw ModProblem("The download is too large to be a mod.") }
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temporary, to: file)
    }
}

struct ModsView: View {
    @StateObject var model: ModsModel
    let close: () -> Void
    @State private var chosen: ModEntry?
    @State private var detailsOf: ModEntry?
    @State private var confirmingInstall: ModEntry?
    @State private var confirmingRemove: ModEntry?

    private func shown(_ binding: Binding<ModEntry?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }

    private var installWarning: String {
        guard let mod = confirmingInstall else { return "" }
        return mod.list("warnings").map { "Warning: \($0)" }.joined(separator: "\n\n")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(model.status).accessibilityAddTraits(.updatesFrequently)
                }
                if let failure = model.failure {
                    Section {
                        Text(failure)
                        Button("Close", action: close)
                    }
                } else if !model.warningAccepted {
                    Section {
                        Text(verbatim: "Mods are not endorsed or tested by Pocket Accessibility. Accessibility may "
                            + "break, so use them at your own risk. Mods are other people's code, and they run on "
                            + "your device.")
                        Button("OK") { model.acceptWarning() }
                        Button("Cancel", action: close)
                    }
                } else {
                    Section {
                        Picker("Game", selection: $model.gameId) {
                            ForEach(model.games) { game in Text(game.name).tag(game.id) }
                        }
                        Picker("Show", selection: $model.view) {
                            ForEach(ModsModel.Listing.allCases) { view in Text(view.rawValue).tag(view) }
                        }
                        if model.view == .index {
                            Button("Refresh the index") { model.load(force: true) }.disabled(model.busy)
                        }
                    }
                    Section(header: Heading(model.view.rawValue)) {
                        ForEach(model.rows) { mod in
                            Button(action: { chosen = mod }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mod.title)
                                    let about = model.subtitle(mod)
                                    if !about.isEmpty {
                                        Text(about).font(.subheadline).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .disabled(model.busy)
                        }
                    }
                    Section {
                        Button("Close", action: close)
                    }
                }
            }
            .navigationTitle("Mods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: close)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { model.load() }
        .onChange(of: model.gameId) { _ in model.load() }
        .onChange(of: model.view) { _ in model.load() }
        .confirmationDialog(chosen?.title ?? "", isPresented: shown($chosen), titleVisibility: .visible) {
            if let mod = chosen {
                if model.view == .index {
                    if mod.string("url") != nil {
                        Button(mod.has("installedVersion") ? "Install again or update" : "Install") {
                            confirmingInstall = mod
                        }
                    }
                } else {
                    if mod.string("id") != nil {
                        let on = mod.flag("enabled")
                        Button(on ? "Turn off for \(model.gameName)" : "Turn on for \(model.gameName)") {
                            model.setEnabled(mod, !on)
                        }
                    }
                    if mod.flag("removable") {
                        Button("Remove", role: .destructive) { confirmingRemove = mod }
                    }
                }
                Button("Details") { detailsOf = mod }
                Button("Cancel", role: .cancel) {}
            }
        }
        .alert(detailsOf?.title ?? "", isPresented: shown($detailsOf)) {
            Button("Close", role: .cancel) {}
        } message: {
            Text(detailsOf.map { model.details($0) } ?? "")
        }
        .alert("Download and install \(confirmingInstall?.title ?? "")?", isPresented: shown($confirmingInstall)) {
            Button("Install") { if let mod = confirmingInstall { model.install(mod) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(installWarning)
        }
        .alert("Remove \(confirmingRemove?.title ?? "")? Its files are deleted.", isPresented: shown($confirmingRemove)) {
            Button("Remove", role: .destructive) { if let mod = confirmingRemove { model.remove(mod) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}
