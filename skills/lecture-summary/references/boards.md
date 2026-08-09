# Reading the picture

The frames are the authoritative copy of the content. Read them; do not OCR
them.

## Sampling

One frame every 30 seconds. A 55-minute lecture gives about 110 frames.

Blackboards accumulate: the lecturer fills panel 1, then 2, then 3, and wipes
only when out of space. Consecutive frames usually differ by a line or two, and
the last frame before a wipe contains everything that was on that board. So:

1. Scan every fifth frame to find the wipes.
2. Read each board's final state in full, before its wipe.
3. Spot-check the skipped frames to confirm nothing was written and erased
   between two samples you looked at.

Step 3 is cheap and is the only guard against a silently missing result.

If the lecturer wipes constantly or uses a rolling board, drop to `--every 15`.

## Enlarging

At 1280×720 a line of chalk is about 25 pixels high. Subscripts, primes, bars
and hats are not legible at that size.

```bash
lectern crop frames/f110.jpg 620x180+635+15 --zoom 400 -o board1.png
lectern crop frames/f110.jpg 130x28+290+278 --zoom 900 --sharpen -o const.png
```

Geometry is `WIDTHxHEIGHT+X+Y` from the top-left. Crop generously first, then
tighten. `--sharpen` helps on chalk and hurts on projected slides.

Anything still unreadable after a 900% crop is not in the recording. Say so.

## What the camera loses

- **Projected slides and screens**, routinely blown out to white by a camera
  exposing for a lit room. Not recoverable. Point at the posted slides and note
  that you did.
- **The bottom of a board**, often below frame or behind heads.
- **Anything the lecturer stands in front of** for as long as it exists.

Recording these as gaps is more useful than filling them from your own
knowledge, because the reader can then go and find the real thing.

## Cross-checking the transcript

Where a board and the transcript disagree, the board is correct. The transcript
is still useful as a check on your own reading: if you read a symbol as `p` and
the lecturer is clearly saying "q" at that timestamp, look again.

Watch for ASR-inserted content that is locally plausible: an extra item in a
list, a digit that fits the surrounding pattern. Verify any data taken from the
transcript rather than prose.

## Slides and document cameras

**Slide decks**: if the posted PDF exists, use it as the content source and the
recording only for what was said over each slide. Frame-match timestamps to
slide numbers to produce an annotated deck.

**Document cameras** (pen on paper, shot from above): the picture is usually
better than a theatre board, but pages get swapped, so there is no accumulation.
Every page is its own board and a page that leaves frame is gone. Sample at
`--every 15` or tighter.
