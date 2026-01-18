--[[
    LootTracker - Database Module
    Handles all data storage, retrieval, and statistics calculations
    Data persists via WoW's SavedVariables system
]]

local _, LT = ...
LT.DB = {}

-- Default database structure
local DB_DEFAULTS = {
    -- Roll session history
    rolls = {},

    -- Player statistics
    stats = {},

    -- Attendance records
    attendance = {
        raids = {},     -- Individual raid records
        players = {},   -- Per-player attendance stats
    },

    -- Active roll session (cleared on completion)
    activeSession = nil,

    -- Active raid session for attendance tracking
    activeRaid = nil,

    -- Configuration
    config = {
        announceWinner = true,
        announceChannel = "RAID",
        autoReroll = true,
        priorityWeight = 0.1,  -- How much attendance affects priority (0-1)
        minAttendanceForPriority = 0,  -- Minimum raids to qualify for priority
    },

    -- Version for future migrations
    version = 1,
}

-- Initialize database (called on ADDON_LOADED)
function LT.DB:Initialize()
    -- Create or load existing database
    if not LootTrackerDB then
        LootTrackerDB = self:DeepCopy(DB_DEFAULTS)
        print("|cff00ff00LootTracker:|r Database initialized for first time")
    else
        -- Merge defaults for any missing keys (handles version upgrades)
        self:MergeDefaults(LootTrackerDB, DB_DEFAULTS)
    end

    self.db = LootTrackerDB
end

-- Deep copy a table
function LT.DB:DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = self:DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Merge defaults into existing table (preserves existing values)
function LT.DB:MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == 'table' then
            if type(target[k]) ~= 'table' then
                target[k] = {}
            end
            self:MergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

--[[
    ROLL SESSION MANAGEMENT
]]

-- Start a new roll session for an item
function LT.DB:StartRollSession(itemLink, startedBy)
    if self.db.activeSession then
        return false, "A roll session is already active"
    end

    self.db.activeSession = {
        item = itemLink,
        startedBy = startedBy,
        startTime = time(),
        rolls = {},
        rerollRound = 0,
        eligiblePlayers = {},  -- Empty = all eligible
        state = "open",        -- open, rerolling, closed
    }

    return true
end

-- Record a roll in the active session
function LT.DB:RecordRoll(playerName, rollValue, minRoll, maxRoll)
    local session = self.db.activeSession
    if not session or session.state == "closed" then
        return false, "No active roll session"
    end

    -- Only accept 1-100 rolls
    if minRoll ~= 1 or maxRoll ~= 100 then
        return false, "Not a 1-100 roll"
    end

    -- Check eligibility if restrictions are set
    if #session.eligiblePlayers > 0 then
        local eligible = false
        for _, name in ipairs(session.eligiblePlayers) do
            if name == playerName then
                eligible = true
                break
            end
        end
        if not eligible then
            return false, "Player not eligible"
        end
    end

    -- Check if player already rolled this round
    local currentRound = session.rerollRound
    for _, roll in ipairs(session.rolls) do
        if roll.player == playerName and roll.round == currentRound then
            return false, "Player already rolled this round"
        end
    end

    -- Record the roll
    table.insert(session.rolls, {
        player = playerName,
        value = rollValue,
        round = currentRound,
        timestamp = time(),
    })

    return true
end

-- Get highest rollers (handles ties)
function LT.DB:GetHighestRollers(round)
    local session = self.db.activeSession
    if not session then return nil end

    round = round or session.rerollRound

    -- Find highest roll value for this round
    local highestValue = 0
    for _, roll in ipairs(session.rolls) do
        if roll.round == round and roll.value > highestValue then
            highestValue = roll.value
        end
    end

    -- Collect all players with that value
    local winners = {}
    for _, roll in ipairs(session.rolls) do
        if roll.round == round and roll.value == highestValue then
            table.insert(winners, roll)
        end
    end

    return winners, highestValue
end

-- Initiate a re-roll for tied players
function LT.DB:StartReroll(tiedPlayers)
    local session = self.db.activeSession
    if not session then return false end

    session.rerollRound = session.rerollRound + 1
    session.state = "rerolling"

    -- Set eligible players to only those who tied
    session.eligiblePlayers = {}
    for _, roll in ipairs(tiedPlayers) do
        table.insert(session.eligiblePlayers, roll.player)
    end

    return true, session.rerollRound
