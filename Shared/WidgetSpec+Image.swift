//
//  WidgetSpec+Image.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

public struct ImageSpec: Hashable, Codable, Sendable {
    public var fileName: String
    public var crop: ImageCropToken

    public init(fileName: String, crop: ImageCropToken = .fill) {
        self.fileName = fileName
        self.crop = crop
    }
}

public enum ImageCropToken: String, CaseIterable, Codable, Hashable, Sendable {
    case fill
    case fit
}

#if canImport(UIKit)
public extension ImageSpec {
    func loadUIImageFromAppGroup() -> UIImage? {
        AppGroup.loadUIImage(fileName: fileName)
    }
}
#endif
