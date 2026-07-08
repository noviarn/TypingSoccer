//
//  GameConfig.swift
//  TypingSoccer
//
//  Central place for all tunable gameplay constants.
//  Tweak these to change feel without touching the game logic.
//

import Foundation
import CoreGraphics

enum GameConfig {

    // MARK: Scene
    static let sceneSize = CGSize(width: 1280, height: 720)

    // MARK: Field layout
    static let fieldInset: CGFloat = 60          // margin around the pitch
    static let hudHeight: CGFloat = 90           // reserved strip at the top for score/timer
    /// Horizontal x for each goal line (inside the field).
    static let leftGoalX: CGFloat = fieldInset + 20
    static let rightGoalX: CGFloat = sceneSize.width - fieldInset - 20
    /// Penalty area depth from each goal line.
    static let penaltyDepth: CGFloat = 150
    /// How far the goalkeeper stands out in front of its own goal line
    /// (toward the penalty line). Larger = further out from the post.
    static let keeperStandoff: CGFloat = 95

    // MARK: Teams / players
    static let playersPerTeam = 4                // 3 outfield + 1 goalkeeper
    static let outfieldPerTeam = 3               // one per lane

    // MARK: Movement (points per second)
    static let baseCarrierSpeed: CGFloat = 120
    static let baseDefenderSpeed: CGFloat = 135  // defenders slightly faster so they can close in
    static let slowMultiplier: CGFloat = 0.70    // -30% after losing a duel
    static let ballCarryMultiplier: CGFloat = 0.80 // a player slows to 80% while carrying the ball
    static let slowDuration: TimeInterval = 3.0  // recovery time
    static let duelTriggerDistance: CGFloat = 38 // how close players must get to collide / start a duel
    /// Minimum time a defender commits to a target before it may switch to a
    /// different opponent (prevents jittery "stuck in the middle" behaviour).
    static let defenderSwitchDelay: TimeInterval = 1.0

    // MARK: Energy
    /// Stamina pool per player. Drains while running (more while carrying the
    /// ball), regenerates while standing still or during stoppages/duels.
    static let energyMax: CGFloat = 100
    static let energyDrainPerSecond: CGFloat = 2
    static let energyCarrierDrainPerSecond: CGFloat = 3
    static let energyRegenPerSecond: CGFloat = 6
    /// Speed factor at 0 energy (linear up to 1.0 at full energy).
    static let energyMinSpeedFactor: CGFloat = 0.5
    /// Energy is NOT reset between rounds — it lasts the whole match. Only a
    /// half-time / extra-time break restores this small amount per player.
    static let energyBreakRestore: CGFloat = 30

    // MARK: Timing
    static let countdownSeconds = 3
    /// Pre-match window (seconds) to choose a starting formation.
    static let strategyPickSeconds = 5
    /// Real match length in seconds (2 minutes), displayed as a 0–90' clock.
    static let matchLengthSeconds: TimeInterval = 120
    /// Displayed football minutes across the whole match.
    static let displayMatchMinutes: Double = 90

    // MARK: Extra time / penalties
    /// Each extra-time half shows as 15 football minutes (played at the same
    /// real-time scale as the regular match, i.e. ~20 real seconds per half).
    static let etDisplayMinutesPerHalf: Double = 15
    static var etHalfLengthSeconds: TimeInterval {
        matchLengthSeconds / displayMatchMinutes * etDisplayMinutesPerHalf
    }
    /// Real seconds of stoppage before a half/match is forced to end.
    /// Regular time shows up to +5, extra time is capped at +3.
    static let addedTimeCutoffRegular: TimeInterval = 10
    static let addedTimeCutoffExtra: TimeInterval = 6
    static let addedTimeCapRegular: Double = 5
    static let addedTimeCapExtra: Double = 3
    /// Penalty shootout: kicks per side before sudden death. 3 = every
    /// outfielder gets one; the goalkeeper is the 4th kicker (sudden death),
    /// then the order loops back to the first taker.
    static let penaltyKicksPerSide = 3
    /// Run-up: the shooter starts this far behind the ball and runs in
    /// before the kick.
    static let penaltyRunUpDistance: CGFloat = 70
    static let penaltyRunUpDuration: TimeInterval = 0.45
    /// How long the ball takes to travel on a pass.
    static let passTravelDuration: TimeInterval = 0.5
    /// Delay before the carrier passes to an off-ball runner who has got
    /// closer to the enemy goal.
    static let passDelay: TimeInterval = 0.8
    /// A goalkeeper's catch pulls the ball in faster than a normal pass.
    static let keeperCatchDuration: TimeInterval = 0.16
    /// Grace period an attacker may sit in an offside position before being
    /// forced to retreat level with the last defender.
    static let offsideGraceSeconds: TimeInterval = 1.0
    /// Once flagged, an offside runner jogs back toward its own goal this long.
    static let offsideRetreatSeconds: TimeInterval = 0.5
    /// After retreating, the runner must be onside this long before it may
    /// resume its run toward the goal.
    static let offsideOnsideResetSeconds: TimeInterval = 0.2

    // MARK: Typing / AI
    /// Simulated opponent typing speed range in characters-per-second.
    /// Higher = tougher AI. Randomised each duel for variety.
    static let aiCharsPerSecondRange: ClosedRange<Double> = 2.5...3.5
    /// Chance the AI "fumbles" and pauses briefly, giving the human a chance.
    static let aiFumbleChance: Double = 0.15
    /// Chance the AI "mistypes" its final shot word — the shot sails wide even
    /// if it out-typed the keeper (mirrors the human's mistype-miss rule).
    static let aiShotMissChance: Double = 0.18

    // MARK: Visuals
    static let playerRadius: CGFloat = 18
    static let ballRadius: CGFloat = 9
}