end

-- End the roll session and determine winner
function LT.DB:EndRollSession()
    local session = self.db.activeSession
    if not session then
        return false, "No active roll session"
    end

    local winners, highestRoll = self:GetHighestRollers()

    if not winners or #winners == 0 then
        -- No rolls recorded
        self.db.activeSession = nil
        return true, nil, "No rolls recorded"
    end

    if #winners > 1 then
        -- Still tied - need another reroll
        return false, winners, "Tie detected"
    end

    -- We have a single winner
    local winner = winners[1]

    -- Create history record
    local record = {
        item = session.item,
        winner = winner.player,
        winningRoll = winner.value,
        startedBy = session.startedBy,
        startTime = session.startTime,
        endTime = time(),
        rolls = session.rolls,
        rerollRounds = session.rerollRound,
    }

    -- Add to roll history
    table.insert(self.db.rolls, record)

    -- Update player stats
    self:UpdatePlayerStats(winner.player, true, winner.value)
    for _, roll in ipairs(session.rolls) do
        if roll.player ~= winner.player then
            self:UpdatePlayerStats(roll.player, false, roll.value)
        end
    end

    -- Clear active session
    self.db.activeSession = nil

    return true, winner, record
end

-- Cancel active roll session without recording
function LT.DB:CancelRollSession()
    if not self.db.activeSession then
        return false, "No active roll session"
    end

    self.db.activeSession = nil
    return true
end

-- Get active session info
function LT.DB:GetActiveSession()
    return self.db.activeSession
end

--[[
    PLAYER STATISTICS
]]

-- Update stats after a roll session
function LT.DB:UpdatePlayerStats(playerName, won, rollValue)
    if not self.db.stats[playerName] then
        self.db.stats[playerName] = {
            wins = 0,
            losses = 0,
            totalRolls = 0,
            rollSum = 0,
            highestRoll = 0,
            lowestRoll = 100,
        }
    end

    local stats = self.db.stats[playerName]
    stats.totalRolls = stats.totalRolls + 1
    stats.rollSum = stats.rollSum + rollValue

    if won then
        stats.wins = stats.wins + 1
    else
        stats.losses = stats.losses + 1
    end

    if rollValue > stats.highestRoll then
        stats.highestRoll = rollValue
    end
    if rollValue < stats.lowestRoll then
        stats.lowestRoll = rollValue
    end
end

-- Get player statistics
function LT.DB:GetPlayerStats(playerName)
    local stats = self.db.stats[playerName]
    if not stats then return nil end

    -- Calculate derived stats
    local derived = self:DeepCopy(stats)
    derived.avgRoll = stats.totalRolls > 0 and (stats.rollSum / stats.totalRolls) or 0
    derived.winRate = (stats.wins + stats.losses) > 0
        and (stats.wins / (stats.wins + stats.losses) * 100) or 0

    return derived
end

-- Get all player stats sorted by wins
function LT.DB:GetAllPlayerStats()
    local allStats = {}

    for name, stats in pairs(self.db.stats) do
        local derived = self:GetPlayerStats(name)
        derived.name = name
        table.insert(allStats, derived)
    end

    -- Sort by wins descending
    table.sort(allStats, function(a, b) return a.wins > b.wins end)

    return allStats
end

--[[
    ATTENDANCE TRACKING
]]

-- Start a new raid attendance session
function LT.DB:StartRaidSession(raidName, startedBy)
    if self.db.activeRaid then
        return false, "A raid session is already active"
    end

    self.db.activeRaid = {
        name = raidName,
        startedBy = startedBy,
        startTime = time(),
        date = date("%Y-%m-%d"),
        attendees = {},
    }

    return true
end

-- Add player to current raid attendance
function LT.DB:AddAttendee(playerName)
    if not self.db.activeRaid then
        return false, "No active raid session"
    end

    -- Check if already added
    for _, name in ipairs(self.db.activeRaid.attendees) do
        if name == playerName then
            return false, "Player already in attendance"
        end
    end

    table.insert(self.db.activeRaid.attendees, playerName)
    return true
end

