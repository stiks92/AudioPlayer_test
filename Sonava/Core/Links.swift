//
//  Links.swift
//  Sonava
//
//  Every outward URL in one place. The domain is the single value the
//  owner changes after buying one; until then GitHub Pages serves the
//  same files from docs/site/ — the pages themselves already exist and
//  ship with the repository.
//

import Foundation

enum Links {
    /// The site root. Owner: replace once the domain is live; GitHub Pages
    /// for the repository serves docs/ meanwhile.
    static let site = URL(string: "https://stiks92.github.io/sonava-site")!

    static let privacyPolicy = site.appendingPathComponent("privacy.html")
    static let support = site.appendingPathComponent("support.html")
    /// Apple's standard EULA — the ToU link App Review expects beside any
    /// subscription offer (3.1.2).
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
