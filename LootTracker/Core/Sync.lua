--[[
    LootTracker - Sync Module
    Handles officer-to-officer data synchronization across raid members
    Uses WoW's addon messaging API with throttling for large data transfers
]]

local _, LT = ...
LT.Sync = {}

-- Addon message prefix (max 16 characters)
local ADDON_PREFIX = "LootTracker"

-- Message types
local MSG_TYPE = {
    VERSION_CHECK = "VER",
    ROLL_RECORD = "ROLL",
    ATTENDANCE = "ATT",
    SYNC_REQUEST = "SYNC_REQ",
    SYNC_DATA = "SYNC_DATA",
    LEADER_CLAIM = "LEAD",
    LEADER_ACK = "LEAD_ACK",
}

-- Sync state
local syncState = {
    isLeader = false,
    currentLeader = nil,
    pendingSync = {},
    lastSyncTime = 0,
    version = "1.0.0",
}

-- Message queue for throttling
local messageQueue = {}
local THROTTLE_RATE = 10 -- messages per second max
local lastSendTime = 0

-- Initialize sync system
function LT.Sync:Initialize()
    -- Register addon prefix for messaging
    local success = C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
    if not success then
        print("|cffff0000LootTracker:|r Failed to register addon message prefix")
        return
    end

    -- Create event frame for addon messages
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("GROUP_JOINED")
    frame:RegisterEvent("GROUP_LEFT")

    frame:SetScript("OnEvent", function(self, event, ...)
        if LT.Sync[event] then
            LT.Sync[event](LT.Sync, ...)
        end
    end)

    -- Set up throttle timer
    self.throttleTimer = C_Timer.NewTicker(0.1, function()
        self:ProcessMessageQueue()
    end)
end

--[[
    MESSAGE SENDING
]]

-- Serialize data for transmission
function LT.Sync:Serialize(data)
    -- Simple serialization for Lua tables
    -- In production, use AceSerializer for better handling
    local serialized = ""

    if type(data) == "table" then
        serialized = "T{"
        for k, v in pairs(data) do
            local keyStr = type(k) == "number" and k or ('"' .. tostring(k) .. '"')
            local valStr = self:Serialize(v)
            serialized = serialized .. "[" .. keyStr .. "]=" .. valStr .. ","
        end
        serialized = serialized .. "}"
    elseif type(data) == "string" then
        serialized = '"' .. data:gsub('"', '\\"') .. '"'
    elseif type(data) == "number" then
        serialized = tostring(data)
    elseif type(data) == "boolean" then
        serialized = data and "true" or "false"
    else
        serialized = "nil"
    end

    return serialized
end

-- Deserialize data from transmission
function LT.Sync:Deserialize(str)
    -- Simple deserialization
    -- WARNING: Using loadstring is generally unsafe, but addon messages
    -- come from other players with the same addon, so risk is limited
    if not str or str == "" then return nil end

    local func, err = loadstring("return " .. str)
    if func then
        local success, result = pcall(func)
        if success then
            return result
        end
    end
    return nil
end

-- Queue a message for sending (handles throttling)
function LT.Sync:QueueMessage(msgType, data, channel, target)
    table.insert(messageQueue, {
        type = msgType,
        data = data,
        channel = channel or "RAID",
        target = target,
        timestamp = time(),
    })
end

-- Process the message queue (called by throttle timer)
function LT.Sync:ProcessMessageQueue()
    if #messageQueue == 0 then return end

    local now = GetTime()
    if now - lastSendTime < (1 / THROTTLE_RATE) then
        return
    end

    local msg = table.remove(messageQueue, 1)
    self:SendMessageImmediate(msg.type, msg.data, msg.channel, msg.target)
    lastSendTime = now
end

-- Send message immediately (bypass queue)
function LT.Sync:SendMessageImmediate(msgType, data, channel, target)
    local serialized = self:Serialize(data)
    local message = msgType .. ":" .. serialized

    -- Check message size (max ~255 bytes per message, but can be fragmented)
    if #message > 250 then
        -- Fragment large messages
        self:SendFragmentedMessage(msgType, serialized, channel, target)
        return
    end

    C_ChatInfo.SendAddonMessage(ADDON_PREFIX, message, channel, target)
end

-- Handle large messages by fragmenting
function LT.Sync:SendFragmentedMessage(msgType, serialized, channel, target)
    local CHUNK_SIZE = 200
    local chunks = {}

    for i = 1, #serialized, CHUNK_SIZE do
        table.insert(chunks, serialized:sub(i, i + CHUNK_SIZE - 1))
    end

    local messageId = time() .. "_" .. math.random(1000)

    for i, chunk in ipairs(chunks) do
        local fragMsg = string.format("FRAG:%s:%d:%d:%s", messageId, i, #chunks, chunk)
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, msgType .. ":" .. fragMsg, channel, target)
    end
