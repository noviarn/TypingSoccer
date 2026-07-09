# Sound files

Drop your audio files here (or anywhere in the target) and **add them to the
`TypingSoccer` target** in Xcode so they get copied into the app bundle:

> drag the files into the Xcode project → tick **Copy items if needed** and the
> **TypingSoccer** target under *Add to targets*.

The game looks each file up by name. Any of these extensions work, tried in
order: `.mp3`, `.m4a`, `.wav`, `.caf`, `.aif`, `.aiff`.

Until a file exists, a built-in macOS system sound stands in, so every trigger
already makes noise — you can add files one at a time.

## Background music (loops)

| File base       | Plays when…                                      |
|-----------------|--------------------------------------------------|
| `music_lobby`   | menu, lobby, results, settings — outside a match |
| `music_ingame`  | during a live match                              |

Music has **no** system-sound fallback — a missing music file just means
silence for that track.

## Sound effects

| File base           | Trigger                                             |
|---------------------|-----------------------------------------------------|
| `sfx_button`        | any UI button tap                                   |
| `sfx_whistle`       | kickoff / half time / full time                     |
| `sfx_battle_start`  | two players collide and a typing duel begins        |
| `sfx_battle_end`    | an interception duel resolves                        |
| `sfx_kick`          | the ball is struck at goal                          |
| `sfx_goal`          | the ball hits the net                               |
| `sfx_saved`         | the keeper catches the shot                         |
| `sfx_miss`          | a shot sails wide (e.g. after a mistype)            |
| `sfx_celebration`   | goal celebration voice ("SIUUUU") — your side only  |
| `sfx_formation`     | you change formation                                |
| `sfx_pass`          | pass / generic cue                                  |

Example: `music_lobby.mp3`, `sfx_goal.wav`, `sfx_celebration.m4a`.

Volumes are controlled independently by the **Music** and **Sound FX** sliders
in Settings (0 mutes). Music volume updates live while a track is playing.
