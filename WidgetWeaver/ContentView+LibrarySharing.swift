//
//  ContentView+LibrarySharing.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import Foundation

extension ContentView {
    func sharePackage(for spec: WidgetSpec) -> WidgetWeaverSharePackage {
        let normalised = spec.normalised()
        let fileName = WidgetWeaverSharePackage.suggestedFileName(prefix: normalised.name, suffix: "design")
        let data = (try? store.exportExchangeData(specs: [normalised], includeImages: true)) ?? Data()
        return WidgetWeaverSharePackage(fileName: fileName, data: data)
    }
}
