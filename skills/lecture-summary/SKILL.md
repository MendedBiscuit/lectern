---
name: lecture-summary
description: Turn a recorded lecture into a written summary — transcribe the audio, read the blackboard or slides from sampled frames, reconcile the two, and write it up (LaTeX or Markdown). Use when the user points at a lecture recording and asks for notes, a summary, a transcript, or "what happened in this lecture". Also covers diagnosing and repairing broken lecture audio, and speed-ramping a recording for faster watching.
---

# Lecture summary

A recording carries its content in two channels. The audio has the narrative:
asides, emphasis, what a theorem was for, admin, what was flagged as examinable.
The picture has the content: every symbol as written.

Speech recognition is unreliable on technical vocabulary and fails fluently.
Observed in one number theory lecture: *abelian* → "a billion", *Fermat* →
"Vermont", *cyclic* → "sickie", *primitive root* → "permanent group", *Bézout* →
"bazou", and a `39` inserted into a list of primes. Each is a plausible English
sentence, and none is recoverable from the transcript.

So: take the mathematics from the frames, the narrative from the audio. Do not
transcribe formulas or names from audio.

## The tool

`lectern` is the CLI in this repo. `lectern doctor` checks its dependencies
(ffmpeg, ImageMagick, uv); `lectern <cmd> --help` documents each subcommand. If
it is not on `PATH`, call `${CLAUDE_PLUGIN_ROOT}/bin/lectern`.

Work in a scratch directory, not next to the user's files.

## 1. Probe

```bash
lectern probe LECTURE.mp4
```

Six seconds on a 55-minute file. Some capture rigs record the right channel with
inverted polarity; both channels then measure normally alone, but a mono downmix
cancels them and the level drops 20–40 dB. Whisper's VAD classifies the file as
silence and returns a few lines of whatever bumper is genuinely mono, with no
error. `probe` compares mid against side and prints the downmix to use. Details
in `references/audio.md`.

Read the verdict before continuing.

## 2. Audio to transcript

```bash
lectern audio LECTURE.mp4 -o work/audio.wav
lectern transcribe work/audio.wav -o work/transcript.txt
```

About five minutes per lecture hour on CPU. `transcribe` prints a coverage
summary: segment count, last cue, gaps over 45 seconds. Check it — a transcript
that stops early is indistinguishable from a complete one otherwise.

## 3. Frames to board

```bash
lectern frames LECTURE.mp4 -o work/frames --every 30
```

Read the frames directly rather than running OCR. Boards accumulate before they
are wiped, so the last frame before each wipe holds everything on that board.
Scan every fifth frame to locate the wipes, read each board's final state in
full, then spot-check the frames you skipped to confirm nothing was written and
erased between samples.

For unresolvable detail:

```bash
lectern crop work/frames/f110.jpg 620x180+635+15 --zoom 400 -o work/board1.png
```

`references/boards.md` covers slides, document cameras, and what the camera
loses.

## 4. Reconcile and write

Work through the transcript in order. For each claim, locate it on a board and
take the symbols from there. Where board and transcript disagree, the board is
correct.

Use the transcript for what the lecturer emphasised, called difficult, said was
examinable, deferred to next lecture, or set as an exercise. That material is
what makes a summary preferable to re-watching.

Structure and LaTeX conventions: `references/writeup.md`. Preamble:
`assets/lecture.tex`.

## 5. Check coverage

Both directions, before reporting completion.

- **Write-up to lecture.** Every statement should trace to a board or a
  transcript line. Flag anything inferred or supplied from your own knowledge —
  it may be correct and still not be what was taught.
- **Lecture to write-up.** Re-read the transcript against your section list.
  Look for the sentences explaining why one result leads to the next; these
  compress out without leaving a visible hole. In one lecture the omission was a
  30-second contrast between two isomorphisms, which motivated the second half.

Then state what could not be recovered. A projected table blown out to white is
not in the recording; say so and point at the posted notes rather than
reconstructing it.

## 6. Build and write back

Build the document and check it: for LaTeX, zero overfull boxes and the expected
page count. Then follow the project's note-keeping convention (`CLAUDE.md`, a
vault, a journal) so the summary is recorded somewhere other than a build
directory.

Check whether this lecture answers a question an earlier one left open, and link
the two.

## Also here

Audio repair for listening — downmix, high-pass, two-pass loudness
normalisation, true-peak limit, video stream-copied:

```bash
lectern clean LECTURE.mp4 -o LECTURE-clean.mp4
```

Speed ramp — faster through pauses, slower while the lecturer writes:

```bash
lectern ramp run LECTURE.mp4 -o LECTURE-fast.mp4
```

`lectern ramp --help` explains the detector and where it does not apply.
