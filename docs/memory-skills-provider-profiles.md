# Memory, Skills, and Provider Profiles

This document describes the persistent-memory, reusable-Skills, learned-workflow,
searchable-model, and custom-provider-profile features.

## Overview

The implementation separates three kinds of knowledge:

1. **Long-term memory** contains short, curated facts and preferences that may
   be useful in a future chat.
2. **User Skills** contain reusable natural-language procedures selected by a
   slash command or relevant trigger words.
3. **Learned workflows** contain successful Android action sequences. They are
   managed separately because replaying UI actions has a higher safety risk.

Provider profiles are independent from memory. They allow users to store and
switch between named OpenAI-compatible API configurations without putting API
keys into profile metadata.

## Long-term memory

Open:

```text
Settings -> Memory & Skills -> Memory
```

From this screen, users can add, edit, disable, or delete an entry. Supported
categories are `general`, `user`, `system`, `project`, and `workflow`.

The chat also accepts these commands:

```text
/remember User prefers concise answers in Russian
/memory
/forget concise answers
```

`/forget` deletes an entry only when the query resolves to one result. If more
than one entry matches, the user is asked to select the entry in the management
screen.

Memory is stored locally and survives a new chat or application restart. The
agent does not inject the entire database into each request. It selects up to
eight relevant enabled entries and limits injected memory to 4,000 characters.
Stored entries are bounded to a total of 12,000 characters.

The memory service rejects empty or oversized entries, exact duplicates,
common secret formats, prompt-injection phrases, and invisible Unicode control
characters. Recalled memory is labeled as lower-priority user context; it must
not override system or safety instructions.

Good memory entries are compact and stable:

```text
User prefers short answers in Russian.
For project X, open application Y before starting the workflow.
```

Do not store passwords, API keys, recovery codes, authentication tokens,
private keys, or temporary screen content.

## User Skills

Open:

```text
Settings -> Memory & Skills -> Skills -> Add
```

A Skill contains:

- a display name;
- a stable slash-command name derived from the display name;
- a short description;
- comma-separated trigger words or phrases;
- the reusable procedure, pitfalls, and verification instructions;
- an enabled/disabled state.

Example:

```text
Name: Battery check
Description: Review battery usage without changing settings
Triggers: battery, charge, power usage
Instructions: Open Android battery settings. Report the current charge and the
three applications with the highest usage. Do not disable or modify anything
without explicit user confirmation.
```

Users can list the catalog with:

```text
/skills
```

They can invoke a Skill explicitly:

```text
/battery-check
```

They can also use a normal request containing a configured trigger. Each model
request receives only a compact catalog. The complete procedure is loaded only
for explicitly selected or lexically relevant Skills, with at most three full
Skills loaded per request.

Skills are model instructions, not executable Dart, shell, or Android code.
Users can edit, disable, or delete them at any time.

## Learned Android workflows

Open:

```text
Settings -> Memory & Skills -> Learned
```

This tab lists successful action sequences learned by the existing automation
engine. The implementation makes replay conservative:

- legacy and newly learned workflows have automatic replay disabled by default;
- exact `type_text` content is never persisted by new code;
- a workflow containing `type_text` cannot be made eligible for automatic
  replay;
- email addresses, long phone numbers, and credential assignments are redacted
  from stored task descriptions;
- matching supports both Cyrillic and Latin tokens.

Automatic replay should be enabled only for harmless, fully reviewed navigation
sequences. It should not be enabled for messages, calls, SMS, purchases,
deletion, account changes, security settings, or any action with an external
side effect.

## Searchable provider models

In Settings or onboarding:

1. Enter the provider API base URL and API key.
2. Fetch the provider's model list.
3. Type any substring into the model search field.
4. Select a filtered model ID.

The picker shows a live result count. If a provider does not expose a compatible
models endpoint, users can still enter the model ID manually.

## Named Custom provider profiles

To create a profile:

1. Open Settings.
2. Configure the API base URL, API key, model, temperature, token limit,
   automation-step limit, screen compression, and system-prompt options.
3. Select **Save as Custom profile**.
4. Enter a descriptive name.

Saved profiles appear in **Saved Custom profile**. Selecting one restores its
settings. Saving with the same name updates the selected profile; saving under
a different name creates a new profile. The selected profile can be deleted
from the same section.

Profile metadata contains the base URL, model, and runtime options, but not the
API key. Each profile key is stored separately through
`flutter_secure_storage`, backed by the Android Keystore. The active legacy key
is migrated once from `SharedPreferences`, after which the unencrypted entry is
removed. Android application backup is disabled so encrypted values are not
restored without their original Keystore key.

## Main implementation files

```text
lib/models/agent_memory_entry.dart
lib/models/provider_profile.dart
lib/models/user_skill.dart
lib/models/saved_skill.dart
lib/services/agent_memory_service.dart
lib/services/provider_profile_service.dart
lib/services/text_relevance.dart
lib/services/user_skill_service.dart
lib/services/skill_memory_service.dart
lib/screens/memory_skills_screen.dart
lib/widgets/searchable_model_picker.dart
```

Memory and Skill context is assembled in `lib/services/ai_service.dart`. Chat
commands are handled in `lib/screens/home_screen.dart`. Learned-workflow safety
rules are enforced in `lib/services/skill_memory_service.dart` and
`lib/services/task_executor.dart`.

## Validation

Run:

```bash
flutter pub get
flutter analyze lib test --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
```

The included model and service tests cover Cyrillic relevance tokenization,
memory secret/prompt-injection rejection, stable Skill command names, provider
profile serialization without API keys, and the prohibition on replaying typed
text.

The Settings profile controls and memory/Skill dialogs use responsive and
scrollable layouts to avoid Flutter overflow indicators on narrow Android
screens and when the software keyboard is open.

## Current limitations and recommended follow-up

This is a conservative first phase, not a full autonomous-learning system:

- old chat sessions are not indexed with full-text search;
- the application does not run a background model review after every chat;
- automatic memory proposals do not yet have a pending/approve/reject queue;
- Skills do not yet import or export the `SKILL.md` format;
- encrypted profile export and a one-button memory erase flow are not included.

Before unattended or production use, the broader application also needs strict
Telegram owner/chat authorization, an allowlist for Shizuku operations,
confirmation gates for sensitive actions, production signing, and physical
device testing of encrypted-key migration and Accessibility workflows.
