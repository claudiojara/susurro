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

## Silero VAD

The voice activity model that finds the speech in a recording, so a recording of silence is not transcribed.
https://github.com/snakers4/silero-vad (by the Silero Team), in the Core ML conversion that FluidInference publishes at
https://huggingface.co/FluidInference/silero-vad-coreml, pinned to commit `b419383c55c110e2c9271fa6ee0ea83d03c70d96`.
Susurro downloads it on the first recording it analyzes; it is not part of the app bundle.

MIT License. Copyright (c) 2020-present Silero Team.

## text-processing-rs

A text normalization library that FluidAudio can link as a prebuilt binary (`NemoTextProcessing`).
https://github.com/FluidInference/text-processing-rs, release 0.3.1 (by FluidInference).

Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0). Susurro turns the
FluidAudio trait that links it off, because dictation does not use it, but the package manager still downloads it, so it
is listed here.

## fastcluster

Hierarchical clustering for speaker diarization. https://github.com/fastcluster/fastcluster. FluidAudio builds it as C++
in its `FastClusterWrapper` target, which its library links, so the code is part of Susurro's build although dictation
never calls it.

BSD 2-Clause License. Copyright:

- Until package version 1.1.23: (c) 2011 Daniel Müllner <https://danifold.net>
- All changes from version 1.1.24 on: (c) Google Inc. <https://www.google.com>

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
following conditions are met:

- Redistributions of source code must retain the above copyright notice, this list of conditions and the following
  disclaimer.
- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
  disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## VBx

Speaker clustering. FluidAudio's offline diarizer is a Swift port of it (`VBxClustering`), built into its library.
https://github.com/BUTSpeechFIT/VBx, Copyright 2021-2024 BUT Speech@FIT (Brno University of Technology).

Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).

## Misaki, cutlet, and Convert-Numbers-to-Japanese

FluidAudio's Japanese text frontend for speech synthesis is a Swift port of these three, built into its library:

- Misaki, https://github.com/hexgrad/misaki, under the Apache License, Version 2.0
  (http://www.apache.org/licenses/LICENSE-2.0).
- cutlet, https://github.com/polm/cutlet, under the MIT License. Copyright (c) 2020 Paul O'Leary McCann.
- Convert-Numbers-to-Japanese, https://github.com/Greatdane/Convert-Numbers-to-Japanese, under the MIT License.
  Copyright (c) 2018 David Wilson, https://github.com/Greatdane.

The MIT License:

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

The dictionary and word list that this frontend reads (UniDic, under the BSD license) are downloaded by FluidAudio only
when it synthesizes Japanese speech, which Susurro does not do, so they are not part of Susurro and are not listed.
The same goes for the other data in FluidAudio's `ThirdPartyLicenses` folder: the Spanish and French lexicons and the
Kokoro conversion notices.

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
