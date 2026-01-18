# Changelog

All notable changes to LootTracker will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-01-18

### Added
- **Joke Roll Removal**: Click any roll entry to remove it (for troll/joke rolls)
  - Hover shows red highlight and tooltip
  - Confirms removal in chat
- **Resizable Windows**: All windows can now be resized via drag grip in bottom-right corner
  - Roll Tracker: 200x200 to 500x600
  - Main Window: 350x280 to 800x700
  - Export Window: 300x250 to 700x600

### Changed
- **Compact Default Sizes**: Windows start smaller to reduce screen clutter
  - Roll Tracker: 300x400 → 250x300
  - Main Window: 600x500 → 450x350
  - Export Window: 500x450 → 380x320
- **WoW 12.0 (Midnight) Compatibility**: Updated Interface version to 120000
- **Secure Serialization**: Replaced `loadstring()`-based deserialization with safe parser
  - Prevents potential code injection from malformed addon messages
  - Future-proofs against WoW 12.0's stricter taint system

### Technical Notes
- LootTracker is minimally affected by Midnight's "secret values" restrictions since it:
  - Tracks loot rolls (system chat messages, not combat data)
  - Manages attendance (group roster queries, not combat-related)
  - Syncs data via addon messages (not affected by combat restrictions)

---

## [1.0.0] - 2026-01-18

### Added
- **Roll Tracking**: Start/end roll sessions with `/lt start [item]` and `/lt end`
- **Tie Detection**: Automatic detection of tied rolls with reroll support via `/lt reroll`
- **Attendance Tracking**: Track raid attendance with `/lt raid start/end/sync`
- **Player Statistics**: Win/loss records, average rolls, attendance rates
- **Loot History**: Persistent storage of all roll outcomes
- **Export System**: Export data in CSV, JSON, and BB Code formats
- **Officer Sync**: Cross-officer data synchronization via addon comms
- **Debug System**: Built-in debug logging with `/lt debug`
- **Test Framework**: Comprehensive unit tests and simulation tools
- **UI Components**: Roll tracker window, main window, export dialog

### Core Features
- Full SavedVariables persistence across sessions
- Modular architecture (Core, UI, Tests)
- Guild/raid officer permission checks
- Raid warning announcements for roll sessions
