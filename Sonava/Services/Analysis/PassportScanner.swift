//
//  PassportScanner.swift
//  Sonava
//
//  Walks the library's files and fills in missing passports, one at a
//  time, at background priority. The Backroom principle: the shop front
//  never waits on the back room — analysis is something the phone does
//  while nobody is looking, and every screen simply reads whatever
//  passports exist right now.
//

import Foundation

@MainActor
final class PassportScanner: ObservableObject {

    static let shared = PassportScanner()

    /// Bumped after every saved passport so views re-read the store.
    @Published private(set) var revision = 0
    @Published private(set) var scannedCount = 0
    @Published private(set) var pendingCount = 0

    private let store: PassportStore
    private var queue: [(id: String, url: URL)] = []
    private var isRunning = false

    init(store: PassportStore = .shared) {
        self.store = store
    }

    /// Queues every file-backed song that has no passport yet. Safe to call
    /// repeatedly — already-queued and already-analysed tracks are skipped.
    func ensureScanned(_ songs: [Song], localURL: (Song) -> URL?) {
        var added = false
        for song in songs {
            guard let url = localURL(song), url.isFileURL else { continue }
            guard !queue.contains(where: { $0.id == song.id }),
                  !store.hasPassport(for: song.id) else { continue }
            queue.append((song.id, url))
            added = true
        }
        pendingCount = queue.count
        if added { run() }
    }

    private func run() {
        guard !isRunning, !queue.isEmpty else { return }
        isRunning = true
        let store = self.store
        let next = queue.removeFirst()
        pendingCount = queue.count

        Task.detached(priority: .utility) {
            let passport = PassportAnalyzer.analyze(url: next.url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let passport {
                    store.save(passport, for: next.id)
                    self.scannedCount += 1
                    self.revision += 1
                }
                self.isRunning = false
                self.run()   // next in queue, still one at a time
            }
        }
    }
}
