# Aurora — Product Roadmap & Growth Plan

Turning the redesigned SwiftUI player into an "ultimate" cross-service music app.
Companion doc: [`INTEGRATIONS.md`](./INTEGRATIONS.md).

## Shipped so far

- Full SwiftUI redesign; custom tab bar; expanding Now Playing; aurora visuals.
- Provider abstraction + dual playback engine (local metering / remote streaming).
- Sources: **Audius** (streaming), **Internet Radio** (Radio Browser),
  **Podcasts** (iTunes discovery + RSS episodes, with 0.8×–2× speed),
  **Self-hosted Subsonic** (Navidrome/Airsonic; Keychain-stored credentials).
- **Aurora Pro** (StoreKit 2) + paywall + settings + Pro gating.
- **AI Mix** (on-device natural-language mix, EN + RU intent), synced **karaoke
  lyrics** (LRCLIB), **ShazamKit** recognition, **sleep timer**, **share card**,
  haptics.
- **Deezer** (search/charts/playlists, 30s previews) + **Apple/iTunes** previews;
  **Editor's picks** curated shelves on Home; **Artist** screen.
- **Bilingual EN/RU** localization (lightweight `L()` system).
- **Endless autoplay** + **resume last session**; cross-source favorites, recents,
  queue editing, and user playlists.
- First-run **onboarding**; performance hardening (clock split, keep-alive tabs,
  energy-aware visuals).

Remaining big rocks are tracked below (EQ/audio quality, Apple Music/Spotify,
platform extensions, scrobbling, offline). **Engineering handoff / how to continue
this project: [`HANDOFF.md`](./HANDOFF.md).**

## 1. Positioning (the one-liner)

> **Aurora — one beautiful player for *all* your music.**
> Your files, your server, free streaming catalogs, your podcasts and radio, and
> your Spotify/Apple accounts — unified, with an on-device AI DJ. Private by design.

Why this wins: Spotify/Apple lock you into *their* catalog. Self-hosted clients
(Navidrome, Plex) are powerful but ugly. Aurora is the only one that is **gorgeous
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
- **Aurora Pro** (subscription ~$3–5/mo or ~$25/yr):
  - Connect unlimited streaming accounts + self-hosted servers
  - On-device **AI DJ**, natural-language playlists, endless smart radio
  - Karaoke lyrics + transcripts, advanced EQ/spatial, gapless/crossfade
  - CarPlay, Watch, Widgets, offline downloads (for permitted content)
  - iCloud library backup + cross-service playlist transfer
- **Lifetime unlock** (~$60–80 one-time) — converts the "I hate subscriptions"
  crowd (this segment overlaps heavily with the self-hosted audience).
- **BYO-AI-key** tier — advanced AI at zero cost to us.
- Principled stance: **no ads, no tracking** — itself a marketing message.

Secondary: affiliate/licensing upsell for Jamendo royalty-free music (creators),
and a possible "Aurora for creators/labels" angle later.

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

Ship **Phase 1** on top of the existing beautiful UI: the `MusicSource`
abstraction + **Audius** streaming + **Radio Browser** + **LRCLIB lyrics** +
**ShazamKit**. That single milestone converts the demo into a real, legal,
free streaming app with two headline "wow" features — the strongest possible
foundation to build the rest on.
