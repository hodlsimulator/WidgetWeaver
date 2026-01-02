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
        guard let url = resourceBundle.url(
            forResource: bundledFileName,
            withExtension: bundledFileExtension
        ) else {
            return
        }

        var cfErr: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfErr)
    }()

    static func font(size: CGFloat) -> Font {
        _ = registerOnce
        // Fixed size keeps the glyph positioning stable under Dynamic Type.
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
