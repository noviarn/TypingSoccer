//
//  HowToPlayView.swift
//  TypingSoccer
//
//  Full game guide: modes, typing duels, movement, passing/chasing,
//  keeper role, offside, breaks and penalties. Localized EN/ID.
//

import SwiftUI

struct HowToPlayView: View {
    @EnvironmentObject var coordinator: GameCoordinator
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Text(L("howto.title"))
                    .font(.system(size: 30, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(red: 238/255, green: 170/255, blue: 82/255))
                HStack { BackButton(); Spacer() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                                .foregroundColor(.yellow)
                            Text(section.body)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 30)
            }
        }
    }

    private struct Section { let title: String; let body: String }

    private var sections: [Section] {
        settings.language == .indonesian ? indonesianSections : englishSections
    }

    private var englishSections: [Section] {
        [
            Section(title: "THE BASICS",
                    body: """
                    Typing Soccer is football decided by your keyboard. Every contest for the ball \
                    is a TYPING DUEL: a word appears at the bottom of the pitch, and whoever types it \
                    first wins the moment. Your progress shows in green; the rival's in orange below it. \
                    A wrong key doesn't advance the word — hit the right letter to continue. \
                    A match lasts two halves shown as a 0–90' clock, with added time, extra time and a \
                    penalty shootout if the score stays level.
                    """),
            Section(title: "GAME MODES",
                    body: """
                    SINGLE PLAYER — you control a full team (3 outfielders + goalkeeper) against the AI. \
                    Pick your nationality; the AI picks a different one.

                    MULTIPLAYER 2v2 — four players over Game Center. Each team has a FIELD player \
                    (controls the three outfielders) and a KEEPER player (controls the goalkeeper). \
                    Claim your seat in the lobby; the match starts when all four seats are filled. \
                    If someone quits mid-match, the AI takes over their seat and the game continues. \
                    Multiplayer results feed the Game Center leaderboards.
                    """),
            Section(title: "KICKOFF & OPEN PLAY",
                    body: """
                    After the countdown, a kickoff word decides who starts with the ball. The ball \
                    carrier runs toward the enemy goal automatically. When a defender gets close, an \
                    INTERCEPTION duel starts — the winner keeps or steals the ball, the loser is \
                    slowed for a few seconds. Players have ENERGY: running drains it, resting refills \
                    it, and tired players run slower. Breaks restore a chunk.
                    """),
            Section(title: "KEYS & FORMATIONS",
                    body: """
                    1 · 2 · 3 — attacking: pass to that lane's teammate. Defending (field player): \
                    choose which outfielder chases the ball carrier.
                    ← / → — cycle your formation (1-2, 2-1, 3-0, 0-3, 1-1-1). Changes made during \
                    live play apply at the next restart.
                    Letters — type the duel word. Only the player whose unit is in the duel types.
                    """),
            Section(title: "SHOOTING & THE KEEPER",
                    body: """
                    Reach the penalty area and the FINAL BATTLE begins: a long word against the \
                    goalkeeper. Beat the keeper to score — but one mistyped letter and the shot \
                    sails wide instantly. If the keeper wins, the save is made and the keeper must \
                    distribute with 1·2·3. In 2v2, the keeper player types these duels.
                    """),
            Section(title: "OFFSIDE & FREE KICKS",
                    body: """
                    A live offside line tracks the last defender. Passing to a teammate beyond it \
                    is offside: whistle, white line, and a free kick for the defenders. The taker \
                    must pass before dribbling.
                    """),
            Section(title: "EXTRA TIME & PENALTIES",
                    body: """
                    Level after 90'? Two extra-time halves. Still level? Penalty shootout: three \
                    kicks each, then sudden death. Each kick is a typing battle — a mistyped \
                    penalty is only revealed at the moment of the kick.
                    """),
            Section(title: "PAUSE (VS AI)",
                    body: """
                    In single player, click the pause button in the top-left corner to freeze the \
                    match. Resume, or go back to the main menu. Multiplayer can't be paused.
                    """),
            Section(title: "PROFILE & LEADERBOARDS",
                    body: """
                    Every match (both modes) feeds your PROFILE: level & XP, win rate, accuracy, \
                    goals, streak, history and achievements. Multiplayer matches also push your \
                    bests to the Game Center LEADERBOARDS: best goals in a match, overall typing \
                    accuracy, best single-game score, shot accuracy from the penalty area, most \
                    saves in a match, and save percentage as a keeper.
                    """),
        ]
    }

    private var indonesianSections: [Section] {
        [
            Section(title: "DASAR PERMAINAN",
                    body: """
                    Typing Soccer adalah sepak bola yang ditentukan lewat keyboard. Setiap perebutan \
                    bola adalah DUEL MENGETIK: sebuah kata muncul di bawah lapangan, dan siapa pun yang \
                    selesai mengetik duluan memenangkan momen itu. Progresmu tampil hijau; lawan tampil \
                    oranye di bawahnya. Tombol salah tidak memajukan kata — tekan huruf yang benar untuk \
                    lanjut. Pertandingan berlangsung dua babak dengan jam 0–90', plus injury time, \
                    perpanjangan waktu, dan adu penalti jika skor tetap imbang.
                    """),
            Section(title: "MODE PERMAINAN",
                    body: """
                    PEMAIN TUNGGAL — kamu mengendalikan satu tim penuh (3 pemain + kiper) melawan AI. \
                    Pilih negaramu; AI memilih negara lain.

                    MULTIPLAYER 2v2 — empat pemain lewat Game Center. Tiap tim punya pemain LAPANGAN \
                    (mengendalikan tiga pemain depan) dan pemain KIPER (mengendalikan penjaga gawang). \
                    Pilih kursimu di lobi; pertandingan mulai saat keempat kursi terisi. Jika ada yang \
                    keluar di tengah laga, AI menggantikan kursinya dan permainan berlanjut. Hasil \
                    multiplayer masuk ke papan peringkat Game Center.
                    """),
            Section(title: "KICKOFF & PERMAINAN TERBUKA",
                    body: """
                    Setelah hitung mundur, kata kickoff menentukan siapa memegang bola. Pembawa bola \
                    berlari otomatis ke gawang lawan. Saat bek mendekat, duel INTERSEP dimulai — \
                    pemenang menguasai bola, yang kalah melambat beberapa detik. Pemain punya ENERGI: \
                    berlari menguras, diam memulihkan, dan pemain lelah berlari lebih lambat.
                    """),
            Section(title: "TOMBOL & FORMASI",
                    body: """
                    1 · 2 · 3 — menyerang: oper ke rekan di jalur itu. Bertahan (pemain lapangan): \
                    pilih pemain mana yang mengejar pembawa bola.
                    ← / → — ganti formasi (1-2, 2-1, 3-0, 0-3, 1-1-1). Perubahan saat bola hidup \
                    berlaku pada restart berikutnya.
                    Huruf — ketik kata duel. Hanya pemain yang unitnya terlibat duel yang mengetik.
                    """),
            Section(title: "MENEMBAK & KIPER",
                    body: """
                    Capai kotak penalti dan PERTARUNGAN FINAL dimulai: kata panjang melawan kiper. \
                    Kalahkan kiper untuk mencetak gol — tapi satu huruf salah dan tembakan langsung \
                    melenceng. Jika kiper menang, bola diselamatkan dan kiper harus mengoper dengan \
                    1·2·3. Di 2v2, pemain kiper yang mengetik duel ini.
                    """),
            Section(title: "OFFSIDE & TENDANGAN BEBAS",
                    body: """
                    Garis offside mengikuti bek terakhir. Mengoper ke rekan di belakang garis itu \
                    berarti offside: peluit, garis putih, dan tendangan bebas untuk tim bertahan. \
                    Pengambil harus mengoper dulu sebelum menggiring.
                    """),
            Section(title: "PERPANJANGAN & PENALTI",
                    body: """
                    Imbang setelah 90'? Dua babak perpanjangan. Masih imbang? Adu penalti: tiga \
                    tendangan tiap tim, lalu sudden death. Tiap tendangan adalah duel mengetik — \
                    kesalahan ketik pada penalti baru terungkap saat bola ditendang.
                    """),
            Section(title: "JEDA (VS AI)",
                    body: """
                    Di pemain tunggal, klik tombol jeda di pojok kiri atas untuk membekukan laga. \
                    Lanjutkan, atau kembali ke menu utama. Multiplayer tidak bisa dijeda.
                    """),
            Section(title: "PROFIL & PAPAN PERINGKAT",
                    body: """
                    Setiap laga (kedua mode) mengisi PROFILmu: level & XP, persentase menang, akurasi, \
                    gol, rentetan, riwayat dan pencapaian. Laga multiplayer juga mengirim rekor \
                    terbaikmu ke PAPAN PERINGKAT Game Center: gol terbanyak dalam satu laga, akurasi \
                    mengetik keseluruhan, skor terbaik satu game, akurasi tembakan dari kotak penalti, \
                    penyelamatan terbanyak dalam satu laga, dan persentase penyelamatan sebagai kiper.
                    """),
        ]
    }
}
