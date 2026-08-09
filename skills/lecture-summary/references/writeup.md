# Writing it up

## What it is for

Not a transcript and not a textbook section. It is what gets read instead of
re-watching, so it has to carry the content and the shape of the lecture: what
was built on what, what was skipped over, what the lecturer treated as the
point.

## Structure

- **Title, lecturer, date.** The date makes it findable.
- **Three or four sentences of abstract** giving the spine: what the lecture was
  doing and where it ended up. Write it last.
- **Sections in the lecture's own order.** Do not reorganise into logical order;
  the sequence is information, and it is what a reader comparing against their
  own notes needs.
- **Numbered environments** (definition / theorem / proposition / corollary) for
  anything stated as such, so it can be cited.
- **Proofs** where given. Where a proof was set as an exercise, say so and
  record the sketch the lecturer offered, since that is what the exercise
  expects.
- **Named asides** via `\paragraph{...}`: the anecdote, the warning, the common
  mistake.
- **A "to do" tail**: exercises set, material deferred, anything flagged and not
  answered.

## Fidelity

**Mark what is not from the lecture.** A standard remark the lecturer did not
make should either be left out or labelled as an editorial note. The reader is
comparing this against their own notes and their exam.

**Keep what the lecturer said about a result.** A description like "magical and
infuriating" conveys more about a non-constructive existence proof than a
paragraph of hedging.

**Record loose ends as loose ends.** "He flagged a reason coming soon and did
not give it" is the hook the next summary attaches to.

**Do not adjust numbers.** If the board says `≈ 0.374`, write that or note that
you have extended it. Silently improving the arithmetic makes the summary
disagree with the board.

## Coverage check

Before reporting completion:

1. **Write-up to lecture**: every claim traces to a board or a transcript line.
2. **Lecture to write-up**: re-read the transcript against the section list,
   looking for the sentences that explain why one result leads to the next.
   These compress out without leaving a hole.
3. **State what is missing**: anything the camera lost, anything unreadable,
   anything inferred.

## LaTeX

`assets/lecture.tex` is a working preamble: `amsmath`/`amsthm`/`amssymb`, 2.5 cm
margins, theorem environments in both styles, and some macros.

```bash
latexmk -pdf -outdir=build lecNN.tex
```

Check the log for overfull and underfull boxes and fix them. Then look at the
rendered pages (`pdftoppm -png -r 100 build/lecNN.pdf page`) rather than
trusting that it compiled.

One directory per lecture keeps `build/` collisions impossible:

```
<subject>/lec05/lec05.tex
<subject>/lec05/build/
```

## Writing back

The summary should leave a record outside its build directory: what was covered,
where the document is, and whether this lecture answered a question an earlier
one left open. Linking those makes a set of summaries usable for study.
