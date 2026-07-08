# Typing Soccer — Technical Design Document (TDD)

**Version:** 1.0 (prototype)
**Language:** Swift 5
**Target:** macOS 14+ (Xcode 15+; Foundation Models feedback needs the macOS 26 SDK)
**App type:** SwiftUI app hosting a SpriteKit scene

> **Status legend used throughout this document**
> ✅ implemented and working · 🎨 placeholder art (logic done, real assets to be added) ·
> 🚧 placeholder / **not implemented yet** · ⚠️ works with a caveat or dependency.

### Implementation status at a glance

All **gameplay logic is implemented** (kickoff, duels, shots, offside, formations,
stamina, halftime, extra time, penalty shootout, single-player AI, and 2v2
networking). The outstanding items are production polish rather than mechanics:

| Area | Status | Note |
|------|--------|------|
| Player / ball / pitch art | 🎨 placeholder | Coloured discs, a white dot, a vector pitch — swap in real assets later |
| Sound effects | 🎨 placeholder | Uses built-in macOS system sounds (`Audio` enum in `GameScene.swift`) |
| Game Center leaderboard | 🚧 not wired to a real board | Code submits scores, but the ID `com.typingsoccer.wpm` is a placeholder; create the real one in App Store Connect |
| Post-match AI coach note | ⚠️ conditional | Needs the macOS 26 SDK / Foundation Models; falls back to a written summary otherwise |
| Multiplayer stamina sync | 🚧 not implemented | Stamina is single-player only; not synced across peers |
| Multiplayer position accuracy | ⚠️ known limit | Machines animate movement locally between synced events; re-align on possession change |

---

## 1. Frameworks and Methods Used

Typing Soccer is built entirely on **first-party Apple frameworks** — no third-party
dependencies. Each framework owns one clearly separated concern.

| Framework | Role in the game | Key file(s) |
|-----------|------------------|-------------|
| **SwiftUI** | App entry, menus, lobby, results screen, and the container that hosts the game | `TypingSoccerApp.swift`, `GameView.swift` |
| **SpriteKit** | The match itself: rendering the pitch, players and ball, plus the per-frame game loop that drives all rules | `GameScene.swift`, `FieldBuilder.swift`, `PlayerNode.swift`, `BallNode.swift`, `HUD.swift` |
| **GameKit (Game Center)** | Player authentication and leaderboard score submission (typing WPM) | `GameCenterManager.swift` |
| **MultipeerConnectivity** | 2v2 networking transport — discovery, connection and message passing between four Macs on a local network | `MultipeerManager.swift` |
| **Foundation Models** | On-device LLM that turns real match stats into a short coaching note after full time | `MatchFeedback.swift` |
| **Foundation / CoreGraphics** | Value types, geometry, tunable constants | `GameModels.swift`, `GameConfig.swift`, `WordProvider.swift`, `TypingController.swift`, `AIOpponent.swift` |

### Key patterns and methods

- **`@main` App + `WindowGroup`** (SwiftUI) — the entry point in
  `TypingSoccerApp.swift` authenticates Game Center on launch and shows `ContentView`.
- **Coordinator (`ObservableObject`) pattern** — `GameCoordinator` in
  `GameView.swift` is the single source of truth that ties SwiftUI, SpriteKit,
  Multipeer, GameKit and Foundation Models together. SwiftUI views observe its
  `@Published` properties (current `screen`, lobby seats, scores, feedback text).
- **`NSViewRepresentable` host** — SwiftUI embeds the SpriteKit `GameScene` via a
  custom `SpriteHostView: NSViewRepresentable` that wraps an `SKView` (done this way
  so the game can control first-responder / keyboard focus).
- **Finite State Machine** — the whole match is driven by a `GamePhase` enum
  (`strategyPick → countdown → kickoff → running → duel → goalScored → halftime →
  finished`), advanced each frame inside SpriteKit's `update(_:)`.
