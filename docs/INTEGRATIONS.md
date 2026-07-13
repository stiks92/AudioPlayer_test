# Aggregator & Integrations — what is *actually* possible

The dream is "one player for all music." The reality is that music services fall
into three legally/technically distinct tiers. Getting this right is the whole
game, so this document is deliberately honest about limits.

## The three tiers

### Tier 1 — Direct-stream sources (raw audio, free, legal) ✅
We can fetch a real audio URL and play it in our own `AVPlayer`. This is the
**core** of the aggregator — it makes the app genuinely useful on day one with
**zero paid partnerships and zero ToS risk**.

| Source | Content | Auth | Notes | Effort |
| --- | --- | --- | --- | --- |
| **Audius** | Millions of tracks (indie, electronic, hip-hop), full length | None for streaming | Open, decentralized API; `/v1/tracks/{id}/stream` returns audio. **Best core source.** | Low |
| **Jamendo** | ~600k Creative-Commons tracks, full length + downloads | Free client ID | Legal free music + royalty-free licensing upsell | Low |
| **Internet Archive** | Public-domain, netlabels, huge **Live Music Archive** (concerts) | None | Direct file URLs; enormous catalog | Low |
| **Radio Browser** | 40k+ internet radio stations worldwide | None | Community API, direct stream URLs → instant "Radio" tab | Low |
| **Podcast Index** + iTunes Search | All public podcasts | Free (PI key) | RSS enclosure = direct audio; iTunes Search for discovery | Low–Med |
| **SomaFM / community stations** | Curated radio | None | Nice hand-picked defaults | Low |

### Tier 2 — Your own library / self-hosted (raw audio, user owns it) ✅
The user points us at *their* music. Beloved by the self-hosted/audiophile crowd
and a strong differentiator that big apps ignore.

| Source | What | Auth | Notes | Effort |
| --- | --- | --- | --- | --- |
| **Subsonic API** (Navidrome, Airsonic, Gonic) | User's self-hosted library, full streaming + transcoding | User creds | De-facto open standard; one client → many servers | Medium |
| **Jellyfin** | Self-hosted media server | User creds/token | Music + full API | Medium |
| **Plex** | Personal library | Plex OAuth | More involved auth | Medium |
| **Local / Files / iCloud Drive / WebDAV / Nextcloud** | User's own files | — | Import + on-device library | Low–Med |

### Tier 3 — Connected accounts (control + metadata, playback via their SDK) ⚠️
We **cannot** extract raw audio. We *can* read the user's library/playlists and
**drive playback through the provider's official player**, gated by their
subscription. Honest framing to users: *"a universal remote and unified library,"*
not raw audio. Still hugely valuable — one search across everything, one queue.

| Service | Metadata/Search API | Full playback | Reality |
| --- | --- | --- | --- |
| **Apple Music (MusicKit)** | ✅ free | ✅ for subscribers, 30s preview otherwise | **Native, cleanest** integration on iOS. Do this first in Tier 3. |
| **Spotify** | ✅ Web API (free): search, playlists, library, recommendations | ▲ via iOS SDK / Spotify Connect, **Premium required**; preview clips being reduced | Great for "unify my Spotify," browse, and remote control. Audio rendered by Spotify. |
| **Deezer** | ✅ | 30s previews free; full needs SDK + premium | Previews are trivial; full playback constrained |
| **TIDAL** | ▲ partner/OAuth API | Subscriber-only, limited access | High effort, gated program |
| **YouTube / YT Music** | ✅ Data API (search, quota-limited) | ❌ audio extraction violates ToS | **Only legal audio-less path is the IFrame *video* player.** Do not build audio aggregation on YouTube. |
| **SoundCloud** | ▲ app registration effectively closed for years | ▲ | Unreliable to build on today — defer |
| **Amazon Music** | ❌ no public streaming API | ❌ | Not possible |

> **Bottom line:** build the product on Tiers 1 + 2 (real, free, legal audio),
> then add Tier 3 as "connect your accounts" for unification and control. That is
> the honest "ultimate" aggregator.

## Supporting free services (metadata, lyrics, identity)

| Service | Use | Free? |
| --- | --- | --- |
| **MusicBrainz** | Canonical track/album/artist metadata, dedup | ✅ |
| **Cover Art Archive** | Album art | ✅ |
| **LRCLIB** | **Synced (karaoke) lyrics** by track — open API | ✅ |
| **AcoustID + Chromaprint** | Audio fingerprint → identify messy local files | ✅ |
| **Last.fm** | Scrobbling, similar artists, charts | ✅ (key) |
| **ListenBrainz** | Open scrobbling + recommendations (privacy-friendly) | ✅ |
| **ShazamKit (Apple)** | Recognize what's playing around you | ✅ framework |

## Provider abstraction (how the code should be organized)

Everything hides behind one protocol so screens never care where a track lives:

```swift
protocol MusicSource: Identifiable {
    var id: String { get }              // "audius", "subsonic:home", "spotify"
    var kind: SourceKind { get }        // .directStream / .selfHosted / .connectedSDK
    var displayName: String { get }

    func search(_ query: String) async throws -> [Track]
    func browse(_ section: BrowseSection) async throws -> [Shelf]

    // Tier 1 & 2: return a real URL for our AVPlayer.
    func streamURL(for track: Track) async throws -> URL

    // Tier 3: hand off to the provider's player instead of returning audio.
    var playbackDelegate: ExternalPlaybackController? { get }
}
```

Playback engine gains two backends behind a common `PlaybackEngine` interface:

- **`LocalPlaybackEngine`** — current `AVAudioPlayer`/`AVPlayer` (Tier 1 & 2,
  streaming + gapless + caching).
- **`ExternalPlaybackEngine`** — wraps Spotify iOS SDK / MusicKit / Deezer;
  our transport UI becomes a controller, position/state come from their SDK.

The unified **library index** (SwiftData/Core Data) stores normalized `Track`s
with a `sourceRef`, so search, favorites, playlists, and the queue work across
every source at once — including **cross-service playlists** (a playlist can mix
an Audius track, a Subsonic track, and a Spotify track).

## Auth, security, offline

- OAuth 2.0 (PKCE) for Spotify/Deezer/Plex; app-password/token for Subsonic/Jellyfin.
- Tokens in **Keychain**; never in `UserDefaults`.
- Offline downloads only where licensing allows (Tier 1 CC/PD content, Tier 2
  user-owned). Never cache Tier 3 audio.
- Respect rate limits with a caching layer (ETag + TTL) in front of every API.

## Legal / App Store guardrails (read before shipping)

- No extracting audio from Spotify / Apple Music / YouTube — SDK playback only,
  subscription-gated.
- Spotify SDK requires the user to have **Premium**; surface this clearly.
- Displaying another service's catalog has branding/attribution rules — follow
  each provider's design guidelines and show "Play on Spotify/Apple" affordances.
- User-hosted servers (Subsonic/Jellyfin/Plex): content is the user's
  responsibility; we're a client.
- Privacy: on-device processing wherever possible; GDPR-compliant, minimal data.
