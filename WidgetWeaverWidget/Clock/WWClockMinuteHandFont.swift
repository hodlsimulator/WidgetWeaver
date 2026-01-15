//
//  WWClockMinuteHandFont.swift
//  WidgetWeaver
//
//  Created by . . on 1/15/26.
//

import CoreText
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum WWClockMinuteHandFont {
    static let postScriptName: String = "WWClockMinuteHand-Regular"
    private static let bundledFileName: String = "WWClockMinuteHand-Regular"
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
                "minuteHandFont missing resource \(bundledFileName).\(bundledFileExtension)",
                category: "clock",
                throttleID: "clock.font.minute.missingResource",
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
                "minuteHandFont register failed err=\(err)",
                category: "clock",
                throttleID: "clock.font.minute.registerFail",
                minInterval: 600,
                now: Date()
            )
            return
        }

        #if canImport(UIKit)
        let available = UIFont(name: postScriptName, size: 12) != nil
        WWClockDebugLog.append(
            "minuteHandFont register ok available=\(available ? 1 : 0)",
            category: "clock",
            throttleID: "clock.font.minute.registerOK",
            minInterval: 600,
            now: Date()
        )
        #endif
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
