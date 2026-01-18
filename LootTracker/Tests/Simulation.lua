--[[
    LootTracker - Simulation Module
    Tools for testing the addon solo, outside of a raid environment

    Commands:
        /lt sim roll [player] [value]   - Simulate a roll event
        /lt sim session [item]          - Start a simulated roll session
        /lt sim players [n]             - Simulate n players rolling
        /lt sim tie                     - Simulate a tie scenario
        /lt sim raid [n]                - Simulate a raid with n players
        /lt sim history [n]             - Generate n fake history records
        /lt sim reset                   - Clear all simulated data
        /lt sim stress [n]              - Stress test with n operations
]]

local _, LT = ...
LT.Sim = {}

local Sim = LT.Sim

-- Simulated player names pool
local FAKE_PLAYERS = {
    "Thunderfury", "Shadowstep", "Healbot", "Tankmaster", "Dpsking",
    "Moonfire", "Frostbolt", "Backstab", "Holylight", "Shieldwall",
    "Pyroblast", "Lifebloom", "Execute", "Mortalstrike", "Chainlightning",
    "Swiftmend", "Bladestorm", "Mindblast", "Crusaderstrike", "Bloodthirst",
    "Starfall", "Arcanemissiles", "Judgement", "Raptorstrike", "Volley",
}

-- Simulated item names pool
local FAKE_ITEMS = {
    "[Thunderfury, Blessed Blade of the Windseeker]",
    "[Ashkandi, Greatsword of the Brotherhood]",
    "[Perdition's Blade]",
    "[Bindings of the Windseeker]",
    "[Eye of Sulfuras]",
    "[Gressil, Dawn of Ruin]",
    "[The Hungering Cold]",
    "[Corrupted Ashbringer]",
    "[Warglaive of Azzinoth]",
    "[Thori'dal, the Stars' Fury]",
}

-- Simulated raid names
local FAKE_RAIDS = {
    "Molten Core", "Blackwing Lair", "Temple of Ahn'Qiraj",
    "Naxxramas", "Karazhan", "Serpentshrine Cavern",
    "Black Temple", "Sunwell Plateau", "Icecrown Citadel",
}

--[[
    SIMULATION UTILITIES
]]

