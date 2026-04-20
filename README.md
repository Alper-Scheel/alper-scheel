# ALVA-TEXT

Quick-and-dirty macOS menu bar dictation app.

## What it does
- Records microphone audio from global modifier-key hotkeys.
- Sends audio to OpenAI `/v1/audio/transcriptions` using `gpt-4o-mini-transcribe` and default language `de`.
- Optional polite rewrite mode via `gpt-4o-mini`.
- Copies the final text to clipboard and can auto-paste with simulated `⌘V`.

## Project
Open `ALVA-TEXT/ALVA_TEXT.xcodeproj` in Xcode 16+ on macOS Sequoia.

## Hotkeys
- **Standard hold:** `Control + Option` (hold to record).
- **Standard toggle:** double-press `Control + Option` within 350ms; press once again to stop.
- **Polite hold:** `Option + Command` (hold to record).
- **Polite toggle:** double-press `Option + Command` within 350ms; press once again to stop.

## Permissions
- Microphone permission (requested on startup).
- Accessibility permission for auto-paste (`⌘V` simulation).

## Settings window
- OpenAI API key (stored in `UserDefaults` for now).
- Auto-paste toggle.
- Enable/disable polite rewrite.
- Last transcript and last rewritten text.
