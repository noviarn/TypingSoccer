# Typing Soccer — Game Design Document (GDD)

**Version:** 1.0 (prototype)
**Platform:** macOS 14+ (Apple Silicon / Intel)
**Genre:** Typing / Sports arcade hybrid
**Modes:** Single Player (vs AI) · Multiplayer 2v2 (local network)

---

## 1. High-Concept

Typing Soccer turns a soccer match into a series of **typing duels**. You never
steer a player with a joystick — instead you win possession, break past defenders,
and score by **typing words faster and more accurately than your opponent**. The
players run themselves; your keyboard is the ball's engine.

The pitch, clock, formations, offside, extra time and penalty shootouts are all
real football furniture — but every contested moment on the field is decided by
who finishes the on-screen word first.

---

## 2. Core Loop

The core loop is the repeating cycle the player lives inside for the whole match.
Every rotation of the loop is a single **typing duel**, wrapped in the football
context of possession → advance → contest → outcome.

### 2.1 Objective (what the player is trying to do)

At the macro level the objective is the sport's objective: **score more goals than
the opponent before full time.** At the micro level — the level the player actually
acts on — the objective is narrower and clearer:

> **Finish the current word before your opponent finishes theirs.**

Each duel has one of three objectives depending on where the ball is:

| Duel | Trigger | Objective |
|------|---------|-----------|
| **Kickoff** | Opening whistle / after a goal | Win the first word to claim possession |
| **Interception** | A defender catches the ball carrier mid-field | Win the word to take or keep the ball |
| **Shot** | The carrier reaches the penalty area | Beat the goalkeeper's word to score |

Because objectives are short (a single word, a few seconds) the player always knows
exactly what "winning right now" means.

### 2.2 Challenge (what makes it hard)

The challenge is a blend of **speed, accuracy, and escalating difficulty**:

- **Speed vs. a live clock.** In every duel the opponent (AI or human) is typing
  the same word at the same time. You are not racing a timer — you are racing a
  competitor who might be faster than you.
- **Accuracy is enforced.** A wrong key does **not** advance you to the next
  letter; you must hit the correct character to move on, and each mistake is logged
  against your accuracy stat (`TypingController`). Panic-mashing loses duels.
- **Difficulty ramps toward the goal.** The word bank has easy / medium / hard
  buckets, and the game biases toward harder words as the ball nears the goal
  (`WordProvider.word(intensity:)`). The make-or-break **shot** always uses a long
  8–12 letter word (`WordProvider.shotWord()`), so finishing is the hardest moment.
- **Fatigue and momentum.** Losing a duel drops you to **70% speed for 3 seconds**
  and takes you out of contact, so a lost word doesn't just cost the ball — it
  costs field position. A shared **stamina** pool drains as players run (faster
  while carrying the ball) and slows them as it empties, so late-match duels feel
  heavier.

### 2.3 Reward (what the player gets for succeeding)

Rewards are layered so that every duel feels worth winning even when no goal
results:

- **Immediate:** correct letters light up **green**; the word completes with a
  sound cue; you gain or keep the ball.
- **Positional:** winning an interception lets your carrier keep auto-running
  toward goal; the loser is slowed, so you also gain space.
- **Score:** winning a **shot** duel scores a **goal** — the headline reward, with
  a celebration beat and a possession reset.
- **Meta / progression:** the match tracks real stats (WPM, accuracy, duels won,
  fastest word). At full time these feed an **AI-generated coach's note** and a
  **Game Center leaderboard** submission for your typing WPM — a reward that
  persists beyond the single match.

### 2.4 The loop, in one diagram

```
        ┌─────────────────────────────────────────────┐
        │                                             │
        ▼                                             │
  KICKOFF DUEL ──win──► CARRY / AUTO-RUN ──reach box──► SHOT DUEL
        ▲                     │                          │
        │                 defender                    win │ lose
        │                 closes in                       │
        │                     ▼                       GOAL / MISS
        │              INTERCEPTION DUEL                   │
        │              win │      │ lose                   │
        │           keep ball   slowed 70%/3s              │
        └──────────────────────── possession resets ◄──────┘
```

---

## 3. Core Experience

### 3.1 The fantasy

The player should feel like a **keyboard athlete** — that their typing skill is
directly, visibly winning a football match. The satisfaction is the same one that
makes typing games compelling (flow, rhythm, clean bursts of accurate speed) but
given **stakes and drama** by wrapping it in a sport the player already understands.

### 3.2 Emotional beats

