# lectern

Tools for turning a lecture recording into a written summary.

Input: a video or audio file. Output: a transcript, frames of the board, and a
LaTeX document to write the summary into.

## Requirements

ffmpeg, ImageMagick 7, [uv](https://docs.astral.sh/uv/). Python dependencies are
declared inline and fetched on first run.

## Install

```bash
git clone https://github.com/MendedBiscuit/lectern.git
ln -s "$PWD/lectern/bin/lectern" ~/.local/bin/lectern
lectern doctor
```

Claude Code plugin:

```
/plugin marketplace add MendedBiscuit/lectern
/plugin install lectern@lectern
```

## Workflow

```bash
mkdir work && cd work

lectern probe      LECTURE.mp4                      # check the audio first
lectern audio      LECTURE.mp4 -o audio.wav         # 16 kHz mono
lectern transcribe audio.wav -o transcript.txt      # ~5 min per lecture hour
lectern frames     LECTURE.mp4 -o frames --every 30
```

Leaves:

```
work/audio.wav
work/transcript.txt      [MM:SS] one line per utterance
work/frames/fNNN.jpg     frame N at (N-1)*30 seconds
```

Read the frames for the content and the transcript for context. ASR is
unreliable on notation, proper nouns and numbers.

Enlarge unreadable regions:

```bash
lectern crop frames/f110.jpg 620x180+635+15 --zoom 400 -o board1.png
```

Geometry is `WIDTHxHEIGHT+X+Y` from the top-left.

Write the summary and build it:

```bash
lectern template -o ../lec05/lec05.tex
cd ../lec05
latexmk -pdf -outdir=build lec05.tex                # -> build/lec05.pdf
```

`-outdir` is relative to the working directory.

With the plugin installed, Claude Code runs all of the above from a path to a
recording.

## Commands

| command | |
|---|---|
| `probe FILE` | duration, streams, levels, phase correlation, recommended downmix |
| `audio FILE` | 16 kHz mono WAV; downmix measured unless `--downmix` given |
| `transcribe WAV` | faster-whisper `distil-large-v3`, CPU int8; `--srt` for subtitles |
| `frames FILE` | one JPEG per `--every` seconds (default 30) |
| `crop FRAME GEOM` | crop and upscale by `--zoom` (default 400) |
| `template` | write out the LaTeX preamble |
| `clean FILE` | downmix, high-pass, two-pass loudnorm, true-peak limit; video stream-copied |
| `ramp run FILE -o OUT` | 1.2x while the lecturer writes, 2x otherwise |
| `doctor` | check dependencies |

`lectern <command> --help` for options. `LECTERN_VERBOSE=1` prints the
underlying ffmpeg and ImageMagick commands.

## probe

Some capture rigs invert the polarity of one channel. Each channel then measures
normally, but a mono downmix cancels them and the level drops 20–40 dB, at which
point Whisper's VAD discards the file and returns an empty transcript with no
error. `probe` compares mid against side and reports which downmix to use;
`audio` applies it automatically. It varies between files from the same source,
so it is worth checking each one.

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

- `clean` measures loudness through the chain that precedes `loudnorm`, not the
  raw file, or the second pass overshoots. `alimiter` gets `level=false`; its
  default of `true` restores full scale. The ceiling is −2.5 dBFS to absorb
  1–2 dB of inter-sample overshoot from lossy encoding.
- `ramp` detects writing by persistence: dark at *t*, not dark at *t−4s*, still
  dark at *t+4s*. Totalling dark pixels fails on a document camera, where pages
  are swapped and the count resets. It renders one ffmpeg per segment in
  parallel and concat-demuxes; a single filtergraph with one `trim` branch per
  segment pushes every frame down every branch. Detects writing, so it does not
  apply to slide decks.
- `transcribe` sets `condition_on_previous_text=False`; repetitive speech
  otherwise sends Whisper into a loop. It reports segment count, last cue and
  any gap over 45 s, since a transcript that stops early otherwise looks
  complete.

## Licence

MIT.
