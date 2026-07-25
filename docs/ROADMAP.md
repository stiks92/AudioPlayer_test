# Sonava — Product Roadmap & Growth Plan

Turning the redesigned SwiftUI player into an "ultimate" cross-service music app.
Companion doc: [`INTEGRATIONS.md`](./INTEGRATIONS.md).

> **This document is the long-range product plan.** Positioning, App Store
> metadata and the conversion funnel were reworked later by a dedicated ASO
> study, which supersedes sections 1, 5 and 6 where the two disagree — the
> short version is: sell *"the player for the music you already control"*, not
> a free Spotify. Renamed from "Aurora" (taken in the App Store); don't
> reintroduce that name as product copy.

## Shipped so far

- Full SwiftUI redesign; custom tab bar; expanding Now Playing; aurora visuals.
- Provider abstraction + dual playback engine (local metering / remote streaming).
- Sources: **Audius** (streaming), **Internet Radio** (Radio Browser),
  **Podcasts** (iTunes discovery + RSS episodes, with 0.8×–2× speed),
  **Self-hosted Subsonic** (Navidrome/Airsonic; Keychain-stored credentials) —
  now **several servers at once**, searched together.
- **Sonava Pro** (StoreKit 2) + paywall + settings + Pro gating, with a 7-day
  trial reached from the end of onboarding.
- **AI Mix** (on-device natural-language mix, EN + RU intent), synced **karaoke
  lyrics** (LRCLIB), **ShazamKit** recognition, **sleep timer**, **share card**,
  haptics.
- **Deezer** (search/charts/playlists, 30s previews) + **Apple/iTunes** previews;
  **Editor's picks** curated shelves on Home; **Artist** screen.
- **10-band equalizer** with presets (local + downloaded audio).
- **Offline downloads** of full-length, rights-clean tracks.
- **Scrobbling to ListenBrainz**; **taste profile** driving "Made for you" and
  on-taste endless radio.
- **Personalisation:** six accent palettes and six matching app icons.
- **"Your Sound"** on-device listening stats — top artists/tracks, day streak,
  shareable card.
- **Siri / Shortcuts / Spotlight** intents: favourites, my radio, resume.
- **Playlist sharing** via `sonava://` links.
- **Bilingual EN/RU** localization — a standard **String Catalog**, with the
  Russian pass run as its own test configuration.
- **Endless autoplay** + **resume last session**; cross-source favorites, recents,
  queue editing, and user playlists.
- First-run **onboarding**; rating prompt at a happy moment; performance
  hardening (clock split, keep-alive tabs, energy-aware visuals).

Remaining big rocks are tracked below (crossfade/gapless, Apple Music/Spotify,
platform extensions, iCloud sync). **Engineering handoff / how to continue
this project: [`HANDOFF.md`](./HANDOFF.md).**

## 1. Positioning (the one-liner)

> **Sonava — one beautiful player for *all* your music.**
> Your files, your server, free streaming catalogs, your podcasts and radio, and
> your Spotify/Apple accounts — unified, with an on-device AI DJ. Private by design.

Why this wins: Spotify/Apple lock you into *their* catalog. Self-hosted clients
(Navidrome, Plex) are powerful but ugly. Sonava is the only one that is **gorgeous
+ universal + private + AI-native**, and it's useful for free on day one via
legal open catalogs.

## 2. Differentiators (why people switch)

1. **Universal library & search** — one query across Audius, your Subsonic server,
   local files, podcasts, radio, and connected accounts.
2. **Cross-service playlists & queue** — mix a CC track, a self-hosted track, and
   a Spotify track in one playlist.
3. **On-device AI DJ** — mood/BPM/key-aware auto-mixing and natural-language
   playlist generation, running privately on the phone.
4. **Instant "wow" features** — ShazamKit recognition, synced karaoke lyrics
   (LRCLIB), gorgeous shareable "aurora" now-playing cards.
5. **Privacy-first** — no tracking, on-device intelligence; a genuine wedge
   against the incumbents.
6. **Self-host friendly** — first-class Subsonic/Jellyfin/Plex support the big
   apps will never build.

## 3. Feature roadmap (phased)

### Phase 1 — "Real streaming app" (foundation)
- `MusicSource` provider abstraction + unified `Track`/`Playlist` model (SwiftData).
- **Audius** (core free catalog) + **Radio Browser** (radio tab) wired into the
  existing UI, streamed via `AVPlayer` (remote URL + caching).
- **Synced lyrics** via LRCLIB → karaoke view in Now Playing.
- **ShazamKit** "identify what's playing" button.
- Local file import (Files/iCloud).
- Robust streaming engine: gapless, crossfade, buffering states, Now Playing/lock
  screen (already have the plumbing), CarPlay stub.

### Phase 2 — "The aggregator"
- **Subsonic** + **Jellyfin** connectors (self-hosted libraries).
- **Podcasts** (Podcast Index) with episode feeds, playback speed, skip-silence.
- **Jamendo** + **Internet Archive** catalogs.
- **Apple Music (MusicKit)** connect (Tier 3, native first).
- Unified cross-source search + cross-service playlists.
- Scrobbling: **Last.fm** + **ListenBrainz**.

### Phase 3 — "AI & delight"
- On-device audio analysis (BPM/key/energy/mood) → **Auto-DJ** & harmonic mixing.
- Natural-language playlist generation ("rainy Sunday focus, no vocals").
- Smart/endless radio that learns taste on-device.
- Podcast/lyrics transcription & search via **WhisperKit** (on-device).
- Advanced EQ, spatial audio, ReplayGain normalization, sleep timer.

