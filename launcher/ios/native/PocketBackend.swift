// The launcher's end of the game's Lua backends on iPhone (docs/access/ios.md, "Save editor and
// mods"): the save editor's (launcher/SaveBackend/service.lua) and the Mods screen's
// (launcher/ModBackend/modservice.lua), the same ones Windows reaches over stdin and Android over
// a local socket.  Here there is no second program and no socket: everything runs on the main
// thread.  A screen calls send(); Lua, inside PocketLauncherBridge.takeRequest(), picks the request
// up, answers it and hands the answer back through putResponse(_:), which resumes send().
// One request at a time, as on the other platforms.

import Foundation

enum BackendError: LocalizedError {
    case closed
    case busy
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .closed: return "The game's backend is closed."
        case .busy: return "Another request is still being answered."
        case .unreadable(let why): return "The answer could not be read: \(why)"
        }
    }
}

enum BackendChannel {
    private static var pending: String?
    private static var waiting: CheckedContinuation<[String: Any], Error>?
    private static var nextId = 1
    private(set) static var isClosed = false

    /// At every launcher showing: a fresh, open channel.
    static func reset() {
        pending = nil
        waiting?.resume(throwing: BackendError.closed)
        waiting = nil
        isClosed = false
    }

    /// Sends one command with its arguments and returns the decoded answer.
    @MainActor
    static func send(_ command: String, _ arguments: [String: Any] = [:]) async throws -> [String: Any] {
        if isClosed { throw BackendError.closed }
        if waiting != nil || pending != nil { throw BackendError.busy }
        var request = arguments
        request["cmd"] = command
        request["id"] = nextId
        nextId += 1
        let data = try JSONSerialization.data(withJSONObject: request)
        guard let line = String(data: data, encoding: .utf8) else { throw BackendError.unreadable("encoding") }
        return try await withCheckedThrowingContinuation { continuation in
            waiting = continuation
            pending = line
        }
    }

    /// The screen has closed: Lua's takeRequest() returns NULL and the program starts again.
    static func close() {
        isClosed = true
        pending = nil
        waiting?.resume(throwing: BackendError.closed)
        waiting = nil
    }

    // ------------------------------------------------------------ Lua's side (PocketLauncherBridge)

    static func takePending() -> String? {
        guard let request = pending else { return nil }
        pending = nil
        return request
    }

    static func deliver(_ text: String) {
        guard let continuation = waiting else { return }
        waiting = nil
        do {
            guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                continuation.resume(throwing: BackendError.unreadable("not an object"))
                return
            }
            continuation.resume(returning: object)
        } catch {
            continuation.resume(throwing: BackendError.unreadable(error.localizedDescription))
        }
    }
}

/// A JSON value from a backend model: option values and row ids may be strings or numbers.
enum JSONValue: Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(_ any: Any?) {
        switch any {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let text as String:
            self = .string(text)
        default:
            self = .null
        }
    }

    /// For sending back exactly as received.
    var json: Any {
        switch self {
        case .string(let text): return text
        case .number(let number):
            if number == number.rounded(), abs(number) < 1e15 { return Int(number) }
            return number
        case .bool(let flag): return flag
        case .null: return NSNull()
        }
    }

    /// As shown and as typed.
    var text: String {
        switch self {
        case .string(let text): return text
        case .number(let number):
            if number == number.rounded(), abs(number) < 1e15 { return String(Int(number)) }
            return String(number)
        case .bool(let flag): return flag ? "On" : "Off"
        case .null: return ""
        }
    }

    var isTrue: Bool {
        switch self {
        case .bool(let flag): return flag
        case .number(let number): return number != 0
        case .string(let text): return text == "true"
        case .null: return false
        }
    }
}
