# LootTracker Testing Guide

This document explains how to test LootTracker thoroughly, even when you're solo and outside of a raid environment.

## Quick Start

After loading the addon in-game:

```
/lt sim full       # Generates test data and opens windows
/lt test           # Runs all unit tests
/lt debug on       # Enables verbose logging
```

---

## Testing Commands Overview

| Command | Purpose |
|---------|---------|
| `/lt test` | Run unit tests |
| `/lt sim` | Simulation commands |
| `/lt debug` | Debug/logging tools |

---

## Unit Tests (`/lt test`)

The addon includes a built-in test framework that validates core functionality.

### Running Tests

```lua
/lt test           -- Run all test suites
/lt test list      -- List available test suites
/lt test Database  -- Run only Database tests
/lt test Events    -- Run only Events tests
```

### Test Suites

| Suite | What It Tests |
|-------|--------------|
| `Database` | Roll sessions, attendance, stats, data persistence |
| `Events` | Roll message parsing, item link extraction |

### Understanding Results

```
=== Running Test Suite: Database ===
  ✓ test_Initialize_CreatesDefaultStructure    # Green = passed
  ✗ test_Something_Fails                       # Red = failed
    Error: expected 5, got 3                   # Failure reason
  12 passed, 1 failed
```

### What to Look For

- **All green**: Core logic is working correctly
- **Roll parsing failures**: Check `test_ParseRoll_*` tests - these validate that we correctly parse the "Player rolls X (1-100)" format
- **Database failures**: Data persistence or session logic issues

---

## Simulation (`/lt sim`)

Since you can't easily get 25 people to `/roll` for testing, the simulation module lets you fake roll events.

### Basic Commands

```lua
/lt sim session [item]      -- Start a test roll session
/lt sim roll [name] [value] -- Simulate a specific roll
/lt sim players [count]     -- Simulate N random players rolling
/lt sim tie                 -- Create a tie scenario for testing reroll
```

### Recommended Test Scenarios

#### Scenario 1: Basic Roll Flow
```lua
/lt sim session [Thunderfury]
/lt sim players 5
/lt end
```
**What to verify:**
- Roll tracker window shows all 5 rolls
- Winner is correctly identified (highest roll)
- History is updated after `/lt end`

#### Scenario 2: Tie Breaking
```lua
/lt sim tie
-- You'll see two players tied
/lt reroll
-- Simulate new rolls for the tied players
/lt sim roll TiePlayer1 75
/lt sim roll TiePlayer2 60
/lt end
```
**What to verify:**
- Tie is detected correctly
- Only tied players can roll in reroll round
- Winner determined after reroll

#### Scenario 3: Data Persistence
```lua
/lt sim history 20    -- Generate 20 fake history records
/lt sim attendance 5  -- Generate 5 raid attendance records
/reload               -- Reload UI
/lt history           -- Check if data persisted
/lt stats Thunderfury -- Check player stats
```
**What to verify:**
- Data survives `/reload`
- Stats calculated correctly
- History shows in main window

#### Scenario 4: Full Scenario
```lua
/lt sim full
```
This generates:
- 10 attendance records
- 20 loot history records
- An active roll session with 8 players
- Opens both main window and roll tracker

#### Scenario 5: Stress Test
```lua
/lt sim stress 100
```
Runs 100 complete roll sessions and reports:
- Time taken
- Memory usage
- Records created

**What to look for:**
- Should complete in <5 seconds
- Memory should not grow excessively
- No Lua errors

---

## Debug System (`/lt debug`)

### Enabling Debug Mode

```lua
/lt debug on         -- Enable logging
/lt debug level 4    -- Set to TRACE level (most verbose)
```

### Debug Levels

| Level | Name | What's Logged |
|-------|------|--------------|
| 1 | ERROR | Only errors |
| 2 | WARN | Errors + warnings (default) |
| 3 | INFO | General information |
| 4 | TRACE | Everything (very verbose) |

### Viewing Logs

```lua
/lt debug log        -- Show last 20 log entries
/lt debug log 50     -- Show last 50 entries
```

### State Inspection

```lua
/lt debug dump database   -- Show database state
/lt debug dump events     -- Show event handler state
/lt debug dump sync       -- Show sync state
/lt debug dump perf       -- Show performance metrics
/lt debug dump all        -- Show everything
```

### What to Log When Testing

1. **Before starting a test session:**
   ```lua
   /lt debug on
   /lt debug level 3
   ```

2. **Run your test scenario**

3. **After the test:**
   ```lua
   /lt debug log 100
   ```

