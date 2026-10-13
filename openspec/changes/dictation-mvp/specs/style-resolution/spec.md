# Delta for Style Resolution

## ADDED Requirements

### Requirement: Categories and tones

The system MUST define the categories email, work_chat, personal_messaging, document, terminal, ai_chat, and other, and the tones formal, neutral, casual, veryCasual, and verbatim. Resolution MUST be a pure, deterministic function with no I/O.

#### Scenario: Same input, same output

- GIVEN identical app, URL, overrides, and table
- WHEN resolution runs twice
- THEN both results are equal

### Requirement: Default tone table

Defaults MUST be: email formal, work_chat casual, personal_messaging veryCasual, document neutral, terminal verbatim, ai_chat neutral, other neutral. The user MUST be able to change the tone of any category, and the change MUST persist.

#### Scenario: Four reference apps

- GIVEN default settings
- WHEN resolving Mail, Slack, Terminal, and a ChatGPT web page
- THEN the tones are formal, casual, verbatim, and neutral respectively

#### Scenario: Edited table

- GIVEN the user sets email to casual
- WHEN Mail is resolved after relaunch
- THEN the tone is casual

### Requirement: Precedence

Resolution MUST apply, in order: a manual override, then the browser URL host when the frontmost app is a browser, then the bundle id, then other/default tone. The result MUST report which rule decided it.

#### Scenario: Browser host beats bundle

- GIVEN Safari is frontmost on host mail.google.com
- WHEN resolved with no overrides
- THEN the category is email and the source is url

#### Scenario: Override wins

- GIVEN an override maps Slack to personal_messaging
- WHEN Slack is resolved
- THEN the category is personal_messaging and the source is override

### Requirement: Matching rules

Bundle ids MUST match by exact value or prefix. URL hosts MUST match case-insensitively after stripping "www.", including subdomains. An unknown app or host MUST resolve to other.

#### Scenario: Subdomain

- GIVEN a rule for slack.com
- WHEN host app.slack.com is resolved
- THEN the rule matches

#### Scenario: Unknown app

- GIVEN a bundle id with no rule and no URL
- WHEN resolved
- THEN the category is other and the source is default

### Requirement: Seed mappings

The shipped table MUST map at least: com.apple.mail to email; com.tinyspeck.slackmacgap to work_chat; com.apple.MobileSMS to personal_messaging; com.apple.Terminal and com.googlecode.iterm2 to terminal; host chatgpt.com and claude.ai to ai_chat; host mail.google.com to email.

#### Scenario: Seeds present

- GIVEN the shipped table
- WHEN each seed key is resolved
- THEN each yields its listed category

### Requirement: User overrides

The user MUST be able to override category, tone, or both for an app (bundle id) or a site (host). Overrides MUST persist and MUST be removable.

#### Scenario: Tone-only override

- GIVEN an override sets Notes to tone casual with no category change
- WHEN Notes is resolved
- THEN the category is document and the tone is casual
