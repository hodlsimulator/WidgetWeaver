//
//  WidgetWeaverClockDesignConfig+FaceToken.swift
//  WidgetWeaver
//
//  Created by . . on 1/21/26.
//

import Foundation

extension WidgetWeaverClockDesignConfig {
    var faceToken: WidgetWeaverClockFaceToken {
        WidgetWeaverClockFaceToken.canonical(from: face)
    }
}
