import AppKit
import SwiftUI

enum AppMotion {
    static var instant: Animation { motion(.easeOut(duration: 0.055)) }
    static var quick: Animation { motion(.spring(response: 0.14, dampingFraction: 0.92)) }
    static var snappy: Animation { motion(.spring(response: 0.18, dampingFraction: 0.90)) }
    static var smooth: Animation { motion(.spring(response: 0.22, dampingFraction: 0.88)) }
    static var selection: Animation { motion(.spring(response: 0.16, dampingFraction: 0.86)) }
    static var hero: Animation { motion(.spring(response: 0.26, dampingFraction: 0.87, blendDuration: 0.02)) }
    static var closeHero: Animation { motion(.spring(response: 0.16, dampingFraction: 0.94, blendDuration: 0.01)) }
    // The focused image uses an explicit, aspect-preserving hero surface. These curves
    // keep its journey deliberate while the surrounding grid recedes without reflowing.
    static var referenceOpen: Animation { motion(.timingCurve(0.16, 1, 0.30, 1, duration: 0.13)) }
    static var referenceClose: Animation { motion(.timingCurve(0.55, 0, 1, 0.45, duration: 0.10)) }
    static var referenceChromeDelayNanoseconds: UInt64 { 0 }
    static var referenceCloseDelayNanoseconds: UInt64 { reduceMotion ? 0 : 105_000_000 }
    static var collectionChange: Animation { motion(.timingCurve(0.20, 0.72, 0.20, 1, duration: 0.24)) }
    static var modeSwitch: Animation { motion(.timingCurve(0.40, 0, 0.20, 1, duration: 0.22)) }
    static var reveal: Animation { motion(.spring(response: 0.30, dampingFraction: 0.84)) }
    static var chromeReveal: Animation { motion(.spring(response: 0.18, dampingFraction: 0.92)) }
    static var panel: Animation { motion(.spring(response: 0.34, dampingFraction: 0.86)) }
    static var toast: Animation { motion(.spring(response: 0.32, dampingFraction: 0.82)) }
    static var hover: Animation { motion(.spring(response: 0.16, dampingFraction: 0.90)) }

    static var bottomToastTransition: AnyTransition {
        .move(edge: .bottom).combined(with: .opacity)
    }

    static var trailingPanelTransition: AnyTransition {
        .move(edge: .trailing).combined(with: .opacity)
    }

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static func motion(_ animation: Animation) -> Animation {
        reduceMotion ? .easeOut(duration: 0.01) : animation
    }
}
