// The save editor on iPhone (docs/access/ios.md, "Save editor and mods"; docs/access/save-editor.md
// for the protocol and the page model).  The same backend as Windows and Android
// (launcher/SaveBackend/service.lua) through BackendChannel; the screen follows Android's
// SaveEditorPage.java with standard SwiftUI controls, so VoiceOver reads them without speech code:
// a Page choice, then each page's pickers, summary, list, fields and buttons, and Save, Undo, Redo,
// Reload and Close.  Long choices (400 species) open as their own searchable list.

import SwiftUI
import UIKit

// ---------------------------------------------------------------- the page model

struct EditorOption: Identifiable {
    let value: JSONValue
    let label: String
    var id: String { value.text }

    static func list(_ any: Any?) -> [EditorOption] {
        (any as? [[String: Any]] ?? []).map {
            EditorOption(value: JSONValue($0["value"]), label: $0["label"] as? String ?? JSONValue($0["value"]).text)
        }
    }

    static func label(of value: JSONValue, in options: [EditorOption]) -> String {
        options.first(where: { $0.value.text == value.text })?.label ?? value.text
    }
}

struct EditorPicker: Identifiable {
    let id: String
    let label: String
    let value: JSONValue
    let options: [EditorOption]
    let below: Bool
}

struct EditorRow: Identifiable {
    /// Row ids reach the backend as strings (save-editor.md).
    let id: String
    let text: String
    let checked: Bool?
}

struct EditorList {
    let label: String
    let rows: [EditorRow]
    let selected: String?
    let checks: Bool
    let filter: Bool
}

struct EditorField: Identifiable {
    let id: String
    let label: String
    let kind: String
    let value: JSONValue
    let lo: Double?
    let hi: Double?
    let options: [EditorOption]
    let help: String?
    let issue: String?
    let enabled: Bool

    /// The name with its range, as the other platforms say it.
    var spokenLabel: String {
        guard kind == "number", let lo = lo, let hi = hi else { return label }
        return "\(label), \(JSONValue.number(lo).text) to \(JSONValue.number(hi).text)"
    }

    var hint: String? {
        let parts = [issue, help].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }
}

struct EditorAction: Identifiable {
    let id: String
    let label: String
    let enabled: Bool
    let confirm: String?
}

struct EditorPage {
    var pickers: [EditorPicker] = []
    var summary: String?
    var list: EditorList?
    var fields: [EditorField] = []
    var actions: [EditorAction] = []

    init() {}

    init(_ model: [String: Any]) {
        pickers = (model["pickers"] as? [[String: Any]] ?? []).map {
            EditorPicker(id: JSONValue($0["id"]).text, label: $0["label"] as? String ?? "",
                         value: JSONValue($0["value"]), options: EditorOption.list($0["options"]),
                         below: ($0["below"] as? Bool) == true)
        }
        summary = model["summary"] as? String
        if let list = model["list"] as? [String: Any] {
            let rows = (list["rows"] as? [[String: Any]] ?? []).map { row -> EditorRow in
                EditorRow(id: JSONValue(row["id"]).text, text: row["text"] as? String ?? "",
                          checked: row["checked"].map { JSONValue($0).isTrue })
            }
            self.list = EditorList(label: list["label"] as? String ?? "List", rows: rows,
                                   selected: list["selected"].map { JSONValue($0).text },
                                   checks: (list["checks"] as? Bool) == true,
                                   filter: (list["filter"] as? Bool) == true)
        }
        fields = (model["fields"] as? [[String: Any]] ?? []).map {
            EditorField(id: JSONValue($0["id"]).text, label: $0["label"] as? String ?? "",
                        kind: $0["kind"] as? String ?? "info", value: JSONValue($0["value"]),
                        lo: ($0["lo"] as? NSNumber)?.doubleValue, hi: ($0["hi"] as? NSNumber)?.doubleValue,
                        options: EditorOption.list($0["options"]),
                        help: $0["help"] as? String, issue: $0["issue"] as? String,
                        enabled: ($0["enabled"] as? Bool) != false)
        }
        actions = (model["actions"] as? [[String: Any]] ?? []).map {
            EditorAction(id: JSONValue($0["id"]).text, label: $0["label"] as? String ?? "",
                         enabled: ($0["enabled"] as? Bool) != false, confirm: $0["confirm"] as? String)
        }
    }
}