-- Get random player from pool
function Sim:GetRandomPlayer(exclude)
    exclude = exclude or {}
    local available = {}

    for _, name in ipairs(FAKE_PLAYERS) do
        local excluded = false
        for _, ex in ipairs(exclude) do
            if ex == name then
                excluded = true
                break
            end
        end
        if not excluded then
            table.insert(available, name)
        end
    end

    return available[math.random(#available)]
end

-- Get random item
function Sim:GetRandomItem()
    return FAKE_ITEMS[math.random(#FAKE_ITEMS)]
end

-- Get random raid name
function Sim:GetRandomRaid()
    return FAKE_RAIDS[math.random(#FAKE_RAIDS)]
end

-- Generate a realistic roll value (weighted towards middle)
function Sim:GetRandomRoll()
    -- Use a simple approximation of normal distribution
    local sum = 0
    for i = 1, 3 do
        sum = sum + math.random(1, 100)
    end
    return math.floor(sum / 3)
end

--[[
    SIMULATION COMMANDS
]]

-- Simulate a single roll
function Sim:SimulateRoll(playerName, rollValue)
    playerName = playerName or self:GetRandomPlayer()
    rollValue = rollValue or self:GetRandomRoll()

    -- Create the fake system message
    local fakeMessage = string.format("%s rolls %d (1-100)", playerName, rollValue)

    -- Process it through the events system
    LT.Events:CHAT_MSG_SYSTEM(fakeMessage)

    print(string.format("|cff00ffff[Sim]|r %s", fakeMessage))

    return playerName, rollValue
end

-- Start a simulated roll session
function Sim:SimulateSession(itemName)
    itemName = itemName or self:GetRandomItem()

    -- Override officer check temporarily
    local originalIsOfficer = LT.Events.IsOfficer
    local originalIsRaidLead = LT.Events.IsRaidLeadership
    LT.Events.IsOfficer = function() return true end
    LT.Events.IsRaidLeadership = function() return true end

    LT:StartRollSession(itemName)

    -- Restore
    LT.Events.IsOfficer = originalIsOfficer
    LT.Events.IsRaidLeadership = originalIsRaidLead

    print(string.format("|cff00ffff[Sim]|r Started roll session for %s", itemName))
end

-- Simulate multiple players rolling
function Sim:SimulatePlayers(count)
    count = count or 5

    local session = LT.DB:GetActiveSession()
    if not session then
        self:SimulateSession()
    end

    print(string.format("|cff00ffff[Sim]|r Simulating %d players rolling...", count))

    local rolled = {}
    for i = 1, count do
        local player = self:GetRandomPlayer(rolled)
        local roll = self:GetRandomRoll()
        self:SimulateRoll(player, roll)
        table.insert(rolled, player)

        -- Small delay between rolls for realism (visual only)
        -- In actual execution this is synchronous
    end

    -- Show summary
    local winners, highRoll = LT.DB:GetHighestRollers()
    if winners and #winners > 0 then
        if #winners == 1 then
            print(string.format("|cff00ffff[Sim]|r Leader: %s (%d)", winners[1].player, highRoll))
        else
            local names = {}
            for _, w in ipairs(winners) do
                table.insert(names, w.player)
            end
            print(string.format("|cff00ffff[Sim]|r TIE at %d: %s", highRoll, table.concat(names, ", ")))
        end
    end
end

-- Simulate a tie scenario
function Sim:SimulateTie()
    self:SimulateSession()

    local tieValue = math.random(70, 99)
    self:SimulateRoll("TiePlayer1", tieValue)
    self:SimulateRoll("TiePlayer2", tieValue)
    self:SimulateRoll("LoserPlayer", tieValue - 10)

    print(string.format("|cff00ffff[Sim]|r Created tie scenario at %d", tieValue))
    print("|cff00ffff[Sim]|r Use '/lt reroll' to resolve")
end

-- Simulate a full raid roster
function Sim:SimulateRaid(count)
    count = count or 25

    -- Override checks
    local originalIsOfficer = LT.Events.IsOfficer
    LT.Events.IsOfficer = function() return true end

    local raidName = self:GetRandomRaid()
    LT:StartRaidSession(raidName)

    local players = {}
    for i = 1, math.min(count, #FAKE_PLAYERS) do
        local player = FAKE_PLAYERS[i]
        LT.DB:AddAttendee(player)
        table.insert(players, player)
    end

    LT.Events.IsOfficer = originalIsOfficer

    print(string.format("|cff00ffff[Sim]|r Created raid '%s' with %d players", raidName, #players))
    print("|cff00ffff[Sim]|r Use '/lt raid end' to finalize")
end

-- Generate fake history records
function Sim:SimulateHistory(count)
    count = count or 10

    print(string.format("|cff00ffff[Sim]|r Generating %d history records...", count))

    local baseTime = time() - (count * 3600)  -- Start from count hours ago

    for i = 1, count do
        local item = self:GetRandomItem()
        local winner = self:GetRandomPlayer()
        local roll = math.random(50, 100)

        local record = {
            item = item,
            winner = winner,
            winningRoll = roll,
            startedBy = "SimOfficer",
            startTime = baseTime + (i * 3600),
            endTime = baseTime + (i * 3600) + 300,
            rolls = {},
            rerollRounds = 0,
        }

        -- Generate fake roll list
        local numRollers = math.random(5, 15)
        local usedPlayers = { winner }
        table.insert(record.rolls, {
            player = winner,
            value = roll,
            round = 0,
            timestamp = record.endTime,
        })

        for j = 2, numRollers do
            local player = self:GetRandomPlayer(usedPlayers)
            table.insert(usedPlayers, player)
            table.insert(record.rolls, {
                player = player,
                value = math.random(1, roll - 1),
                round = 0,
                timestamp = record.endTime - math.random(1, 60),
            })
        end

        table.insert(LT.DB.db.rolls, record)

        -- Update stats
        for _, rollData in ipairs(record.rolls) do
            LT.DB:UpdatePlayerStats(rollData.player, rollData.player == winner, rollData.value)
        end
    end

    print(string.format("|cff00ffff[Sim]|r Generated %d history records", count))
end

-- Generate fake attendance history
function Sim:SimulateAttendance(raidCount)
    raidCount = raidCount or 5

    print(string.format("|cff00ffff[Sim]|r Generating %d attendance records...", raidCount))

    local baseTime = time() - (raidCount * 86400)  -- Start from raidCount days ago

    for i = 1, raidCount do
        local raid = {
            name = self:GetRandomRaid(),
            startedBy = "SimLeader",
            startTime = baseTime + (i * 86400),
            endTime = baseTime + (i * 86400) + 10800,  -- 3 hour raid
            date = date("%Y-%m-%d", baseTime + (i * 86400)),
            attendees = {},
        }

        -- Random attendance (10-25 players)
        local attendeeCount = math.random(10, 25)
        for j = 1, attendeeCount do
            if j <= #FAKE_PLAYERS then
                -- Higher index players have lower attendance rate
                if j <= 10 or math.random() > 0.3 then
                    table.insert(raid.attendees, FAKE_PLAYERS[j])
                end
            end
        end

        table.insert(LT.DB.db.attendance.raids, raid)

        -- Update player attendance stats
        for _, player in ipairs(raid.attendees) do
            if not LT.DB.db.attendance.players[player] then
                LT.DB.db.attendance.players[player] = {
                    totalRaids = 0,
                    raidDates = {},
                }
            end
            local pAtt = LT.DB.db.attendance.players[player]
            pAtt.totalRaids = pAtt.totalRaids + 1
            table.insert(pAtt.raidDates, raid.date)
        end
    end

    print(string.format("|cff00ffff[Sim]|r Generated %d attendance records", raidCount))
end

-- Reset all simulated data
function Sim:Reset()
    LT.DB:WipeData()
    print("|cff00ffff[Sim]|r All data wiped")
end

-- Stress test
function Sim:StressTest(count)
    count = count or 100

    print(string.format("|cff00ffff[Sim]|r Running stress test with %d operations...", count))

    local startTime = GetTime()
    local startMem = collectgarbage("count")

    -- Run many operations
    for i = 1, count do
        -- Create and end sessions
        LT.DB:StartRollSession("Stress Item " .. i, "StressTester")

        local numRolls = math.random(5, 20)
        for j = 1, numRolls do
            local player = self:GetRandomPlayer() .. j
            local roll = self:GetRandomRoll()
            LT.DB:RecordRoll(player, roll, 1, 100)
        end

        local winners = LT.DB:GetHighestRollers()
        if winners and #winners > 1 then
            LT.DB:StartReroll(winners)
            for _, w in ipairs(winners) do
                LT.DB:RecordRoll(w.player, self:GetRandomRoll(), 1, 100)
            end
        end

        LT.DB:EndRollSession()
    end

    local endTime = GetTime()
    local endMem = collectgarbage("count")

    print(string.format("|cff00ffff[Sim]|r Stress test complete:"))
    print(string.format("  Time: %.2f seconds", endTime - startTime))
    print(string.format("  Memory: %.1f KB -> %.1f KB (delta: %.1f KB)",
        startMem, endMem, endMem - startMem))
    print(string.format("  Records created: %d", #LT.DB.db.rolls))
end

-- Complete simulation scenario
function Sim:RunFullScenario()
    print("|cff00ffff[Sim]|r Running full test scenario...")

    -- Generate history
    self:SimulateAttendance(10)
    self:SimulateHistory(20)

    -- Create active session with rolls
    self:SimulateSession()
    self:SimulatePlayers(8)

    -- Show UI
    LT:ShowMainWindow()

    if LT.RollTracker then
        LT.RollTracker:Show()
    end

    print("|cff00ffff[Sim]|r Scenario complete - windows opened")
    print("|cff00ffff[Sim]|r Use '/lt end' to finish the roll session")
end

--[[
    SLASH COMMAND HANDLER
]]

function Sim:HandleCommand(args)
    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "roll" then
        local player = args[2]
        local value = tonumber(args[3])
        self:SimulateRoll(player, value)

    elseif cmd == "session" then
        local item = table.concat(args, " ", 2)
        if item == "" then item = nil end
        self:SimulateSession(item)

    elseif cmd == "players" then
        local count = tonumber(args[2]) or 5
        self:SimulatePlayers(count)

    elseif cmd == "tie" then
        self:SimulateTie()

    elseif cmd == "raid" then
        local count = tonumber(args[2]) or 25
        self:SimulateRaid(count)

    elseif cmd == "history" then
        local count = tonumber(args[2]) or 10
        self:SimulateHistory(count)

    elseif cmd == "attendance" then
        local count = tonumber(args[2]) or 5
        self:SimulateAttendance(count)

    elseif cmd == "reset" then
        self:Reset()

    elseif cmd == "stress" then
        local count = tonumber(args[2]) or 100
        self:StressTest(count)

    elseif cmd == "full" or cmd == "scenario" then
        self:RunFullScenario()

    else
        print("|cff00ffff=== LootTracker Simulation Commands ===|r")
        print("  /lt sim roll [player] [value] - Simulate a roll")
        print("  /lt sim session [item]        - Start simulated session")
        print("  /lt sim players [n]           - Simulate n players rolling")
        print("  /lt sim tie                   - Create a tie scenario")
        print("  /lt sim raid [n]              - Create raid with n players")
        print("  /lt sim history [n]           - Generate n history records")
        print("  /lt sim attendance [n]        - Generate n attendance records")
        print("  /lt sim reset                 - Wipe all data")
        print("  /lt sim stress [n]            - Stress test with n sessions")
        print("  /lt sim full                  - Run complete test scenario")
    end
end
