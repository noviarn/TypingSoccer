//
//  WorldCupTeams.swift
//  TypingSoccer
//
//  Selectable teams (9), each with its three star outfielders +
//  starting goalkeeper and their
//  EA FC 26 PACE rating (for keepers: the GK SPEED stat). Values marked
//  "est." could not be verified from fcratings.com and are close estimates.
//
//  Player order = [top lane, middle lane, bottom lane, goalkeeper].
//

import Foundation
import CoreGraphics

struct WCPlayer: Hashable {
    let name: String        // short display name (fits under the circle)
    let pace: Int           // FC 26 PAC (outfield) or GK SPEED (keepers)
}

struct WCTeam: Identifiable, Hashable {
    let id: String          // stable identifier, also the display name
    let players: [WCPlayer] // exactly 4: three outfielders + GK
    var name: String { id }
}

enum WorldCupTeams {

    // MARK: Pace → game speed mapping

    /// FC 26 pace (roughly 55–99 across these squads) → points/sec.
    /// 60 pace ≈ 100 (slow), 96 pace ≈ 154 (Mbappé). Baseline was 120.
    static func outfieldSpeed(pace: Int) -> CGFloat {
        let speed = 100 + CGFloat(pace - 60) * 1.5
        return min(160, max(95, speed))
    }

    /// GK SPEED stat (roughly 44–65) → points/sec, kept near the old 135
    /// keeper baseline since keepers mostly shuffle across the goal mouth.
    static func keeperSpeed(gkSpeed: Int) -> CGFloat {
        let speed = 90 + CGFloat(gkSpeed) * 0.8
        return min(150, max(115, speed))
    }

    // MARK: Teams (selectable roster — 9 teams)

    static let all: [WCTeam] = [
        WCTeam(id: "France", players: [
            WCPlayer(name: "Mbappé", pace: 96),
            WCPlayer(name: "Olise", pace: 78),
            WCPlayer(name: "Saliba", pace: 77),
            WCPlayer(name: "Maignan", pace: 64),
        ]),
        WCTeam(id: "Argentina", players: [
            WCPlayer(name: "J. Álvarez", pace: 82),   // est.
            WCPlayer(name: "Messi", pace: 78),        // est.
            WCPlayer(name: "Enzo F.", pace: 68),      // est.
            WCPlayer(name: "E. Martínez", pace: 48),  // est.
        ]),
        WCTeam(id: "Portugal", players: [
            WCPlayer(name: "Vitinha", pace: 77),      // est.
            WCPlayer(name: "Ronaldo", pace: 76),
            WCPlayer(name: "Bruno F.", pace: 72),     // est.
            WCPlayer(name: "D. Costa", pace: 55),     // est.
        ]),
        WCTeam(id: "England", players: [
            WCPlayer(name: "Saka", pace: 83),
            WCPlayer(name: "Bellingham", pace: 80),
            WCPlayer(name: "Kane", pace: 64),
            WCPlayer(name: "Pickford", pace: 53),
        ]),
        WCTeam(id: "Brazil", players: [
            WCPlayer(name: "Vini Jr.", pace: 93),
            WCPlayer(name: "Cunha", pace: 78),
            WCPlayer(name: "Guimarães", pace: 66),
            WCPlayer(name: "Alisson", pace: 56),
        ]),
        WCTeam(id: "Spain", players: [
            WCPlayer(name: "N. Williams", pace: 93),
            WCPlayer(name: "Yamal", pace: 86),
            WCPlayer(name: "Pedri", pace: 77),
            WCPlayer(name: "Simón", pace: 49),
        ]),
        WCTeam(id: "Morocco", players: [
            WCPlayer(name: "Hakimi", pace: 92),
            WCPlayer(name: "Brahim", pace: 81),
            WCPlayer(name: "Khannouss", pace: 75),    // est.
            WCPlayer(name: "Bounou", pace: 45),       // est.
        ]),
        WCTeam(id: "Netherlands", players: [
            WCPlayer(name: "Frimpong", pace: 94),     // est.
            WCPlayer(name: "Gakpo", pace: 84),        // est.
            WCPlayer(name: "F. de Jong", pace: 70),   // est.
            WCPlayer(name: "Verbruggen", pace: 50),   // est.
        ]),
        WCTeam(id: "Mexico", players: [
            WCPlayer(name: "Mora", pace: 80),         // est.
            WCPlayer(name: "Giménez", pace: 78),
            WCPlayer(name: "E. Álvarez", pace: 66),   // est.
            WCPlayer(name: "Rangel", pace: 50),       // est.
        ]),
    ]

    static func team(named name: String) -> WCTeam? {
        all.first { $0.id == name }
    }
}
