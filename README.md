# lectern

Command-line tools for turning a lecture recording into a written summary.

The end product is a LaTeX document: the lecture's definitions, theorems and
proofs, with the asides and admin that make it worth reading instead of
re-watching. `lectern` produces the raw material for that — a transcript and a
set of readable frames of the board — and a Claude Code skill drives the whole
thing if you want it done for you.

## Requirements

`ffmpeg`, `ImageMagick 7`, and [`uv`](https://docs.astral.sh/uv/). The Python
scripts declare their dependencies inline, so uv fetches them on first run.

## Install

```bash
git clone https://github.com/MendedBiscuit/lectern.git
ln -s "$PWD/lectern/bin/lectern" ~/.local/bin/lectern
lectern doctor
```

## Use it with Claude Code

```
/plugin marketplace add MendedBiscuit/lectern
/plugin install lectern@lectern
```

Then point Claude at a recording:

> summarise ~/lectures/ntc-05.mp4

It runs the steps below, reads the board off the frames itself, writes the
`.tex`, builds it, and tells you what it could not recover from the recording.
A 55-minute lecture takes about 20 minutes end to end, most of it transcription.

## Use it by hand

Everything writes where you tell it to. Working in a scratch directory:

```bash
mkdir -p work && cd work

# 1. check the audio before transcoding it (see below)
lectern probe ~/lectures/ntc-05.mp4

# 2. audio -> 16 kHz mono wav
lectern audio ~/lectures/ntc-05.mp4 -o audio.wav

# 3. wav -> timestamped transcript (~5 min per lecture hour, CPU)
lectern transcribe audio.wav -o transcript.txt

# 4. video -> one frame per 30 s
lectern frames ~/lectures/ntc-05.mp4 -o frames --every 30
```

That leaves you with:

```
work/audio.wav          16 kHz mono
work/transcript.txt     [MM:SS] one line per utterance
work/frames/f001.jpg    frame N is at (N-1)*30 seconds, so f110.jpg is 54:30
work/frames/f002.jpg
...
```

Now read them. **The transcript is not the content.** Speech recognition mangles
technical vocabulary fluently — one number theory lecture gave "a billion" for
*abelian*, "Vermont" for *Fermat*, and a `39` inserted into a list of primes.
Take the mathematics off the frames and use the transcript for what was said
about it: emphasis, asides, what was set as an exercise, what was deferred.

When a subscript will not resolve at 1280×720, crop and enlarge it:

```bash
lectern crop frames/f110.jpg 620x180+635+15 --zoom 400 -o board1.png
```

Geometry is `WIDTHxHEIGHT+X+Y` from the top-left.

Then write the summary into the template and build it:

```bash
lectern template -o ../lec05/lec05.tex
cd ../lec05
$EDITOR lec05.tex
latexmk -pdf -outdir=build lec05.tex      # -> lec05/build/lec05.pdf
```

(`-outdir` is relative to the current directory, so build from inside `lec05/`.)

`skills/lecture-summary/references/writeup.md` covers what to put in it and how
to check you have not missed anything.

## Preprocessing checks

```bash
lectern probe LECTURE.mp4
```

Run this before transcoding. It prints duration, streams, channel levels and
phase correlation, then recommends a downmix. It exists because some capture
rigs record one channel with inverted polarity, which sounds fine until you
downmix to mono and the two channels cancel — after which the transcript comes
back empty with no error. Six seconds on a 55-minute file.

`lectern audio` applies the recommendation on its own; `probe` is for seeing
why, and for the cases it flags as ambiguous.

## Other commands

```bash
lectern clean LECTURE.mp4 -o LECTURE-clean.mp4
```

Audio repair for listening: downmix, 80 Hz high-pass, two-pass EBU R128
normalisation, true-peak limiter. Video is stream-copied, so a 55-minute file
takes about a minute. Defaults to `LECTURE-clean.mp4` beside the input.

```bash
lectern ramp run LECTURE.mp4 -o LECTURE-fast.mp4
```

Plays 1.2× while the lecturer is writing and 2× when they are not. One
55-minute lecture came out at 37. Scratch files go in `.lectern-ramp/` beside
the video. Split into `detect`, `plan`, `render` and `verify` to tune it. It
detects writing, so it does not apply to slide decks.

`lectern <command> --help` for options. `LECTERN_VERBOSE=1` prints the ffmpeg
and ImageMagick commands as they run.

## Layout

```
bin/lectern                          dispatcher
lib/*.sh  lib/*.py                   one file per subcommand
skills/lecture-summary/SKILL.md      the workflow, for Claude Code
  references/audio.md                phase inversion, loudnorm, limiter settings
  references/boards.md               reading frames
  references/writeup.md              summary structure and LaTeX
  assets/lecture.tex                 the template `lectern template` writes out
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
speech sends Whisper into a loop. It prints a coverage summary at the end —
segment count, last cue, any gap over 45 seconds — because a transcript that
stops early otherwise looks complete.

## Licence

MIT.
