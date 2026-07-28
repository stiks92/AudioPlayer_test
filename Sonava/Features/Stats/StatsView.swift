//
//  StatsView.swift
//  Sonava
//
//  "Your Sound" — the listener's own year-in-review, computed on device from
//  the local play log. It earns its place twice over: the streak brings people
//  back daily, and the share card is a small advert every time it's posted.
//
//  The last week is free. The longer windows are a Sonava Pro perk, which is a
//  soft, fair gate: nothing you already had is taken away.
//

import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var history: ListeningHistory
    @EnvironmentObject private var proStore: ProStore
    @Environment(\.dismiss) private var dismiss

    @State private var range: StatsRange = .week
    @State private var showPaywall = false
    @State private var shareItem: ShareableImage?
    @State private var confirmClear = false

    /// The hero number is text people read, so it has to scale — but no text
    /// style is anywhere near 52pt. `@ScaledMetric` scales the measurement
    /// itself, which is the only way to keep a display size and Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 52

    private var stats: ListeningStats {
        history.stats(range: range)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        rangePicker
                        if stats.isEmpty {
                            emptyState
                        } else {
                            hero
                            chart
                            tiles
                            topList("Top artists", entries: stats.topArtists, showDetail: false)
                            topList("Top tracks", entries: stats.topTracks, showDetail: true)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Your Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }.foregroundColor(Theme.accentSoft)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            shareItem = StatsShareCardRenderer.render(stats, range: range)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .disabled(stats.isEmpty)
                        Button(role: .destructive) { confirmClear = true } label: {
                            Label("Clear history", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis").foregroundColor(Theme.accentSoft)
                    }
                    .identified(AccessibilityID.statsMenu, label: "More")
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView().environmentObject(proStore) }
            .sheet(item: $shareItem) { ShareSheet(items: [$0.image]) }
            // An alert, not a confirmation dialog: from inside a sheet the
            // latter becomes a popover with no visible Cancel, and this
            // destroys data that cannot be recovered.
            .alert("Clear listening history?", isPresented: $confirmClear) {
                Button("Clear", role: .destructive) { history.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your stats are stored only on this device. This can't be undone.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Range

    private var rangePicker: some View {
        HStack(spacing: 8) {
            ForEach(StatsRange.allCases) { option in
                let locked = option.isPro && !proStore.isPro
                let selected = range == option
                Button {
                    if locked {
                        showPaywall = true
                    } else {
                        withAnimation(.snappy) { range = option }
                        Haptics.selection()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(option.title)
                        if locked {
                            Image(systemName: "lock.fill").font(.system(.caption2).weight(.bold))
                        }
                    }
                    .font(.sonavaRowMeta.weight(.semibold))
                    .foregroundColor(selected ? .white : Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: Space.hitTarget)
                    .background {
                        if selected {
                            Capsule().fill(Theme.accent.opacity(0.9))
                        } else {
                            Capsule().fill(Color.white.opacity(0.06))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stats.range.\(option.rawValue)")
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You listened for")
                .font(.system(.footnote).weight(.medium))
                .foregroundColor(Theme.textSecondary)
            Text(ListeningStats.duration(stats.totalSeconds))
                .font(.system(size: heroSize, weight: .heavy, design: .rounded))
                // Not `brandGradient`: it ends on accentDeep, which measures
                // 2.25:1 on this ground, so the minutes half of the number
                // dissolved into the background.
                .foregroundStyle(Theme.brandGradientOnDark)
                .contentTransition(.numericText())
                .accessibilityIdentifier(AccessibilityID.statsTotal)
            // Two keys rather than one: a single string with two plural
            // variables needs substitutions in the catalog, and translators
            // read "%lld tracks" far more reliably than "%lld … · %lld …".
            (Text("\(stats.plays) tracks")
                + Text(verbatim: " · ")
                + Text("\(stats.artistCount) artists"))
                .font(.system(.footnote))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chart

    private var chart: some View {
        Chart(stats.days) { bucket in
            BarMark(
                x: .value("Day", bucket.day, unit: .day),
                y: .value("Minutes", bucket.seconds / 60)
            )
            .foregroundStyle(
                LinearGradient(colors: [Theme.accentSoft, Theme.accent],
                               startPoint: .top, endPoint: .bottom)
            )
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text("\(Int(minutes))m").foregroundColor(Theme.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 7)) { value in
                AxisValueLabel(format: .dateTime.day(.defaultDigits).month(range == .week ? .omitted : .abbreviated))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(height: 160)
        .padding(14)
        .card(cornerRadius: Radius.card)
    }

    // MARK: - Tiles

    private var tiles: some View {
        HStack(spacing: 12) {
            tile(icon: "flame.fill",
                 value: "\(stats.streak)",
                 caption: "day streak",
                 tint: Theme.accentPink)
            tile(icon: "clock.fill",
                 value: peakHourText,
                 caption: "peak hour",
                 tint: Theme.accentSoft)
        }
    }

    private var peakHourText: String {
        guard let hour = stats.peakHour,
              let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())
        else { return "—" }
        return date.formatted(.dateTime.hour())
    }

    private func tile(icon: String, value: String, caption: LocalizedStringKey, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(.body).weight(.bold)).foregroundColor(tint)
            Text(value).font(.system(.title, design: .rounded).weight(.heavy))
                .foregroundColor(Theme.textPrimary)
            Text(caption).font(.system(.caption)).foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card(cornerRadius: Radius.card)
    }

    // MARK: - Ranked lists

    @ViewBuilder
    private func topList(_ title: LocalizedStringKey, entries: [ListeningStats.Entry], showDetail: Bool) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .textCase(.uppercase)
                    .font(.system(.caption).weight(.bold))
                    .tracking(1)
                    .foregroundColor(Theme.textTertiary)
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                        }
                        row(rank: index + 1, entry: entry, showDetail: showDetail)
                    }
                }
                .padding(.horizontal, 16)
                .card(cornerRadius: Radius.card)
            }
        }
    }

    private func row(rank: Int, entry: ListeningStats.Entry, showDetail: Bool) -> some View {
        HStack(spacing: 14) {
            Text(rank, format: .number)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundColor(Theme.accentSoft)
                .frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(.subheadline).weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                if showDetail, !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.system(.caption))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(ListeningStats.duration(entry.seconds))
                .font(.system(.footnote).weight(.medium))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundColor(Theme.accentSoft.opacity(0.7))
            Text("Nothing here yet")
                .font(.system(.body).weight(.bold))
                .foregroundColor(Theme.textPrimary)
            Text("Play something and your stats will start building — privately, on this device.")
                .font(.system(.footnote))
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Home entry point

/// The compact strip on Home. Leads with the streak because that is the number
/// that makes someone open the app again tomorrow.
struct StatsTeaserCard: View {
    let stats: ListeningStats
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.18)).frame(width: 44, height: 44)
                    Image(systemName: "chart.bar.fill")
                        .font(.system(.body).weight(.bold))
                        .foregroundColor(Theme.accentSoft)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Sound")
                        .font(.system(.subheadline).weight(.bold))
                        .foregroundColor(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(.footnote))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                if stats.streak > 1 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").font(.system(.caption).weight(.bold))
                        Text(stats.streak, format: .number)
                            .font(.system(.footnote, design: .rounded).weight(.heavy))
                    }
                    .foregroundColor(Theme.accentPink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accentPink.opacity(0.14)))
                }
                Image(systemName: "chevron.right")
                    .font(.system(.caption).weight(.semibold))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(14)
            .card(cornerRadius: Radius.card)
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.98))
        .identified(AccessibilityID.statsCard, label: "Your Sound")
    }

    private var subtitle: LocalizedStringKey {
        "\(ListeningStats.duration(stats.totalSeconds)) this week"
    }
}

