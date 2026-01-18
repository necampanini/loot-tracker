--[[
    LootTracker - Main Addon File
    Raid loot roll tracking, attendance, and statistics

    Slash Commands:
        /lt or /loottracker - Show main window
        /lt start [item] - Start a roll session
        /lt end - End roll session, announce winner
        /lt cancel - Cancel active roll session
        /lt reroll - Initiate reroll for tied players
        /lt raid start [name] - Start attendance tracking
        /lt raid end - End attendance tracking
        /lt raid sync - Sync current raid roster
        /lt stats [player] - Show stats for player (or self)
        /lt history - Show loot history window
        /lt export - Show export window
        /lt sync - Request sync from leader
        /lt lead - Claim sync leadership
        /lt config - Show config options
        /lt help - Show help
]]

local ADDON_NAME, LT = ...

-- Addon version
LT.VERSION = "1.1.0"

-- Create main frame for ADDON_LOADED event
local mainFrame = CreateFrame("Frame")
mainFrame:RegisterEvent("ADDON_LOADED")

-- Initialization
mainFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon == ADDON_NAME then
        LT:Initialize()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Main initialization
function LT:Initialize()
    -- Initialize core modules (order matters)
    self.Debug:Initialize()  -- Debug first for logging
    self.DB:Initialize()
    self.Events:Initialize()
    self.Sync:Initialize()

    -- Register slash commands
    self:RegisterSlashCommands()

    -- Initialize UI modules (they may create frames on demand)
    -- UI modules self-register when loaded

    -- Log initialization
    self.Debug:Info("Main", "LootTracker v%s initialized", self.VERSION)

    print(string.format("|cff00ff00LootTracker|r v%s loaded. Type /lt help for commands.", self.VERSION))
    print("|cff888888Testing:|r /lt test, /lt sim, /lt debug")
end

-- Register slash commands
function LT:RegisterSlashCommands()
    SLASH_LOOTTRACKER1 = "/lt"
    SLASH_LOOTTRACKER2 = "/loottracker"

    SlashCmdList["LOOTTRACKER"] = function(msg)
        self:HandleSlashCommand(msg)
    end
end

-- Parse and handle slash commands
function LT:HandleSlashCommand(msg)
    -- Parse command and arguments
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end

    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "" or cmd == "show" then
        self:ShowMainWindow()

    elseif cmd == "start" then
        -- /lt start [item link or name]
        local item = msg:match("start%s+(.+)") or "Unknown Item"
        self:StartRollSession(item)

    elseif cmd == "end" or cmd == "stop" then
        self:EndRollSession()

    elseif cmd == "cancel" then
        self:CancelRollSession()

    elseif cmd == "reroll" then
        self:InitiateReroll()

    elseif cmd == "raid" then
        local subCmd = args[2] and args[2]:lower() or ""
        if subCmd == "start" then
            local raidName = table.concat(args, " ", 3) or "Raid"
            if raidName == "" then raidName = "Raid" end
            self:StartRaidSession(raidName)
        elseif subCmd == "end" or subCmd == "stop" then
            self:EndRaidSession()
        elseif subCmd == "sync" then
            self:SyncRaidRoster()
        elseif subCmd == "cancel" then
            self:CancelRaidSession()
        else
            print("|cffff9900Usage:|r /lt raid start [name], /lt raid end, /lt raid sync")
        end

    elseif cmd == "stats" then
        local playerName = args[2] or UnitName("player")
        self:ShowPlayerStats(playerName)

    elseif cmd == "history" then
        self:ShowHistoryWindow()

    elseif cmd == "export" then
        self:ShowExportWindow()

    elseif cmd == "sync" then
        self.Sync:RequestSync()

    elseif cmd == "lead" or cmd == "leader" then
        self.Sync:ClaimLeadership()

    elseif cmd == "versions" then
        self.Sync:CheckVersions()

    elseif cmd == "config" or cmd == "options" then
        self:ShowConfig()

    elseif cmd == "wipe" then
        -- Dangerous: wipe all data
        if args[2] == "confirm" then
            self.DB:WipeData()
            print("|cffff0000LootTracker:|r All data wiped!")
        else
            print("|cffff9900LootTracker:|r Type '/lt wipe confirm' to delete ALL data")
        end

    elseif cmd == "debug" then
        -- Pass remaining args to debug module
        local debugArgs = {}
        for i = 2, #args do
            table.insert(debugArgs, args[i])
        end
        self.Debug:HandleCommand(debugArgs)

    elseif cmd == "test" then
        -- Pass remaining args to test harness
        local testArgs = {}
        for i = 2, #args do
            table.insert(testArgs, args[i])
        end
        self.Test:HandleCommand(testArgs)

    elseif cmd == "sim" or cmd == "simulate" then
        -- Pass remaining args to simulation module
        local simArgs = {}
        for i = 2, #args do
            table.insert(simArgs, args[i])
        end
        self.Sim:HandleCommand(simArgs)

    elseif cmd == "help" then
        self:ShowHelp()

    else
        print("|cffff9900LootTracker:|r Unknown command. Type /lt help for commands.")
    end