- **Tension** during the run-up: the ball is auto-running to goal and you can see
  the defender closing — you know a duel is coming.
- **Spike** at the moment a word appears: full attention, race to finish.
- **Relief or sting** on the outcome: green completion and possession kept, or the
  slow penalty and lost ground.
- **Peak** at the shot on goal: the longest word, the goalkeeper opposite you, one
  contest for a goal.
- **Reflection** at full time: the coach's note translates your raw stats into a
  human, encouraging read on how you played.

### 3.3 Pacing

A full match is **2 real minutes displayed as a 0–90' clock**, so the whole
experience is short and replayable. Play flows in bursts: quiet auto-run seconds,
then a sharp duel, then resolution. Structural breaks — **half time (45')**,
optional **extra time (2×15')** and a **penalty shootout** — give the match a
familiar rise and fall and a decisive ending even from a draw.

### 3.4 Accessibility of skill

The rules are complex (offside, formations, stamina) but the **input is dead
simple**: everything is the keyboard, and at any moment you are only ever doing one
thing — typing the word in front of you, or (in multiplayer) pressing **1 / 2 / 3**
to pick a runner. Depth lives in the football simulation; the moment-to-moment
action stays legible.

---

## 4. Game Rules (In Detail)

### 4.1 The field

- The pitch has **three horizontal lanes**: top, middle, bottom.
- Each side fields **four players**: **3 outfielders** (one per lane) + **1
  goalkeeper**.
- Two goals, one per end, each with a **penalty area** in front of it. The keeper
  stands slightly in front of its own goal line.

### 4.2 Teams and identity

- Two sides: **home** ("YOU") and **away** ("RIVAL"). In single player the away
  side is the AI; in multiplayer it is the remote humans.
- Each side picks a **World Cup national team** for flavour/colours
  (`WorldCupTeams`). In single player you pick both; in multiplayer each side
  brings its own pick over the network.

### 4.3 Match structure and clock

- Regular time is **120 real seconds**, shown as a **0–90 football-minute** clock.
- **Half time** occurs at 45'; teams switch ends.
- Added (stoppage) time is shown up to **+5'** in regular time and **+3'** in extra
  time, with real-time cutoffs before a half is forced to end.
- If scores are level at full time, the match goes to **extra time**: two halves of
  a displayed **15'** each (about 20 real seconds per half).
- If still level after extra time, a **penalty shootout** decides it.

### 4.4 Starting a match — strategy pick and kickoff

1. **Strategy pick (5s):** before kickoff you choose a starting **formation** with
   keys **1–5** (see 4.9).
2. **Countdown:** a **3-2-1** count with a whistle.
3. **Kickoff duel:** both teams type the **same word**. The first to finish wins
   possession. The ball spawns to a **random outfielder** (never the keeper) on the
   winning side.

### 4.5 Carrying and auto-running

- Whoever has the ball **auto-runs toward the enemy goal** along their lane.
- A carrier moves at **80% of base speed** (carrying slows you) and drains stamina
  faster than a non-carrier.
- Off-ball runners advance too; a carrier may **pass** to a teammate who has got
  closer to goal (auto in single player; manual with **1 / 2 / 3** in multiplayer).

### 4.6 Interception duels

- The opposing **defender in the ball's lane** closes in (defenders are slightly
  faster than carriers so they can catch up).
- On contact (within the duel trigger distance) a **new word** appears — an
  **interception duel**.
- **Winner takes or keeps the ball.** The **loser** is penalised:
  **70% speed for 3 seconds** and **cannot enter a new duel** (collision off) until
  recovered. This is the game's main risk/consequence rule.
- Defenders commit to a target for a minimum time before switching, to prevent
  jittery "stuck in the middle" behaviour.

### 4.7 The shot on goal

- When the carrier reaches the **penalty area**, a **shot duel** fires against the
  **goalkeeper**, using a long 8–12 letter word.
- Three outcomes (`computeShotOutcome`):
  - **Goal** — you out-typed the keeper cleanly → the ball goes in, celebration,
    score +1.
  - **Saved** — the keeper wins → the keeper catches; possession goes to the
    defending side.
  - **Wide / Miss** — even if you out-typed the keeper, a **mistype** (or, for the
    AI, its shot-miss chance) can send the shot **wide**; the ball goes out and
    possession resets to the other side.
- After any shot the game resets possession and play resumes (or, on a goal, runs a
  celebration then a fresh kickoff).

### 4.8 Offside

- An attacking runner ahead of the last defender is flagged **offside**.
- There is a short **grace period** to be in an offside position; after that the
  runner is forced to **retreat level with the last defender**, then must be
  **onside again for a moment** before it may resume its run.
- This keeps runners from camping in front of the keeper waiting for a pass.

### 4.9 Formations

Set with keys **1–5**, applied at every reset (kickoff, half time, after a goal):

| Key | Formation | Shape (depth by lane) |
|-----|-----------|------------------------|
| 1 | **1-2** (default) | centre deep, wings advanced |
| 2 | **2-1** | wings deep, centre advanced |
| 3 | **3-0** | all three deep |
| 4 | **0-3** | all three advanced |
| 5 | **1-1-1** | staggered: one forward, one middle, one back |

Formation changes trade defensive cover for attacking presence and are a light
layer of pre-duel strategy.

### 4.10 Stamina (single-player detail)

- Each player has a **stamina pool (max 100)** that **drains while running** (more
  while carrying) and **regenerates while still** or during stoppages/duels.
- Low stamina lowers a player's speed (down to a floor of 50% at empty).
- Stamina is **not** reset each round — it lasts the whole match; only a half-time /
  extra-time break restores a small amount. (Stamina is single-player only; it is
  not synced in multiplayer.)

### 4.11 Typing rules (how a duel is actually won)

- The word appears in the prompt bar; both sides type the **same** word.
- **Correct** next character advances you and turns green; a **wrong** key does
  **not** advance and is counted as a **mistake**.
- The **first to complete** the word wins the duel.
- Every keystroke feeds per-player stats: words completed, keystrokes, mistakes,
  duels won/lost, fastest word, and total typing time → used for **WPM** and
  **accuracy**.

### 4.12 Penalty shootout

- Taken if extra time is still level.
- **3 kicks per side** before sudden death; all three outfielders take one, then
  the **goalkeeper is the 4th kicker** (sudden death), then the order loops.
- Each kick is a **run-up + typing duel** between shooter and keeper, resolved with
  the same goal / saved / wide logic.
- Standard shootout resolution: whoever is ahead once the other cannot catch up
  wins; otherwise sudden death continues.

### 4.13 End of match

- At full time (or after the shootout) the match ends.
- The player's real stats are turned into a short **coach's note** (on-device AI,
  with a written fallback), and the typing **WPM is submitted to Game Center**.

---

## 5. Multiplayer Rules Summary (2v2)

- Four Macs on the same local network connect via MultipeerConnectivity: one
  **hosts**, three **join**; seats fill in a lobby and the match starts when all
  four are taken.
- Each team has two humans with split roles:
  - **Field player** — runs the three outfielders: types kickoff/interception and
    attacking shot duels, passes with **1 · 2 · 3**, sets the formation, and (on
    defence) presses **1 · 2 · 3** to choose which outfielder chases.
  - **Keeper player** — guards the goal: types shot/penalty duels, and when the
    keeper holds the ball presses **1 · 2 · 3** to choose who to distribute to.
- The **host is authoritative**: it picks every duel word, resolves winners, and
  decides possession, passes, offside, breaks, extra time and penalties, then
  broadcasts each as an event. Joiners mirror those events (teams flipped to their
  own view) and send back only their own inputs.

---

## 6. Implementation Status

All the rules and mechanics above are **implemented and playable**. The items below
are placeholders or not-yet-finished production polish:

| Feature | Status |
|---------|--------|
| Core gameplay (duels, run, shots, offside, formations, stamina, halftime, extra time, penalties) | ✅ Implemented |
| Single-player AI opponent | ✅ Implemented |
| Multiplayer 2v2 (host-authoritative) | ✅ Implemented |
| Player / ball / pitch **art** | 🎨 Placeholder (coloured discs, white dot, vector pitch) |
| **Sound effects** | 🎨 Placeholder (built-in macOS system sounds) |
| **Game Center leaderboard** | 🚧 Not wired to a real board — placeholder ID `com.typingsoccer.wpm` |
| Post-match **AI coach's note** | ⚠️ Needs macOS 26 / Foundation Models; written fallback otherwise |
| Multiplayer **stamina sync** | 🚧 Not implemented — stamina is single-player only |

**Legend:** ✅ implemented · 🎨 placeholder art · 🚧 not implemented yet · ⚠️ works with a caveat.

*This document describes the prototype's intended and implemented behaviour. Art is
placeholder (coloured discs for players, a white dot for the ball, a vector pitch);
the design and rules are the finished part.*
