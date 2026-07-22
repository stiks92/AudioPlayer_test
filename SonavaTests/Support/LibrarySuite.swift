//
//  LibrarySuite.swift
//  SonavaTests
//
//  Library tests share one on-disk media directory, and Swift Testing runs
//  suites in parallel by default — which had them deleting each other's
//  fixtures mid-run. Nesting them under one serialized parent is enough; the
//  alternative, injecting a directory everywhere, would bend the app's shape
//  to suit the tests.
//

import Testing

@Suite(.serialized)
struct LibrarySuite {}
