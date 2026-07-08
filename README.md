# Typing Soccer ⚽⌨️

A macOS SpriteKit prototype of a typing-driven soccer game. Type words fast to win
the ball, auto-run to goal, break through defenders with more words, and beat the
keeper with a final word to score. Built with **SpriteKit**, **GameKit**,
**MultipeerConnectivity**, and **Apple Foundation Models**.

> All art is placeholder (coloured discs, a white dot for the ball, vector pitch).
> Swap in real assets later — the code is structured so you only touch the node files.

## How to run

1. Open `TypingSoccer.xcodeproj` in Xcode 15+ (Foundation Models feedback needs the
   macOS 26 SDK / Xcode 26; it degrades gracefully to a written summary on older SDKs).
2. Select the **TypingSoccer** scheme and press **Run** (⌘R).
3. In the menu choose **Single Player** (vs AI) or **Multiplayer** (Host / Join).

Target: macOS 14+. Signing is set to **Automatic** — pick your team in
*Signing & Capabilities* the first time.

## Controls

Everything is the keyboard. When a word appears in the prompt bar, type it. Correct
letters turn green; wrong keys don't advance and count against your accuracy. First
side to finish the word wins that contest.

## Match flow (matches the design spec)

1. **Countdown + whistle** — 3‑2‑1, then a whistle blows.
2. **Kickoff word** — both teams "type" the same word; the first to finish gets the
   ball, which spawns to a random outfield player (never the keeper).
3. **Auto-run** — whoever has the ball automatically runs toward the enemy goal along
   its lane.
4. **Interception** — the opposing defender in that lane closes in. On contact a new
   word appears. Winner takes/keeps the ball.
5. **Slow penalty** — the player who loses a contest drops to **70% speed for 3s** and
   can't be involved in a new contest (collision off) until they recover.
6. **The shot** — reaching the penalty area triggers a final word vs the goalkeeper.
   Win → **goal**. Lose (slower / mistyped) → **miss**: the ball goes out and
   possession resets to the other side.
7. Repeat until full time; then a coach's note is generated from your stats.

Three lanes (top / middle / bottom), four players a side (3 outfield + 1 keeper).

## Modes

- **Single player** — the rival side is an AI (`AIOpponent.swift`) that "types" at a
  randomised words-per-second with occasional fumbles. Tune difficulty in
  `GameConfig.aiCharsPerSecondRange`.
- **Multiplayer** — `MultipeerManager.swift` connects two Macs on the same network via
  MultipeerConnectivity. One hosts, one joins; word-completion events are exchanged as
  peer messages. (Auto-accepts invitations for the prototype.)

## AI usage

- **In-game words**: local word bank in `WordProvider.swift` (easy/medium/hard buckets,
  harder near the goal). Fast and offline by design.
- **Post-match feedback**: `MatchFeedback.swift` uses Apple's on-device
  **Foundation Models** to turn your real match stats (WPM, accuracy, duels, goals)
  into a short coaching note. Falls back to a written summary when the model isn't
  available.

## Project layout

```
TypingSoccer/
  GameConfig.swift        – all tunable constants
  GameModels.swift        – Team / Lane / PlayerRole / GamePhase / PlayerStats
  WordProvider.swift      – local word bank (in-game words)
  TypingController.swift  – tracks the human's typing of the current word
  AIOpponent.swift        – simulated rival typing (single player)
  PlayerNode.swift        – dummy player sprite + movement + slow penalty
  BallNode.swift          – dummy ball sprite
  FieldBuilder.swift      – draws pitch, lanes, boxes, goals
  HUD.swift               – score, timer, countdown, word prompt
  GameScene.swift         – the match loop / all game rules
  MultipeerManager.swift  – MultipeerConnectivity transport (multiplayer)
  GameCenterManager.swift – GameKit auth + leaderboard submit
  MatchFeedback.swift     – Foundation Models post-match feedback
  GameView.swift          – SwiftUI menu + SpriteKit host + coordinator
  TypingSoccerApp.swift   – @main entry
```

## Where to plug in real assets

- Player art → `PlayerNode.makeBody()`
- Ball art → `BallNode.make()`
- Pitch art → `FieldBuilder.build()`
- Whistle / SFX → `Audio` enum at the bottom of `GameScene.swift`
  (currently uses built-in macOS system sounds)

## Known prototype limits

- Multiplayer syncs word-completion but keeps scoring local per client — add
  authoritative host scoring using the `PeerMessage.score` / `.goal` cases already
  defined.
- Game Center leaderboard ID (`com.typingsoccer.wpm`) is a placeholder; create the real
  one in App Store Connect.
