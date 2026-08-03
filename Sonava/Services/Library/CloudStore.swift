//
//  CloudStore.swift
//  Sonava
//
//  The listener's cloud drives, remembered.
//
//  Modelled on `ServerStore` deliberately — same rules, same shape: the
//  non-secret part lives in a JSON file, the password lives in the Keychain
//  under the drive's id, and a lapsed subscription never deletes anything.
//  One drive is free; more is a Pro perk, the same line the servers draw.
//

import SwiftUI
import Combine

struct CloudDrive: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var label: String
    var provider: WebDAVService.Provider
    /// For `.other`; the known providers carry their own address.
    var urlString: String
    var username: String
    /// Where the listener keeps music, so the browser doesn't open on a drive
    /// root full of documents and photos.
    var rootPath: String

    var url: URL? {
        provider.baseURL ?? URL(string: urlString)
    }

    var displayName: String {
        label.isEmpty ? (url?.host ?? urlString) : label
    }
}

@MainActor
final class CloudStore: ObservableObject {

    @Published private(set) var drives: [CloudDrive] = []
    @Published var lastError: String?
    @Published var isConnecting = false

    /// Mirrors the subscription, like `ServerStore.isPro`.
    @Published var isPro = false

    static let freeLimit = 1

    private let store: JSONFileStore<[CloudDrive]>

    init(store: JSONFileStore<[CloudDrive]> = JSONFileStore("clouds.json", default: [])) {
        self.store = store
        drives = store.read()
    }

    var usableDrives: [CloudDrive] {
        isPro ? drives : Array(drives.prefix(Self.freeLimit))
    }

    var canAddDrive: Bool { isPro || drives.count < Self.freeLimit }

    func service(for drive: CloudDrive) -> WebDAVService? {
        guard let url = drive.url,
              let password = Keychain.get(Self.passwordKey(drive.id))
        else { return nil }
        return WebDAVService(baseURL: url, username: drive.username, password: password)
    }

    // MARK: - Add / remove

    /// Validates the credentials against the drive before saving them —
    /// storing a login that doesn't work just moves the failure to the moment
    /// the listener taps a folder.
    func add(provider: WebDAVService.Provider, urlString: String,
             username: String, password: String,
             label: String = "", rootPath: String = "/") async -> Bool {
        lastError = nil
        guard canAddDrive else {
            lastError = String(localized: "Connecting more than one drive needs Sonava Pro.")
            return false
        }

        var normalized = urlString.trimmingCharacters(in: .whitespaces)
        if provider == .other, !normalized.isEmpty, !normalized.contains("://") {
            normalized = "https://" + normalized
        }
        guard let url = provider.baseURL ?? URL(string: normalized), url.host != nil else {
            lastError = String(localized: "Invalid drive address.")
            return false
        }

        isConnecting = true
        defer { isConnecting = false }

        let candidate = WebDAVService(baseURL: url, username: username, password: password)
        switch await candidate.validate() {
        case .failure(let error):
            lastError = error.message
            return false
        case .success:
            break
        }

        let id = UUID().uuidString
        Keychain.set(password, for: Self.passwordKey(id))
        drives.append(CloudDrive(id: id, label: label, provider: provider,
                                 urlString: normalized, username: username,
                                 rootPath: rootPath.isEmpty ? "/" : rootPath))
        store.write(drives)
        Haptics.success()
        return true
    }

    func remove(_ drive: CloudDrive) {
        Keychain.delete(Self.passwordKey(drive.id))
        drives.removeAll { $0.id == drive.id }
        store.write(drives)
    }

    /// Remembers where in the drive the music lives, so the next visit opens
    /// there instead of at the root.
    func setRoot(_ path: String, for drive: CloudDrive) {
        guard let index = drives.firstIndex(where: { $0.id == drive.id }) else { return }
        drives[index].rootPath = path
        store.write(drives)
    }

    private static func passwordKey(_ id: String) -> String { "cloud.password.\(id)" }
}