// ---------------------------------------------------------------- the editor's state

@MainActor
final class SaveEditorModel: ObservableObject {
    struct PageRef: Identifiable {
        let id: String
        let label: String
    }

    let game: CatalogGame
    @Published var title: String
    @Published var opened = false
    @Published var failure: String?
    @Published var pages: [PageRef] = []
    @Published var pageId: String?
    @Published var page = EditorPage()
    @Published var status = "Opening the save."
    @Published var dirty = false
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var canSave = false
    @Published var alert: String?

    /// Requests go one after another, in the order the player made them.
    private var last: Task<Void, Never>?
    private var started = false

    init(game: CatalogGame) {
        self.game = game
        title = "\(game.name) save"
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = last
        last = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    private static func firstLine(_ text: String) -> String {
        text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
    }

    /// Sends one request and takes in the status every answer carries.
    private func request(_ command: String, _ arguments: [String: Any] = [:]) async -> [String: Any]? {
        do {
            let answer = try await BackendChannel.send(command, arguments)
            dirty = (answer["dirty"] as? Bool) == true
            canUndo = (answer["canUndo"] as? Bool) == true
            canRedo = (answer["canRedo"] as? Bool) == true
            canSave = (answer["canSave"] as? Bool) == true
            if let text = answer["status"] as? String, !text.isEmpty { status = text }
            if (answer["ok"] as? Bool) != true {
                alert = "That did not work: " + Self.firstLine(answer["error"] as? String ?? "unknown error")
            } else if let message = answer["message"] as? String, !message.isEmpty {
                if (answer["messageKind"] as? String) == "error" {
                    alert = message
                } else {
                    say(message)
                }
            }
            return answer
        } catch {
            if let backendError = error as? BackendError, case .closed = backendError { return nil }
            alert = error.localizedDescription
            return nil
        }
    }

    func say(_ text: String) {
        status = text
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    func open() {
        guard !started else { return }
        started = true
        enqueue {
            guard let answer = await self.request("open", ["version": self.game.id]) else {
                self.failure = "The save editor could not start."
                return
            }
            if (answer["ok"] as? Bool) != true {
                self.alert = nil
                self.failure = "The save could not be opened: "
                    + Self.firstLine(answer["error"] as? String ?? "unknown error")
                return
            }
            if let missing = answer["missingCache"] as? String, !missing.isEmpty {
                self.failure = missing
                return
            }
            if let title = answer["title"] as? String { self.title = title }
            if answer["corrupt"] is String {
                self.alert = "This save could not be read, so saving is turned off. " + self.status
            }
            self.pages = (answer["pages"] as? [[String: Any]] ?? []).map {
                PageRef(id: JSONValue($0["id"]).text, label: $0["label"] as? String ?? "")
            }
            self.opened = true
            if let first = self.pages.first { self.showPage(first.id) }
        }
    }

    func showPage(_ id: String) {
        pageId = id
        page = EditorPage()
        pageCommand("model")
    }

    /// A page command; its answer carries the page's fresh model.
    func pageCommand(_ command: String, _ arguments: [String: Any] = [:]) {
        guard let id = pageId else { return }
        var request = arguments
        request["page"] = id
        enqueue {
            guard let answer = await self.request(command, request) else { return }
            // a slow answer for a page the player has left is not shown
            if self.pageId == id, let model = answer["model"] as? [String: Any] {
                self.page = EditorPage(model)
            }
        }
    }

    func select(_ row: EditorRow) { pageCommand("select", ["row": row.id]) }
    func pick(_ picker: EditorPicker, _ option: EditorOption) {
        pageCommand("pick", ["picker": picker.id, "value": option.value.json])
    }
    func set(_ field: EditorField, _ value: Any) { pageCommand("set", ["field": field.id, "value": value]) }
    func toggle(_ row: EditorRow, _ checked: Bool) { pageCommand("toggle", ["row": row.id, "checked": checked]) }
    func action(_ action: EditorAction) { pageCommand("action", ["action": action.id]) }

    func save(then done: (() -> Void)? = nil) {
        enqueue {
            let answer = await self.request("save")
            if (answer?["saved"] as? Bool) == true { done?() }
        }
    }

    func history(_ command: String) {
        enqueue {
            let answer = await self.request(command)
            if (answer?["changed"] as? Bool) == true, let id = self.pageId {
                if let model = await self.request("model", ["page": id])?["model"] as? [String: Any] {
                    self.page = EditorPage(model)
                }
            }
        }
    }

    func reload() {
        enqueue {
            _ = await self.request("reload")
            if let id = self.pageId,
               let model = await self.request("model", ["page": id])?["model"] as? [String: Any] {
                self.page = EditorPage(model)
            }
        }
    }

    /// Runs `then` once every earlier request has been answered (typing included).
    func afterPending(_ then: @escaping @MainActor () -> Void) {
        enqueue { then() }
    }
}

// ---------------------------------------------------------------- screens

/// A choice from a list that may be long: its own page, searchable, the current one marked.
struct OptionListView: View {
    let title: String
    let options: [EditorOption]
    let current: JSONValue
    let choose: (EditorOption) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var search = ""

    private var shown: [EditorOption] {
        search.isEmpty ? options : options.filter { $0.label.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List(shown) { option in
            Button(action: {
                choose(option)
                presentationMode.wrappedValue.dismiss()
            }) {
                HStack {
                    Text(option.label)
                    Spacer()
                    if option.value.text == current.text {
                        Image(systemName: "checkmark").accessibilityHidden(true)
                    }
                }
            }
            .accessibilityAddTraits(option.value.text == current.text ? .isSelected : [])
        }
        .searchable(text: $search)
        .navigationTitle(title)
    }
}

/// A row that opens an option list, read as "label, current choice".
struct ChoiceLink: View {
    let label: String
    let options: [EditorOption]
    let value: JSONValue
    let hint: String?
    let enabled: Bool
    let choose: (EditorOption) -> Void

    var body: some View {
        NavigationLink(destination: OptionListView(title: label, options: options, current: value, choose: choose)) {
            HStack {
                Text(label)
                Spacer()
                Text(EditorOption.label(of: value, in: options)).foregroundColor(.secondary)
            }
        }
        .disabled(!enabled)
        .accessibilityHint(hint ?? "")
    }
}

/// A number or text field: typed, then sent with Return (or Done).  Numbers also adjust by one
/// with VoiceOver's swipe up and down.
struct TypedFieldRow: View {
    let field: EditorField
    let send: (Any) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    private func commit() {
        if field.kind == "number" {
            guard let number = Double(draft.trimmingCharacters(in: .whitespaces)) else {
                draft = field.value.text
                UIAccessibility.post(notification: .announcement, argument: "Type a number.")
                return
            }
            if draft != field.value.text { send(JSONValue.number(number).json) }
        } else if draft != field.value.text {
            send(draft)
        }
    }

    private func adjust(_ step: Double) {
        guard field.enabled, case .number(let current) = field.value else { return }
        var next = current + step
        if let lo = field.lo { next = max(lo, next) }
        if let hi = field.hi { next = min(hi, next) }
        if next != current { send(JSONValue.number(next).json) }
    }

    var body: some View {
        HStack {
            Text(field.label)
            TextField(field.spokenLabel, text: $draft)
                .multilineTextAlignment(.trailing)
                .keyboardType(field.kind == "number" ? .numbersAndPunctuation : .default)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(commit)
                .disabled(!field.enabled)
                .accessibilityLabel(field.spokenLabel)
                .accessibilityHint(field.hint ?? "")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: adjust(1)
                    case .decrement: adjust(-1)
                    @unknown default: break
                    }
                }
        }
        .onAppear { draft = field.value.text }
        .onChange(of: field.value) { value in if !focused { draft = value.text } }
        .onChange(of: focused) { isFocused in if !isFocused { commit() } }
    }
}

struct FieldRow: View {
    let field: EditorField
    @ObservedObject var model: SaveEditorModel

