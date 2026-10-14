# 0030. Busy presses use a FIFO ProcessingQueue

- Status: accepted
- Date: 2026-10-14

## Context and Problem Statement

A user can press the hotkey again while the last dictation is still being transcribed or cleaned up. Ignoring the press
loses speech. Processing the recordings at the same time lets a short, quick dictation overtake a long one, so the texts
reach the app out of the order they were spoken, and the speech model works on one clip at a time anyway.

## Considered Options

- Ignore presses while a dictation is processing (the walking skeleton's busy guard).
- Process recordings at the same time, and insert each text when it is ready.
- Queue the finished recordings and process them one at a time, first in, first out.

## Decision Outcome

A `ProcessingQueue` actor in `SusurroCore/Pipeline`. At most one recording is active, but a finished recording becomes a
job at once, so recording never waits for processing. Jobs run one at a time in the order they were finished, which keeps
the insertions in the order they were spoken.

The queue reports how it ended for each job: `jobEnqueued` when a job is queued and `jobFinished` exactly once when it
ends, whichever way (done, no speech, failed, or cancelled, a cancelled job that never started included). Both carry the
number of jobs in flight after the change, which arms Esc while any job is in flight and disarms it after the last. A
waiting job that is cancelled never starts, and the jobs ahead of it are not touched. A running job gets its task
cancelled and is reported cancelled whatever it returns, so a late result of a cancelled dictation is never inserted.

A retry from the history does not go through the queue: it never inserts, so it neither waits for live dictations nor
holds them back.

### Consequences

- Good: speech is never lost, and the insertion order is the speaking order.
- Good: Esc and the overlay read one count of jobs in flight.
- Bad: a long dictation delays the text of the ones behind it. Accepted: the order matters more than the delay, and the
  overlay shows what is still pending.
