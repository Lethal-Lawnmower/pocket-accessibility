// Pocket Accessibility's iOS launcher: the bridge between the game (Lua) and the native launcher.
//
// How the launcher comes first (docs/access/ios.md, "Startup architecture"):
//
// SDL starts LÖVE's main() from its scene delegate, and on iOS LÖVE's main() never returns:
// love.cpp turns every quit into a fresh start of the Lua state.  Each fresh start runs
// main.lua, whose first line installs src/access/PackagedBuild.lua, and that calls
// waitForGame() below through LuaJIT's FFI and the Objective-C runtime
// (src/access/IosLauncher.lua).  waitForGame() puts the launcher in its own window above SDL's
// game window and runs the main run loop itself until the player picks a game, the same way
// SDL's own message boxes wait on iOS.  Then it sets the POKEPORT_* variables, as Android's
// GameStarter does, hides the launcher and returns, and main.lua boots that game.
//
// When the game quits or refuses to start, LÖVE starts a new Lua state, main.lua calls
// waitForGame() again, and the player is back on the launcher in the same process.  Nothing in
// SDL or LÖVE is swizzled or patched for this; the only cost is that SDL's window already
// exists (black, hidden from VoiceOver) while the launcher shows.
//
// The save editor and the Mods screen (docs/access/ios.md, "Save editor and mods") need the game's
// Lua backends.  Opening one makes waitForGame() return 2 with POCKET_BACKEND set and the launcher
// left on screen; Lua then calls takeRequest() (which runs the run loop until the screen sends a
// request) and putResponse(_:) for each one, through BackendChannel (PocketBackend.swift).  When
// the screen closes, takeRequest() returns NULL, Lua quits, and LÖVE starts it again here.
//
// The class name and the selectors are read by src/access/IosLauncher.lua: rename together.

import SwiftUI
import UIKit

/// What the launcher hands the game: which game, and the ROM to import first, if any.
struct GameStart {
    let gameId: String
    let romPath: String?
}

/// What ends a launcher showing: a game to start, or a screen that needs a backend.
enum LauncherChoice {
    case game(GameStart)
    /// "save" or "mods" (POCKET_BACKEND, read by src/access/IosLauncher.lua)
    case backend(String)
}

/// The POKEPORT_* variables, set the way Android's GameStarter sets them.
enum GameEnvironment {
    /// Cleared before every launcher showing: the process outlives each game.
    static let variables = [
        "POKEPORT_IMPORT_ROM", "POKEPORT_VERSION", "POKEPORT_GAME", "POKEPORT_FORCE_IMPORT",
        "POCKET_EDITOR_PORT", "POCKET_EDITOR_TOKEN", "POCKET_BACKEND",
    ]

    static func clear() {
        for name in variables { unsetenv(name) }
    }

    static func apply(_ start: GameStart) {
        clear()
        // upstream's self-updater would replace the game with plain upstream
        setenv("POKEPORT_PORTMASTER_MANAGED", "1", 1)
        if let rom = start.romPath {
            setenv("POKEPORT_IMPORT_ROM", rom, 1)
            setenv("POKEPORT_VERSION", start.gameId, 1)
            setenv("POKEPORT_FORCE_IMPORT", "1", 1)
        }
        setenv("POKEPORT_GAME", start.gameId, 1)
    }
}

@objc(PocketLauncherBridge)
public final class PocketLauncherBridge: NSObject {
    private static var launcherWindow: UIWindow?
    private static var chosen: LauncherChoice?
    /// The C string handed to Lua by takeRequest(), kept until the next call.
    private static var requestBuffer: UnsafeMutablePointer<CChar>?
    private static var exitRequested = false
    private static var autostartTried = false
    private static var timesShown = 0
    private static var upkeepTimer: Timer?
    private static var markedView: UIView?

    static let gameScreenLabel = "Game screen"
    static let closeActionName = "Close the game and return to the launcher"

    /// Called by Lua (src/access/IosLauncher.lua) at every start of the game program.
    /// Shows the launcher and returns 1 once a game is chosen, with the environment set;
    /// 2 when a screen needs a backend (the launcher stays up; Lua then serves takeRequest);
    /// 0 when the launcher cannot be shown (the game then carries on as if there were no launcher).
    @objc public static func waitForGame() -> Int {
        guard Thread.isMainThread else {
            log("not called on the main thread; the launcher cannot be shown")
            return 0
        }
        stopUpkeep()
        GameEnvironment.clear()
        exitRequested = false
        chosen = nil
        guard let scene = windowScene() else {
            log("no window scene; the launcher cannot be shown")
            return 0
        }

        let model = LauncherModel()
        model.onStart = { start in chosen = .game(start) }
        model.onOpenBackend = { kind in chosen = .backend(kind) }
        model.prepare()
        BackendChannel.reset()
        // the window of a backend screen that just closed stays up until this one replaces it
        let previousWindow = launcherWindow

        // the game's window stays underneath; VoiceOver must not find it while the launcher shows
        setGameScreen(accessible: false)
        let window = UIWindow(windowScene: scene)
        // above SDL's launch-screen window (normal + 1) and its game window (normal)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 2)
        window.rootViewController = UIHostingController(rootView: LauncherView(model: model))
        window.makeKeyAndVisible()
        launcherWindow = window
        previousWindow?.isHidden = true
        previousWindow?.rootViewController = nil
        timesShown += 1
        log("shown (\(timesShown))")
        if let refusal = model.refusal { log("refusal shown: \(refusal)") }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        autostartIfAsked()

        // The main run loop, run here until the player chooses (SDL's message boxes do the same).
        // UIKit, VoiceOver, the document picker and timers all keep working.
        while chosen == nil {
            autoreleasepool {
                _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.1, false)
            }
        }
        let choice = chosen!
        chosen = nil
        guard case .game(let start) = choice else {
            if case .backend(let kind) = choice {
                // the launcher stays up with its screen; Lua serves the requests
                GameEnvironment.clear()
                setenv("POCKET_BACKEND", kind, 1)
                log("\(kind) backend")
            }
            return 2
        }

