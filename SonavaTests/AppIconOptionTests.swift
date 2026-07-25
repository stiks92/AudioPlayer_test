//
//  AppIconOptionTests.swift
//  SonavaTests
//
//  Alternate icons fail in a specific, silent way: the option is listed, the
//  user taps it, and iOS refuses because the asset was never bundled or the
//  build setting was never updated. So the interesting assertion is against the
//  built product, not against the Swift.
//

import Testing
import Foundation
import UIKit
@testable import Sonava

@MainActor
struct AppIconOptionTests {

    private var appBundle: Bundle { Bundle(identifier: "com.sonava.player") ?? .main }

    /// The alternate icons iOS actually knows about, from the built Info.plist.
    private var bundledAlternateIcons: [String: Any] {
        let icons = appBundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        return icons?["CFBundleAlternateIcons"] as? [String: Any] ?? [:]
    }

    @Test("The default icon is free; the rest are Pro")
    func defaultIsFree() {
        #expect(AppIconOption.aurora.isPro == false)
        #expect(AppIconOption.aurora.isDefault)
        for option in AppIconOption.all where option.id != "aurora" {
            #expect(option.isPro, "\(option.id) should be Pro")
            #expect(option.alternateName != nil, "\(option.id) has no asset name")
        }
    }

    @Test("Ids are unique and lookup falls back to the default")
    func lookup() {
        let ids = AppIconOption.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(AppIconOption.option(alternateName: "AppIcon-Ocean").id == "ocean")
        #expect(AppIconOption.option(alternateName: nil).id == "aurora")
        #expect(AppIconOption.option(alternateName: "AppIcon-Nope").id == "aurora")
    }

    @Test("Every icon has a matching accent palette, so the two never disagree")
    func idsMatchPalettes() {
        let paletteIDs = Set(ThemePalette.all.map(\.id))
        for option in AppIconOption.all {
            #expect(paletteIDs.contains(option.id), "\(option.id) has no matching palette")
        }
        #expect(AppIconOption.all.count == ThemePalette.all.count)
    }

    @Test("Every alternate icon is actually bundled")
    func alternatesAreBundled() throws {
        let bundled = bundledAlternateIcons
        #expect(!bundled.isEmpty, "no alternate icons reached the bundle — check the build settings")

        for option in AppIconOption.all {
            guard let name = option.alternateName else { continue }
            #expect(bundled[name] != nil,
                    "'\(name)' is offered in the UI but isn't in CFBundleAlternateIcons")
        }
    }

    @Test("Each bundled alternate points at real artwork")
    func alternatesHaveArtwork() throws {
        for (name, value) in bundledAlternateIcons {
            let entry = try #require(value as? [String: Any], "\(name) has no icon dictionary")
            // Asset-catalog icons name an image set; loose-file icons list
            // filenames. Either is fine — an empty entry is not.
            let named = entry["CFBundleIconName"] as? String
            let files = entry["CFBundleIconFiles"] as? [String] ?? []
            #expect(named?.isEmpty == false || !files.isEmpty,
                    "\(name) declares no artwork at all")
        }
    }

    @Test("The manager reflects whatever icon is actually applied")
    func managerReflectsSystemState() {
        let manager = AppIconManager.shared
        #expect(manager.current == AppIconOption.option(
            alternateName: UIApplication.shared.alternateIconName
        ))
    }
}
