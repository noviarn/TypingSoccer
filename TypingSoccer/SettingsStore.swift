//
//  SettingsStore.swift
//  TypingSoccer
//
//  User preferences (language, audio volume, text size) persisted in
//  UserDefaults, plus the tiny English/Indonesian localization table.
//  `L(...)` is the app-wide translation helper.
//

import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case indonesian = "id"

    var id: String { rawValue }
    var displayName: String { self == .english ? "English" : "Bahasa Indonesia" }
}

final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }
    /// 0…1 master volume for the game's sound effects. 0 = muted.
    @Published var audioVolume: Double {
        didSet { defaults.set(audioVolume, forKey: Keys.audio) }
    }
    /// 1.0…1.5 multiplier applied to the in-game word prompt and HUD text.
    @Published var textScale: Double {
        didSet { defaults.set(textScale, forKey: Keys.textScale) }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let language = "settings.language"
        static let audio = "settings.audioVolume"
        static let textScale = "settings.textScale"
    }

    private init() {
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "en") ?? .english
        audioVolume = defaults.object(forKey: Keys.audio) as? Double ?? 0.7
        textScale = defaults.object(forKey: Keys.textScale) as? Double ?? 1.0
    }
}

// MARK: - Localization

/// Translate a key using the current language. Keys missing from the
/// Indonesian table fall back to English; unknown keys return themselves
/// (so a forgotten entry is visible instead of crashing).
func L(_ key: String) -> String {
    let lang = SettingsStore.shared.language
    if lang == .indonesian, let id = Localization.indonesian[key] { return id }
    return Localization.english[key] ?? key
}

enum Localization {

    static let english: [String: String] = [
        "menu.title": "TYPING SOCCER",
        "menu.tagline": "Type fast. Win the ball. Score.",
        "menu.single": "SINGLE PLAYER (vs AI)",
        "menu.multi": "MULTIPLAYER 2v2 (GAME CENTER)",
        "menu.howto": "HOW TO PLAY",
        "menu.hint": "Countdown whistle → type the word → first to finish gets the ball.\nCarriers auto-run to goal; defenders intercept with new words.\nKeys 1·2·3: pass when attacking, pick your chaser when defending.",

        "lobby.title": "WAITING FOR PLAYER",
        "lobby.searching": "Looking for players on Game Center…",
        "lobby.waitingSeats": "seats filled — waiting for players…",
        "lobby.starting": "All seats filled — starting…",
        "lobby.waitingJoin": "Waiting to join...",
        "lobby.claim": "TAP TO CLAIM",
        "lobby.open": "— open —",
        "lobby.cancel": "CANCEL",
        "lobby.start": "START",
        "lobby.hint": "Sign in to Game Center on every Mac. Field players run the 3 outfielders;\nkeeper players guard the goal. If someone quits mid-match, the AI takes over.",
        "lobby.noPlayers": "Couldn't find 3 other players. Search again or cancel.",
        "lobby.retry": "SEARCH AGAIN",

        "gc.needSignIn": "Sign in to Game Center",
        "gc.needSignInDetail": "Multiplayer needs Game Center. Open System Settings › Game Center to sign in, then try Find Match again.",
        "alert.ok": "OK",

        "pause.title": "PAUSE",
        "pause.resume": "Resume",
        "pause.menu": "Back To Main Menu",

        "settings.title": "SETTINGS",
        "settings.language": "LANGUAGE",
        "settings.audio": "AUDIO",
        "settings.textSize": "TEXT SIZE",

        "profile.title": "PROFILE",
        "profile.stats": "STATS",
        "profile.matches": "Matches Played",
        "profile.winRate": "Win Rate",
        "profile.accuracy": "Total Accuracy",
        "profile.goals": "Total Goals",
        "profile.streak": "Current Streak",
        "profile.history": "MATCH HISTORY",
        "profile.achievements": "ACHIEVEMENTS",
        "profile.level": "Lv.",
        "profile.noMatches": "No matches yet — play one!",

        "leaderboard.title": "LEADERBOARDS",
        "leaderboard.rank": "RANK",
        "leaderboard.player": "PLAYER",
        "leaderboard.bestGoal": "BEST GOAL",
        "leaderboard.accuracy": "ACCURACY",
        "leaderboard.bestScore": "BEST SCORE",
        "leaderboard.shotAcc": "SHOT ACC",
        "leaderboard.bestSaves": "BEST SAVES",
        "leaderboard.savePct": "SAVE %",
        "leaderboard.you": "You",
        "leaderboard.loading": "Loading Game Center leaderboards…",
        "leaderboard.empty": "No scores yet. Play a multiplayer match to get on the board!",
        "leaderboard.notAuth": "Sign in to Game Center to see the leaderboards.",
        "leaderboard.error": "Couldn't load leaderboards. Check that the leaderboard IDs are configured in App Store Connect.",
        "leaderboard.mpOnly": "Multiplayer matches only.",

        "howto.title": "HOW TO PLAY",

        "results.fulltime": "FULL TIME",
        "results.penalties": "on penalties",
        "results.coach": "GET COACH ANALYSIS",
        "results.coachWait": "Your coach is reviewing the match…",
        "results.back": "BACK TO MENU",
        "results.stats": "MATCH STATS",

        "common.back": "Back",
        "common.you": "YOU",
        "common.ai": "AI",
    ]

