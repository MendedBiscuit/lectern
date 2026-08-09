# Audio

## Phase-inverted stereo

Some lecture-capture rigs record the right channel as a polarity flip of the
left. Nothing in the usual checks shows it: both channels play normally, both
measure around −26 dBFS mean, ffprobe reports an ordinary AAC stereo stream.

Downmixing to mono cancels them:

```
left        mean  -26.5    peak  -1.8
right       mean  -26.6    peak  -1.8
mid  (L+R)  mean  -44.3    peak  -3.9
side (L-R)  mean  -26.6    peak  -1.8
```

`ffmpeg -ac 1` averages the channels, producing the mid. Whisper's VAD scores
that as non-speech and discards it, returning only whatever leader or bumper is
genuinely mono. No error is raised.

It also affects listening: hollow, no centre image, and nearly inaudible on a
mono speaker.

### Diagnosing

Per-channel levels will not detect it. Two things will:

```bash
# compare sum against difference
ffmpeg -i IN -vn -af "pan=mono|c0=0.5*c0+0.5*c1,volumedetect" -f null -
ffmpeg -i IN -vn -af "pan=mono|c0=0.5*c0-0.5*c1,volumedetect" -f null -

# phase correlation: +1 identical, 0 uncorrelated, -1 inverted
ffmpeg -ss 600 -t 120 -i IN -vn \
  -af "aphasemeter=video=0:phasing=0,ametadata=print:key=lavfi.aphasemeter.phase:file=-" \
  -f null - 2>/dev/null | grep -oP 'phase=\K[-0-9.]+'
```

An inverted file reads a median near −1.000 with side 15–20 dB above mid. A
normal one reads +1.000 with side 60 dB below mid. The two cases are far apart.

`lectern probe` runs both over three sampled windows.

### Recovering

Use the difference:

```
pan=mono|c0=0.5*c0-0.5*c1
```

A single channel also works, but the difference is about 3 dB better: both
channels carry the same signal with independent codec quantisation noise, so
subtracting adds the signal coherently while the noise adds in quadrature.

### It varies per file

The same rig can produce affected and unaffected recordings. Check every file.

## Cleaning up for listening

`lectern clean`: downmix → 80 Hz high-pass → two-pass EBU R128 loudnorm →
true-peak limiter, video stream-copied. Three settings matter.

**loudnorm's second pass needs measurements from the exact preceding chain.**
Measure after the pan and high-pass, not on the raw file. Both change the
integrated loudness, and mismatched `measured_*` values make the second pass
overshoot.

**`alimiter`'s `level` option defaults to `true`,** which auto-levels the output
back to full scale and undoes the headroom. The symptom is peaks at exactly
0.0 dB. Pass `level=false:latency=true`.

**Lossy encoding adds overshoot after the limiter,** 1–2 dB of inter-sample
peaks. Limit to about −2.5 dBFS to land under −1.5 dBTP.

Re-measure the output rather than assuming.

## ASR settings

- `condition_on_previous_text=False`. Whisper loops on repetitive input;
  repeated filler is enough to make it emit the same sentence for minutes.
- `vad_filter=True` with `min_silence_duration_ms=700` suits a lecture, skipping
  the silences while someone writes. Note that VAD is a threshold: quiet audio
  produces an empty transcript rather than a poor one. `--no-vad` is the
  diagnostic.
- `distil-large-v3` on int8 CPU: 55 minutes in about five minutes on 16 threads.
  `large-v3` is slower and marginally better on proper nouns. Neither is
  reliable for notation.