- **Delegate protocols** — `GameScene` talks back to the coordinator through a
  delegate (match finished, word completed, formation changed, peer send) so the
  scene stays decoupled from networking/UI.
- **`Codable` message passing** — multiplayer state is serialised as `PeerMessage`
  values and sent over the Multipeer session; the host is authoritative.
- **Async/await** — `MatchFeedback.generate(...)` is an `async` call to the
  on-device model, awaited when the results screen appears.
- **Configuration-as-constants** — `GameConfig` centralises every tunable number
  (speeds, timings, energy, AI difficulty) so behaviour can be tuned without
  touching logic.

---

## 2. How the Frameworks Work (in this game)

### 2.1 SwiftUI — shell, menus, and coordinator

SwiftUI provides the **app lifecycle and all non-gameplay screens**. `@main
TypingSoccerApp` builds a single resizable window and injects a shared
`GameCoordinator` into the environment. Views (`menu`, `lobby`, `results`) read the
coordinator's `@Published` state and re-render automatically when it changes — the
standard reactive SwiftUI data-flow.

The coordinator is the hub: it starts single-player or multiplayer matches, owns the
`MultipeerManager`, holds the live `GameScene`, tracks lobby seats and team picks,
and receives the final stats/score to show on the results screen. This keeps every
framework's touch-point in one place instead of scattered through the views.

### 2.2 SpriteKit — the match engine

The match runs as a **`GameScene: SKScene`**. SpriteKit gives three things:

1. **A scene graph** — the pitch, lanes, goals and boxes (`FieldBuilder`), the
   player discs (`PlayerNode`), the ball (`BallNode`) and the HUD (`HUD`) are all
   `SKNode`s positioned in a fixed 1280×720 scene.
2. **A per-frame game loop** — `override func update(_ currentTime:)` is called
   every frame. It computes a delta-time and switches on the current `GamePhase` to
   advance exactly the right subsystem: run the countdown, tick the current duel,
   move the carrier and defenders, drain stamina, check offside, or do nothing
   during a stoppage. **This is where all game rules live.**
3. **Actions and physics helpers** — movement, passes, run-ups, celebrations and
   the ball's travel are expressed as `SKAction` sequences and simple vector math
   (points-per-second speeds from `GameConfig`).

Player movement is **rule-driven, not user-steered**: the loop moves the carrier
toward the enemy goal along its lane and moves the lane defender to intercept, then
starts a duel when they collide. Keyboard input never moves a sprite directly — it
only feeds the typing controller and (in multiplayer) picks runners.

### 2.3 The typing sub-system

Two small classes model the contest:

- **`TypingController`** tracks the human's progress on the current word. Each typed
  character is validated against the expected next letter: a correct key advances
  (`typedCount++`), a wrong key is recorded as a `mistake` and does **not** advance.
  It exposes `progress`, `typedPrefix`/`remaining` for the HUD, and timing for stats.
- **`AIOpponent`** (single player) simulates the rival "typing" the same word. On
  `begin(word:skill:)` it computes a finish time up front from a randomised
  characters-per-second rate (scaled by skill, with jitter and an occasional
  fumble), then counts down in `update(deltaTime:)`. Whoever's completion fires
  first wins the duel.

`WordProvider` supplies the words from a **local, offline bank** bucketed easy /
medium / hard, biased harder near goal, with a dedicated long-word pool for the
shot. Words are intentionally local so duels are instant and never wait on a network
or model.

### 2.4 GameKit (Game Center)

`GameCenterManager` is a thin singleton. On launch it sets
`GKLocalPlayer.local.authenticateHandler` so the system presents sign-in when
needed. After a match it calls `GKLeaderboard.submitScore(...)` with the player's
average WPM against a leaderboard ID (currently the placeholder
`com.typingsoccer.wpm`). Auth state is published so the UI can react.

