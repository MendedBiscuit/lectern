# lectern

Command-line tools for turning a lecture recording into notes. Extract the
audio, transcribe it, sample frames so the board can be read, clean up bad
sound, speed up playback. Ships with a Claude Code skill that drives them.

## Requirements

`ffmpeg`, `ImageMagick 7`, and [`uv`](https://docs.astral.sh/uv/). The Python
scripts declare their dependencies inline, so uv fetches them on first run and
there is nothing to install by hand.

## Install

```bash
git clone https://github.com/MendedBiscuit/lectern.git
ln -s "$PWD/lectern/bin/lectern" ~/.local/bin/lectern
lectern doctor
```

As a Claude Code plugin:

```
/plugin marketplace add MendedBiscuit/lectern
/plugin install lectern@lectern
```

## Commands

```bash
lectern probe LECTURE.mp4
```

Prints duration, streams, per-channel levels, mid/side levels and phase
correlation, then recommends a downmix. Six seconds on a 55-minute file.

Run it before anything else. Some capture rigs record the right channel with
inverted polarity. Each channel measures normally on its own, but `ffmpeg -ac 1`
averages them and they cancel:

```
   left        mean    -26.5   peak     -1.8
   right       mean    -26.6   peak     -1.8
   mid  (L+R)  mean    -44.3   peak     -3.9
   side (L-R)  mean    -26.6   peak     -1.8
```

Whisper's voice-activity filter then drops the whole file as silence and returns
only whatever bumper happens to be mono. There is no error. Two lectures from
the same subject, recorded a day apart in the same theatre, differed on this, so
it needs checking per file.

```bash
lectern audio LECTURE.mp4 -o work/audio.wav
```

16 kHz mono WAV for ASR. Picks the downmix by measuring mid against side;
override with `--downmix mid|side|left|right`. Warns if the result is too quiet
to be speech.

```bash
lectern transcribe work/audio.wav -o work/transcript.txt
```

faster-whisper, `distil-large-v3`, CPU int8. About five minutes per lecture
hour on 16 threads. `--srt` for subtitles. Prints a coverage summary at the end:
segment count, where the last cue falls, and any gap over 45 seconds.

```bash
lectern frames LECTURE.mp4 -o work/frames --every 30
lectern crop work/frames/f110.jpg 620x180+635+15 --zoom 400 -o board.png
```

Sample frames and enlarge a region. At 1280×720 a line of chalk is about 25
pixels high, which is not enough to read a subscript; cropping and upscaling
3–5× is.

```bash
lectern clean LECTURE.mp4 -o LECTURE-clean.mp4
```

Downmix, 80 Hz high-pass, two-pass EBU R128 normalisation, true-peak limiter.
Video is stream-copied, so a 55-minute file takes about a minute. Re-measures
the output and reports it.

```bash
lectern ramp run LECTURE.mp4 -o LECTURE-fast.mp4
```

Plays 1.2× while the lecturer is writing and 2× when they are not. One 55-minute
lecture came out at 37. Split into `detect`, `plan`, `render` and `verify` for
tuning. It detects writing, so it does not apply to slide decks.

Set `LECTERN_VERBOSE=1` to see the ffmpeg and ImageMagick commands.

## Layout

```
bin/lectern                          dispatcher
lib/probe.sh                         diagnostics
lib/audio.sh                         ASR extraction
lib/clean.sh                         loudness repair
lib/frames.sh  lib/crop.sh           frame sampling and cropping
lib/transcribe.py                    faster-whisper wrapper
lib/ramp.py                          speed ramp: detect / plan / render / verify
skills/lecture-summary/SKILL.md      the workflow, for Claude Code
  references/audio.md                phase inversion, loudnorm, limiter settings
  references/boards.md               reading frames
  references/writeup.md              summary structure and LaTeX
  assets/lecture.tex                 preamble
```

## Notes

`clean` measures loudness through the same filter chain that precedes
`loudnorm`, not on the raw file, or the second pass overshoots. It passes
`level=false` to `alimiter`, whose default is `true` and silently restores full
scale. It limits to −2.5 dBFS, because lossy encoding adds 1–2 dB of
inter-sample overshoot on top.

`ramp` finds writing by persistence: a pixel dark at *t*, not dark at *t−4s*,
still dark at *t+4s*. Totalling dark pixels does not work on a document camera
because pages get swapped and the count resets. Rendering is one ffmpeg per
segment in parallel, then a concat demux; a single filtergraph with one `trim`
branch per segment makes ffmpeg push every frame down every branch.

`transcribe` sets `condition_on_previous_text=False`, otherwise repetitive
speech sends Whisper into a loop.

## Licence

MIT.
