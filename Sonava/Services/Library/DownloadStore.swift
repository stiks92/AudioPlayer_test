//
//  DownloadStore.swift
//  Sonava
//
//  Offline downloads — a Sonava Pro feature. Saves full-length, rights-clean
//  tracks (Audius CC, the user's own server) to disk so they play with no
//  network. 30-second previews and live radio are never downloadable.
//
//  Downloaded audio lives in Documents/Downloads and is resolved ahead of the
//  stream URL at playback, so a saved track also runs through the local
//  AVAudioEngine graph — and therefore gets the equalizer too.
//
//  ## Why a background session
//
//  This used to be `URLSession.shared.download(from:)` inside a `Task`. That
//  works for exactly as long as the app stays in the foreground: lock the
//  phone or switch apps mid-album and iOS suspends the process, the transfer
//  dies, and the bytes already fetched are thrown away. Which is to say the
//  feature failed in its own headline scenario — "put a few albums on before
//  a flight" — and failed silently, leaving a row stuck at 40%.
//
//  A background `URLSession` hands the transfer to the system: it continues
//  while the app is suspended, survives the app being killed, and relaunches
//  the app to finish up. Failures now carry resume data, so a dropped
//  connection costs the last few seconds rather than the whole file.
//
//  The delegate is a separate non-isolated object because iOS calls it on its
//  own queue; it hops to the main actor to publish. `pending` is persisted so
//  that after a relaunch the store can still say which song a system task
//  belongs to — the in-memory map is gone by then.
//

import Foundation
import Combine

@MainActor
final class DownloadStore: ObservableObject {

    /// Progress/state per track id, so rows can show a spinner or a check.
    enum DownloadState: Equatable {
        case none
        case downloading(Double)   // 0...1
        case downloaded
        case failed
    }

    /// The saved tracks, newest first — the "Downloaded" library section.
    @Published private(set) var downloads: [Song] = []
    @Published private(set) var states: [String: DownloadState] = [:]

    private let index = JSONFileStore<[Song]>("downloads.json", default: [])
    /// Transfers the system is carrying for us, so a relaunch can match a
    /// finished task back to its track.
    private let pendingStore = JSONFileStore<[Song]>("downloads_pending.json", default: [])
    private var pending: [String: Song] = [:]

    static let sessionIdentifier = "com.sonava.downloads"

    /// Set by the app delegate when iOS wakes us to finish background work;
    /// called once the session says it has delivered everything.
    var backgroundCompletionHandler: (() -> Void)?

    private var delegate: DownloadSessionDelegate!
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        // The listener asked for these files; they should not wait for a
        // charger and good Wi-Fi the way a discretionary transfer may.
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()

    nonisolated static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = documents.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `useBackgroundSession: false` keeps tests and previews off the system
    /// transfer daemon, which refuses to run against a test bundle.
    init(useBackgroundSession: Bool = true) {
        // Keep only entries whose file is still present.
        downloads = index.read().filter { song in
            FileManager.default.fileExists(atPath: Self.fileURL(for: song).path)
        }
        for song in downloads { states[song.id] = .downloaded }
        index.write(downloads)

        // Transfers the system may still be carrying. They start as *failed*,
        // not "downloading": a pending entry left by a process the system
        // killed has no task behind it, and marking it in-flight left the row
        // spinning forever and — worse — made `download` refuse to retry it,
        // because a track already downloading is not downloaded again. The
        // reconciliation below promotes back the ones that really are live.
        pending = Dictionary(uniqueKeysWithValues: pendingStore.read().map { ($0.id, $0) })
        for song in pending.values where states[song.id] == nil {
            states[song.id] = .failed
        }

        guard useBackgroundSession else { return }
        delegate = DownloadSessionDelegate(
            progress: { [weak self] id, fraction in
                Task { @MainActor in self?.report(id: id, fraction: fraction) }
            },
            finished: { [weak self] id, location in
                // The file must be moved *here*, synchronously on the
                // delegate's queue — iOS deletes it the moment this callback
                // returns. So the delegate stages it and we finish the
                // bookkeeping on the main actor.
                Task { @MainActor in self?.complete(id: id, staged: location) }
            },
            failed: { [weak self] id, resumeData in
                Task { @MainActor in self?.fail(id: id, resumeData: resumeData) }
            },
            finishedEvents: { [weak self] in
                Task { @MainActor in
                    self?.backgroundCompletionHandler?()
                    self?.backgroundCompletionHandler = nil
                }
            })
        // Touching `session` re-attaches to transfers already in flight from a
        // previous launch, which is what makes "download, quit, come back"
        // work at all.
        session.getAllTasks { [weak self] tasks in
            let live = tasks.compactMap(\.taskDescription)
            Task { @MainActor in self?.reconcile(live: Set(live)) }
        }
    }

