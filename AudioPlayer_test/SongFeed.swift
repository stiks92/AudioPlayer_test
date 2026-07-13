//
//  SongFeed.swift
//  AudioPlayer_test
//
//  A tiny reusable loader for asynchronous lists of songs (trending,
//  radio stations, online search …) with clean loading / empty / error
//  states and cancellation handling.
//

import SwiftUI

@MainActor
final class SongFeed: ObservableObject {
    enum State: Equatable {
        case idle, loading, loaded, empty, failed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var songs: [Song] = []

    func load(_ fetch: @escaping () async throws -> [Song]) async {
        state = .loading
        do {
            let result = try await fetch()
            if Task.isCancelled { return }
            songs = result
            state = result.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            // superseded by a newer request
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            if Task.isCancelled { return }
            state = .failed
        }
    }

    func clear() {
        songs = []
        state = .idle
    }
}