-- Remove player from current raid attendance
function LT.DB:RemoveAttendee(playerName)
    if not self.db.activeRaid then
        return false, "No active raid session"
    end

    for i, name in ipairs(self.db.activeRaid.attendees) do
        if name == playerName then
            table.remove(self.db.activeRaid.attendees, i)
            return true
        end
    end

    return false, "Player not in attendance list"
end

-- Sync attendance from current raid roster
function LT.DB:SyncRaidRoster()
    if not self.db.activeRaid then
        return false, "No active raid session"
    end

    if not IsInRaid() then
        return false, "Not in a raid"
    end

    -- Clear and rebuild from current roster
    self.db.activeRaid.attendees = {}

    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name then
            -- Remove server suffix if present
            name = strsplit("-", name)
            table.insert(self.db.activeRaid.attendees, name)
        end
    end

    return true, #self.db.activeRaid.attendees
end

-- End raid session and save attendance record
function LT.DB:EndRaidSession()
    if not self.db.activeRaid then
        return false, "No active raid session"
    end

    local raid = self.db.activeRaid
    raid.endTime = time()

    -- Save to raid history
    table.insert(self.db.attendance.raids, raid)

    -- Update per-player attendance stats
    for _, playerName in ipairs(raid.attendees) do
        if not self.db.attendance.players[playerName] then
            self.db.attendance.players[playerName] = {
                totalRaids = 0,
                raidDates = {},
            }
        end

        local playerAtt = self.db.attendance.players[playerName]
        playerAtt.totalRaids = playerAtt.totalRaids + 1
        table.insert(playerAtt.raidDates, raid.date)
    end

    local record = self:DeepCopy(raid)
    self.db.activeRaid = nil

    return true, record
end

-- Cancel active raid session
function LT.DB:CancelRaidSession()
    if not self.db.activeRaid then
        return false, "No active raid session"
    end

    self.db.activeRaid = nil
    return true
end

-- Get player attendance stats
function LT.DB:GetPlayerAttendance(playerName)
    return self.db.attendance.players[playerName]
end

-- Get attendance rate for player
function LT.DB:GetAttendanceRate(playerName)
    local totalRaids = #self.db.attendance.raids
    if totalRaids == 0 then return 0 end

    local playerAtt = self.db.attendance.players[playerName]
    if not playerAtt then return 0 end

    return (playerAtt.totalRaids / totalRaids) * 100
end

-- Calculate priority score for a player (based on attendance)
function LT.DB:GetPlayerPriority(playerName)
    local config = self.db.config
    local attendance = self:GetAttendanceRate(playerName)
    local playerAtt = self.db.attendance.players[playerName]

    -- Check minimum attendance requirement
    if not playerAtt or playerAtt.totalRaids < config.minAttendanceForPriority then
        return 0
    end

    -- Priority is attendance rate scaled by weight
    return attendance * config.priorityWeight
end

-- Get active raid session info
function LT.DB:GetActiveRaid()
    return self.db.activeRaid
end

--[[
    HISTORY & QUERIES
]]

-- Get roll history with optional filters
function LT.DB:GetRollHistory(filters)
    filters = filters or {}
    local results = {}

    for _, record in ipairs(self.db.rolls) do
        local include = true

        -- Filter by player
        if filters.player and record.winner ~= filters.player then
            include = false
        end

        -- Filter by date range
        if filters.startDate and record.startTime < filters.startDate then
            include = false
        end
        if filters.endDate and record.endTime > filters.endDate then
            include = false
        end

        -- Filter by item (partial match)
        if filters.item and not string.find(record.item:lower(), filters.item:lower()) then
            include = false
        end

        if include then
            table.insert(results, record)
        end
    end

    -- Sort by time descending (most recent first)
    table.sort(results, function(a, b) return a.endTime > b.endTime end)

    return results
end

-- Get attendance history
function LT.DB:GetAttendanceHistory()
    local raids = self:DeepCopy(self.db.attendance.raids)
    table.sort(raids, function(a, b) return a.startTime > b.startTime end)
    return raids
end

-- Get configuration
function LT.DB:GetConfig()
    return self.db.config
end

-- Update configuration
function LT.DB:SetConfig(key, value)
    if self.db.config[key] ~= nil then
        self.db.config[key] = value
        return true
    end
    return false
end

-- Wipe all data (for testing/reset)
function LT.DB:WipeData()
    LootTrackerDB = self:DeepCopy(DB_DEFAULTS)
    self.db = LootTrackerDB
end