    /// Marks the transfers the system confirms it is still carrying. Anything
    /// pending that it does not know about stays failed, which is both true
    /// and retryable.
    private func reconcile(live: Set<String>) {
        for id in live where states[id] != .downloaded {
            states[id] = .downloading(0)
        }
    }

    // MARK: - Queries

    /// The ids the listener chose to keep offline. A backup carries these
    /// rather than the audio: the files are re-fetchable, the *choice* is not.
    var downloadedIDs: [String] { downloads.map(\.id) }

    func isDownloaded(_ song: Song) -> Bool {
        states[song.id] == .downloaded
    }

    func state(for song: Song) -> DownloadState {
        states[song.id] ?? .none
    }

    /// A local file URL for a saved track, or nil — playback prefers this over
    /// the stream so downloaded tracks work offline.
    func localURL(for song: Song) -> URL? {
        guard isDownloaded(song) else { return nil }
        let url = Self.fileURL(for: song)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Download / remove

    /// Downloads a track. Silently ignores anything not downloadable or already
    /// saved. `isPro` gating happens at the call site.
    func download(_ song: Song) {
        guard song.isDownloadable, let source = song.streamURL else { return }
        guard state(for: song) == .none || state(for: song) == .failed else { return }

        states[song.id] = .downloading(0)
        pending[song.id] = song
        persistPending()

        // A background session speaks HTTP and nothing else. A `file://`
        // source — a fixture in a test, or a server exposed over a local file
        // share — has to go the direct route, and there is nothing to gain by
        // deferring it anyway: it is a copy, not a transfer.
        guard delegate != nil, source.scheme?.hasPrefix("http") == true else {
            directTasks[song.id] = Task { await copyDirectly(song, from: source) }
            return
        }

        let task: URLSessionDownloadTask
        if let resume = Self.resumeData(for: song.id) {
            // Pick up where the last attempt stopped rather than re-fetching a
            // 60 MB FLAC because a lift lost signal.
            task = session.downloadTask(withResumeData: resume)
            Self.clearResumeData(for: song.id)
        } else {
            task = session.downloadTask(with: source)
        }
        task.taskDescription = song.id
        task.resume()
    }

    /// The non-HTTP path: fetch it here and hand the result to the same
    /// bookkeeping the background session uses, so both routes end identically.
    private var directTasks: [String: Task<Void, Never>] = [:]

    private func copyDirectly(_ song: Song, from source: URL) async {
        defer { directTasks[song.id] = nil }
        do {
            let (temp, response) = try await URLSession.shared.download(from: source)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let staged = temp.deletingLastPathComponent()
                .appendingPathComponent("sonava-staged-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: temp, to: staged)
            complete(id: song.id, staged: staged)
        } catch is CancellationError {
            states[song.id] = nil
        } catch {
            fail(id: song.id, resumeData: nil)
        }
    }

    func remove(_ song: Song) {
        cancelTask(for: song.id)
        pending[song.id] = nil
        persistPending()
        Self.clearResumeData(for: song.id)
        try? FileManager.default.removeItem(at: Self.fileURL(for: song))
        downloads.removeAll { $0.id == song.id }
        states[song.id] = nil
        index.write(downloads)
    }

    func removeAll() {
        for song in downloads { remove(song) }
    }

    private func cancelTask(for id: String) {
        directTasks[id]?.cancel()
        directTasks[id] = nil
        guard delegate != nil else { return }
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription == id { task.cancel() }
        }
    }

    // MARK: - Delegate callbacks

    private func report(id: String, fraction: Double) {
        guard states[id] != .downloaded else { return }
        states[id] = .downloading(min(max(fraction, 0), 1))
    }

    private func complete(id: String, staged: URL) {
        guard let song = pending[id] ?? downloads.first(where: { $0.id == id }) else {
            try? FileManager.default.removeItem(at: staged)
            return
        }
        let destination = Self.fileURL(for: song)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: staged, to: destination)
        } catch {
            states[id] = .failed
            StorageDiagnostics.report(filename: destination.lastPathComponent,
                                      message: (error as NSError).localizedDescription)
            return
        }