### Phase 4 — "Platform & social"
- **Spotify** connect (Web API + Connect control, Premium playback).
- Widgets, Live Activities, Apple Watch app, Siri Shortcuts, Handoff.
- **SharePlay** listening parties; collaborative playlists.
- iCloud sync of library/settings; cross-service playlist transfer/import.
- Shareable now-playing cards (viral loop).

## 4. AI features — the free / on-device path

Truly "free" means **on-device Apple frameworks + open data**, no server bills:

| Feature | How (free) |
| --- | --- |
| Song recognition | **ShazamKit** (Apple, free framework) |
| Synced/karaoke lyrics | **LRCLIB** open API |
| Podcast & lyric transcription, searchable | **WhisperKit / whisper.cpp** on-device |
| BPM/key/energy analysis → Auto-DJ, harmonic mixing | Accelerate/`Essentia` on-device DSP |
| Natural-language playlist & search | On-device LLM via **Apple MLX / Core ML** (small Phi/Llama), or **Apple Intelligence** Writing Tools (iOS 18+) |
| Taste-based recommendations / endless radio | On-device collaborative filtering + audio-feature embeddings |
| Clean up messy local libraries (auto-tag) | **AcoustID/Chromaprint** fingerprint + **MusicBrainz** |
| Smart crossfade / beat-matched transitions | On-device beat/key detection |

Optional **"bring-your-own-key"** upgrade lets power users plug in a cloud LLM
for richer "AI DJ banter" and semantic search — cost falls on the user, not us.

## 5. Monetization ("продающие функции")

**Freemium + one-time unlock** (indie-music-app sweet spot):

- **Free forever:** open catalogs (Audius/Jamendo/Archive), radio, podcasts,
  local files, basic playback, ShazamKit, basic lyrics. This alone is a complete,
  useful app — great for word of mouth.
- **Sonava Pro** (subscription, 7-day trial). Gated **today**: offline
  downloads, the 10-band equalizer, AI Mix, ListenBrainz scrobbling, accent
  palettes, alternate app icons, unlimited self-hosted servers (searched
  together), and the month/all-time stats views.
  Still on the list: gapless/crossfade, CarPlay, Watch, Widgets, iCloud backup
  and cross-service playlist transfer.
- **Lifetime unlock** (~$60–80 one-time) — converts the "I hate subscriptions"
  crowd (this segment overlaps heavily with the self-hosted audience).
- **BYO-AI-key** tier — advanced AI at zero cost to us.
- Principled stance: **no ads, no tracking** — itself a marketing message.

Secondary: affiliate/licensing upsell for Jamendo royalty-free music (creators),
and a possible "Sonava for creators/labels" angle later.

## 6. Go-to-market & growth

**Beachhead communities (they'll love this specifically):**
- r/selfhosted, r/Navidrome, r/jellyfin, r/plex — "a beautiful client for your
  server" is a constant request.
- r/audiophile, r/headphones — EQ/spatial/gapless + self-host.
- Creative-Commons & indie artists (Audius, Jamendo) — they get a beautiful home.
- Podcast + internet-radio communities.

**Launch motions:**
- **TestFlight** public beta → gather testimonials.
- **Product Hunt** launch with the aurora visuals (very screenshot-friendly).
- Short demo videos of AI DJ + Shazam + karaoke + "play from your own server."
- **Shareable now-playing cards** (the gradient artwork) = built-in viral loop;
  every share is an ad.
- **ASO:** target long-tail intent — "subsonic client," "navidrome ios,"
  "spotify apple music combined," "self hosted music player," "karaoke lyrics."
- **Referral:** invite a friend → both get Pro time.
- Press/newsletters in the self-hosted and indie-music niches.

**North-star metric:** weekly active listeners with ≥2 connected sources
(proves the "aggregator" value prop). Track connect-rate, AI-DJ usage, share rate.

## 7. Technical work this unlocks (engineering summary)

- Provider plugin system (`MusicSource`) + dual `PlaybackEngine` (local URL vs
  external SDK). See INTEGRATIONS.md.
- Remote streaming via `AVPlayer` with buffering UI, caching, gapless, crossfade.
- SwiftData unified library index; iCloud sync.
- OAuth (PKCE) + Keychain token storage; per-provider rate-limit/caching layer.
- On-device AI module (ShazamKit, WhisperKit, DSP analysis, Core ML/MLX).
- Platform extensions: CarPlay, WidgetKit, Watch, App Intents/Siri, SharePlay.

## 8. Risks & honest constraints

- Tier-3 audio is **SDK + subscription gated** (no raw audio) — set user
  expectations; lead with Tier 1/2 value.
- YouTube audio aggregation is against ToS — excluded by design.
- App Store review scrutinizes multi-service apps — follow each provider's
  branding/usage rules.
- On-device LLM quality/size trade-offs on older devices — feature-flag by device.
- Some open APIs (community radio, Podcast Index) need graceful failure handling.

## 9. Recommended immediate next step

Phases 1–3 are largely shipped. What is left, in order of value:

1. **Owner, not code:** create the `com.sonava.pro.*` products with the 7-day
   trial in App Store Connect, paste the name/subtitle/keywords, upload the
   screenshots, and add the RU + second English store localizations. None of
   the monetization above earns anything until this is done.
2. **Crossfade / gapless.** High value and the most-requested audio feature,
   but the DSP is not ear-verifiable in a simulator and it is a real
   dual-playback refactor of `LocalAudioEngine`. Do it *with* device listening.
3. **A home-screen widget / Live Activity.** Strong retention and a good store
   screenshot, but it needs a new Xcode target — add it in Xcode, never by
   hand-editing the project file.
4. **iCloud sync** of favourites, playlists and settings.
5. **MusicKit (Apple Music)** — needs a device and an entitlement.
