# Snapshot tests

A presentational view has a snapshot test: a picture of the view is compared with a reference PNG in `__Snapshots__`,
next to the test file. The suites that hold them have `Snapshot` in their name (`AtomSnapshotTests`), which is how
`make test` skips them and `make snapshots` runs them. Each atom has a gallery in `Sources/DesignSystem/Atoms/` that
shows all its variants; the previews and the snapshot tests draw the same gallery, so there is one list of variants.

## How a picture is made

`SnapshotSupport` (`Sources/UITestSupport`) fixes everything that could make two runs differ:

- the canvas size (360 by 280 points unless the test says otherwise), with a margin, on the theme's window color;
- the scale, 2 pixels to the point, whatever screen the machine has;
- the theme (the default unless the test gives one) and the appearance, which the test names, never the system's;
- the locale (`en_US`), the layout direction, the legibility weight, and `\.motionEnabled`, which is off, so a view is
  drawn in its end state.

The view is drawn by `ImageRenderer.render` into a bitmap of our own, on the CPU, in sRGB. `ImageRenderer.cgImage` and a
hosting view are not used: the first picture of a view that `cgImage` made differed in a few pixels from the later ones
(a pill needed three), and a hosting view takes its scale from the screen. With the bitmap, a view gives the same bytes
from the first picture on, in any order and in any process.

What stays outside our control is the macOS version: the fonts and the way text is drawn change a little between
versions. So the references are made on the CI image, which is the machine that compares against them. A picture
matches when 99.9 % of its pixels do (`precision` 0.999), and a pixel matches when it is within 2 % of the reference
(`perceptualPrecision` 0.98). Both numbers were measured: the same code drawn on macOS 26.6.2 and on the CI image
(27.0.1) differed in a few hundredths to a tenth of a percent of the pixels, all at the edges of letters, and at 99.99 %
five of the six pictures failed. So a view can change by up to a tenth of a percent of its canvas without a snapshot test
noticing, and two things keep that from hiding a mistake:

- **Small canvases.** Each atom gallery is drawn on a canvas just big enough for it (`AtomCanvas` in the tests). Recoloring
  the smallest view of a gallery (a caption-sized icon, a status dot) changes about 200 pixels, so the canvases are small
  enough to let fewer than two thirds of that through. `AtomCanvasTests` measures it: a canvas must hold its gallery with
  little to spare, and the smallest recolor must change at least 1.5 times as many pixels as the canvas lets pass.
- **Exact colors.** `AtomColorTests` reads the pixels each atom paints and compares them with the token, to within one step
  of a channel: the middle of a dot, the fill and the track of a bar, the fill and the title of a button in each state, and
  a pixel inside a stroke of a label, an icon, or a pill's text. A snapshot says the picture did not change; these say the
  colors are the right ones.

## Adding an atom

An atom is a public struct that is a `View` in `Sources/DesignSystem/Atoms`. `AtomCoverageTests` finds it by reading the
folder and fails, naming the step, until all of these are done:

1. **The atom.** Colors come from a `Tint` (an optional one for text), sizes and states from tokens, and the text VoiceOver
   says from `label:`. Add a token to the theme for anything it needs that is not there: do not borrow the token of another
   role. `AtomConventionsTests` checks the shape of the initializer; the token lint checks that no literal is written.
2. **A gallery** (`extension MyAtom { struct Gallery }` in `AtomGalleries.swift`) that shows every variant: every `Tint`
   with `Tint.allCases`, every kind, every state. One `#Preview("MyAtom") { PreviewMatrix { MyAtom.Gallery() } }` in the
   atom's file draws it in light and dark on every bundled theme.
3. **A canvas** (a case of `AtomCanvas` in `Tests/DesignSystemTests/Atoms`) just big enough for the gallery, and the smallest
   variant of it in `recoloredPixels`. Take the size from `AtomCanvasTests`, which says how far the canvas is from the
   gallery.
4. **A snapshot test** in `AtomSnapshotTests`, in light and dark, that draws the gallery on its canvas.
5. **A color test** in `AtomColorTests` that reads the colors the atom paints, in light and dark.
6. **The list of atoms** in `AtomConventionsTests.atomsAreFound`.
7. **The references.** Put the label `record-snapshots` on the pull request and read the new pictures.

## Recording

Only the CI image records. `make snapshots` never writes a file: a missing reference fails the test. Recording is the
`record-snapshots` workflow, which runs on the branch of an open pull request and nowhere else.

Start it by putting the label `record-snapshots` on the pull request, or with `gh workflow run record-snapshots.yml
--ref <branch>` once the workflow is on `main` (GitHub dispatches only workflows that are on the default branch, so on
a branch that adds or changes the workflow the label is the only way). Then look at the PNGs in the diff: a reference is
only as good as the person who read it.

The workflow has three jobs, so that the code of a pull request never runs next to a token that can write:

1. **target** reads the open pull requests and refuses the default branch and any branch that has no open pull request
   from this repository (a fork, a closed pull request, a branch nobody reviews). It hands the commit to record on to
   the next jobs. It runs `.github/scripts/guard-record-target.sh`.
2. **record** runs the pull request's code (`make snapshots RECORD=1`, then `make snapshots` to check) with a read-only
   token and no credentials in `.git`. Every test fails on purpose while recording, because that is how recording
   reports itself. It packs the pictures and `environment.txt` and uploads them as an artifact.
3. **commit** runs none of that code. It unpacks the artifact after checking that every entry is a regular file named like
   a snapshot picture inside a `__Snapshots__` folder of a package's `Tests`, commits it as `github-actions[bot]`, pushes,
   and starts CI for the new head, since a push by the workflow token starts no workflow. The write token is in the last
   step only (`.github/scripts/publish-references.sh`).

If the job fails after the push (the CI dispatch is the usual place), run the workflow again, or re-run the failed
job. The push step finds that the branch already has the references, and starts CI for the head whenever the head has no
CI run that passed, failed, or is still going (a run waiting for approval gives no result). The same is one command:
`gh workflow run ci.yml --ref <branch>`. If the branch moved while the pictures were recorded, the push is refused and
nothing is overwritten: run the workflow again.

## The runner image

`runs-on: xcode-27` is a label that GitHub moves to newer images; there is no way to pin an image version. So the
references say which machine made them: recording writes `environment.txt` next to them (`__Snapshots__`), with the macOS
version and build and the Xcode version and build. A run on CI that finds other values fails with "the runner image
changed" and tells you to record again, instead of failing a list of pictures that look the same. A run on another Mac
only prints a note, since it is known to differ. Both workflows log `sw_vers`, `xcodebuild -version`, and the image
version at the start of the job.

Because 99.9 % leaves little room for an image that moves the letters, expect to record again when the image changes.

## When a snapshot test fails

The failure names the reference and the picture it got. On CI the picture that failed, the reference
(`<name>-reference.png`), and the difference (`<name>-difference.png`) are in the artifact `snapshot-failures` of the run.
Locally they are in the folder `$SNAPSHOT_ARTIFACTS`, or the temporary folder if it is not set. If the change is meant,
record again. If it is not, fix the view. `make snapshots` on a Mac with another macOS version than the CI image can fail
on the edges of text without any change to the code; run it there to see the difference, and trust the CI run.
