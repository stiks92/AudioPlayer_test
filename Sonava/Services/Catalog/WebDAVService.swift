//
//  WebDAVService.swift
//  Sonava
//
//  Music kept in a cloud drive — the RU market's own answer to "where does my
//  library live".
//
//  Two thousand three hundred Russian-language reviews of file players name
//  the same handful of wants, and cloud storage is one of them: "А где мэйл
//  облако!!!??? У меня там музыка(". Yandex.Disk and Mail.ru Cloud are where
//  a great many Russian listeners actually keep their files, and both — like
//  Nextcloud, ownCloud and every NAS — speak WebDAV.
//
//  Verified live before a line was written: `PROPFIND` against
//  webdav.yandex.ru and webdav.cloud.mail.ru both answer `401` with
//  `WWW-Authenticate: Basic`. One client, Basic auth, three ecosystems.
//
//  ## What this is not
//
//  It is not a sync engine and does not copy anyone's drive onto the phone.
//  It lists folders, and it hands back stream URLs the player can open —
//  with the offline downloader already in place for anything the listener
//  wants to keep. The password lives in the Keychain, exactly like a Subsonic
//  server's, and never in a file (see `LibraryBackup` for why that rule is
//  now written down).
//

import Foundation
import SwiftUI

struct WebDAVService: Sendable {

    /// A known provider, so the listener types a login rather than a URL.
    /// "Other" exists because the whole point of WebDAV is that it isn't a
    /// list of blessed vendors.
    enum Provider: String, CaseIterable, Codable, Sendable {
        case yandex, mailru, other

        var title: LocalizedStringKey {
            switch self {
            case .yandex: return "Yandex.Disk"
            case .mailru: return "Mail.ru Cloud"
            case .other:  return "Other (WebDAV)"
            }
        }

        /// The endpoint, for providers whose address never changes.
        var baseURL: URL? {
            switch self {
            case .yandex: return URL(string: "https://webdav.yandex.ru")
            case .mailru: return URL(string: "https://webdav.cloud.mail.ru")
            case .other:  return nil
            }
        }

        /// What the listener has to know before typing anything.
        var hint: LocalizedStringKey {
            switch self {
            case .yandex:
                return "Use an app password from Yandex ID — not your account password."
            case .mailru:
                return "Use an app password from your Mail.ru account settings."
            case .other:
                return "The address of your Nextcloud, ownCloud or NAS, including https://."
            }
        }
    }

    let baseURL: URL
    let username: String
    let password: String

    // MARK: - Listing

    /// One entry in a folder. Deliberately thin: WebDAV replies carry a dozen
    /// properties this app has no use for.
    struct Entry: Identifiable, Equatable, Sendable {
        let path: String
        let name: String
        let isDirectory: Bool
        let size: Int64?
        var id: String { path }

        /// Whether this is something the player could open.
        var isAudio: Bool {
            guard !isDirectory else { return false }
            let ext = (name as NSString).pathExtension.lowercased()
            return ["mp3", "m4a", "aac", "flac", "wav", "aiff", "aif",
                    "alac", "ogg", "opus", "wma"].contains(ext)
        }
    }

    /// Lists one folder. `path` is relative to the account root.
    func list(path: String = "/") async throws -> [Entry] {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = "PROPFIND"
        // Depth 1: this folder's children, not the entire drive. Depth
        // infinity on a large account is how a client gets rate-limited.
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.httpBody = Data(Self.propfindBody.utf8)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw WebDAVError.unauthorized
        case 404: throw WebDAVError.notFound
        default: throw WebDAVError.server(http.statusCode)
        }

