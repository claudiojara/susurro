# 0013. Parakeet takes whole clips; chunking is for providers that have a limit

- Status: accepted
- Date: 2026-10-14

## Context and Problem Statement

The design left an open question: what is the longest clip Parakeet v3 takes in one call (`maxClipDuration`)? The pipeline
splits a clip longer than that at pauses (`AudioChunker`) and joins the transcripts. A recording may run for ten minutes.

## Considered Options

- Give `ParakeetRecognizer` a limit (60 s, say) and let the pipeline split every long clip.
- Leave the limit nil, because FluidAudio splits long audio itself (windows of about 15 s with 2 s of overlap).

## Decision Outcome

The limit is nil. The opt-in `RealModelTests` (`longClip`) hand Parakeet whole clips of synthetic Spanish speech on an M1 Max
with macOS 26.6.2 and FluidAudio 0.17.7. Every clip came back complete:

| Clip | Sentences found | Time |
| --- | --- | --- |
| 30 s | 4 of 4 | 0.5 s |
| 60 s | 8 of 8 | 1.1 s |
| 121 s | 16 of 16 | 1.3 s |
| 152 s | 20 of 20 | 4.6 s |
| 607 s (ten minutes) | 80 of 80 | 7.4 s |

A ten-minute dictation takes 7.4 s, inside the 30 s limit of one transcription call, so the recording cap is ten minutes and
the pipeline hands over the clip whole.

`AudioChunker` and `ChunkedTranscriber` stay, behind `SpeechRecognizer.maxClipDuration`, for the providers that do have a
limit (Deepgram, a local Whisper server, the on-device speech framework of macOS for very long audio). A new provider
declares its limit, and the pipeline splits at pauses.

### Consequences

- Good: no seam in the transcript of a long dictation; no code path for Parakeet that splits audio.
- Bad: the 30 s call limit, not the model, sets the longest clip. A slower Mac (an 8 GB M1 under load) would need a limit
  that scales with the clip. Revisit if a user reports a timeout on a long dictation.