### 2.5 MultipeerConnectivity (2v2 networking)

`MultipeerManager` wraps an `MCSession` plus advertiser/browser to connect four
Macs on the same local network. One machine **hosts** (advertises), the others
**join** (browse). Game state travels as `Codable` **`PeerMessage`** values.

The design is **host-authoritative**: only the host picks duel words, resolves
winners, and decides possession, passes, offside, breaks, extra time and penalties,
broadcasting each decision. Joiners **mirror** those events (flipping teams to their
own perspective) and send back only their **seat-tagged inputs** — live typing
progress, word completions, pass/chase requests, shot mistypes. This avoids
divergent simulations for outcomes, though each machine still animates its own
player motion between synced events (positions re-align on every possession change).

### 2.6 Foundation Models (post-match coach)

`MatchFeedback.generate(...)` runs Apple's **on-device** language model. It builds a
short instruction ("upbeat typing coach, 2–3 sentences, under 60 words") plus the
player's real stats (result, WPM, accuracy, fastest word, duels, goals) and awaits a
response. It degrades gracefully:

```
#if canImport(FoundationModels)      // SDK present?
  if #available(macOS 26.0, …)       // OS new enough?
    switch model.availability {
      case .available: → run the model
      default:         → written fallback summary
    }
  else → fallback
#else → fallback                     // built on older SDK
```

So on any machine without the model the player still gets a sensible written note;
where the model exists they get a personalised one — all **without leaving the
device**.

---

## 3. File & Screen Flow

### 3.1 Screen flow (what the player moves through)

The coordinator's `Screen` enum defines four screens: **menu → lobby → playing →
results**. Single player skips the lobby.

```
                        ┌──────────────────────────────────────────┐
                        │                                          │
   launch               │  SINGLE PLAYER                           │
     │                  │  (pick teams, press Play)                │
     ▼                  ▼                                          │
 ┌────────┐   Single  ┌──────────┐                                 │
 │  MENU  │──────────►│ PLAYING  │─ full time ─► ┌──────────┐      │
 │        │           │(GameScene)│              │ RESULTS  │──────┘
 │        │           └──────────┘               │ + coach  │  Play again
 │        │ Multiplayer   ▲                       └──────────┘
 │        │──────┐        │ all seats filled
 └────────┘      ▼        │
             ┌────────┐   │
             │ LOBBY  │───┘
             │ host / │
             │  join  │
             └────────┘
```

- **Menu** — choose Single Player or Multiplayer; pick World Cup teams / formation.
- **Lobby** (multiplayer only) — host advertises, joiners claim seats (field /
  keeper per side); match auto-starts when all four seats fill.
- **Playing** — the SpriteKit `GameScene` runs the full match state machine.
- **Results** — final score, your stats, and the AI coach's note; option to return
  to menu / play again.

### 3.2 In-match phase flow (inside GameScene)

The `GamePhase` state machine, advanced each frame in `update(_:)`:

```
 strategyPick ─► countdown ─► kickoff ─► running ─► duel ─┬─(win, at box)─► shot ─► goalScored
   (pick          (3-2-1        (first     (auto-run   (word)│                          │
   formation)     whistle)      word)      + defenders)      └─(interception win/loss)──┘
                                                                                         │
                                              ┌── halftime (45') ◄──────────────────────┘
                                              │
                                              └── full time ─► [extra time ─► penalties] ─► finished
```

### 3.3 File-by-file responsibilities (source order of control)

