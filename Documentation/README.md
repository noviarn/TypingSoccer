# Typing Soccer — Documentation ⚽⌨️

This folder holds the design and technical documentation for **Typing Soccer**, a
macOS SpriteKit prototype where you win a football match by **typing words faster and
more accurately than your opponent**. Players run themselves; your keyboard is the
ball's engine.

## What's in this folder

| File | What it covers |
|------|----------------|
| **[Game-Design-Document.md](./Game-Design-Document.md)** | The design: the **core loop** (objective, challenge, reward), the intended **core experience**, and the full **game rules** in detail. |
| **[Technical-Design-Document.md](./Technical-Design-Document.md)** | The build: the **frameworks/methods** used, **how each framework works** in this game, and the **file & screen flow**. |
| **README.md** | This file — an index and quick orientation. |

## The game in 30 seconds

Every contested moment on the pitch is a **typing duel**: both sides type the same
word and the first to finish wins. Win the kickoff to get the ball, auto-run toward
goal, out-type defenders who intercept you, then beat the goalkeeper with a long word
to **score**. A match is 2 real minutes shown as a 0–90' clock, with half time,
extra time and penalty shootouts. At full time your real typing stats (WPM,
accuracy, duels) become an AI-generated coach's note.

- **Modes:** Single Player (vs AI) · Multiplayer 2v2 (local network, host-authoritative)
- **Built with:** SwiftUI · SpriteKit · GameKit · MultipeerConnectivity · Apple Foundation Models
- **Target:** macOS 14+ (Xcode 15+; the post-match AI note needs the macOS 26 SDK)

## How to run

1. Open `TypingSoccer.xcodeproj` in **Xcode 15+**.
2. Select the **TypingSoccer** scheme and press **Run (⌘R)**. Signing is Automatic —
   pick your team in *Signing & Capabilities* the first time.
3. In the menu choose **Single Player** (vs AI) or **Multiplayer** (Host / Join).

## Suggested reading order

1. Start with the **Game Design Document** to understand what the game is and how it
   plays.
2. Then read the **Technical Design Document** to see how it's built and how the code
   fits together.

## Note on scope

This is a **prototype**. All art is placeholder (coloured discs for players, a white
dot for the ball, a vector pitch); the design, rules and architecture are the
finished part. The code is structured so real assets and a real Game Center
leaderboard ID can be dropped in without touching game logic — see the "Where to plug
in real assets" section of the Technical Design Document.