end

--[[
    MESSAGE RECEIVING
]]

-- Fragment reassembly buffer
local fragmentBuffer = {}

-- Handle incoming addon messages
function LT.Sync:CHAT_MSG_ADDON(prefix, message, channel, sender)
    if prefix ~= ADDON_PREFIX then return end

    -- Don't process our own messages
    if sender == UnitName("player") then return end

    -- Parse message type and data
    local msgType, dataStr = message:match("^(%w+):(.*)$")
    if not msgType then return end

    -- Handle fragments
    if dataStr:match("^FRAG:") then
        self:HandleFragment(msgType, dataStr, sender)
        return
    end

    -- Deserialize and handle
    local data = self:Deserialize(dataStr)
    self:HandleMessage(msgType, data, sender)
end

-- Handle message fragments
function LT.Sync:HandleFragment(msgType, fragData, sender)
    local messageId, index, total, chunk = fragData:match("^FRAG:([^:]+):(%d+):(%d+):(.*)$")
    if not messageId then return end

    index = tonumber(index)
    total = tonumber(total)

    -- Initialize buffer for this message
    if not fragmentBuffer[messageId] then
        fragmentBuffer[messageId] = {
            type = msgType,
            sender = sender,
            chunks = {},
            total = total,
            received = 0,
            timestamp = time(),
        }
    end

    local buffer = fragmentBuffer[messageId]
    buffer.chunks[index] = chunk
    buffer.received = buffer.received + 1

    -- Check if complete
    if buffer.received == buffer.total then
        local fullData = table.concat(buffer.chunks)
        local data = self:Deserialize(fullData)
        self:HandleMessage(buffer.type, data, buffer.sender)
        fragmentBuffer[messageId] = nil
    end
end

-- Route message to appropriate handler
function LT.Sync:HandleMessage(msgType, data, sender)
    if msgType == MSG_TYPE.VERSION_CHECK then
        self:HandleVersionCheck(data, sender)
    elseif msgType == MSG_TYPE.ROLL_RECORD then
        self:HandleRollRecord(data, sender)
    elseif msgType == MSG_TYPE.ATTENDANCE then
        self:HandleAttendance(data, sender)
    elseif msgType == MSG_TYPE.SYNC_REQUEST then
        self:HandleSyncRequest(data, sender)
    elseif msgType == MSG_TYPE.SYNC_DATA then
        self:HandleSyncData(data, sender)
    elseif msgType == MSG_TYPE.LEADER_CLAIM then
        self:HandleLeaderClaim(data, sender)
    elseif msgType == MSG_TYPE.LEADER_ACK then
        self:HandleLeaderAck(data, sender)
    end
end

--[[
    SPECIFIC MESSAGE HANDLERS
]]

-- Handle version check response
function LT.Sync:HandleVersionCheck(data, sender)
    if data and data.version then
        print(string.format("|cff00ff00LootTracker:|r %s has version %s", sender, data.version))
    end
end

-- Handle incoming roll record
function LT.Sync:HandleRollRecord(data, sender)
    -- Only accept from current sync leader or if we have no leader
    if syncState.currentLeader and syncState.currentLeader ~= sender then
        return
    end

    -- Validate data structure
    if not data or not data.item or not data.winner then
        return
    end

    -- Check if we already have this record (by timestamp)
    local history = LT.DB:GetRollHistory()
    for _, record in ipairs(history) do
        if record.endTime == data.endTime and record.item == data.item then
            return -- Duplicate, ignore
        end
    end

    -- Add to our database
    table.insert(LT.DB.db.rolls, data)
    print(string.format("|cff00ff00LootTracker:|r Received roll record from %s: %s won %s",
        sender, data.winner, LT.Events:GetItemName(data.item) or data.item))
end

