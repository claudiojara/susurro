# Third-party notices

Susurro uses the software and the model weights below. Each keeps its own license, which applies to it and not to
Susurro's own code.

## KeyboardShortcuts

Global keyboard shortcuts for the dictation hotkey. https://github.com/sindresorhus/KeyboardShortcuts, version 3.1.0.

MIT License

Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## FluidAudio

Runs the speech model on the Apple Neural Engine. https://github.com/FluidInference/FluidAudio, version 0.17.7 (by
FluidInference).

Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0). The license text is the
`LICENSE` file at the root of that repository.

## text-processing-rs

A text normalization library that FluidAudio can link as a prebuilt binary (`NemoTextProcessing`).
https://github.com/FluidInference/text-processing-rs, release 0.3.1 (by FluidInference).

Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0). Susurro turns the
FluidAudio trait that links it off, because dictation does not use it, but the package manager still downloads it, so it
is listed here.

## Parakeet TDT 0.6b v3 model weights

The speech model that turns audio into text. The original model is NVIDIA's `parakeet-tdt-0.6b-v3`
(https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). The Core ML conversion that Susurro downloads on first run is
FluidInference's `parakeet-tdt-0.6b-v3-coreml` (https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml),
pinned to commit `7dd20fe6b1797d35f5e3307e8b1732d9a178edfe`.

Licensed under the Creative Commons Attribution 4.0 International license (CC BY 4.0,
https://creativecommons.org/licenses/by/4.0/). The weights were converted to Core ML and quantized by FluidInference,
which is a change to the original. The weights are not part of this repository: the app downloads them to
`~/Library/Application Support/Susurro/Models`.

## Before the app is distributed

The Apache License 2.0 asks that a copy of the license travels with the software it covers. This file names the
licenses; the release packaging has to bundle their full texts with the app.
