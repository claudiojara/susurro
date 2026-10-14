# 0017. The interface language switches live through one observable locale

- Status: accepted
- Date: 2026-10-14

## Context and Problem Statement

The app's words were English only, spread over Swift `*Copy` types and a small string catalog. The user wants to pick
the interface language in Settings: System (the default, following macOS), English, or Spanish. Susurro is a menu bar
app (`LSUIElement`): its surfaces are the SwiftUI menu of `MenuBarExtra`, three SwiftUI windows hosted in AppKit, and the
overlay panel. The dictation language (`SpeechLanguageMode`) is a separate setting and keeps its meaning.

## Considered Options

- Write `AppleLanguages` for the app and ask for a relaunch, so Foundation picks the language at launch.
- Pass a `Locale` explicitly through every copy function and view model.
- One process-wide, observable language (`InterfaceLocale`) that every lookup reads, with the catalogs as the single
  source of the words.

## Decision Outcome

One observable language, live, without a relaunch.

- Each UI module has a string catalog (`SusurroFeatures/Presentation` and `SusurroUI`, both `defaultLocalization: "en"`)
  with an `en` and an `es` value for every key. Code looks words up through `L10n.string(key, englishDefault)`, which
  calls `InterfaceLocale.string`. It reads the sentence from the `<code>.lproj` folder of the module's bundle, so the
  chosen language wins over the languages the system prefers, and English is the fallback for a missing key.
- `InterfaceLocale` (DesignSystem) holds the language code behind a `Mutex` and reports reads and writes to an
  `ObservationRegistrar`. Every SwiftUI body and every computed view state that shows a word reads it, so all of them
  are drawn again when it changes. AppKit window titles follow it through `followLanguage`.
- The setting is `GeneralSettings.interfaceLanguage` (`system`, `en`, `es`) in `UserDefaults`, like the others. The app
  applies it at launch and when it is picked; `system` resolves to the first preferred language the app has, else
  English. The language names stay in their own language ("English", "Español") so they can be found in either.
- Tests pin a language with the task-local `InterfaceLocale.$override`, so tests running side by side never change the
  language of one another, and the app's own holder is set only by the live composition.

`AppleLanguages` plus a relaunch was rejected: every surface here is SwiftUI or a window title, so a live switch costs
little, and a relaunch would also drop a dictation in flight. Passing a locale everywhere was rejected for its size: it
would touch every copy function and view model signature for the same result.

### Consequences

- Good: a pick applies at once in the menu, the open windows, and the next overlay. The catalogs hold every word, and a
  test fails when a key lacks Spanish, has other placeholders in Spanish, or is not used by the code.
- Bad: the language is global state. Code that shows a word must look it up when it draws, not cache it; the overlay
  text already shown keeps its language until the next state. A change of the macOS language while System is picked
  applies at the next launch. Texts that macOS itself shows (the permission prompts' usage descriptions) and the reasons
  the speech adapters give for a failed load stay in English.
