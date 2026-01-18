# Changelog

All notable changes to LootTracker will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-01-18

### Changed
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