        let entries = Self.parse(data, base: path)
        // Folders first, then names — the order a person expects a file
        // browser to be in, which WebDAV itself makes no promise about.
        return entries.sorted {
            $0.isDirectory == $1.isDirectory
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.isDirectory
        }
    }

    /// Checks credentials by listing the root. Returns the plain truth: this
    /// is the call behind the "Connect" button.
    func validate() async -> Result<Void, WebDAVError> {
        do {
            _ = try await list(path: "/")
            return .success(())
        } catch let error as WebDAVError {
            return .failure(error)
        } catch {
            return .failure(.unreachable)
        }
    }

    // MARK: - Playback

    /// A playable URL for a file on the drive.
    ///
    /// Credentials go in the URL because `AVPlayer` will not carry a header
    /// for us. That is the same trade Subsonic streaming makes, and it is why
    /// `PlaylistSharing` strips both: a URL that authenticates is a URL that
    /// must never be shared.
    func streamURL(for path: String) -> URL? {
        guard var components = URLComponents(url: url(for: path), resolvingAgainstBaseURL: false)
        else { return nil }
        components.user = username
        components.password = password
        return components.url
    }

    /// Turns a file entry into something the player understands.
    func song(from entry: Entry, libraryID: String) -> Song? {
        guard entry.isAudio, let stream = streamURL(for: entry.path) else { return nil }
        let title = (entry.name as NSString).deletingPathExtension
        return Song(
            id: "webdav:\(libraryID):\(entry.path)",
            title: title,
            // The tags aren't read until it plays, so the folder is the only
            // honest thing to show — better than inventing "Unknown Artist"
            // for a file whose name says exactly who it is.
            artist: (entry.path as NSString).deletingLastPathComponent
                .components(separatedBy: "/").last ?? "",
            album: "",
            source: .webdav,
            fileExtension: (entry.name as NSString).pathExtension.lowercased(),
            streamURL: stream,
            gradientHex: Palette.hex(forSeed: entry.path))
    }

    // MARK: - Plumbing

    private var authorization: String {
        let raw = "\(username):\(password)"
        return "Basic \(Data(raw.utf8).base64EncodedString())"
    }

    private func url(for path: String) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !trimmed.isEmpty else { return baseURL }
        return baseURL.appendingPathComponent(trimmed)
    }

    /// Asking for only what is used. Some servers answer `allprop` with
    /// megabytes of properties per file.
    private static let propfindBody = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:">
      <d:prop>
        <d:displayname/>
        <d:resourcetype/>
        <d:getcontentlength/>
        <d:getcontenttype/>
      </d:prop>
    </d:propfind>
    """

    /// Parses a `multistatus` reply.
    ///
    /// Written by hand rather than with a dependency because the shape needed
    /// here is four fields, and because servers disagree about namespace
    /// prefixes (`d:`, `D:`, none) in ways a strict parser trips over.
    static func parse(_ data: Data, base: String) -> [Entry] {
        let parser = MultistatusParser(base: base)
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.shouldProcessNamespaces = true
        guard xml.parse() else { return [] }
        return parser.entries
    }
}

enum WebDAVError: Error, Equatable, Sendable {
    case unauthorized
    case notFound
    case unreachable
    case server(Int)

    var message: String {
        switch self {
        case .unauthorized:
            return String(localized: "Those credentials weren't accepted. Yandex and Mail.ru need an app password, not your account password.")
        case .notFound:
            return String(localized: "That folder isn't there.")
        case .unreachable:
            return String(localized: "Couldn't reach the drive. Check the address and your network.")
        case .server(let code):
            return String(localized: "The drive answered with an error (\(code)).")
        }
    }
}

// MARK: - XML

/// Collects `<response>` elements into entries.
private final class MultistatusParser: NSObject, XMLParserDelegate {
    private let base: String
    private(set) var entries: [Entry] = []

    typealias Entry = WebDAVService.Entry

    private var href = ""
    private var isCollection = false
    private var length: Int64?
    private var current = ""
    private var insideResponse = false

    init(base: String) {
        // Normalised so a reply's self-entry can be recognised whatever
        // trailing slash the server chose.
        self.base = base.hasSuffix("/") ? base : base + "/"
    }

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        current = ""
        switch element.lowercased() {
        case "response":
            insideResponse = true
            href = ""; isCollection = false; length = nil
        case "collection":
            isCollection = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        current += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
        switch element.lowercased() {
        case "href" where insideResponse && href.isEmpty:
            href = text.removingPercentEncoding ?? text
        case "getcontentlength":
            length = Int64(text)
        case "response":
            insideResponse = false
            appendEntry()
        default:
            break
        }
        current = ""
    }

    private func appendEntry() {
        guard !href.isEmpty else { return }
        // A server may return an absolute URL or a bare path.
        let path = URL(string: href)?.path ?? href
        let normalised = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        // The folder describes itself first; listing it inside itself would
        // give every screen a row that navigates nowhere.
        let selfPath = base.count > 1 ? String(base.dropLast()) : "/"
        guard normalised != selfPath, normalised != "/" else { return }

        let name = (normalised as NSString).lastPathComponent
        guard !name.isEmpty else { return }
        entries.append(Entry(path: normalised, name: name,
                             isDirectory: isCollection, size: length))
    }
}