    var body: some View {
        switch field.kind {
        case "number", "text":
            TypedFieldRow(field: field) { value in model.set(field, value) }
        case "choice":
            ChoiceLink(label: field.label, options: field.options, value: field.value, hint: field.hint,
                       enabled: field.enabled) { option in model.set(field, option.value.json) }
        case "check":
            Toggle(field.label, isOn: Binding(get: { field.value.isTrue }, set: { model.set(field, $0) }))
                .disabled(!field.enabled)
                .accessibilityHint(field.hint ?? "")
        default:
            Text("\(field.label): \(field.value.text)")
                .accessibilityHint(field.hint ?? "")
        }
    }
}

struct EditorListSection: View {
    let list: EditorList
    @ObservedObject var model: SaveEditorModel
    @State private var filter = ""

    private var rows: [EditorRow] {
        filter.isEmpty ? list.rows : list.rows.filter { $0.text.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        Section(header: Heading(list.label)) {
            if list.filter {
                TextField("Filter \(list.label)", text: $filter)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
            }
            if list.rows.isEmpty {
                Text("Empty")
            }
            ForEach(rows) { row in
                if list.checks {
                    Toggle(row.text, isOn: Binding(get: { row.checked == true },
                                                   set: { model.toggle(row, $0) }))
                } else {
                    Button(action: { model.select(row) }) {
                        HStack {
                            Text(row.text)
                            Spacer()
                            if row.id == list.selected {
                                Image(systemName: "checkmark").accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(row.id == list.selected ? .isSelected : [])
                }
            }
        }
    }
}

struct SaveEditorView: View {
    @StateObject var model: SaveEditorModel
    let close: () -> Void
    @State private var confirming: EditorAction?
    @State private var askingToClose = false
    @State private var askingToReload = false

    private var alertShown: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
    }
    private var confirmShown: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private func pickerRows(below: Bool) -> some View {
        ForEach(model.page.pickers.filter { $0.below == below }) { picker in
            ChoiceLink(label: picker.label, options: picker.options, value: picker.value, hint: nil,
                       enabled: true) { option in model.pick(picker, option) }
        }
    }

    private func requestClose() {
        // anything typed is sent first, then the dirty flag is up to date
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        model.afterPending {
            if model.dirty { askingToClose = true } else { close() }
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(model.status)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if let failure = model.failure {
                    Section {
                        Text(failure)
                        Button("Close", action: close)
                    }
                } else if model.opened {
                    Section {
                        ChoiceLink(label: "Page",
                                   options: model.pages.map { EditorOption(value: .string($0.id), label: $0.label) },
                                   value: .string(model.pageId ?? ""), hint: nil, enabled: true) { option in
                            model.showPage(option.value.text)
                        }
                        pickerRows(below: false)
                    }
                    if let summary = model.page.summary, !summary.isEmpty {
                        Section {
                            Text(summary)
                        }
                    }
                    if let list = model.page.list {
                        EditorListSection(list: list, model: model)
                    }
                    if model.page.pickers.contains(where: { $0.below }) {
                        Section { pickerRows(below: true) }
                    }
                    if !model.page.fields.isEmpty {
                        Section {
                            ForEach(model.page.fields) { field in FieldRow(field: field, model: model) }
                        }
                    }
                    if !model.page.actions.isEmpty {
                        Section {
                            ForEach(model.page.actions) { action in
                                Button(action.label) {
                                    if action.confirm != nil { confirming = action } else { model.action(action) }
                                }
                                .disabled(!action.enabled)
                            }
                        }
                    }
                    Section(header: Heading("Save")) {
                        Button("Save") { model.save() }.disabled(!model.canSave)
                        Button("Undo") { model.history("undo") }.disabled(!model.canUndo)
                        Button("Redo") { model.history("redo") }.disabled(!model.canRedo)
                        Button("Reload from storage") {
                            if model.dirty { askingToReload = true } else { model.reload() }
                        }
                        Button("Close", action: requestClose)
                    }
                }
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: requestClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.save() }.disabled(!model.canSave)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { model.open() }
        .alert(model.alert ?? "", isPresented: alertShown) {
            Button("OK", role: .cancel) {}
        }
        .alert(confirming?.confirm ?? "", isPresented: confirmShown) {
            Button("Yes") { if let action = confirming { model.action(action) } }
            Button("No", role: .cancel) {}
        }
        .alert("Save your changes before closing?", isPresented: $askingToClose) {
            Button("Save") { model.save(then: close) }
            Button("Don't save", role: .destructive, action: close)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Discard your unsaved changes and reload the save from storage?", isPresented: $askingToReload) {
            Button("Discard", role: .destructive) { model.reload() }
            Button("Keep editing", role: .cancel) {}
        }
    }
}
