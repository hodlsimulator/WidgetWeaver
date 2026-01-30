//
//  RemindersSmartStackKitUpgraderTests.swift
//  WidgetWeaver
//
//  Created by . . on 1/30/26.
//

import Foundation
import Testing
@testable import WidgetWeaver

struct RemindersSmartStackKitUpgraderTests {

    private func makeRemindersSpec(
        name: String,
        mode: WidgetWeaverRemindersMode,
        kitVersion: Int = 1
    ) -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = name
        spec.layout.template = .reminders

        var config = WidgetWeaverRemindersConfig(mode: mode, presentation: .dense)
        config.smartStackKitVersion = kitVersion
        spec.remindersConfig = config

        spec.style.accent = .pink
        spec.layout.showsAccentBar = true
        return spec
    }

    @Test func upgrade_setsKitVersionTo2_forMatchingSlot() {
        let slot = WidgetWeaverRemindersSmartStackKitUpgrader.Slot.upcoming
        let spec = makeRemindersSpec(name: slot.v1DefaultDesignName, mode: slot.mode, kitVersion: 1)

        let r = WidgetWeaverRemindersSmartStackKitUpgrader.upgradeV1ToV2IfNeeded(spec: spec, slot: slot)

        #expect(r.didChange == true)
        #expect(r.spec.remindersConfig?.smartStackKitVersion == 2)
    }

    @Test func upgrade_renamesLegacyKitNames_onlyWhenNameMatchesDefault() {
        let slot = WidgetWeaverRemindersSmartStackKitUpgrader.Slot.highPriority
        let spec = makeRemindersSpec(name: slot.v1DefaultDesignName, mode: slot.mode, kitVersion: 1)

        let r = WidgetWeaverRemindersSmartStackKitUpgrader.upgradeV1ToV2IfNeeded(spec: spec, slot: slot)

        #expect(r.spec.name == slot.v2DefaultDesignName)
    }

    @Test func upgrade_preservesCustomDesignNames() {
        let slot = WidgetWeaverRemindersSmartStackKitUpgrader.Slot.anytime
        let customName = "My Anytime"
        let spec = makeRemindersSpec(name: customName, mode: slot.mode, kitVersion: 1)

        let r = WidgetWeaverRemindersSmartStackKitUpgrader.upgradeV1ToV2IfNeeded(spec: spec, slot: slot)

        #expect(r.spec.name == customName)
        #expect(r.spec.remindersConfig?.smartStackKitVersion == 2)
    }

    @Test func upgrade_isIdempotent() {
        let slot = WidgetWeaverRemindersSmartStackKitUpgrader.Slot.upcoming
        let spec = makeRemindersSpec(name: slot.v1DefaultDesignName, mode: slot.mode, kitVersion: 1)

        let r1 = WidgetWeaverRemindersSmartStackKitUpgrader.upgradeV1ToV2IfNeeded(spec: spec, slot: slot)
        let r2 = WidgetWeaverRemindersSmartStackKitUpgrader.upgradeV1ToV2IfNeeded(spec: r1.spec, slot: slot)

        #expect(r1.spec == r2.spec)
        #expect(r2.didChange == false)
    }

    @Test func upgrade_doesNothing_forNonRemindersSpecs() {
        let slot = WidgetWeaverRemindersSmartStackKitUpgrader.Slot.today

        var spec = WidgetSpec.defaultSpec()
        spec.name = slot.v1DefaultDesignName
        spec.layout.template = .classic
        spec.remindersConfig = nil

        let r = WidgetWeaverRemindersSmartStackKitUpgrader.upgradeV1ToV2IfNeeded(spec: spec, slot: slot)

        #expect(r.didChange == false)
        #expect(r.spec == spec)
    }

    @Test func upgrade_doesNothing_whenModeDoesNotMatchSlot() {
        let slot = WidgetWeaverRemindersSmartStackKitUpgrader.Slot.upcoming
        let spec = makeRemindersSpec(name: slot.v1DefaultDesignName, mode: .today, kitVersion: 1)

        let r = WidgetWeaverRemindersSmartStackKitUpgrader.upgradeV1ToV2IfNeeded(spec: spec, slot: slot)

        #expect(r.didChange == false)
        #expect(r.spec == spec)
    }
}
