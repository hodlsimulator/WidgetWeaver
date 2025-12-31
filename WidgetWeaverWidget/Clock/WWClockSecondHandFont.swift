//
//  WWClockSecondHandFont.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/27/25.
//

import CoreText
import Foundation
import SwiftUI

enum WWClockSecondHandFont {
    static let postScriptName: String = "WWClockSecondHand-Regular"
    private static let bundledFileName: String = "WWClockSecondHand-Regular"
    private static let bundledFileExtension: String = "ttf"

    private static let registerOnce: Void = {
        guard let url = Bundle.main.url(
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
        return .custom(postScriptName, size: size)
    }
}
