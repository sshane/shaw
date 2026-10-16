# Shaw

A digital audio workstation for macOS built around **compositions**, the way After Effects and Premiere work, with a piano roll, a step sequencer, and Ableton-style clip launching.

## Build and run

Requires macOS 14+ and Xcode (Xcode-beta works; the script picks it up automatically).

```sh
scripts/build-app.sh          # release build → build/Shaw.app
open build/Shaw.app
swift test                    # engine + editing tests
```

## Demo song

Shaw opens with **"First Light"**, a 72-bar A-minor house track at 124 BPM (File → Open Demo Project brings it back). It's arranged from linked sections: **Intro** (also the outro), **Build** (twice), **Drop** (four times), and **Breakdown**. Open any section and change it, and every copy changes. It also shows effects at every level: a filter sweeping the whole Intro composition, sidechain pump inside the Drop, delay and reverb on the lead, and EQ + limiter on Main as a master bus. Session slots are filled too, if you open the optional Session view from a ☰ menu.

## The idea

| After Effects / Premiere | Shaw |
| --- | --- |
| Project panel (footage, comps, folders) | **Project** panel — compositions, patterns, beats, audio files, folders |
| Composition | **Composition** — tracks of clips, its own length and effects |
| Precomp layer | A composition placed as a clip inside another composition |
| Layers | **Tracks** — simultaneous lanes you drag clips around on |
| Effect Controls | **Effect Controls** panel — the effect stack of whatever is selected |
| Effects & Presets search | **Browser** — search "reverb", drag it onto anything |
| Pre-compose (⇧⌘C) | Pre-compose (⇧⌘C) |
| Composition duration | Drag the blue end marker on the ruler |

**Everything is linked.** Clips, session slots and nested compositions all point at the original asset. Edit the "Drop" composition or the "Chords" pattern once and every place it's used changes. Use **Make Unique** (⇧⌘U) on a clip when you want an independent copy.

**Effects stack the way you'd expect.** Clip effects run first, then track effects, then composition effects. A composition's effects apply after everything inside it, exactly like an effect on a precomp layer. Each placement of a composition renders with its own effect state, so two copies of a comp with reverb each ring out independently.

## Getting started

A new project is empty on purpose. Click **Add an instrument** (or pick one in the Browser's **Instruments** tab: click to hear it, double-click to add). Shaw makes a track with a one-bar pattern, opens it in the piano roll and loops it. Press Space and start adding notes.

## Editing

**Piano roll** (synths *and* drums: a drum kit shows one row per sound)
- Double-click to add a note, double-click a note to delete it. Drag empty space to select.
- Drag notes to move, drag the right edge to resize (⌥← / ⌥→ too), ⌥-drag to copy.
- ⌘C / ⌘X / ⌘V / ⌘D, arrows to move, ↑/↓ to transpose. **B** toggles draw mode (click to draw).
- Drum patterns have a **Steps** view: the same notes as an FL Studio-style step grid.
- Clicking notes is silent by default (and always while playing); the headphones button turns previews on.

**Play with your keyboard** — A S D F G H J K L ; ' are white keys, W E T Y U O P black keys, Z / X octave, C / V velocity. Drum kits: A = kick, S = snare, and so on.

**Variations without recording** — while a pattern loops, tweak it, then press **Save Variation** (⇧⌘D). The current version stays put and a copy appears right after it, now looping, ready for the next idea. **Loop All** plays every version in a row.

**Swap an instrument** — drag an instrument onto a clip or into the open piano roll: the notes stay, the sound changes.

**Timeline**
- Drag a clip to move it (across tracks too). ⌘ while dragging disables snapping.
- Drag an edge to trim. Past the end of the content is silence (hatched).
- **Option-drag the right edge to loop** the content past its end. Repeats show notches.
- Option-drag a clip body to duplicate it. ⌘D duplicates the selection right after itself.
- Double-click a clip to open it (and loop it). Double-click an empty lane to draw a new pattern there.
- Drag the top strip of the ruler to set the loop region; click it to toggle looping.
- Scroll to pan, ⌘/⌥-scroll or pinch to zoom, ⌘0 to fit.

**Effects** — each effect shows its main knobs; **More** reveals the rest, ✕ deletes it.

**Session view** (optional) — an Ableton-style clip launcher, available from any panel's ☰ menu.

## Shortcuts

| Key | Action |
| --- | --- |
| Space | Play / stop (returns to where you started) |
| ⇧⌘D | Save variation |
| A–' · Z/X · C/V | Play notes · octave · velocity |
| ⌘L / ⌘K | Loop / metronome |
| ⌘N / ⌘T | New composition / new track |
| ⇧⌘P / ⇧⌘B | New pattern / new drum pattern |
| ⌘D / ⌘E | Duplicate / split at playhead |
| ⇧⌘C / ⇧⌘U | Pre-compose / make unique |
| ⇧⌘L | Toggle loop on selected clips |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘S / ⇧⌘E | Save / export WAV |
| ⌘= / ⌘- / ⌘0 | Zoom in / out / fit |

## What's built in

- **Shaw Synth** — polyphonic subtractive synth: 2 oscillators, sub, noise, up to 7-voice unison, resonant filter with envelope and key tracking, pitch envelope, mono/legato glide, drive. Presets: Init, Supersaw, Pluck, Pad, Reese Bass, Sub Bass, 808 Bass, Acid, Keys, Lead, Bell, Noise Riser.
- **Drum kits** (synthesized, no samples to license): Trap 808, House 909, Boom Bap, Lo-Fi, Techno — kick, snare, clap, closed/open hat (choked), toms, rim, perc, crash.
- **Effects**: Reverb, Delay (tempo-synced, ping-pong), Chorus, Phaser, Auto Pan, Sidechain Pump, Compressor, Limiter, EQ Three, Auto Filter (with synced LFO), Saturator, Bitcrusher, Utility.
- Audio import (WAV, AIFF, MP3, M4A…) by dragging from Finder or ⌘I. WAV export of the current composition.
- Autosave to `~/Library/Application Support/Shaw/`, projects save as `.shaw` (JSON).

## Architecture

```
Sources/ShawCore/       platform-independent model + audio engine
  Model/Project.swift   value-type project: assets, compositions, tracks, clips, patterns
  Engine/GraphBuilder   project snapshot → render graph (state reused by path across edits)
  Engine/RenderGraph    clip / track / composition / source nodes
  Engine/AudioEngine    AVAudioEngine host, transport, session launching, preview, export
  DSP/                  effects, synth, drum synthesis, filters
Sources/Shaw/           SwiftUI app (Mac UI)
Tests/                  engine and editing tests
```

The project is plain value types, so undo is a snapshot and the audio thread gets an immutable copy. The engine pulls the whole graph from one render callback. Only the audio host and the UI are Mac-specific, which keeps a later Windows or web port to rewriting those two layers.

## Roadmap ideas

Automation keyframes (After Effects style), time-stretch / warping for audio, Audio Unit plugins, MIDI keyboard input, recording, sidechain routing, sample instruments, recording session clips into the timeline, and per-clip fades.