end

--[[
    ROLL SESSION COMMANDS
]]

function LT:StartRollSession(item)
    -- Check if officer/leader
    if not self.Events:IsRaidLeadership() and not self.Events:IsOfficer() then
        print("|cffff9900LootTracker:|r You must be raid leader/assistant or guild officer")
        return
    end

    local success, err = self.DB:StartRollSession(item, UnitName("player"))
    if not success then
        print("|cffff0000LootTracker:|r " .. err)
        return
    end

    -- Announce to raid
    local itemName = self.Events:GetItemName(item) or item
    self.Events:Announce(string.format("Roll session started for %s - /roll now!", item), "RAID_WARNING")
    print("|cff00ff00LootTracker:|r Roll session started for " .. itemName)

    -- Update UI
    if self.RollTracker then
        self.RollTracker:Show()
        self.RollTracker:Update()
    end
end

function LT:EndRollSession()
    local success, winner, result = self.DB:EndRollSession()

    if not success then
        if winner and type(winner) == "table" then
            -- Tie detected
            local names = {}
            for _, roll in ipairs(winner) do
                table.insert(names, string.format("%s (%d)", roll.player, roll.value))
            end
            print(string.format("|cffff9900LootTracker:|r Tie detected between: %s", table.concat(names, ", ")))
            print("|cffff9900LootTracker:|r Use /lt reroll to have tied players roll again")
            return
        else
            print("|cffff0000LootTracker:|r " .. (result or "Unknown error"))
            return
        end
    end

    if not winner then
        print("|cffff9900LootTracker:|r No rolls were recorded")
        return
    end

    -- Announce winner
    local itemName = self.Events:GetItemName(result.item) or result.item
    self.Events:Announce(
        string.format("%s wins %s with a roll of %d!", winner.player, itemName, winner.value),
        "RAID_WARNING"
    )

    -- Broadcast to other officers
    self.Sync:BroadcastRollRecord(result)

    -- Update UI
    if self.RollTracker then
        self.RollTracker:Hide()
    end

    print(string.format("|cff00ff00LootTracker:|r %s wins %s (roll: %d)", winner.player, itemName, winner.value))
end

function LT:CancelRollSession()
    local success, err = self.DB:CancelRollSession()
    if success then
        print("|cff00ff00LootTracker:|r Roll session cancelled")
        if self.RollTracker then
            self.RollTracker:Hide()
        end
    else
        print("|cffff0000LootTracker:|r " .. err)
    end
end

function LT:InitiateReroll()
    local session = self.DB:GetActiveSession()
    if not session then
        print("|cffff0000LootTracker:|r No active roll session")
        return
    end

    local winners = self.DB:GetHighestRollers()
    if not winners or #winners < 2 then
        print("|cffff9900LootTracker:|r No tie to resolve - use /lt end to finish")
        return
    end

    local success, round = self.DB:StartReroll(winners)
    if success then
        local names = {}
        for _, roll in ipairs(winners) do
            table.insert(names, roll.player)
        end

        self.Events:Announce(
            string.format("REROLL (Round %d): %s please /roll again!", round, table.concat(names, ", ")),
            "RAID_WARNING"
        )

        if self.RollTracker then
            self.RollTracker:Update()
        end
    end
end

--[[
    RAID/ATTENDANCE COMMANDS
]]

function LT:StartRaidSession(raidName)
    local success, err = self.DB:StartRaidSession(raidName, UnitName("player"))
    if not success then
        print("|cffff0000LootTracker:|r " .. err)
        return
    end

    -- Auto-sync roster if in raid
    if IsInRaid() then
        self:SyncRaidRoster()
    end

    print(string.format("|cff00ff00LootTracker:|r Raid attendance started: %s", raidName))
end

