//
//  ScrobbleStore.swift
//  Sonava
//
//  Owns the ListenBrainz connection: the token (in the Keychain), the on/off
//  state, and the submission of "now playing" and completed listens. A dropped
//  scrobble is never allowed to affect playback.
//
//  ## Why there is a queue
//
//  Submission used to be fire-and-forget: a listen on the underground, on a
//  plane, or during any of the minutes a phone spends with no usable network
//  simply evaporated. For a feature whose entire promise is "your listening
//  history is complete", silently dropping the listens that happen away from
//  Wi-Fi is the failure that matters most — and it is invisible, which is
//  worse. Failed listens now wait on disk and are flushed on the next
//  success, on connect, and when the app returns to the foreground.
//
//  "Now playing" is never queued: it is a statement about this second, and a
//  late one is a lie about what is playing.
//

import Foundation
import Combine
import UIKit

@MainActor
final class ScrobbleStore: ObservableObject {

    @Published private(set) var isConnected = false
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }
    @Published var lastError: String?
    @Published private(set) var isConnecting = false
    /// How many listens are waiting for a network. Shown in Settings so the
    /// backlog is a fact the listener can see rather than a silent loss.
    @Published private(set) var pendingCount = 0

    private let service = ScrobbleService()
    private let tokenKey = "listenbrainz.token.v1"
    private let enabledKey = "listenbrainz.enabled.v1"

    // MARK: - Pending listens

    /// A listen waiting for a network. Stores the identity ListenBrainz needs
    /// rather than the whole `Song`: the payload must survive a track whose
    /// stream URL has since rotted, and it must never persist credentials.
    struct PendingListen: Codable, Equatable, Sendable {
        let title: String
        let artist: String
        let album: String
        let source: String
        let listenedAt: Date
    }

    private let queueStore = JSONFileStore<[PendingListen]>("scrobble_queue.json", default: [])
    private var pending: [PendingListen] = [] {
        didSet { pendingCount = pending.count }
    }
    /// Bounded so a long offline stretch cannot grow the file without limit;
    /// the oldest go first, because a listen from last month is the least
    /// useful thing in the queue.
    private static let queueLimit = 500
    private var isFlushing = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        isEnabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        isConnected = Keychain.get(tokenKey) != nil
        pending = queueStore.read()
        pendingCount = pending.count

        // Coming back to the foreground is the moment a phone most often has
        // network again after a stretch without one.
        NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.flush() }
            .store(in: &cancellables)
    }

    private var token: String? { Keychain.get(tokenKey) }

    /// Should we be scrobbling right now?
    var isActive: Bool { isConnected && isEnabled }

    // MARK: - Connect

    /// Validates the token against ListenBrainz and, on success, stores it.
    func connect(token rawToken: String) async -> Bool {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return false }
        isConnecting = true
        defer { isConnecting = false }

        guard await service.validate(token: token) else {
            lastError = String(localized: "That token wasn't accepted. Check it and try again.")
            return false
        }
        Keychain.set(token, for: tokenKey)
        isConnected = true
        lastError = nil
        // Whatever piled up before the account existed — or while the token
        // was wrong — goes out now.
        flush()
        return true
    }

    func disconnect() {
        Keychain.delete(tokenKey)
        isConnected = false
    }

    // MARK: - Submit

    func scrobbleNowPlaying(_ song: Song) {
        guard isActive, let token, ScrobbleService.isScrobblable(song) else { return }
        Task { _ = await service.submit(listenType: .playingNow, song: song, token: token) }
    }

    /// A track finished (or was played enough to count). Submitted with the
    /// time it actually happened — which is what ListenBrainz records, and why
    /// a listen queued today still lands on the right day when it finally
    /// goes out.
    func scrobbleListen(_ song: Song, at date: Date = Date()) {
        guard isActive, let token, ScrobbleService.isScrobblable(song) else { return }
        let service = self.service
        Task { [weak self] in
            let ok = await service.submit(listenType: .single, song: song,
                                          token: token, listenedAt: date)
            guard let self else { return }
            if ok {
                // A success means the network is back: drain anything waiting.
                self.flush()
            } else {
                self.enqueue(PendingListen(title: song.title, artist: song.artist,
                                           album: song.album, source: song.source.rawValue,
                                           listenedAt: date))
            }
        }
    }

    // MARK: - Queue

    private func enqueue(_ listen: PendingListen) {
        pending.append(listen)
        if pending.count > Self.queueLimit {
            pending.removeFirst(pending.count - Self.queueLimit)
        }
        queueStore.write(pending)
    }

    /// Sends everything waiting, oldest first, and stops at the first failure
    /// so a dead network costs one request rather than the whole backlog.
    func flush() {
        guard isActive, let token, !isFlushing, !pending.isEmpty else { return }
        isFlushing = true
        Task { [weak self] in
            defer { self?.isFlushing = false }
            while true {
                guard let self, let next = self.pending.first else { return }
                // The source travels because `isScrobblable` is decided by it
                // — a queued listen must pass the same gate it passed live.
                let song = Song(id: "queued:\(next.listenedAt.timeIntervalSince1970)",
                                title: next.title, artist: next.artist, album: next.album,
                                source: TrackSource(rawValue: next.source) ?? .local,
                                gradientHex: Palette.hex(forSeed: next.title))
                let ok = await self.service.submit(listenType: .single, song: song,
                                                   token: token, listenedAt: next.listenedAt)
                guard ok else { return }
                self.pending.removeFirst()
                self.queueStore.write(self.pending)
            }
        }
    }
}