        window.isHidden = true
        window.rootViewController = nil
        launcherWindow = nil
        GameEnvironment.apply(start)
        gameWindow()?.makeKey()
        setGameScreen(accessible: true)
        startUpkeep()
        log("starting \(start.gameId)" + (start.romPath != nil ? " with import" : ""))
        return 1
    }

    /// Called by Lua while it serves a backend: runs the run loop until the open screen sends a
    /// request, and returns it as a C string (kept until the next call), or NULL once the screen
    /// has closed.
    @objc public static func takeRequest() -> UnsafePointer<CChar>? {
        if let old = requestBuffer {
            free(old)
            requestBuffer = nil
        }
        while true {
            if let request = BackendChannel.takePending() {
                requestBuffer = strdup(request)
                return UnsafePointer(requestBuffer)
            }
            if BackendChannel.isClosed { return nil }
            autoreleasepool {
                _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, true)
            }
        }
    }

    /// Called by Lua with the answer to the request takeRequest() returned.
    @objc public static func putResponse(_ text: UnsafePointer<CChar>) {
        BackendChannel.deliver(String(cString: text))
    }

    /// Polled by Lua while a game runs: 1 once after the player chose the game screen's
    /// "close the game" action.
    @objc public static func takeExitRequest() -> Int {
        guard exitRequested else { return 0 }
        exitRequested = false
        return 1
    }

    static func requestExit() {
        guard launcherWindow == nil else { return }
        exitRequested = true
        log("close requested from the game screen")
        UIAccessibility.post(notification: .announcement, argument: "Closing the game.")
    }

    // CI only (launcher/ios/simulator_smoke.sh): POCKET_LAUNCHER_AUTOSTART=<game id> starts that
    // game once, without an import, as Play would.  Without a ROM the game refuses, which tests
    // the way back to this launcher.
    private static func autostartIfAsked() {
        guard !autostartTried else { return }
        autostartTried = true
        guard let raw = ProcessInfo.processInfo.environment["POCKET_LAUNCHER_AUTOSTART"],
              let game = GameCatalog.all.first(where: { $0.id == raw.lowercased() }) else { return }
        log("autostart \(game.id)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            chosen = .game(GameStart(gameId: game.id, romPath: nil))
        }
    }

    // ------------------------------------------------------------ the game's window

    private static func windowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    }

    /// SDL's window: its root view controller is SDL_uikitviewcontroller, whose view gets the touches.
    private static func gameWindow() -> UIWindow? {
        guard let scene = windowScene() else { return nil }
        return scene.windows.first(where: { window in
            guard window !== launcherWindow, !window.isHidden, let root = window.rootViewController else {
                return false
            }
            return NSStringFromClass(type(of: root)).contains("SDL_uikitviewcontroller")
        })
    }

    /// While a game runs, its view is one VoiceOver element that allows direct interaction, so
    /// VoiceOver hands its touches to the game (src/access/touch/).  The launcher's own views never
    /// get this trait.
    private static func setGameScreen(accessible: Bool) {
        guard let scene = windowScene() else { return }
        for window in scene.windows where window !== launcherWindow {
            window.accessibilityElementsHidden = !accessible
        }
        guard let view = gameWindow()?.rootViewController?.view else {
            if accessible { log("game screen not found yet") }
            return
        }
        mark(view, accessible: accessible)
        if accessible {
            UIAccessibility.post(notification: .screenChanged, argument: view)
        }
    }

    private static func mark(_ view: UIView, accessible: Bool) {
        view.isAccessibilityElement = accessible
        view.accessibilityLabel = accessible ? gameScreenLabel : nil
        view.accessibilityHint = accessible
            ? "Touches go to the game when Direct Touch is on. Actions: close the game." : nil
        view.accessibilityTraits = accessible ? .allowsDirectInteraction : []
        view.accessibilityCustomActions = accessible
            ? [UIAccessibilityCustomAction(name: closeActionName, actionHandler: { _ in
                requestExit()
                return true
            })]
            : nil
        if accessible, markedView !== view {
            markedView = view
            log("game screen marked for direct touch (\(NSStringFromClass(type(of: view))))")
        }
    }

    /// LÖVE may create its window again while a game starts (a display option), which brings a
    /// new view without our marking: check once a second while the game runs.
    private static func startUpkeep() {
        stopUpkeep()
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            guard launcherWindow == nil, let view = gameWindow()?.rootViewController?.view else { return }
            if !view.isAccessibilityElement || view.accessibilityLabel != gameScreenLabel {
                mark(view, accessible: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        upkeepTimer = timer
    }

    private static func stopUpkeep() {
        upkeepTimer?.invalidate()
        upkeepTimer = nil
        markedView = nil
    }

    /// One line on the console (the smoke test reads it) and in the system log.
    static func log(_ text: String) {
        let line = "[pocket-launcher] " + text
        print(line)
        fflush(stdout)
        NSLog("%@", line)
    }
}
