// Step and bump haptics on iPhone (decision 68, docs/access/ios.md "Haptics").
//
// src/access/Haptics.lua calls +[PocketHaptics play:] through LuaJIT's FFI and the
// Objective-C runtime, on the main thread where LÖVE runs: 1 is a step, 2 is a bump.
// UIKit's impact feedback is used rather than love.system.vibrate, which on iOS is the long
// system vibration.  It follows the phone's own System Haptics setting.
//
// The class name and selector are read by src/access/Haptics.lua: rename together.

import UIKit

@objc(PocketHaptics)
public final class PocketHaptics: NSObject {
    /// A soft, light tap for every step.
    private static let step = UIImpactFeedbackGenerator(style: .soft)
    /// A firmer, crisp tap for walking into something.
    private static let bump = UIImpactFeedbackGenerator(style: .rigid)

    @objc public static func play(_ kind: Int) {
        switch kind {
        case 1:
            step.impactOccurred(intensity: 0.5)
            step.prepare()
        case 2:
            bump.impactOccurred(intensity: 0.8)
            bump.prepare()
        default:
            break
        }
    }
}