// MARK: - Share card

/// Rendered to an image and shared. Deliberately readable at thumbnail size —
/// a shared card is only useful if the numbers survive a feed.
struct StatsShareCard: View {
    let stats: ListeningStats
    let range: StatsRange

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: ThemeManager.shared.palette.accentDeep),
                         Color(hex: ThemeManager.shared.palette.accent),
                         Color(hex: ThemeManager.shared.palette.accentPink)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Color.black.opacity(0.18)

            VStack(spacing: 34) {
                Spacer()
                Text("MY SOUND")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .tracking(10)
                    .foregroundColor(.white.opacity(0.85))

                VStack(spacing: 6) {
                    Text(ListeningStats.duration(stats.totalSeconds))
                        .font(.system(size: 130, weight: .black, design: .rounded))
                    Text(range == .all ? "all time" : (range == .month ? "this month" : "this week"))
                        .font(.system(size: 38, weight: .medium))
                        .opacity(0.85)
                }
                .foregroundColor(.white)

                if !stats.topArtists.isEmpty {
                    VStack(spacing: 18) {
                        ForEach(Array(stats.topArtists.prefix(3).enumerated()), id: \.element.id) { index, entry in
                            HStack(spacing: 22) {
                                Text(index + 1, format: .number)
                                    .font(.system(size: 44, weight: .black, design: .rounded))
                                    .foregroundColor(.white.opacity(0.55))
                                    .frame(width: 60, alignment: .leading)
                                Text(entry.name)
                                    .font(.system(size: 46, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 90)
                }

                if stats.streak > 1 {
                    HStack(spacing: 12) {
                        Image(systemName: "flame.fill").font(.system(size: 38, weight: .bold))
                        Text("\(stats.streak)-day streak").font(.system(size: 40, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.95))
                }

                Spacer()

                HStack(spacing: 14) {
                    Image(systemName: "sparkles").font(.system(.largeTitle).weight(.bold))
                    Text("Sonava").font(.system(size: 40, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.95))
                .padding(.bottom, 60)
            }
        }
        .frame(width: 1080, height: 1350)
    }
}

enum StatsShareCardRenderer {
    @MainActor
    static func render(_ stats: ListeningStats, range: StatsRange) -> ShareableImage? {
        let renderer = ImageRenderer(content: StatsShareCard(stats: stats, range: range))
        renderer.scale = 2
        guard let image = renderer.uiImage else { return nil }
        return ShareableImage(image: image)
    }
}