    static let indonesian: [String: String] = [
        "menu.title": "TYPING SOCCER",
        "menu.tagline": "Ketik cepat. Rebut bola. Cetak gol.",
        "menu.single": "PEMAIN TUNGGAL (vs AI)",
        "menu.multi": "MULTIPLAYER 2v2 (GAME CENTER)",
        "menu.howto": "CARA BERMAIN",
        "menu.hint": "Peluit hitung mundur → ketik kata → yang selesai duluan dapat bola.\nPembawa bola lari otomatis ke gawang; bek memotong dengan kata baru.\nTombol 1·2·3: oper saat menyerang, pilih pengejar saat bertahan.",

        "lobby.title": "MENUNGGU PEMAIN",
        "lobby.searching": "Mencari pemain di Game Center…",
        "lobby.waitingSeats": "kursi terisi — menunggu pemain…",
        "lobby.starting": "Semua kursi terisi — memulai…",
        "lobby.waitingJoin": "Menunggu bergabung...",
        "lobby.claim": "KLIK UNTUK PILIH",
        "lobby.open": "— kosong —",
        "lobby.cancel": "BATAL",
        "lobby.start": "MULAI",
        "lobby.hint": "Masuk ke Game Center di setiap Mac. Pemain lapangan mengendalikan 3 pemain;\npemain kiper menjaga gawang. Jika ada yang keluar di tengah laga, AI menggantikan.",
        "lobby.noPlayers": "Tidak menemukan 3 pemain lain. Cari lagi atau batal.",
        "lobby.retry": "CARI LAGI",

        "gc.needSignIn": "Masuk ke Game Center",
        "gc.needSignInDetail": "Multipemain memerlukan Game Center. Buka Pengaturan Sistem › Game Center untuk masuk, lalu coba Cari Pertandingan lagi.",
        "alert.ok": "OKE",

        "pause.title": "JEDA",
        "pause.resume": "Lanjutkan",
        "pause.menu": "Kembali ke Menu Utama",

        "settings.title": "PENGATURAN",
        "settings.language": "BAHASA",
        "settings.audio": "AUDIO",
        "settings.textSize": "UKURAN TEKS",

        "profile.title": "PROFIL",
        "profile.stats": "STATISTIK",
        "profile.matches": "Total Pertandingan",
        "profile.winRate": "Persentase Menang",
        "profile.accuracy": "Akurasi Total",
        "profile.goals": "Total Gol",
        "profile.streak": "Rentetan Saat Ini",
        "profile.history": "RIWAYAT LAGA",
        "profile.achievements": "PENCAPAIAN",
        "profile.level": "Lv.",
        "profile.noMatches": "Belum ada pertandingan — ayo main!",

        "leaderboard.title": "PAPAN PERINGKAT",
        "leaderboard.rank": "PERINGKAT",
        "leaderboard.player": "PEMAIN",
        "leaderboard.bestGoal": "GOL TERBAIK",
        "leaderboard.accuracy": "AKURASI",
        "leaderboard.bestScore": "SKOR TERBAIK",
        "leaderboard.shotAcc": "AKURASI TEMBAKAN",
        "leaderboard.bestSaves": "PENYELAMATAN",
        "leaderboard.savePct": "% SAVE",
        "leaderboard.you": "Kamu",
        "leaderboard.loading": "Memuat papan peringkat Game Center…",
        "leaderboard.empty": "Belum ada skor. Mainkan pertandingan multiplayer untuk masuk papan!",
        "leaderboard.notAuth": "Masuk ke Game Center untuk melihat papan peringkat.",
        "leaderboard.error": "Gagal memuat papan peringkat. Pastikan ID leaderboard sudah diatur di App Store Connect.",
        "leaderboard.mpOnly": "Hanya pertandingan multiplayer.",

        "howto.title": "CARA BERMAIN",

        "results.fulltime": "PELUIT AKHIR",
        "results.penalties": "lewat adu penalti",
        "results.coach": "MINTA ANALISIS PELATIH",
        "results.coachWait": "Pelatihmu sedang meninjau pertandingan…",
        "results.back": "KEMBALI KE MENU",
        "results.stats": "STATISTIK LAGA",

        "common.back": "Kembali",
        "common.you": "KAMU",
        "common.ai": "AI",
    ]
}
