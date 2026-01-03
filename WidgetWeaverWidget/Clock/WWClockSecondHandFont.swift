//
//  WWClockSecondHandFont.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/27/25.
//

import CoreText
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum WWClockSecondHandFont {
    static let postScriptName: String = "WWClockSecondHand-Regular"
    private static let bundledFileName: String = "WWClockSecondHand-Regular"
    private static let bundledFileExtension: String = "ttf"

    private final class BundleToken {}

    private static var resourceBundle: Bundle {
        Bundle(for: BundleToken.self)
    }

    private static let registerOnce: Void = {
        #if canImport(UIKit)
        // The font is listed in the widget extension Info.plist (UIAppFonts),
        // so it is often already registered. Avoid logging a scary failure in that case.
        if UIFont(name: postScriptName, size: 12) != nil {
            return
        }
        #endif

        guard let url = resourceBundle.url(
            forResource: bundledFileName,
            withExtension: bundledFileExtension
        ) else {
            WWClockDebugLog.append(
                "secondHandFont missing resource \(bundledFileName).\(bundledFileExtension)",
                category: "clock",
                throttleID: "clock.font.missingResource",
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
                "secondHandFont register failed err=\(err)",
                category: "clock",
                throttleID: "clock.font.registerFail",
                minInterval: 600,
                now: Date()
            )
            return
        }

        #if canImport(UIKit)
        let available = UIFont(name: postScriptName, size: 12) != nil
        WWClockDebugLog.append(
            "secondHandFont register ok available=\(available ? 1 : 0)",
            category: "clock",
            throttleID: "clock.font.registerOK",
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
