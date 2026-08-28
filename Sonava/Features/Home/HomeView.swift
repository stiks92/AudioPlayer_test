//
//  HomeView.swift
//  Sonava
//
//  The landing tab: greeting, recently played, featured playlists and
//  quick picks.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var proStore: ProStore
    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var journeyStore: JourneyStore
    @EnvironmentObject private var playlistStore: PlaylistStore
    @EnvironmentObject private var cloudStore: CloudStore
    @EnvironmentObject private var scrobble: ScrobbleStore
    @EnvironmentObject private var history: ListeningHistory

    @StateObject private var trending = SongFeed()
    @StateObject private var charts = SongFeed()
    @StateObject private var serverFeed = SongFeed()
    @StateObject private var madeForYou = SongFeed()
    private let mixStore = MondayMix.Store()
    @State private var editorial: [RemotePlaylist] = []
    @State private var tasteSeed: [String] = []
    @State private var showSettings = false
    @State private var showAIMix = false
    @State private var showShazam = false
    @State private var showStats = false
    @State private var showImportFiles = false
    @State private var showConnectServer = false
    @State private var showHistoryImport = false
    @StateObject private var radioRail = SongFeed()

    private var greeting: LocalizedStringKey {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Late night vibes"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    // The order is the argument.
                    //
                    // It used to run: greeting, AI Mix banner, stats card, two
                    // algorithmic shelves, a chart of 30-second previews, and
                    // *then*, at positions eight and ten, the listener's own
                    // server and their own imported files. An app for people
                    // who own their music put the music they own last. No
                    // amount of typography fixes that, and it is the single
                    // largest change here.
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        masthead
                        // Day zero is a different newspaper. A person with a
                        // library opens on their own time and their own
                        // files; a person without one used to open on «0 с»,
                        // «0 файлов» and a feature index — an empty shop
                        // with the lights off. Now the empty state leads
                        // with things that PLAY this minute (live radio,
                        // Audius trending) and one quiet card of beginnings.
                        if libraryIsEmpty {
                            startHereSection
                            radioNowSection
                            trendingSection
                            popularSection
                            indexSection
                        } else {
                            figure
                            yourFilesSection
                            serverSection
                            madeForYouSection
                            popularSection
                            trendingSection
                            indexSection
                        }
                    }
                    .padding(.horizontal, Space.screenMargin)
                    .padding(.top, 8)
                    .padding(.bottom, 140)
                }
            }
            .navigationBarHidden(true)
            .task {
                if libraryIsEmpty, radioRail.state == .idle {
                    await radioRail.load { try await RadioBrowserService.shared.trending() }
                }
                if charts.state == .idle {
                    await charts.load { try await DeezerService.shared.chartTracks() }
                }
                if editorial.isEmpty {
                    editorial = (try? await DeezerService.shared.chartPlaylists()) ?? []
                }
                if trending.state == .idle {
                    await trending.load { try await AudiusService.shared.trending() }
                }
                await loadServerIfNeeded()
                await loadMadeForYou()
            }
            .onChange(of: serverStore.isConnected) {
                Task { await loadServerIfNeeded(force: true) }
            }
            .onChange(of: library.favoriteSongs.count) {
                Task { await loadMadeForYou(force: true) }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(audio)
                    .environmentObject(proStore)
                    .environmentObject(serverStore)
                    .environmentObject(scrobble)
                    .environmentObject(library)
                    .environmentObject(playlistStore)
                    .environmentObject(journeyStore)
                    .environmentObject(cloudStore)
            }
            .fileImporter(isPresented: $showImportFiles,
                          allowedContentTypes: [.audio],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await library.importFiles(at: urls) }
                }
            }
            .sheet(isPresented: $showConnectServer) {
                ConnectServerView()
                    .environmentObject(serverStore)
                    .environmentObject(proStore)
            }
            .sheet(isPresented: $showHistoryImport) {
                ImportHistoryView()
                    .environmentObject(journeyStore)
                    .environmentObject(library)
            }
            .sheet(isPresented: $showAIMix) {
                AIMixView()
                    .environmentObject(audio)
                    .environmentObject(library)
                    .environmentObject(proStore)
            }
            .sheet(isPresented: $showShazam) {
                ShazamView().environmentObject(audio)
            }
            .sheet(isPresented: $showStats) {
                StatsView()
                    .environmentObject(history)
                    .environmentObject(proStore)
            }
        }
    }

    private func loadServerIfNeeded(force: Bool = false) async {
        guard serverStore.isConnected else {
            if serverFeed.state != .idle { serverFeed.clear() }
            return
        }
        if force || serverFeed.state == .idle {
            await serverFeed.load { try await serverStore.randomSongs() }
        }
    }

    // MARK: - From your server

    // MARK: - Made for you (taste-based)

    /// Loads the week's pinned mix, building it only when the week rolled or
    /// the taste changed. It used to refetch on every cold launch — a shelf
    /// that was different at breakfast and at lunch, which is a feed, not a
    /// mix. Pinned for the week, it becomes something Monday delivers.
    private func loadMadeForYou(force: Bool = false) async {
        let profile = library.tasteProfile
        guard !profile.isEmpty else { madeForYou.clear(); return }
        let week = MondayMix.weekStamp()
        let seed = profile.seedQueries
        if !force, let pinned = mixStore.songs(week: week, seed: seed) {
            guard tasteSeed != seed || madeForYou.state != .loaded else { return }
            tasteSeed = seed
            await madeForYou.load { pinned }
            return
        }
        guard force || seed != tasteSeed || madeForYou.state != .loaded else { return }
        tasteSeed = seed
        let known = library.knownTrackIDs
        await madeForYou.load {
            Array(await StationService.recommendations(for: profile, excluding: known).prefix(20))
        }
        if case .loaded = madeForYou.state, !madeForYou.songs.isEmpty {
            mixStore.pin(madeForYou.songs, week: week, seed: seed)
        }
    }

    @ViewBuilder
    private var madeForYouSection: some View {
        if madeForYou.state == .loaded, !madeForYou.songs.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                Department(title: "Monday Mix",
                           fact: String(localized: "\(madeForYou.songs.count) tracks").uppercased())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: Space.m) {
                        ForEach(Array(madeForYou.songs.enumerated()), id: \.element.id) { index, song in
                            Button {
                                audio.play(song, in: madeForYou.songs)
                            } label: {
                                // The lead sleeve is 1.5x its followers, and the
                                // row is bottom-aligned so they share a
                                // baseline. A rail whose first item is larger
                                // cannot be mistaken for a stock carousel — and
                                // the old one had twenty identical tiles.
                                // Two tokens, not a token times a fudge. The
                                // followers were `Tile.standard * 0.84` —
                                // 117.6pt, a number that is in the design
                                // system only in the sense that it was derived
                                // from something that is.
                                let side: CGFloat = index == 0 ? Tile.feature : Tile.standard
                                VStack(alignment: .leading, spacing: Space.s) {
                                    ArtworkThumbnail(song: song, size: side,
                                                     cornerRadius: 2, showBadge: false)
                                    Text(song.title)
                                        .font(index == 0 ? .sonavaName : .sonavaByline)
                                        .foregroundColor(index == 0 ? Theme.textPrimary : Theme.textSecondary)
                                        .lineLimit(1)
                                        .frame(width: side, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .carouselBleed()
            }
        }
    }


    // MARK: - AI Mix banner

    private var aiMixCard: some View {
        Button {
            Haptics.impact()
            showAIMix = true
        } label: {
            HStack(spacing: Space.l) {
                SonavaIcon(glyph: .aiMix, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Create an AI Mix")
                        .font(.system(.body).weight(.bold))
                        .foregroundColor(.white)
                    Text("Describe a vibe — get an instant mix")
                        .font(.system(.caption))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                if !proStore.isPro {
                    Text("PRO")
                        .font(.system(.caption2).weight(.heavy))
                        .foregroundColor(Theme.background)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white))
                }
                SonavaIcon(glyph: .chevronRight, size: 15, tint: .white.opacity(0.8))
            }
            .padding(Space.l)
            // The gradient peaks magenta mid-card, which put this copy at
            // 1.9:1. `StatsShareCard` solves the identical problem on the
            // identical gradient with a scrim; same answer here.
            .background(Theme.proGradient.overlay(Color.black.opacity(0.40)))
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.98))
    }

    // MARK: - Editor's picks (curated playlists)

    @ViewBuilder
    private var editorialSection: some View {
        if !editorial.isEmpty {
            VStack(alignment: .leading, spacing: Space.l) {
                Department(title: "Editor's picks")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.l) {
                        ForEach(editorial) { playlist in
                            NavigationLink {
                                RemotePlaylistView(playlist: playlist)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    AsyncImage(url: playlist.artworkURL) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        ZStack {
                                            LinearGradient(colors: playlist.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                                            SonavaIcon(glyph: .note, size: 34, tint: .white.opacity(0.85))
                                        }
                                    }
                                    .frame(width: Tile.feature, height: Tile.feature)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                                    Text(playlist.title)
                                        .font(.system(.footnote).weight(.semibold))
                                        .foregroundColor(Theme.textPrimary)
                                        .lineLimit(1)
                                        .frame(width: Tile.feature, alignment: .leading)
                                }
                            }
                            .buttonStyle(BouncyButtonStyle(scale: 0.96))
                        }
                    }
                }
                .carouselBleed()
            }
        }
    }

    // MARK: - Popular now (Deezer charts)


    // MARK: - Trending on Audius (live)


    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.sonavaDisplay)
                    .foregroundColor(Theme.textPrimary)
                Text("What do you feel like hearing?")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button {
                Haptics.impact()
                showShazam = true
            } label: {
                // Both header buttons must be one species and one size. The
                // left one used to draw its circle *inside* the glyph
                // (`waveform.circle.fill`), which rendered 26.7pt against the
                // right one's 40 — a 33% break in a two-item cluster.
                headerButtonFace(.wave, tint: Theme.accentSoft)
            }
            .buttonStyle(BouncyButtonStyle())
            .hitTarget()
            .identified(AccessibilityID.shazamButton, label: "Discover")

            Button {
                showSettings = true
            } label: {
                // `sparkles` belongs to AI Mix; using it here too pointed one
                // glyph at two unrelated destinations in the same viewport.
                headerButtonFace(.person,
                                 tint: Theme.accentSoft)
            }
            .buttonStyle(BouncyButtonStyle())
            .hitTarget()
            .identified(AccessibilityID.settingsButton, label: "Settings")
        }
    }

    /// One shape, one size, for every control in the header.
    private func headerButtonFace(_ glyph: SonavaIcon.Glyph, tint: Color) -> some View {
        Circle()
            .fill(Theme.surfaceElevated)
            .frame(width: 40, height: 40)
            .overlay(SonavaIcon(glyph: glyph, size: 19, tint: tint))
            .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Your Sound

    /// Hidden until there is something to show — an empty stats card on a fresh
    /// install is noise, not a feature.
    @ViewBuilder
    private var statsCard: some View {
        if history.hasHistory {
            StatsTeaserCard(stats: history.stats(range: .week)) {
                Haptics.impact()
                showStats = true
            }
        }
    }

    // MARK: - Recently played

    private var recentlyPlayed: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Department(title: "Recently played")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.l) {
                    ForEach(library.recentSongs) { song in
                        Button {
                            audio.play(song, in: library.songs)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ArtworkThumbnail(song: song, size: Tile.standard, cornerRadius: Radius.card)
                                Text(song.title)
                                    .font(.system(.footnote).weight(.semibold))
                                    .foregroundColor(Theme.textPrimary)
                                    .lineLimit(1)
                                    .frame(width: Tile.standard, alignment: .leading)
                            }
                        }
                        .buttonStyle(BouncyButtonStyle(scale: 0.95))
                    }
                }
            }
            .carouselBleed()
        }
    }

    // MARK: - Quick picks

    private var quickPicks: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Department(title: "Quick picks")
            LazyVStack(spacing: 2) {
                ForEach(library.songs.prefix(8)) { song in
                    Button {
                        audio.play(song, in: library.songs)
                    } label: {
                        SongRow(song: song)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - The editorial Home

extension HomeView {

    /// The nameplate. A fixed word and a dateline that is never the same twice.
    ///
    /// Replaces "Good evening / What do you feel like hearing?" — 60pt of
    /// rounded display type saying nothing about the app. Hardware does not
    /// greet you, and neither does a record sleeve.
    var masthead: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(verbatim: "SONAVA")
                .font(.sonavaMasthead)
                .tracking(-1.6)
                .foregroundColor(Theme.textPrimary)
            // The only full-bleed rule in the app. It says "this is the top of
            // the page" once, and nothing else may claim it.
            Rectangle()
                .fill(Theme.textPrimary)
                .frame(height: Rule.masthead)
                .padding(.horizontal, -Space.screenMargin)
            HStack(alignment: .firstTextBaseline) {
                Text(Self.dateline.string(from: Date()).uppercased())
                Spacer(minLength: Space.m)
                Text(inventory)
            }
            .font(.sonavaStamp)
            .tracking(1.2)
            .foregroundColor(Theme.textTertiary)
            .lineLimit(1)
        }
    }

    static let dateline: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return formatter
    }()

    /// What this install actually holds. Every number measured, and a count of
    /// zero is still printed — an instrument with nothing to measure says so.
    var inventory: String {
        var parts: [String] = ["\(library.songs.count) \(String(localized: "FILES"))"]
        if serverStore.servers.count > 0 {
            parts.append("\(serverStore.servers.count) \(String(localized: "SERVERS"))")
        }
        return parts.joined(separator: " · ")
    }

    /// One hero figure per screen, and it is the listener's own time.
    ///
    /// This was a 90pt card containing 17pt text. The card was *containing* a
    /// small number; now the number is the thing, and the container is gone.
    @ViewBuilder
    var figure: some View {
        let stats = history.stats(range: .week)
        Button {
            showStats = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(ListeningStats.duration(stats.totalSeconds))
                    .font(.sonavaFigure)
                    .tracking(-1.2)
                    .foregroundColor(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(weekLine(stats))
                    .font(.sonavaStamp)
                    .tracking(1.2)
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        // The stats card is gone; the figure is the way in now, and it carries
        // the identifier the journey was always about.
        .identified(AccessibilityID.statsCard, label: "Your sound")
    }

    func weekLine(_ stats: ListeningStats) -> String {
        var parts = [String(localized: "THIS WEEK")]
        if stats.plays > 0 { parts.append(String(localized: "\(stats.plays) tracks").uppercased()) }
        if stats.artistCount > 0 { parts.append("\(stats.artistCount) \(String(localized: "ARTISTS"))") }
        if stats.streak > 0 { parts.append("\(String(localized: "DAY")) \(stats.streak)") }
        return parts.joined(separator: " · ")
    }

    /// The listener's own imported files — moved from position ten to position
    /// three, and given the artwork the charts no longer get.
    @ViewBuilder
    var yourFilesSection: some View {
        if !library.songs.isEmpty {
            let songs = Array(library.songs.prefix(4))
            VStack(alignment: .leading, spacing: Space.m) {
                Department(title: "Your files",
                           fact: "\(library.songs.count) \(String(localized: "IMPORTED"))")
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        audio.play(song, in: library.songs)
                    } label: {
                        OwnedRow(song: song, fact: song.fileExtension.uppercased())
                    }
                    .buttonStyle(.plain)
                    if index < songs.count - 1 { RowRule(inset: 56) }
                }
            }
        }
    }

    /// A ranked list, not a rail. The numerals are the point.
    @ViewBuilder
    func chart(_ title: LocalizedStringKey, fact: String, feed: SongFeed) -> some View {
        if feed.state == .loaded, !feed.songs.isEmpty {
            let songs = Array(feed.songs.prefix(5))
            VStack(alignment: .leading, spacing: Space.m) {
                Department(title: title, fact: fact)
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        audio.play(song, in: feed.songs)
                    } label: {
                        RankedRow(rank: index + 1, song: song)
                    }
                    .buttonStyle(.plain)
                    if index < songs.count - 1 { RowRule(inset: Rail.text) }
                }
            }
        }
    }

    var popularSection: some View {
        chart("Popular now", fact: "DEEZER · 30s", feed: charts)
    }

    /// The department label is the machine's own name, and the fact beside it
    /// is its measured state. No other music app would ever print a latency on
    /// its home screen, because no other music app's library lives in your
    /// house.
    @ViewBuilder
    var serverSection: some View {
        if serverStore.isConnected, serverFeed.state == .loaded, !serverFeed.songs.isEmpty {
            let songs = Array(serverFeed.songs.prefix(4))
            VStack(alignment: .leading, spacing: Space.m) {
                Department(title: LocalizedStringKey(serverStore.active?.host.uppercased() ?? "YOUR SERVER"),
                           fact: serverFact)
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        audio.play(song, in: serverFeed.songs)
                    } label: {
                        OwnedRow(song: song,
                                 fact: audio.downloads.isDownloaded(song) ? String(localized: "SAVED") : nil)
                    }
                    .buttonStyle(.plain)
                    if index < songs.count - 1 { RowRule(inset: 56) }
                }
            }
        }
    }

    var serverFact: String {
        guard let active = serverStore.active else { return "" }
        let health = serverStore.health(for: active)
        switch health.state {
        case .online:
            var parts = [String(localized: "ONLINE")]
            if let latency = health.latency { parts.append("\(Int((latency * 1000).rounded())) ms") }
            if let files = health.files { parts.append(files.formatted(.number)) }
            return parts.joined(separator: " · ")
        case .unreachable: return String(localized: "UNREACHABLE")
        case .checking:    return String(localized: "CHECKING")
        case .unknown:     return ""
        }
    }

    var trendingSection: some View {
        chart("Trending", fact: "AUDIUS", feed: trending)
    }

    // MARK: - Day zero

    private var libraryIsEmpty: Bool {
        library.songs.isEmpty && serverStore.servers.isEmpty
    }

    /// Three honest beginnings, set as index rows — not banners, not a
    /// wizard. Each one is the real door, not a tour of it.
    private var startHereSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Department(title: "Start here")
            indexRow(1, "Import your music files", fact: nil,
                     id: "home.start.import") { showImportFiles = true }
            RowRule(inset: Rail.text)
            indexRow(2, "Connect your server", fact: nil,
                     id: "home.start.server") { showConnectServer = true }
            RowRule(inset: Rail.text)
            indexRow(3, "Bring your listening history", fact: nil,
                     id: "home.start.history") { showHistoryImport = true }
        }
    }

    /// Live stations, playable on the first tap of the first minute.
    @ViewBuilder
    private var radioNowSection: some View {
        if radioRail.state == .loaded, !radioRail.songs.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                Department(title: "Radio, right now",
                           fact: String(localized: "LIVE"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.m) {
                        ForEach(radioRail.songs.prefix(8)) { station in
                            Button {
                                audio.play(station, in: [station])
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ArtworkImage(song: station, glyphSize: 22)
                                        .frame(width: 104, height: 104)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.card,
                                                                    style: .continuous))
                                    Text(station.title)
                                        .font(.sonavaByline)
                                        .foregroundColor(Theme.textSecondary)
                                        .lineLimit(1)
                                        .frame(width: 104, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// The app's own features, set as an index rather than as banners.
    var indexSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Department(title: "In the app")
            // The index is the app's own contents page, and each entry keeps
            // the identifier its journey has always used. The banner and the
            // two round chrome buttons are gone; the routes are not.
            indexRow(1, "Create an AI Mix", fact: proStore.isPro ? nil : "PRO",
                     id: AccessibilityID.aiMixCard) { showAIMix = true }
            RowRule(inset: Rail.text)
            indexRow(2, "Identify a track", fact: nil,
                     id: AccessibilityID.shazamButton) { showShazam = true }
            RowRule(inset: Rail.text)
            indexRow(3, "Settings", fact: nil,
                     id: AccessibilityID.settingsButton) { showSettings = true }
        }
    }

    func indexRow(_ rank: Int, _ title: LocalizedStringKey, fact: String?,
                  id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Space.l) {
                Text(String(format: "%02d", rank))
                    .font(.sonavaOrdinal)
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: Rail.ordinal, alignment: .trailing)
                Text(title)
                    .font(.system(.title3))
                    .foregroundColor(Theme.textPrimary)
                Spacer(minLength: Space.s)
                if let fact {
                    Text(fact)
                        .font(.sonavaStamp)
                        .tracking(1.2)
                        .foregroundColor(Theme.accentSoft)
                }
            }
            .frame(minHeight: Space.hitTarget + 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .identified(id, label: title)
    }
}