function LT:EndRaidSession()
    local success, result = self.DB:EndRaidSession()
    if not success then
        print("|cffff0000LootTracker:|r " .. result)
        return
    end

    -- Broadcast to other officers
    self.Sync:BroadcastAttendance(result)

    print(string.format("|cff00ff00LootTracker:|r Raid ended: %s (%d attendees)", result.name, #result.attendees))
end

function LT:CancelRaidSession()
    local success, err = self.DB:CancelRaidSession()
    if success then
        print("|cff00ff00LootTracker:|r Raid session cancelled")
    else
        print("|cffff0000LootTracker:|r " .. err)
    end
end

function LT:SyncRaidRoster()
    local success, count = self.DB:SyncRaidRoster()
    if not success then
        print("|cffff0000LootTracker:|r " .. count)
        return
    end

    print(string.format("|cff00ff00LootTracker:|r Synced %d players from raid roster", count))
end

--[[
    INFO/DISPLAY COMMANDS
]]

function LT:ShowPlayerStats(playerName)
    local stats = self.DB:GetPlayerStats(playerName)
    local attendance = self.DB:GetPlayerAttendance(playerName)

    print("|cff00ff00=== LootTracker Stats: " .. playerName .. " ===|r")

    if stats then
        print(string.format("  Wins: %d | Losses: %d | Win Rate: %.1f%%",
            stats.wins, stats.losses, stats.winRate))
        print(string.format("  Total Rolls: %d | Avg Roll: %.1f",
            stats.totalRolls, stats.avgRoll))
        print(string.format("  Best Roll: %d | Worst Roll: %d",
            stats.highestRoll, stats.lowestRoll))
    else
        print("  No roll data recorded")
    end

    if attendance then
        local rate = self.DB:GetAttendanceRate(playerName)
        print(string.format("  Raids Attended: %d | Attendance Rate: %.1f%%",
            attendance.totalRaids, rate))
    else
        print("  No attendance data recorded")
    end
end

function LT:ShowMainWindow()
    if self.MainWindow then
        self.MainWindow:Toggle()
    else
        print("|cffff9900LootTracker:|r Main window not yet loaded")
    end
end

function LT:ShowHistoryWindow()
    if self.MainWindow then
        self.MainWindow:Show()
        self.MainWindow:ShowTab("history")
    else
        -- Fallback: print recent history
        local history = self.DB:GetRollHistory()
        print("|cff00ff00=== LootTracker History (Last 10) ===|r")
        for i = 1, math.min(10, #history) do
            local record = history[i]
            local itemName = self.Events:GetItemName(record.item) or record.item
            print(string.format("  %s: %s won %s (roll: %d)",
                date("%m/%d %H:%M", record.endTime),
                record.winner, itemName, record.winningRoll))
        end
    end
end

function LT:ShowExportWindow()
    if self.Export then
        self.Export:Show()
    else
        print("|cffff9900LootTracker:|r Export window not yet loaded")
    end
end

function LT:ShowConfig()
    local config = self.DB:GetConfig()
    print("|cff00ff00=== LootTracker Config ===|r")
    print(string.format("  Announce Winner: %s", config.announceWinner and "Yes" or "No"))
    print(string.format("  Announce Channel: %s", config.announceChannel))
    print(string.format("  Auto-Reroll: %s", config.autoReroll and "Yes" or "No"))
    print(string.format("  Priority Weight: %.1f", config.priorityWeight))
    print("  (Config UI coming soon)")
end

function LT:DebugInfo()
    print("|cff00ff00=== LootTracker Debug ===|r")

    local session = self.DB:GetActiveSession()
    if session then
        print("  Active Roll Session: " .. (self.Events:GetItemName(session.item) or session.item))
        print("    State: " .. session.state)
        print("    Rolls: " .. #session.rolls)
        print("    Reroll Round: " .. session.rerollRound)
    else
        print("  No active roll session")
    end

    local raid = self.DB:GetActiveRaid()
    if raid then
        print("  Active Raid: " .. raid.name)
        print("    Attendees: " .. #raid.attendees)
    else
        print("  No active raid session")
    end

    local syncState = self.Sync:GetState()
    print("  Sync Leader: " .. (syncState.currentLeader or "None"))
    print("  Is Leader: " .. (syncState.isLeader and "Yes" or "No"))

    print("  Total Roll Records: " .. #self.DB.db.rolls)
    print("  Total Raid Records: " .. #self.DB.db.attendance.raids)
end

function LT:ShowHelp()
    print("|cff00ff00=== LootTracker Commands ===|r")
    print("|cff88ff88Roll Commands:|r")
    print("  /lt start [item] - Start a roll session for an item")
    print("  /lt end - End session and announce winner")
    print("  /lt cancel - Cancel active roll session")
    print("  /lt reroll - Reroll for tied players")
    print("")
    print("|cff88ff88Attendance Commands:|r")
    print("  /lt raid start [name] - Start tracking attendance")
    print("  /lt raid end - End and save attendance")
    print("  /lt raid sync - Sync from current raid roster")
    print("  /lt raid cancel - Cancel without saving")
    print("")
    print("|cff88ff88Info Commands:|r")
    print("  /lt - Show main window")
    print("  /lt stats [player] - Show player statistics")
    print("  /lt history - Show loot history")
    print("  /lt export - Show export window")
    print("")
    print("|cff88ff88Sync Commands:|r")
    print("  /lt sync - Request sync from leader")
    print("  /lt lead - Claim sync leadership")
    print("  /lt versions - Check addon versions in raid")
    print("")
    print("|cff88ff88Testing & Debug:|r")
    print("  /lt test - Run unit tests (/lt test list for suites)")
    print("  /lt sim - Simulation commands (/lt sim for options)")
    print("  /lt debug - Debug tools (/lt debug for options)")
    print("")
    print("|cff88ff88Other:|r")
    print("  /lt config - Show configuration")
    print("  /lt help - Show this help")
end