4. **Save the output** - Copy from chat for later analysis

### Event Tracing

For deep debugging of WoW events:
```lua
/lt debug events     -- Toggle event tracing
```
This logs ALL WoW events (filtered for relevance). Warning: very verbose!

---

## Manual Testing Checklist

### Phase 1: Core Roll Tracking

- [ ] Start session with `/lt sim session Test Item`
- [ ] Simulate 5 rolls with `/lt sim players 5`
- [ ] Verify roll tracker UI shows correct data
- [ ] End session with `/lt end`
- [ ] Verify winner announced correctly
- [ ] Verify history updated (`/lt history`)

### Phase 2: Tie Handling

- [ ] Create tie with `/lt sim tie`
- [ ] Verify tie is detected
- [ ] Initiate reroll with `/lt reroll`
- [ ] Simulate rerolls for tied players
- [ ] End and verify winner

### Phase 3: Attendance

- [ ] Start raid with `/lt sim raid 20`
- [ ] Verify attendee list
- [ ] End raid with `/lt raid end`
- [ ] Check attendance stats for a player

### Phase 4: UI

- [ ] Open main window (`/lt`)
- [ ] Navigate each tab (History, Stats, Attendance, Config)
- [ ] Open export window (`/lt export`)
- [ ] Test each export format (CSV, Markdown, Discord)
- [ ] Verify "Select All" works for copying

### Phase 5: Data Persistence

- [ ] Generate data with `/lt sim full`
- [ ] `/reload` the UI
- [ ] Verify all data persisted

### Phase 6: Edge Cases

- [ ] Cancel session mid-roll (`/lt cancel`)
- [ ] Start session when one already active
- [ ] End session with no rolls
- [ ] Very long item names
- [ ] Player names with special characters

---

## Interpreting Test Results

### Common Issues

| Symptom | Likely Cause | Debug Command |
|---------|--------------|---------------|
| Rolls not captured | Roll parsing failed | `/lt debug dump events` |
| Winner not determined | Tie not resolved | Check reroll state |
| Data lost on reload | SavedVariables issue | Check WTF folder |
| UI not updating | Event handler issue | `/lt debug events` |

### SavedVariables Location

Your data is stored in:
```
World of Warcraft/_retail_/WTF/Account/[ACCOUNT]/SavedVariables/LootTracker.lua
```

You can inspect this file directly to see raw data.

---

## Reporting Bugs

When reporting issues, include:

1. **Steps to reproduce**
2. **Debug log output:**
   ```lua
   /lt debug on
   /lt debug level 4
   -- reproduce the issue
   /lt debug log 100
   ```
3. **State dump:**
   ```lua
   /lt debug dump all
   ```
4. **Test results:**
   ```lua
   /lt test
   ```

---

## Advanced: Writing New Tests

Tests are defined in `Tests/DatabaseTests.lua` and `Tests/EventsTests.lua`.

### Test Structure

```lua
test_DescriptiveName = function(ctx)
    -- Arrange
    LT.DB:StartRollSession("Test Item", "Tester")

    -- Act
    local success = LT.DB:RecordRoll("Player", 85, 1, 100)

    -- Assert
    ctx.assert.isTrue(success, "Should record roll")
    ctx.assert.equals(#LT.DB:GetActiveSession().rolls, 1, "Should have 1 roll")
end,
```

### Available Assertions

```lua
ctx.assert.equals(actual, expected, message)
ctx.assert.notEquals(actual, notExpected, message)
ctx.assert.isTrue(value, message)
ctx.assert.isFalse(value, message)
ctx.assert.isNil(value, message)
ctx.assert.isNotNil(value, message)
ctx.assert.isType(value, "table", message)
ctx.assert.contains(table, value, message)
ctx.assert.hasKey(table, key, message)
ctx.assert.greaterThan(actual, threshold, message)
ctx.assert.matches(string, pattern, message)
```

---

## Data Collection for Future Iterations

### What to Record

After each testing session, note:

1. **Test date and WoW version**
2. **Tests run and results**
3. **Any Lua errors** (check with `/script print(GetCVar("scriptErrors"))`)
4. **Performance observations**
5. **UI/UX issues noticed**
6. **Feature gaps identified**

### Suggested Testing Cadence

| When | What |
|------|------|
| After code changes | `/lt test` (unit tests) |
| Before raid testing | `/lt sim full` + manual checks |
| After raid testing | `/lt debug dump all` + export data |
| Weekly | `/lt sim stress 500` (performance) |
