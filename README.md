# Typing Soccer ⚽⌨️

A macOS SpriteKit prototype of a typing-driven soccer game. Type words fast to win
the ball, auto-run to goal, break through defenders with more words, and beat the
keeper with a final word to score. Built with **SpriteKit**, **GameKit**
(auth, real-time 2v2 multiplayer, leaderboards), and **Apple Foundation Models**.

> All art is placeholder (coloured discs, a white dot for the ball, vector pitch).
> Swap in real assets later — the code is structured so you only touch the node files.

## How to run

1. Open `TypingSoccer.xcodeproj` in Xcode 15+ (Foundation Models feedback needs the
   macOS 26 SDK / Xcode 26; it degrades gracefully to a written summary on older SDKs).
2. Select the **TypingSoccer** scheme and press **Run** (⌘R).
3. In the menu choose **Single Player** (vs AI) or **Multiplayer 2v2** (Game Center).

Target: macOS 14+. Signing is set to **Automatic** — pick your team in
*Signing & Capabilities* the first time.

## Screens

- **Main menu** — Single player, Multiplayer 2v2, How To Play; top bar has the
  player chip (→ Profile), trophy (→ Leaderboards) and gear (→ Settings).
- **Profile** — level & XP, career stats across both modes (matches, win rate,
  accuracy, goals, streak), recent match history, achievements. Persisted locally.
- **Leaderboards** — Game Center boards, multiplayer matches only: Rank, Player,
  Best Goal, Accuracy, Best Score, Shot Accuracy, Best Saves, Save %.
- **Settings** — language (English / Bahasa Indonesia), audio volume, text size
  (scales the in-game word prompt + HUD). Persisted in UserDefaults.
- **How To Play** — full game guide, localized EN/ID.
- **Pause (vs AI only)** — pause button in the top-left corner of the pitch:
  Resume / Back To Main Menu. Multiplayer can't be paused.

## Controls

Everything is the keyboard. When a word appears in the prompt bar, type it. Correct
letters turn green; wrong keys don't advance and count against your accuracy. First
side to finish the word wins that contest. `1·2·3` pass (attacking) or pick the
chaser (defending); `←/→` cycle formations.

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
7. Repeat until full time (added time, extra time and penalties if level); then a
   coach's note can be generated from your stats.

Three lanes (top / middle / bottom), four players a side (3 outfield + 1 keeper).

## Modes

- **Single player** — the rival side is an AI (`AIOpponent.swift`) that "types" at a
  randomised words-per-second with occasional fumbles. Tune difficulty in
  `GameConfig.aiCharsPerSecondRange`. Pausable from the top-left button.
- **Multiplayer 2v2** — `GameKitMatchManager.swift` automatches **four players over
  Game Center** (GKMatchmaker → GKMatch). Each team has a FIELD player (3 outfielders)
  and a KEEPER player. The host is elected deterministically (lowest `gamePlayerID`)
  and owns the authoritative simulation; the same seat/`PeerMessage` protocol as the
  old Multipeer build runs over `GKMatch`.
  **If a player quits mid-match, the AI takes over their seat and the match continues**
  (only the host leaving ends it, since the host owns the sim).

## Game Center setup (App Store Connect)

Multiplayer and the leaderboards need Game Center enabled for the app's bundle ID:

1. App Store Connect → your app → **Game Center**: enable **Multiplayer**
   (real-time, 4 players).
2. Create six **Classic** integer leaderboards ("best score wins") with these IDs
   (see `GameCenterManager.Board`):
   - `com.typingsoccer.bestscore` — best single-game score (the ranking column)
   - `com.typingsoccer.bestgoal` — most goals in one match
   - `com.typingsoccer.accuracy` — overall typing accuracy (basis points: 9820 = 98.20%)
   - `com.typingsoccer.shotaccuracy` — penalty-area shot accuracy (basis points)
   - `com.typingsoccer.bestsaves` — most saves in one match
   - `com.typingsoccer.savepct` — save percentage as keeper (basis points)
3. Sign in to Game Center on every test Mac (Sandbox accounts while in development).

For local testing without four Macs, temporarily drop
`GameKitMatchManager.requiredPlayers` (and the GKMatchRequest min/max) to 2.

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
  GameConfig.swift         – all tunable constants
  GameModels.swift         – Team / Lane / GamePhase / PlayerStats (+ shots, saves, combo, score)
  WordProvider.swift       – local word bank (in-game words)
  TypingController.swift   – tracks the human's typing of the current word
  AIOpponent.swift         – simulated rival typing (single player + seat takeover)
  PlayerNode.swift         – dummy player sprite + movement + slow penalty
  BallNode.swift           – dummy ball sprite
  FieldBuilder.swift       – draws pitch, lanes, boxes, goals
  HUD.swift                – score, timer, countdown, word prompt (text-size aware)
  GameScene.swift          – the match loop / all game rules / pause / AI takeover
  GameKitMatchManager.swift– GameKit real-time 2v2 transport + host election
  GameCenterManager.swift  – GameKit auth + 6 leaderboards (submit & fetch)
  PlayerProfileStore.swift – persistent profile, history, XP, achievements
  SettingsStore.swift      – language / audio / text-size + EN-ID localization
  MatchFeedback.swift      – Foundation Models post-match feedback
  GameView.swift           – SwiftUI menu + SpriteKit host + coordinator + pause overlay
  ProfileView.swift        – profile screen
  LeaderboardView.swift    – Game Center leaderboard screen
  SettingsView.swift       – settings screen
  HowToPlayView.swift      – how-to-play guide (EN/ID)
  TypingSoccerApp.swift    – @main entry + texture preloading
```

## Performance notes

- Textures are preloaded to the GPU at launch (`AssetPreloader` — add new asset
  names there as art lands).
- System sounds are cached once and volume-controlled from Settings.
- SKLabelNode / SKShapeNode updates are change-guarded (labels only re-rasterize
  when text actually changes; the offside line slides instead of rebuilding its path).
- Rosters are cached once per match; the update loop avoids per-frame allocations.

## Where to plug in real assets

- Player art → `PlayerNode.makeBody()`
- Ball art → `BallNode.make()`
- Pitch art → `FieldBuilder.build()`
- Whistle / SFX → `Audio` enum at the bottom of `GameScene.swift`
  (currently uses built-in macOS system sounds; respects the Settings volume)

## Known prototype limits

- The Leaderboard screen is empty until the six leaderboard IDs exist in
  App Store Connect and at least one multiplayer match has been reported.
- Achievements are local (profile store), not Game Center achievements.
- In-game SpriteKit text (GOAL!, SAVED!, …) stays in English; all SwiftUI
  screens are localized EN/ID.
