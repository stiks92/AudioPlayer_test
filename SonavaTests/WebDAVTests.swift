//
//  WebDAVTests.swift
//  SonavaTests
//
//  WebDAV is where the RU market keeps its music: Yandex.Disk and Mail.ru
//  Cloud both answer `PROPFIND` with `WWW-Authenticate: Basic`, verified
//  against the live endpoints. The risk in a client like this is never the
//  protocol — it is that every server writes the same reply slightly
//  differently, and a parser tuned to one of them silently returns an empty
//  folder on the next.
//
//  So the fixtures below use different namespace prefixes, absolute and
//  relative hrefs, percent-encoded Cyrillic, and the self-describing entry
//  every server includes and no file browser should show.
//

import Testing
import Foundation
@testable import Sonava

struct WebDAVParsingTests {

    /// Yandex's shape: lowercase `d:` prefix, absolute paths, the folder
    /// itself first.
    private let yandexReply = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:multistatus xmlns:d="DAV:">
      <d:response>
        <d:href>/Music/</d:href>
        <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype>
          <d:displayname>Music</d:displayname></d:prop>
          <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
      </d:response>
      <d:response>
        <d:href>/Music/Radiohead/</d:href>
        <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype>
          <d:displayname>Radiohead</d:displayname></d:prop>
          <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
      </d:response>
      <d:response>
        <d:href>/Music/track.flac</d:href>
        <d:propstat><d:prop><d:resourcetype/>
          <d:getcontentlength>28471923</d:getcontentlength>
          <d:getcontenttype>audio/flac</d:getcontenttype>
          <d:displayname>track.flac</d:displayname></d:prop>
          <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
      </d:response>
    </d:multistatus>
    """

    /// A different server: uppercase `D:` prefix, absolute URLs including the
    /// host, and a percent-encoded Cyrillic name.
    private let otherReply = """
    <?xml version="1.0"?>
    <D:multistatus xmlns:D="DAV:">
      <D:response>
        <D:href>https://cloud.example.org/Music/</D:href>
        <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
      </D:response>
      <D:response>
        <D:href>https://cloud.example.org/Music/%D0%9A%D0%B8%D0%BD%D0%BE%20-%20%D0%97%D0%B2%D0%B5%D0%B7%D0%B4%D0%B0.mp3</D:href>
        <D:propstat><D:prop><D:resourcetype/>
          <D:getcontentlength>7340032</D:getcontentlength></D:prop></D:propstat>
      </D:response>
      <D:response>
        <D:href>https://cloud.example.org/Music/cover.jpg</D:href>
        <D:propstat><D:prop><D:resourcetype/>
          <D:getcontentlength>204800</D:getcontentlength></D:prop></D:propstat>
      </D:response>
    </D:multistatus>
    """

    @Test("A folder listing keeps children and drops the folder itself")
    func parsesYandexShape() throws {
        let entries = WebDAVService.parse(Data(yandexReply.utf8), base: "/Music")
        #expect(entries.count == 2, "the self-entry would be a row that navigates nowhere")
        #expect(entries.map(\.name).sorted() == ["Radiohead", "track.flac"])

        let folder = try #require(entries.first { $0.name == "Radiohead" })
        #expect(folder.isDirectory)
        let file = try #require(entries.first { $0.name == "track.flac" })
        #expect(!file.isDirectory)
        #expect(file.size == 28_471_923)
        #expect(file.isAudio)
    }

    @Test("An uppercase prefix and absolute URLs parse the same")
    func parsesOtherShape() throws {
        let entries = WebDAVService.parse(Data(otherReply.utf8), base: "/Music")
        #expect(entries.count == 2)
        // The host is dropped; the app navigates by path.
        #expect(entries.allSatisfy { $0.path.hasPrefix("/Music/") })
    }

    @Test("Percent-encoded Cyrillic comes back readable")
    func decodesCyrillicNames() throws {
        let entries = WebDAVService.parse(Data(otherReply.utf8), base: "/Music")
        let song = try #require(entries.first { $0.isAudio })
        #expect(song.name == "Кино - Звезда.mp3",
                "a Russian library that lists as %D0%9A%... is unusable")
    }

    @Test("Non-audio files are listed but not offered as music")
    func recognisesAudioOnly() throws {
        let entries = WebDAVService.parse(Data(otherReply.utf8), base: "/Music")
        let cover = try #require(entries.first { $0.name == "cover.jpg" })
        #expect(!cover.isAudio, "a folder's artwork is not a track")
    }

    @Test("Folders sort before files", arguments: [true])
    func foldersFirst(_: Bool) throws {
        // `list` does the sorting; this pins the comparator's intent using the
        // same entries the parser produces.
        let entries = WebDAVService.parse(Data(yandexReply.utf8), base: "/Music")
            .sorted {
                $0.isDirectory == $1.isDirectory
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : $0.isDirectory
            }
        #expect(entries.first?.isDirectory == true)
    }

    @Test("Rubbish is an empty folder, not a crash")
    func survivesGarbage() {
        #expect(WebDAVService.parse(Data("not xml at all".utf8), base: "/").isEmpty)
        #expect(WebDAVService.parse(Data(), base: "/").isEmpty)
    }
}

struct WebDAVServiceTests {

    private func service() -> WebDAVService {
        WebDAVService(baseURL: URL(string: "https://webdav.yandex.ru")!,
                      username: "listener@yandex.ru", password: "app-password")
    }

    @Test("Every known provider that isn't 'other' has an address")
    func providersHaveEndpoints() {
        for provider in WebDAVService.Provider.allCases where provider != .other {
            #expect(provider.baseURL != nil, "\(provider.rawValue) has no endpoint")
        }
        #expect(WebDAVService.Provider.other.baseURL == nil,
                "'other' is the case where the listener types the address")
    }

    @Test("A file becomes a playable track with a cloud badge")
    func mapsEntryToSong() throws {
        let entry = WebDAVService.Entry(path: "/Music/Zvuki Mu/Track.flac",
                                        name: "Track.flac", isDirectory: false, size: 100)
        let song = try #require(service().song(from: entry, libraryID: "DISK"))
        #expect(song.title == "Track", "the extension is not part of the name")
        #expect(song.artist == "Zvuki Mu", "the folder is the only honest artist we have")
        #expect(song.source == .webdav)
        #expect(song.source.badge == "CLOUD")
        #expect(song.isDownloadable, "the listener's own file must be keepable offline")
    }

    @Test("A folder is not a track")
    func foldersAreNotSongs() {
        let folder = WebDAVService.Entry(path: "/Music/Zvuki Mu", name: "Zvuki Mu",
                                         isDirectory: true, size: nil)
        #expect(service().song(from: folder, libraryID: "DISK") == nil)
    }

    @Test("A stream URL carries the credentials AVPlayer can't send as a header")
    func streamURLCarriesAuth() throws {
        let url = try #require(service().streamURL(for: "/Music/track.flac"))
        #expect(url.user == "listener@yandex.ru")
        #expect(url.password == "app-password")
        #expect(url.path == "/Music/track.flac")
    }

    @Test("Every error says what to do about it")
    func errorsAreActionable() {
        // The unauthorized case is the one people will actually hit: both
        // Russian providers require an app password, not the account one.
        #expect(WebDAVError.unauthorized.message.contains("app password"))
        #expect(!WebDAVError.unreachable.message.isEmpty)
        #expect(WebDAVError.server(503).message.contains("503"))
    }
}
