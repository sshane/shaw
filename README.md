# Shaw

Shaw is a music app for the Mac that works like After Effects. I came from After Effects and Premiere, so I wanted compositions, linked clips, effects on anything and keyframes, but for making music. It's also as simple as I could make it: you start with one button, and everything else shows up when you need it.

![Shaw playing the demo song](docs/images/demo-song.png)

## What's different

- **One timeline.** There's no separate session view. The orange loop bar at the top loops any part of the song, and opening a clip loops it.
- **Linked clips.** When you duplicate a clip, every copy shares the same notes. Edit one and they all change. Make Unique gives a copy its own notes, and Merge joins clips into one.
- **Compositions inside compositions.** Pre-compose a few clips and drop the result anywhere like a single clip, just like a precomp.
- **Effects on anything.** Put effects on a clip, a layer or a whole composition. Copy and paste them with ⌘C and ⌘V.
- **Keyframes.** Click a setting's stopwatch and change it over time. Diamonds show up under the layer, and you drag them around like in After Effects.
- **Variations without recording.** Tweak a loop while it plays, then Save Variation keeps that version and gives you a fresh copy right after it. Play them back to back when you're done.
- **Your keyboard is a piano.** The home row plays notes and Z / X change the octave. On drums, A is the kick and S is the snare.

## Install

Download `Shaw.zip` from the [releases page](../../releases), unzip it and drag Shaw into Applications. It runs on macOS 14 (Sonoma) or newer, on Apple Silicon and Intel.

Shaw isn't signed with an Apple developer account, so macOS blocks it the first time. Open it once, then go to System Settings, Privacy & Security, and click **Open Anyway**.

## Build it yourself

You need Xcode (the beta works too).

```sh
scripts/build-app.sh      # builds build/Shaw.app
open build/Shaw.app
scripts/package.sh        # builds a universal build/Shaw.zip to share
swift test                # runs the tests
```

## Getting started

New projects start empty with one button: **Add an instrument**. Pick drums or a synth in the Browser on the left. Click one to hear it, and double-click it to add it. Shaw makes a layer with a one-bar pattern, opens it in the piano roll and loops it. Press Space and start adding notes.

To hear what a full song looks like, open **File → Open Demo Project**. The demo, "First Light", is a 72-bar house track built out of linked Intro, Build, Drop and Breakdown compositions.

![Starting a new project](docs/images/start.png)

## Editing

**Timeline**
- Drag a clip to move it. Hold ⌘ to move it off the grid.
- Drag a clip's edge to trim it. Option-drag the right edge to loop it past its end.
- ⌘D duplicates a clip right after itself, and the copy stays linked.
- Double-click a clip to open it. Double-click an empty spot on a layer to draw a new pattern there.
- Right-click a clip for Fade In, Fade Out, Merge, Make Unique and more.
- Click a layer's header and press Delete to remove the layer.

**Piano roll** (melodies and drums)
- Double-click to add a note, and double-click a note to delete it.
- Drag notes to move them, drag their right edge to resize them, and Option-drag to copy them.
- Drag across empty space to select notes. ⌘C, ⌘X, ⌘V and ⌘D work on the selection.
- ⌥← and ⌥→ change note length. ↑ and ↓ transpose.
- Press B to switch to draw mode, where a single click adds a note.
- Drum patterns can switch to a step grid with the **Steps** button.

**Effects and keyframes**
- Search the Browser's Effects tab and drag an effect onto a clip, a layer header or a composition tab.
- Each effect shows its main settings. Click **More** for the rest, or ✕ to delete it.
- Click an effect's name to select it. ⌘A selects every effect on that layer.
- Click the stopwatch next to a setting to start keyframing it. Every change at the playhead adds a diamond.

![Keyframes fading a bass in and out](docs/images/keyframes.png)

## Shortcuts

| Keys | What they do |
| --- | --- |
| Space | Play / stop |
| ⌘L / ⌘K | Loop / metronome |
| ⌘N / ⌘T | New composition / new layer |
| ⇧⌘P / ⇧⌘B | New pattern / new drum pattern |
| ⌘D / ⇧⌘D | Duplicate / save variation |
| ⌘E / ⌘J | Split at playhead / merge clips |
| ⇧⌘C / ⇧⌘U | Pre-compose / make unique |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘S / ⇧⌘E | Save / export WAV |
| ⌘= / ⌘- / ⌘0 | Zoom in / out / fit |
| A–' · Z/X · C/V | Play notes · octave · velocity |

## What's inside

- **Shaw Synth**, a polyphonic synth with two oscillators, a sub, noise, unison, a resonant filter, envelopes, glide and drive. It comes with 12 presets, including Supersaw, Reese Bass, 808 Bass, Acid, Pluck and Pad.
- **Five drum kits**: Trap 808, House 909, Boom Bap, Lo-Fi and Techno. Shaw generates every sound in code, so there are no samples to download or license.
- **14 effects**: Reverb, Delay, Chorus, Phaser, Auto Pan, Sidechain Pump, Compressor, Limiter, EQ Three, Auto Filter, Saturator, Bitcrusher, Volume and Utility.
- Audio import (drag files in from Finder), WAV export, autosave, and projects saved as `.shaw` files.

## How it works

```
Sources/ShawCore/   the project model and audio engine (no Mac UI code)
Sources/Shaw/       the SwiftUI app
Tests/              engine and editing tests
```

A project is plain data, so undo just keeps snapshots and the audio thread always reads a frozen copy. Every edit rebuilds a small render graph, and each placement of a composition gets its own branch, so two copies of the same composition keep separate reverb tails. Only the audio output and the interface are Mac-specific, which keeps a Windows or web version possible later.

## Ideas for later

Keyframes on synth settings, audio time-stretching, Audio Unit plugins, MIDI keyboards and recording.