| File | Responsibility | Status |
|------|----------------|--------|
| `TypingSoccerApp.swift` | `@main` entry; authenticates Game Center; shows `ContentView` | ✅ Implemented |
| `GameView.swift` | SwiftUI menu / lobby / results + `GameCoordinator` (the hub) + `SKView` host (`SpriteHostView`); bridges Multipeer, GameKit, Foundation Models | ✅ Implemented |
| `GameScene.swift` | The match: `GamePhase` state machine, per-frame update loop, **all** game rules (kickoff, run, duels, shots, offside, formations, stamina, halftime, extra time, penalties) | ✅ Implemented |
| `GameConfig.swift` | All tunable constants (sizes, speeds, timings, energy, AI) | ✅ Implemented |
| `GameModels.swift` | Value types: `Team`, `Lane`, `PlayerRole`, `GamePhase`, `DuelKind`, `Formation`, `MatchMode`, `PlayerStats` (WPM/accuracy math) | ✅ Implemented |
| `WordProvider.swift` | Local word bank (easy / medium / hard + long shot words) | ✅ Implemented |
| `TypingController.swift` | Tracks the human's typing of the current word | ✅ Implemented |
| `AIOpponent.swift` | Simulated rival typing (single player) | ✅ Implemented |
| `PlayerNode.swift` | Player sprite + movement + slow penalty + stamina | ✅ Implemented · 🎨 art is placeholder (coloured disc) |
| `BallNode.swift` | Ball sprite | ✅ Implemented · 🎨 art is placeholder (white dot) |
| `FieldBuilder.swift` | Draws pitch, lanes, penalty boxes, goals | ✅ Implemented · 🎨 vector placeholder pitch |
| `HUD.swift` | Score, timer, countdown, word prompt bar | ✅ Implemented |
| `MultipeerManager.swift` | MultipeerConnectivity transport (host-authoritative 2v2) | ✅ Implemented · ⚠️ positions can drift; stamina not synced |
| `GameCenterManager.swift` | GameKit auth + WPM leaderboard submit | ✅ Code works · 🚧 leaderboard ID is a placeholder |
| `MatchFeedback.swift` | Foundation Models post-match coaching note (+ written fallback) | ⚠️ Needs macOS 26 SDK; falls back to a written note otherwise |
| `WorldCupTeams.swift` | National team data (names / colours) for team selection | ✅ Implemented |

**Legend:** ✅ implemented and working · 🎨 placeholder art (logic done, real assets to be added) · 🚧 placeholder / not implemented yet · ⚠️ works with a caveat or dependency.

### 3.4 Control & data flow at a glance

1. **Input** → keystrokes reach `GameScene`, which feeds `TypingController`
   (and, single player, races it against `AIOpponent`).
2. **Simulation** → `GameScene.update(_:)` advances the `GamePhase`, moves nodes,
   resolves duels, updates the `HUD` and per-player `PlayerStats`.
3. **Networking** (multiplayer) → the host resolves outcomes and broadcasts
   `PeerMessage`s via `MultipeerManager`; joiners mirror them and return inputs.
4. **Callbacks** → on match end `GameScene` notifies `GameCoordinator`, which
   submits the WPM to `GameCenterManager` and awaits `MatchFeedback`.
5. **Output** → SwiftUI's **results** screen renders the score, stats and coach's
   note.

### 3.5 Where to plug in real assets

The prototype uses placeholder art, isolated so swapping assets touches only the
node/builder files: players → `PlayerNode.makeBody()`, ball → `BallNode.make()`,
pitch → `FieldBuilder.build()`, and SFX → the `Audio` enum at the bottom of
`GameScene.swift` (currently built-in macOS system sounds).

---

## 4. Build & Configuration Notes

- Open `TypingSoccer.xcodeproj` in **Xcode 15+**; select the **TypingSoccer**
  scheme and Run (⌘R). Signing is **Automatic** — pick your team in *Signing &
  Capabilities* on first run.
- **Foundation Models** requires the macOS 26 SDK / Xcode 26; on older toolchains
  the post-match note degrades to a written summary automatically.
- The Game Center leaderboard ID `com.typingsoccer.wpm` is a **placeholder** —
  create the real one in App Store Connect before shipping.
- **Known limits:** multiplayer positions can drift slightly between synced events
  (re-align on possession change); stamina is single-player only.