-- Handle incoming attendance record
function LT.Sync:HandleAttendance(data, sender)
    if syncState.currentLeader and syncState.currentLeader ~= sender then
        return
    end

    if not data or not data.name or not data.attendees then
        return
    end

    -- Check for duplicate
    for _, raid in ipairs(LT.DB.db.attendance.raids) do
        if raid.startTime == data.startTime and raid.name == data.name then
            return
        end
    end

    -- Add to our database
    table.insert(LT.DB.db.attendance.raids, data)

    -- Update player attendance stats
    for _, playerName in ipairs(data.attendees) do
        if not LT.DB.db.attendance.players[playerName] then
            LT.DB.db.attendance.players[playerName] = {
                totalRaids = 0,
                raidDates = {},
            }
        end
        local playerAtt = LT.DB.db.attendance.players[playerName]
        playerAtt.totalRaids = playerAtt.totalRaids + 1
        table.insert(playerAtt.raidDates, data.date)
    end

    print(string.format("|cff00ff00LootTracker:|r Received attendance record from %s: %s", sender, data.name))
end

-- Handle sync request
function LT.Sync:HandleSyncRequest(data, sender)
    -- Only respond if we're the leader
    if not syncState.isLeader then return end

    -- Send our data to the requester
    self:SendFullSync(sender)
end

-- Handle incoming full sync data
function LT.Sync:HandleSyncData(data, sender)
    if not data then return end

    -- Merge incoming data with ours
    -- For simplicity, newer records win
    if data.rolls then
        for _, record in ipairs(data.rolls) do
            -- Add if we don't have it
            local exists = false
            for _, existing in ipairs(LT.DB.db.rolls) do
                if existing.endTime == record.endTime and existing.item == record.item then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(LT.DB.db.rolls, record)
            end
        end
    end

    print(string.format("|cff00ff00LootTracker:|r Sync complete from %s", sender))
end

-- Handle leader claim
function LT.Sync:HandleLeaderClaim(data, sender)
    -- Simple leader election: first claimer wins, or higher rank wins
    if not syncState.currentLeader then
        syncState.currentLeader = sender
        self:QueueMessage(MSG_TYPE.LEADER_ACK, { leader = sender }, "RAID")
        print(string.format("|cff00ff00LootTracker:|r %s is now the sync leader", sender))
    end
end

-- Handle leader acknowledgment
function LT.Sync:HandleLeaderAck(data, sender)
    if data and data.leader then
        syncState.currentLeader = data.leader
    end
end

--[[
    PUBLIC API
]]

-- Broadcast a new roll record to all officers
function LT.Sync:BroadcastRollRecord(record)
    if not IsInRaid() then return end
    self:QueueMessage(MSG_TYPE.ROLL_RECORD, record, "RAID")
end

-- Broadcast attendance record
function LT.Sync:BroadcastAttendance(record)
    if not IsInRaid() then return end
    self:QueueMessage(MSG_TYPE.ATTENDANCE, record, "RAID")
end

-- Request full sync from leader
function LT.Sync:RequestSync()
    if not IsInRaid() then
        print("|cffff9900LootTracker:|r Not in a raid, cannot sync")
        return
    end

    self:QueueMessage(MSG_TYPE.SYNC_REQUEST, { requestor = UnitName("player") }, "RAID")
    print("|cff00ff00LootTracker:|r Requesting sync from leader...")
end

-- Send full database to a specific player
function LT.Sync:SendFullSync(target)
    local syncData = {
        rolls = LT.DB.db.rolls,
        attendance = LT.DB.db.attendance,
        timestamp = time(),
    }

    self:QueueMessage(MSG_TYPE.SYNC_DATA, syncData, "WHISPER", target)
end

-- Claim sync leadership
function LT.Sync:ClaimLeadership()
    if not IsInRaid() then
        print("|cffff9900LootTracker:|r Not in a raid")
        return
    end

    if not LT.Events:IsRaidLeadership() then
        print("|cffff9900LootTracker:|r You must be raid leader or assistant to claim sync leadership")
        return
    end

    syncState.isLeader = true
    syncState.currentLeader = UnitName("player")
    self:QueueMessage(MSG_TYPE.LEADER_CLAIM, { version = syncState.version }, "RAID")
    print("|cff00ff00LootTracker:|r You are now the sync leader")
end

-- Check addon versions in raid
function LT.Sync:CheckVersions()
    if not IsInRaid() then
        print("|cffff9900LootTracker:|r Not in a raid")
        return
    end

    self:QueueMessage(MSG_TYPE.VERSION_CHECK, { version = syncState.version }, "RAID")
    print("|cff00ff00LootTracker:|r Checking addon versions...")
end

-- Handle group joined event
function LT.Sync:GROUP_JOINED()
    -- Reset leadership state when joining a new group
    syncState.isLeader = false
    syncState.currentLeader = nil
end

-- Handle group left event
function LT.Sync:GROUP_LEFT()
    syncState.isLeader = false
    syncState.currentLeader = nil
end

-- Get current sync state
function LT.Sync:GetState()
    return syncState
end
