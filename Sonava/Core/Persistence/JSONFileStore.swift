//
//  JSONFileStore.swift
//  Sonava
//
//  One place that knows how the app puts Codable values on disk. Favourites,
//  recents, playlists, downloads, servers and the local library all live
//  through this file.
//
//  ## Why this is careful now
//
//  Research into what makes people abandon a music app produced one answer
//  louder than every feature request combined: a library that disappears.
//  "my entire large library of flac gone in a puff of WTF"; "как 50гб музыки
//  просто исчезло???????". Across two review corpora, data loss and
//  update-broke-it outrank every missing feature.
//
//  The old implementation had two silent failure modes, both of which
//  produce exactly that experience:
//
//  1. `try? data.write(...)` — a full disk, a sandbox hiccup or a
//     protected-data window (the file system is unavailable for a moment
//     after a locked-phone launch) discarded the write and said nothing. The
//     app carried on with in-memory state that would vanish at quit.
//  2. `try? JSONDecoder().decode(...)` returning the default — a truncated
//     or partially-written file silently became "you have no favourites",
//     and the *next* write then made that permanent.
//
//  So: every successful write leaves the previous good copy as `.bak`; a
//  read that cannot decode the main file recovers from `.bak` before giving
//  up; a file that cannot be decoded at all is moved aside rather than
//  overwritten, so nothing is destroyed by the act of failing to read it;
//  and both kinds of failure are recorded in `StorageDiagnostics`, which the
//  UI can show. Losing data must at minimum be *visible*.
//

import Foundation

/// What went wrong on disk, so the app can say so instead of pretending.
///
/// Deliberately tiny and observable: the point is not telemetry, it is that
/// a person whose disk is full finds out from the app rather than from an
/// empty library three days later.
@MainActor
final class StorageDiagnostics: ObservableObject {
    static let shared = StorageDiagnostics()

    struct Failure: Identifiable, Equatable {
        let id = UUID()
        let filename: String
        let message: String
        let date: Date
        /// Whether user data was recovered from the backup copy.
        var recovered: Bool = false
    }

    @Published private(set) var failures: [Failure] = []

    /// The most recent write failure, if any — what a warning banner shows.
    var lastWriteFailure: Failure? { failures.last { !$0.recovered } }

    func record(_ failure: Failure) {
        failures.append(failure)
        if failures.count > 20 { failures.removeFirst(failures.count - 20) }
    }

    func clear() { failures.removeAll() }

    nonisolated static func report(filename: String, message: String, recovered: Bool = false) {
        Task { @MainActor in
            shared.record(Failure(filename: filename, message: message,
                                  date: Date(), recovered: recovered))
        }
    }
}

/// A typed JSON file in Application Support, with a rolling backup.
///
/// Reads never throw: a missing file yields the default value, which is the
/// right behaviour for user state — refusing to launch is worse. A *corrupt*
/// file is a different thing entirely and is treated as one.
struct JSONFileStore<Value: Codable & Sendable>: Sendable {

    private let filename: String
    private let defaultValue: Value

    init(_ filename: String, default defaultValue: Value) {
        self.filename = filename
        self.defaultValue = defaultValue
    }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    var url: URL { Self.directory.appendingPathComponent(filename) }
    /// The last copy that decoded cleanly.
    var backupURL: URL { Self.directory.appendingPathComponent(filename + ".bak") }

    // MARK: - Read

    func read() -> Value {
        let fm = FileManager.default

        // The happy path.
        if let data = try? Data(contentsOf: url) {
            if let value = try? JSONDecoder().decode(Value.self, from: data) {
                return value
            }
            // The file is there but unreadable. Recover from the backup if we
            // can, and either way move the bad copy aside — overwriting it on
            // the next save is how a recoverable glitch becomes permanent.
            let recovered = (try? Data(contentsOf: backupURL))
                .flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
            let quarantine = Self.directory.appendingPathComponent(
                "\(filename).corrupt-\(Int(Date().timeIntervalSince1970))")
            try? fm.moveItem(at: url, to: quarantine)
            if let recovered {
                StorageDiagnostics.report(filename: filename,
                                          message: "The file was damaged; the previous copy was restored.",
                                          recovered: true)
                return recovered
            }
            StorageDiagnostics.report(filename: filename,
                                      message: "The file was damaged and could not be read. A copy was kept.")
            return defaultValue
        }

        // No main file: a first launch, or one lost between writes. The backup
        // is the only other place the data could be.
        if let data = try? Data(contentsOf: backupURL),
           let value = try? JSONDecoder().decode(Value.self, from: data) {
            StorageDiagnostics.report(filename: filename,
                                      message: "The file was missing; the previous copy was restored.",
                                      recovered: true)
            return value
        }
        return defaultValue
    }

    // MARK: - Write

    /// Saves, keeping the previous good copy as `.bak`. Returns whether it
    /// worked; callers that don't check still get the failure recorded in
    /// `StorageDiagnostics`, because the failure mode this guards against is
    /// precisely the one nobody notices.
    @discardableResult
    func write(_ value: Value) -> Bool {
        let fm = FileManager.default
        guard let data = try? JSONEncoder().encode(value) else {
            StorageDiagnostics.report(filename: filename,
                                      message: "This data could not be encoded, so it was not saved.")
            return false
        }

        do {
            try data.write(to: url, options: .atomic)
            // The backup mirrors the value that just landed, so it is always a
            // copy of something known-good. Rolling the *previous file* in
            // instead was the obvious design and the wrong one: once the main
            // file went bad, every later write skipped the roll and the store
            // was left with no recoverable copy at all — the failure this
            // whole mechanism exists to prevent.
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: url, to: backupURL)
            return true
        } catch {
            // Full disk, protected-data window, sandbox trouble. This used to
            // be `try?` — the app would carry on with in-memory state and lose
            // it at quit, which is the shape of every "my library vanished"
            // review in the corpus.
            StorageDiagnostics.report(filename: filename,
                                      message: Self.describe(error))
            return false
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSFileWriteOutOfSpaceError:
            return String(localized: "There isn't enough space to save this. Free some up and try again.")
        case NSFileWriteVolumeReadOnlyError:
            return String(localized: "The storage is read-only, so this couldn't be saved.")
        case NSFileWriteFileExistsError, NSFileWriteNoPermissionError:
            return String(localized: "Sonava wasn't allowed to save this file.")
        default:
            return nsError.localizedDescription
        }
    }
}
