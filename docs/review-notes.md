# App Review notes — черновик для поля "Notes" в ASC

Владелец вставляет это в App Store Connect → App Review Information → Notes
(EN), подставив реальные адреса демо-сервера. Ревьюеры смотрят приложение без
музыкальной библиотеки и без подписок — эти заметки закрывают каждый «пустой»
экран, который они увидят.

---

Sonava is a player for music the user already has: local files, their own
Subsonic/Navidrome server, WebDAV drives, plus their Apple Music subscription
via Apple's MusicKit. The app has no accounts and no backend of ours.

**Demo server (Subsonic/Navidrome).** The library screens are naturally empty
on a fresh install. To see the app with content, connect our demo server:
Library → sources hub → "Your server":

- Address: `https://DEMO-HOST` ← владелец подставляет
- Username: `reviewer`
- Password: `PASSWORD` ← владелец подставляет

All music on the demo server is Creative Commons netlabel material.

**Apple Music.** Playback of the full catalogue requires an active Apple Music
subscription on the test device (MusicKit; our token comes from the MusicKit
App Service). Without a subscription the connector states this honestly and
the rest of the app is unaffected. Note: DRM playback does not work in the
simulator — device only.

**Pro subscription.** Sonava Pro gates convenience features: offline downloads
of the user's own server music, Crate Mix (DJ-style queue ordering), the
10-band equalizer, headphone correction, AI Mix, accent themes and alternate
app icons, more than one self-hosted server / cloud drive (and searching all
servers at once), and listening stats beyond the current week. Free tier is
fully usable: playback, one server, one cloud drive, radio, podcasts, lyrics,
gapless, loudness levelling and scrobbling are all free. Lifetime is a
non-consumable; monthly / yearly are auto-renewable with an introductory
trial. Privacy Policy and Terms of Use (Apple standard EULA) are linked on
the paywall and in Settings.

**Microphone** is used only for the "what's playing" recognizer (ShazamKit),
triggered explicitly by the user from Home. **Local network** access is used
only when the user connects a LAN media server by an `http://` address.

**Privacy.** No analytics, no tracking, no data collection by us
(PrivacyInfo.xcprivacy in the bundle; the only network calls are to
user-connected services and open catalogues — details on our privacy page).

---

## Чек-лист владельца перед сабмитом

- [ ] Поднять демо-Navidrome с CC-музыкой, создать пользователя `reviewer`,
      вставить адрес/пароль выше.
- [ ] Убедиться, что MusicKit App Service включён в App Information.
- [ ] На тестовом устройстве с активной Apple Music-подпиской пройти
      end-to-end: подключение → поиск → воспроизведение.
- [ ] Ссылки Privacy Policy / Support в ASC указывают на опубликованный
      `docs/site/` (GitHub Pages или домен).
