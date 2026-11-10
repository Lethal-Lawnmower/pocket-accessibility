// Pocket Accessibility's iOS launcher: its screens.  Standard SwiftUI controls only (lists,
// buttons, navigation links, headings), so VoiceOver reads them without any speech code here.
// No view here allows direct interaction; only the game's own screen does (PocketLauncherBridge).

import SwiftUI
import UniformTypeIdentifiers

enum LauncherText {
    /// Required by License Term 1, visibly, in any launcher.
    static let upstreamCredit = "Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC "
        + "(https://github.com/bryanthaboi/gen1recomp)"
    static let soundsSource = "https://github.com/nuive/pokemon-access/archive/refs/heads/master.zip"
}

/// A heading VoiceOver can jump to with the rotor.
struct Heading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.headline).accessibilityAddTraits(.isHeader)
    }
}

/// A page of plain text under headings.
struct TextPage<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
    }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @State private var pickingRoms = false

    private var showingRefusal: Binding<Bool> {
        Binding(get: { model.refusal != nil }, set: { shown in if !shown { model.refusal = nil } })
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text(model.message)
                }
                Section(header: Heading("Games")) {
                    ForEach(model.rows) { row in
                        Button(action: { model.play(row) }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.game.name)
                                Text(row.status).font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Plays the game.")
                    }
                }
                Section(header: Heading("ROMs")) {
                    Button("Import ROMs") { pickingRoms = true }
                    Button("Refresh game list") { model.refresh(announce: true) }
                }
                Section(header: Heading("More")) {
                    NavigationLink("Touch controls", destination: TouchControlsView())
                    NavigationLink("Sounds", destination: SoundsView(model: model))
                    NavigationLink("Credits and licenses", destination: CreditsView())
                }
                Section {
                    Text(LauncherText.upstreamCredit).font(.footnote)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Pocket Accessibility")
        }
        .navigationViewStyle(.stack)
        .fileImporter(isPresented: $pickingRoms, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                model.importRoms(urls)
            case .failure(let error):
                model.say("The files could not be opened: \(error.localizedDescription)")
            }
        }
        .alert("The game did not start", isPresented: showingRefusal) {
            Button("Close", role: .cancel) {}
        } message: {
            Text(model.refusal ?? "")
        }
    }
}

struct TouchControlsView: View {
    var body: some View {
        TextPage("Touch controls") {
            Group {
                Text(verbatim: "While a game runs, its whole screen is one item for VoiceOver, called Game screen. "
                    + "With VoiceOver's Direct Touch on, your touches on it go straight to the game, which reads "
                    + "them as the gestures below. VoiceOver stays on for everything else: this launcher, "
                    + "notifications, calls and system pop-ups.")
                Heading("Turning on Direct Touch")
                Text(verbatim: "iPhone keeps Direct Touch off until you turn it on for an app. When the Game screen is "
                    + "focused, turn the VoiceOver rotor to Direct Touch and switch it on. iPhone remembers this for "
                    + "Pocket Accessibility; you can also find it in Settings, Accessibility, VoiceOver, Rotor, "
                    + "Direct Touch Apps.")
            }
            // The gestures, as in README.md "Controls" and docs/access/android.md: keep them in step.
            Group {
                Heading("Gestures")
                Text(verbatim: "They work anywhere on the Game screen, held either way up. What matters is how many "
                    + "fingers you use, not where you touch.")
                Text(verbatim: "Swipe: walk on the map. In menus, battles and dialogue, it moves the cursor.")
                Text(verbatim: "Two-finger swipe left or right: the previous or next thing on the map. "
                    + "Two-finger swipe up or down: change the category.")
                Text(verbatim: "Double tap: A. Two-finger double tap: B. Three-finger double tap: Start. "
                    + "Three-finger tap: Select.")
                Text(verbatim: "Any gesture stops a walk.")
            }
            Group {
                Heading("Settings")
                Text(verbatim: "In the game's OPTIONS, ACCESSIBILITY has TOUCH GESTURES (on by default here) and "
                    + "TOUCH WALKING. Manual: each swipe is one step. Hybrid: the game says the next straight "
                    + "stretch, like 18 up; swipe that way to walk all of it. Auto: a swipe, any way, walks all "
                    + "the way to what you picked. HAPTICS gives a light tap for each step and a firmer one when "
                    + "you walk into something.")
                Heading("Leaving a game")
                Text(verbatim: "Save in the game first; leaving does not save. On the title screen, a two-finger "
                    + "triple tap brings you back here. Or, with Direct Touch switched off, swipe up or down "
                    + "on the Game screen to the action \(PocketLauncherBridge.closeActionName) and double tap. "
                    + "Closing Pocket Accessibility from the App Switcher works too, and it opens on this launcher "
                    + "next time.")
            }
        }
    }
}

struct SoundsView: View {
    @ObservedObject var model: LauncherModel
    @State private var pickingFolder = false

    var body: some View {
        TextPage("Sounds") {
            Text(verbatim: model.soundsInstalled ? "The Pokémon Access sounds are installed."
                 : "The Pokémon Access sounds are not installed. The game uses its built-in sounds.")
            Text(model.message)
            Group {
                Heading("Getting the sounds")
                Text(verbatim: "Pocket Accessibility doesn't come with the Pokémon Access sounds, and this iPhone version "
                    + "cannot download them by itself yet. They come from the Pokémon Access project on GitHub:")
                Text(verbatim: "1. Open the download link below. Safari saves a zip file to Downloads.")
                Text(verbatim: "2. In the Files app, open Downloads and tap the zip. Files unpacks it into a folder.")
                Text(verbatim: "3. Come back here, choose Import sounds from a folder, and pick that folder "
                    + "or the sounds folder inside it.")
            }
            Link("Download the Pokémon Access sounds (opens Safari)",
                 destination: URL(string: LauncherText.soundsSource)!)
            Button("Import sounds from a folder") { pickingFolder = true }
            if model.soundsInstalled {
                Button("Remove Pokémon Access sounds") { model.removeSounds() }
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let folder = urls.first { model.importSounds(from: folder) }
            case .failure(let error):
                model.say("The folder could not be opened: \(error.localizedDescription)")
            }
        }
    }
}

struct CreditsView: View {
    /// The license texts build_ipa.py puts in the app's licenses folder.
    private var licenseFiles: [URL] {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("licenses", isDirectory: true),
              let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        var files: [URL] = []
        for case let file as URL in walker {
            if (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                files.append(file)
            }
        }
        return files.sorted(by: { $0.path < $1.path })
    }

    var body: some View {
        List {
            Section {
                Text(verbatim: "Pocket Accessibility: screen reader accessibility for the Pokémon recompilation games.")
                Text(LauncherText.upstreamCredit)
                Text(verbatim: "Speech by Prism (MPL-2.0). Game engine LÖVE (zlib license).")
            }
            Section(header: Heading("Licenses")) {
                ForEach(licenseFiles, id: \.self) { file in
                    NavigationLink(file.deletingPathExtension().lastPathComponent,
                                   destination: LicenseTextView(file: file))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Credits and licenses")
    }
}

struct LicenseTextView: View {
    let file: URL
    var body: some View {
        TextPage(file.deletingPathExtension().lastPathComponent) {
            Text((try? String(contentsOf: file, encoding: .utf8)) ?? "This license text could not be read.")
        }
    }
}
