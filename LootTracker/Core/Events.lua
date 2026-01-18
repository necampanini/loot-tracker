--[[
    LootTracker - Events Module
    Handles WoW events for roll detection, loot tracking, and raid changes
]]

local _, LT = ...
LT.Events = {}

-- Event frame for registering WoW events
local eventFrame = CreateFrame("Frame")

-- Roll pattern: "Playername rolls 85 (1-100)"
-- This pattern handles various locales and edge cases
local ROLL_PATTERN = "(.+) rolls (%d+) %((%d+)%-(%d+)%)"

-- Alternative patterns for different WoW localizations
local ROLL_PATTERNS = {
    "(.+) rolls (%d+) %((%d+)%-(%d+)%)",           -- English
    "(.+) würfelt%. Ergebnis: (%d+) %((%d+)%-(%d+)%)", -- German
    "(.+) lance les dés et obtient (%d+) %((%d+)%-(%d+)%)", -- French
}

-- Initialize event handlers
function LT.Events:Initialize()
    -- Register for events
    eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_LOGOUT")
    eventFrame:RegisterEvent("LOOT_OPENED")
    eventFrame:RegisterEvent("LOOT_SLOT_CLEARED")

    -- Set up event handler
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if LT.Events[event] then
            LT.Events[event](LT.Events, ...)
        end
    end)
end

-- Parse roll from system message
function LT.Events:ParseRoll(message)
    for _, pattern in ipairs(ROLL_PATTERNS) do
        local player, roll, minRoll, maxRoll = string.match(message, pattern)
        if player and roll then
            return player, tonumber(roll), tonumber(minRoll), tonumber(maxRoll)
        end
    end
    return nil
end

-- Handle system chat messages (roll results appear here)
function LT.Events:CHAT_MSG_SYSTEM(message)
    local player, roll, minRoll, maxRoll = self:ParseRoll(message)

    if player and roll then
        -- Attempt to record the roll
        local session = LT.DB:GetActiveSession()
        if session then
            local success, err = LT.DB:RecordRoll(player, roll, minRoll, maxRoll)

            if success then
                -- Update UI if it exists
                if LT.RollTracker and LT.RollTracker.UpdateRollList then
                    LT.RollTracker:UpdateRollList()
                end

                -- Check for auto-end conditions
                self:CheckRollSessionState()
            end
        end
    end
end

-- Check if we should prompt for reroll or have a winner
function LT.Events:CheckRollSessionState()
    local session = LT.DB:GetActiveSession()
    if not session then return end

    -- Only check in rerolling state
    if session.state ~= "rerolling" then return end

    -- Check if all eligible players have rolled
    local currentRound = session.rerollRound
    local rollsThisRound = 0

    for _, roll in ipairs(session.rolls) do
        if roll.round == currentRound then
            rollsThisRound = rollsThisRound + 1
        end
    end

    if rollsThisRound >= #session.eligiblePlayers then
        -- All eligible players have rolled, check for winner
        local winners = LT.DB:GetHighestRollers(currentRound)

        if winners and #winners == 1 then
            -- We have a winner from the reroll
            if LT.RollTracker then
                LT.RollTracker:OnRerollComplete(winners[1])
            end
        elseif winners and #winners > 1 then
            -- Still tied, need another reroll
            if LT.RollTracker then
                LT.RollTracker:OnTieDetected(winners)
            end
        end
    end
end

-- Handle group roster changes
function LT.Events:GROUP_ROSTER_UPDATE()
    -- Auto-update attendance if raid session is active and configured
    local activeRaid = LT.DB:GetActiveRaid()
    if activeRaid then
        -- Could auto-sync roster here if configured
        -- For now, just notify the UI
        if LT.MainWindow and LT.MainWindow.UpdateAttendance then
            LT.MainWindow:UpdateAttendance()
        end
    end
end

-- Handle raid roster changes (same as group for raids)
function LT.Events:RAID_ROSTER_UPDATE()
    self:GROUP_ROSTER_UPDATE()
end

-- Handle player logout - ensure data is saved
function LT.Events:PLAYER_LOGOUT()
    -- SavedVariables are automatically saved, but we can do cleanup here
    -- Cancel any active sessions to prevent data corruption
    if LT.DB:GetActiveSession() then
        print("|cffff9900LootTracker:|r Active roll session cancelled due to logout")
        LT.DB:CancelRollSession()
    end

    if LT.DB:GetActiveRaid() then
        print("|cffff9900LootTracker:|r Active raid session ended due to logout")
        LT.DB:EndRaidSession()
    end
end

-- Handle loot window opening (potential future feature)
function LT.Events:LOOT_OPENED()
    -- Could auto-detect loot and suggest starting roll sessions
    -- For now, just track that loot is available
end

-- Handle loot being taken
function LT.Events:LOOT_SLOT_CLEARED(slot)
    -- Future: could track what items were looted
end

--[[
    UTILITY FUNCTIONS
]]

-- Check if player is a raid/guild officer
function LT.Events:IsOfficer(playerName)
    playerName = playerName or UnitName("player")

    -- Check if in a guild
    if not IsInGuild() then
        return false
    end

    -- Get guild rank info
    local guildName, guildRankName, guildRankIndex = GetGuildInfo("player")

    if not guildRankIndex then
        return false
    end

    -- Rank 0 = Guild Master, Rank 1 = usually Officers
    -- This varies by guild setup, so we check if rank can promote/demote
    local canPromote = C_GuildInfo.GuildControlGetRankFlags(guildRankIndex)

    -- Alternative: check specific rank numbers (configurable)
    -- For simplicity, ranks 0-2 are considered officers
    if guildRankIndex <= 2 then
        return true
    end

    return false
end

-- Check if player is raid leader or assistant
function LT.Events:IsRaidLeadership(playerName)
    if not IsInRaid() then
        return false
    end

    playerName = playerName or UnitName("player")

    for i = 1, GetNumGroupMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if name then
            local shortName = strsplit("-", name)
            if shortName == playerName then
                -- rank 2 = leader, rank 1 = assistant
                return rank >= 1
            end
        end
    end

    return false
end

-- Announce message to appropriate channel
function LT.Events:Announce(message, channel)
    channel = channel or LT.DB:GetConfig().announceChannel

    if channel == "RAID" and IsInRaid() then
        SendChatMessage(message, "RAID")
    elseif channel == "PARTY" and IsInGroup() then
        SendChatMessage(message, "PARTY")
    elseif channel == "RAID_WARNING" and IsInRaid() and LT.Events:IsRaidLeadership() then
        SendChatMessage(message, "RAID_WARNING")
    else
        -- Fallback to print locally
        print("|cff00ff00LootTracker:|r " .. message)
    end
end

-- Get item link from item ID or partial name
function LT.Events:GetItemLink(itemIdentifier)
    -- If it's already a link, return it
    if string.match(itemIdentifier, "|H") then
        return itemIdentifier
    end

    -- Try to get item info (may need to be cached)
    local itemID = tonumber(itemIdentifier)
    if itemID then
        local itemLink = select(2, GetItemInfo(itemID))
        return itemLink
    end

    -- Return as-is (plain text item name)
    return itemIdentifier
end

-- Extract item name from item link
function LT.Events:GetItemName(itemLink)
    if not itemLink then return nil end

    -- Match item name from link format: |Hitem:id|h[Item Name]|h
    local itemName = string.match(itemLink, "%[(.+)%]")
    return itemName or itemLink
end
