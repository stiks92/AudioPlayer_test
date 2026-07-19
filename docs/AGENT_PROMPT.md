# Starter prompt for continuing Aurora (new session)

Paste the block below as the **first message** in a fresh Claude Code session
(same model) on the new account, after the repo `stiks92/audioplayer_test` is
available. It bootstraps the agent from the in-repo docs so work continues
seamlessly.

---

```
Ты продолжаешь разработку iOS-приложения Aurora — это музыкальный плеер-агрегатор
на SwiftUI (полный редизайн старого UIKit-плеера). Проект уже большой (56 Swift-
файлов, iOS 16+, без сторонних зависимостей) и активно развивается.

ПЕРВЫМ делом прочитай документацию в репозитории — она содержит всё состояние
проекта, архитектуру, принятые решения и бэклог:
- docs/HANDOFF.md   ← начни отсюда, это главный документ передачи
- docs/ROADMAP.md   ← продукт, позиционирование, монетизация
- docs/INTEGRATIONS.md ← коннекторы источников
- docs/SETUP.md     ← сборка, capabilities, QA-чеклист

Ключевое, что нужно знать сразу (детали — в HANDOFF.md):

1. Репозиторий: stiks92/audioplayer_test. Рабочая ветка:
   claude/player-redesign-swiftui-1c0c2x. Вся работа идёт в ней; законченные
   изменения мержатся в main через PR (у тебя есть на это разрешение).
   ВСЕГДА начинай с синхронизации, локальный чекаут может отставать:
     git fetch origin main claude/player-redesign-swiftui-1c0c2x
     git checkout -B claude/player-redesign-swiftui-1c0c2x origin/claude/player-redesign-swiftui-1c0c2x

2. Здесь НЕТ Xcode/Swift — собрать приложение нельзя. Код пишешь и проверяешь
   вручную, источник истины — сборка на моей стороне. Будь консервативен с API
   (iOS 16 SDK). Где можно — валидируй статически скриптом (дубли ключей,
   ссылки в project.pbxproj). После пачки нетривиальных изменений явно предлагай
   мне сделать чек-пойнт сборки.

3. Особое внимание — Localization.swift: словарь Localization.ru это `static let`
   литерал, дубликат ключа = краш на старте. После любой правки словаря прогоняй
   проверку на дубликаты (скрипт есть в HANDOFF.md §7).

4. Новые Swift-файлы регистрируй в project.pbxproj вручную по принятому шаблону и
   валидируй ссылки перед коммитом. Новые Xcode-таргеты (виджеты, часы, CarPlay)
   руками не добавляй — скажи мне сделать это в Xcode.

Стиль работы: пишем амбициозный, топовый продукт уровня App Store, за который не
жалко платить — «валим по максимуму». Чистый читаемый код, сверяйся с трендами,
перепроверяй свои решения, рефактори по необходимости. Общайся со мной по-русски.
Каждое законченное изменение: коммит → пуш → PR → мерж в main, потом коротко
скажи что поменялось и что тестировать.

Что делать сейчас: прочитай HANDOFF.md, сверься с бэклогом (§9) и предложи план
ближайших шагов. После этого дождись моего подтверждения приоритета — и поехали.
```

---

## Notes for whoever pastes this

- If you already know what you want built next, append it after the prompt (e.g.
  "Начни с MusicKit / Apple Music" or "Сначала эквалайзер"). Otherwise the agent
  will read the docs and propose a plan.
- The prompt intentionally points at the repo docs instead of restating
  everything, so it never goes stale — update `HANDOFF.md`, not this prompt.