        states[id] = .downloaded
        // A downloaded track should have downloaded lyrics: warm the cache
        // now, while there is still a network to warm it from.
        Task { [song] in
            await LyricsService.shared.prefetch(
                artist: song.artist, title: song.title,
                album: song.album, duration: song.durationSeconds)
        }
        if !downloads.contains(where: { $0.id == id }) {
            downloads.insert(song, at: 0)
        }
        index.write(downloads)
        pending[id] = nil
        persistPending()
        Haptics.success()
    }

    private func fail(id: String, resumeData: Data?) {
        if let resumeData { Self.saveResumeData(resumeData, for: id) }
        // A cancelled transfer has already had its state cleared by `remove`.
        guard pending[id] != nil else { return }
        states[id] = .failed
    }

    private func persistPending() {
        pendingStore.write(Array(pending.values))
    }

    // MARK: - Paths

    /// Deterministic filename from the track id, so it round-trips across
    /// launches. The id can contain "/" (e.g. a URL-ish id), so hash it.
    private nonisolated static func fileURL(for song: Song) -> URL {
        URL(fileURLWithPath: directory.path)
            .appendingPathComponent("\(safeName(song.id)).\(song.fileExtension.isEmpty ? "mp3" : song.fileExtension)")
    }

    private nonisolated static func safeName(_ id: String) -> String {
        String(id.unicodeScalars.map {
            $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0)))
                ? Character($0) : "_"
        })
    }

    // MARK: - Resume data

    private nonisolated static var resumeDirectory: URL {
        let dir = directory.appendingPathComponent("resume", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private nonisolated static func resumeURL(for id: String) -> URL {
        resumeDirectory.appendingPathComponent("\(safeName(id)).resume")
    }

    private nonisolated static func saveResumeData(_ data: Data, for id: String) {
        try? data.write(to: resumeURL(for: id), options: .atomic)
    }

    private nonisolated static func resumeData(for id: String) -> Data? {
        try? Data(contentsOf: resumeURL(for: id))
    }

    private nonisolated static func clearResumeData(for id: String) {
        try? FileManager.default.removeItem(at: resumeURL(for: id))
    }
}

// MARK: - Session delegate

/// iOS calls these on its own queue, and after a relaunch it calls them on an
/// object the app has only just created — so this holds no state beyond the
/// closures it forwards through.
private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private let progress: @Sendable (String, Double) -> Void
    private let finished: @Sendable (String, URL) -> Void
    private let failed: @Sendable (String, Data?) -> Void
    private let finishedEvents: @Sendable () -> Void

    init(progress: @escaping @Sendable (String, Double) -> Void,
         finished: @escaping @Sendable (String, URL) -> Void,
         failed: @escaping @Sendable (String, Data?) -> Void,
         finishedEvents: @escaping @Sendable () -> Void) {
        self.progress = progress
        self.finished = finished
        self.failed = failed
        self.finishedEvents = finishedEvents
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        progress(id, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            failed(id, nil)
            return
        }
        // The system deletes `location` as soon as this returns, so the bytes
        // are moved somewhere of our own *synchronously*, and the main actor
        // does the bookkeeping afterwards.
        let staged = location.deletingLastPathComponent()
            .appendingPathComponent("sonava-staged-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: staged)
            finished(id, staged)
        } catch {
            failed(id, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let error else { return }
        let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        failed(id, resume)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        finishedEvents()
    }
}
