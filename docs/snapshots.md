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
versions. So the references are made on the CI image, which is the only machine that compares against them. A pixel
matches when it is within 2 % of the reference (`perceptualPrecision` 0.98), and every pixel has to match
(`precision` 1), so a small view in a large picture cannot hide a wrong color.

## Recording

Only the CI image records. `make snapshots` never writes a file: a missing reference fails the test. The
`record-snapshots` workflow runs `make snapshots RECORD=1` (every test fails on purpose, because that is how recording
reports itself), runs `make snapshots` again to check the new references, commits `__Snapshots__`, and starts CI for the
new commit, since a push by the workflow token starts no workflow.

Start it with `gh workflow run record-snapshots.yml --ref <branch>` or from the Actions tab. GitHub runs a dispatch of
a workflow that is on `main` only, so on a branch that adds or changes the workflow, put the label `record-snapshots` on
the pull request instead. Then look at the PNGs in the diff: a reference is only as good as the person who read it.

## When a snapshot test fails

The failure names the reference and the picture it got; the picture, the reference, and the difference are in the folder
`$SNAPSHOT_ARTIFACTS` (the temporary folder if it is not set). If the change is meant, record again. If it is not, fix
the view. `make snapshots` on a Mac with another macOS version than the CI image can fail on the edges of text without
any change to the code; run it there to see the difference, and trust the CI run.
