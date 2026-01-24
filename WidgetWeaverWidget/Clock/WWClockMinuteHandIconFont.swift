//
//  WWClockMinuteHandIconFont.swift
//  WidgetWeaver
//
//  Created by . . on 1/24/26.
//

import CoreText
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Icon-face minute-hand ticking font.
///
/// This is intentionally separate from WWClockMinuteHandFont so the Icon face can use
/// a different hand thickness without affecting Ceramic or other render targets.
enum WWClockMinuteHandIconFont {
    static let postScriptName: String = "WWClockMinuteHandIcon-Regular"
    private static let bundledFileName: String = "WWClockMinuteHandIcon-Regular"
    private static let bundledFileExtension: String = "ttf"

    private final class BundleToken {}

    private static var resourceBundle: Bundle {
        Bundle(for: BundleToken.self)
    }

    private static let registerOnce: Void = {
        #if canImport(UIKit)
        if UIFont(name: postScriptName, size: 12) != nil {
            return
        }
        #endif

        guard let url = resourceBundle.url(
            forResource: bundledFileName,
            withExtension: bundledFileExtension
        ) else {
            WWClockDebugLog.append(
                "minuteHandIconFont missing resource \(bundledFileName).\(bundledFileExtension)",
                category: "clock",
                throttleID: "clock.font.minuteIcon.missingResource",
                minInterval: 600,
                now: Date()
            )
            return
        }

        var cfErr: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfErr)

        if !ok {
            #if canImport(UIKit)
            if UIFont(name: postScriptName, size: 12) != nil {
                return
            }
            #endif

            let err = cfErr?.takeRetainedValue().localizedDescription ?? "unknown"
            WWClockDebugLog.append(
                "minuteHandIconFont register failed err=\(err)",
                category: "clock",
                throttleID: "clock.font.minuteIcon.registerFail",
                minInterval: 600,
                now: Date()
            )
            return
        }
    }()

    static func font(size: CGFloat) -> Font {
        _ = registerOnce
        return .custom(postScriptName, fixedSize: size)
    }

    static func isAvailable() -> Bool {
        _ = registerOnce
        #if canImport(UIKit)
        return UIFont(name: postScriptName, size: 12) != nil
        #else
        return true
        #endif
    }
}
