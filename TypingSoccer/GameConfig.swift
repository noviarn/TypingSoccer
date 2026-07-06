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

    // MARK: Teams / players
    static let playersPerTeam = 4                // 3 outfield + 1 goalkeeper
    static let outfieldPerTeam = 3               // one per lane

    // MARK: Movement (points per second)
    static let baseCarrierSpeed: CGFloat = 120
    static let baseDefenderSpeed: CGFloat = 135  // defenders slightly faster so they can close in
    static let slowMultiplier: CGFloat = 0.70    // -30% after losing a duel
    static let slowDuration: TimeInterval = 3.0  // recovery time
    static let duelTriggerDistance: CGFloat = 70 // how close a defender must get to start a duel

    // MARK: Timing
    static let countdownSeconds = 3
    static let matchLengthSeconds: TimeInterval = 90

    // MARK: Typing / AI
    /// Simulated opponent typing speed range in characters-per-second.
    /// Higher = tougher AI. Randomised each duel for variety.
    static let aiCharsPerSecondRange: ClosedRange<Double> = 2.5...3.5
    /// Chance the AI "fumbles" and pauses briefly, giving the human a chance.
    static let aiFumbleChance: Double = 0.15

    // MARK: Visuals
    static let playerRadius: CGFloat = 18
    static let ballRadius: CGFloat = 9
}
