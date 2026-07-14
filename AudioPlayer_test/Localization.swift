//
//  Localization.swift
//  AudioPlayer_test
//
//  Lightweight, dependency-free localization. `L("English key")` returns the
//  Russian string when the device language is Russian, otherwise the key
//  itself. Missing keys fall back gracefully to English.
//

import Foundation

func L(_ key: String) -> String {
    guard Localization.isRussian else { return key }
    return Localization.ru[key] ?? key
}

enum Localization {
    static let isRussian: Bool = {
        (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("ru")
    }()

    static let ru: [String: String] = [
        // Tabs
        "Home": "Главная",
        "Search": "Поиск",
        "Radio": "Радио",
        "Podcasts": "Подкасты",
        "Library": "Медиатека",

        // Home
        "Good morning": "Доброе утро",
        "Good afternoon": "Добрый день",
        "Good evening": "Добрый вечер",
        "Late night vibes": "Ночной вайб",
        "What do you feel like hearing?": "Что хочется послушать?",
        "Create an AI Mix": "Собрать AI-микс",
        "Describe a vibe — get an instant mix": "Опиши настроение — получи микс",
        "Popular now": "Популярно сейчас",
        "Recently played": "Недавно играли",
        "Trending on Audius": "В тренде на Audius",
        "Featured": "Подборки",
        "Quick picks": "Быстрый выбор",
        "From your server": "С твоего сервера",

        // Search
        "Songs, artists, stations…": "Песни, артисты, станции…",
        "In your library": "В медиатеке",
        "Your server": "Твой сервер",
        "Audius · full tracks": "Audius · полные треки",
        "Deezer": "Deezer",
        "Apple Music": "Apple Music",
        "Browse moods": "Настроения",
        "Couldn't reach Audius. Check your connection.": "Не удалось связаться с Audius. Проверь соединение.",
        "No Audius tracks matched.": "На Audius ничего не найдено.",
        "No results": "Ничего не найдено",
        "Cinematic": "Кинематографично",
        "Dark": "Мрачно",
        "Tense": "Напряжённо",
        "Uplifting": "Воодушевляюще",
        "Melancholy": "Меланхолия",
        "Epic": "Эпично",

        // Radio
        "Tuning in…": "Настраиваемся…",
        "No stations found for this genre.": "Станций в этом жанре не найдено.",
        "Top": "Топ",
        "News": "Новости",
        "Rock": "Рок",
        "Ambient": "Эмбиент",

        // Podcasts
        "Search podcasts": "Искать подкасты",
        "No podcasts found.": "Подкасты не найдены.",
        "Play latest": "Слушать свежий",
        "Couldn't load episodes.": "Не удалось загрузить эпизоды.",
        "No episodes found.": "Эпизоды не найдены.",
        "Technology": "Технологии",
        "Comedy": "Юмор",
        "Business": "Бизнес",
        "Science": "Наука",
        "Health": "Здоровье",
        "Sports": "Спорт",
        "History": "История",
        "Education": "Образование",

        // Library
        "Your Library": "Твоя медиатека",
        "Playlists": "Плейлисты",
        "Songs": "Песни",
        "Favorites": "Избранное",
        "New Playlist": "Новый плейлист",
        "No favourites yet": "Пока нет избранного",
        "Tap the heart on any track to save it here.": "Нажми на сердечко у трека, чтобы добавить его сюда.",
        "New playlist": "Новый плейлист",
        "Name": "Название",
        "Create": "Создать",
        "Cancel": "Отмена",

        // Now Playing / Queue
        "Queue": "Очередь",
        "Now Playing": "Сейчас играет",
        "Up Next": "Далее",
        "Done": "Готово",
        "Lyrics": "Текст",
        "No lyrics found for this track.": "Текст для этого трека не найден.",
        "Couldn't load lyrics.": "Не удалось загрузить текст.",

        // Context menu
        "Play Next": "Играть следующим",
        "Add to Queue": "В очередь",
        "Start Station": "Запустить станцию",
        "Favorite": "В избранное",
        "Remove from Favorites": "Убрать из избранного",
        "Remove from playlist": "Убрать из плейлиста",
        "Add to Playlist": "Добавить в плейлист",
        "Rename": "Переименовать",
        "Delete playlist": "Удалить плейлист",
        "Play": "Слушать",
        "Shuffle": "Вперемешку",

        // Sleep timer
        "Sleep timer": "Таймер сна",
        "Turn off": "Выключить",
        "Off": "Выкл",

        // Settings
        "Settings": "Настройки",
        "Playback": "Воспроизведение",
        "Sources": "Источники",
        "Connected": "Подключено",
        "Self-hosted (Subsonic)": "Свой сервер (Subsonic)",
        "Connect": "Подключить",
        "Support": "Поддержка",
        "Restore purchases": "Восстановить покупки",
        "Privacy": "Приватность",
        "On-device": "На устройстве",
        "Internet Radio": "Интернет-радио",
        "Spotify / Apple Music": "Spotify / Apple Music",
        "Soon": "Скоро",

        // Pro / Paywall
        "Aurora Pro": "Aurora Pro",
        "Unlock Aurora Pro": "Открыть Aurora Pro",
        "AI Mix · all sources · EQ · offline": "AI-микс · все источники · EQ · офлайн",
        "Active — thank you for your support!": "Активна — спасибо за поддержку!",
        "Unlock Aurora Pro to the fullest.": "Открой Aurora Pro полностью.",
        "Restore purchases": "Восстановить покупки",
        "Processing…": "Обработка…",
        "Plans will be available at launch.": "Тарифы появятся на релизе.",
        "Loading plans…": "Загрузка тарифов…",

        // AI Mix
        "AI Mix": "AI-микс",
        "Describe a vibe": "Опиши настроение",
        "Generate mix": "Собрать микс",
        "Composing…": "Собираем…",
        "AI Mix is a Pro feature": "AI-микс — функция Pro",
        "Unlock with Aurora Pro": "Открыть в Aurora Pro",
        "Couldn't build a mix. Try another vibe or check your connection.": "Не удалось собрать микс. Попробуй другое настроение или проверь соединение.",

        // Discover / Shazam
        "Discover": "Распознать",
        "Tap to identify the music around you": "Нажми, чтобы распознать музыку вокруг",
        "Listening…": "Слушаем…",
        "No match — try again": "Не найдено — попробуй ещё",
        "Something went wrong": "Что-то пошло не так",
        "Play on Aurora": "Слушать в Aurora",
        "Searching…": "Ищем…",
        "Open in Apple Music": "Открыть в Apple Music",
        "Identify another": "Распознать ещё",
        "Music recognition needs a physical device.": "Распознавание работает только на реальном устройстве.",

        // Connect server
        "Self-hosted server": "Свой сервер",
        "Disconnect": "Отключить",
        "Server URL": "Адрес сервера",
        "Username": "Имя пользователя",
        "Password": "Пароль",
        "Connecting…": "Подключение…",

        // Onboarding
        "Skip": "Пропустить",
        "Continue": "Далее",
        "Start listening": "Начать слушать",
        "All your music, one player": "Вся музыка в одном плеере",
        "Search everything at once": "Ищи везде сразу",
        "AI Mix & Shazam": "AI-микс и распознавание",
        "Private by design": "Приватно по умолчанию"
    ]
}
