--[[
    LootTracker - Debug Module
    Comprehensive logging, debugging, and diagnostic tools

    Usage:
        /lt debug on|off|level [1-4]  - Toggle debug mode or set verbosity
        /lt debug log                  - Show recent log entries
        /lt debug dump [module]        - Dump internal state
        /lt debug events               - Toggle event tracing
        /lt debug inspect [var]        - Inspect a variable
]]

local _, LT = ...
LT.Debug = {}

local Debug = LT.Debug

-- Debug configuration
local debugConfig = {
    enabled = false,
    level = 2,           -- 1=ERROR, 2=WARN, 3=INFO, 4=TRACE
    logToChat = true,
    logToFile = true,    -- Stores in SavedVariables
    maxLogEntries = 500,
    traceEvents = false,
    timestamps = true,
    colors = {
        ERROR = "|cffff0000",
        WARN  = "|cffff9900",
        INFO  = "|cff00ff00",
        TRACE = "|cff888888",
        DEBUG = "|cff00ffff",
    },
}

-- Log levels
local LOG_LEVEL = {
    ERROR = 1,
    WARN = 2,
    INFO = 3,
    TRACE = 4,
}

-- In-memory log buffer
local logBuffer = {}

-- Performance tracking
local perfMetrics = {
    rollsProcessed = 0,
    eventsHandled = 0,
    syncMessagesSent = 0,
    syncMessagesReceived = 0,
    uiUpdates = 0,
    startTime = 0,
}

-- Initialize debug system
function Debug:Initialize()
    perfMetrics.startTime = GetTime()

    -- Load saved debug config if exists
    if LootTrackerDB and LootTrackerDB.debugConfig then
        for k, v in pairs(LootTrackerDB.debugConfig) do
            if debugConfig[k] ~= nil then
                debugConfig[k] = v
            end
        end
    end

    -- Load saved log buffer
    if LootTrackerDB and LootTrackerDB.debugLog then
        logBuffer = LootTrackerDB.debugLog
    end

    self:Log("INFO", "Debug", "Debug system initialized (level=%d, enabled=%s)",
        debugConfig.level, tostring(debugConfig.enabled))
end

-- Save debug state to SavedVariables
function Debug:SaveState()
    if not LootTrackerDB then return end
    LootTrackerDB.debugConfig = debugConfig
    LootTrackerDB.debugLog = logBuffer
end

--[[
    CORE LOGGING
]]

-- Main logging function
function Debug:Log(level, module, message, ...)
    local levelNum = LOG_LEVEL[level] or 3

    -- Check if we should log this
    if not debugConfig.enabled and levelNum > LOG_LEVEL.WARN then
        return
    end

    if levelNum > debugConfig.level then
        return
    end

    -- Format message with arguments
    if select('#', ...) > 0 then
        message = string.format(message, ...)
    end

    -- Create log entry
    local entry = {
        time = time(),
        gameTime = GetTime(),
        level = level,
        module = module,
        message = message,
        stack = (level == "ERROR") and debugstack(2) or nil,
    }

    -- Add to buffer
    table.insert(logBuffer, entry)

    -- Trim buffer if too large
    while #logBuffer > debugConfig.maxLogEntries do
        table.remove(logBuffer, 1)
    end

    -- Output to chat if enabled
    if debugConfig.logToChat then
        local color = debugConfig.colors[level] or "|cffffffff"
        local timestamp = debugConfig.timestamps and
            string.format("[%s] ", date("%H:%M:%S", entry.time)) or ""

        print(string.format("%s%s[LT-%s] %s:|r %s",
            color, timestamp, level, module, message))
    end
end

-- Convenience logging methods
function Debug:Error(module, message, ...)
    self:Log("ERROR", module, message, ...)
end

function Debug:Warn(module, message, ...)
    self:Log("WARN", module, message, ...)
end

function Debug:Info(module, message, ...)
    self:Log("INFO", module, message, ...)
end

function Debug:Trace(module, message, ...)
    self:Log("TRACE", module, message, ...)
end

--[[
    PERFORMANCE TRACKING
]]

-- Track a metric
function Debug:TrackMetric(metric, increment)
    increment = increment or 1
    if perfMetrics[metric] then
        perfMetrics[metric] = perfMetrics[metric] + increment
    end
end

-- Get performance report
function Debug:GetPerfReport()
    local uptime = GetTime() - perfMetrics.startTime
    return {
        uptime = uptime,
        uptimeFormatted = string.format("%.1f minutes", uptime / 60),
        rollsProcessed = perfMetrics.rollsProcessed,
        rollsPerMinute = uptime > 0 and (perfMetrics.rollsProcessed / (uptime / 60)) or 0,
        eventsHandled = perfMetrics.eventsHandled,
        syncSent = perfMetrics.syncMessagesSent,
        syncReceived = perfMetrics.syncMessagesReceived,
        uiUpdates = perfMetrics.uiUpdates,
        memoryKB = collectgarbage("count"),
    }
end

--[[
    STATE INSPECTION
]]

-- Dump internal state of a module
function Debug:DumpState(moduleName)
    local dumps = {
        database = function()
            return {
                activeSession = LT.DB:GetActiveSession(),
                activeRaid = LT.DB:GetActiveRaid(),
                rollCount = LT.DB.db and #LT.DB.db.rolls or 0,
                raidCount = LT.DB.db and #LT.DB.db.attendance.raids or 0,
                playerStats = LT.DB.db and LT.DB:GetAllPlayerStats() or {},
                config = LT.DB.db and LT.DB.db.config or {},
            }
        end,

        events = function()
            return {
                isInRaid = IsInRaid(),
                isInGroup = IsInGroup(),
                groupSize = GetNumGroupMembers(),
                isOfficer = LT.Events:IsOfficer(),
                isRaidLead = LT.Events:IsRaidLeadership(),
            }
        end,

        sync = function()
            return LT.Sync:GetState()
        end,

        ui = function()
            return {
                rollTrackerShown = LT.RollTracker and LootTrackerRollFrame and
                    LootTrackerRollFrame:IsShown() or false,
                mainWindowShown = LT.MainWindow and LootTrackerMainFrame and
                    LootTrackerMainFrame:IsShown() or false,
                exportShown = LT.Export and LootTrackerExportFrame and
                    LootTrackerExportFrame:IsShown() or false,
            }
        end,

        perf = function()
            return self:GetPerfReport()
        end,

        all = function()
            return {
                database = dumps.database(),
                events = dumps.events(),
                sync = dumps.sync(),
                ui = dumps.ui(),
                perf = dumps.perf(),
            }
        end,
    }

    local dumpFunc = dumps[moduleName] or dumps.all
    return dumpFunc()
end

-- Pretty print a table
function Debug:PrettyPrint(tbl, indent, visited)
    indent = indent or 0
    visited = visited or {}

    if type(tbl) ~= "table" then
        return tostring(tbl)
    end

    if visited[tbl] then
        return "<circular reference>"
    end
    visited[tbl] = true

    local lines = {}
    local prefix = string.rep("  ", indent)

    table.insert(lines, "{")
    for k, v in pairs(tbl) do
        local keyStr = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
        local valStr

        if type(v) == "table" then
            valStr = self:PrettyPrint(v, indent + 1, visited)
        elseif type(v) == "string" then
            valStr = '"' .. v .. '"'
        else
            valStr = tostring(v)
        end

        table.insert(lines, prefix .. "  " .. keyStr .. " = " .. valStr .. ",")
    end
    table.insert(lines, prefix .. "}")

    return table.concat(lines, "\n")
end

--[[
    EVENT TRACING
]]

-- Hook into event system for tracing
function Debug:SetupEventTracing()
    if not debugConfig.traceEvents then return end

    -- Create a frame to capture all events
    local traceFrame = CreateFrame("Frame")
    traceFrame:RegisterAllEvents()

    local ignoredEvents = {
        "ACTIONBAR_UPDATE_COOLDOWN",
        "SPELL_UPDATE_COOLDOWN",
        "UNIT_POWER_UPDATE",
        "UNIT_AURA",
        "COMBAT_LOG_EVENT_UNFILTERED",
        "UNIT_HEALTH",
        "UPDATE_MOUSEOVER_UNIT",
    }

    traceFrame:SetScript("OnEvent", function(self, event, ...)
        for _, ignored in ipairs(ignoredEvents) do
            if event == ignored then return end
        end
        Debug:Trace("Event", "%s: %s", event, Debug:SerializeArgs(...))
    end)

    self.traceFrame = traceFrame
    self:Info("Debug", "Event tracing enabled")
end

-- Serialize function arguments for logging
function Debug:SerializeArgs(...)
    local args = {}
    for i = 1, select('#', ...) do
        local arg = select(i, ...)
        if type(arg) == "table" then
            table.insert(args, "<table>")
        elseif type(arg) == "string" then
            table.insert(args, '"' .. arg:sub(1, 50) .. '"')
        else
            table.insert(args, tostring(arg))
        end
    end
    return table.concat(args, ", ")
end

--[[
    LOG RETRIEVAL
]]

-- Get recent log entries
function Debug:GetLog(count, levelFilter, moduleFilter)
    count = count or 50
    local results = {}

    for i = #logBuffer, math.max(1, #logBuffer - count + 1), -1 do
        local entry = logBuffer[i]

        local include = true
        if levelFilter and entry.level ~= levelFilter then
            include = false
        end
        if moduleFilter and entry.module ~= moduleFilter then
            include = false
        end

        if include then
            table.insert(results, entry)
        end
    end

    return results
end

-- Format log entry for display
function Debug:FormatLogEntry(entry)
    local color = debugConfig.colors[entry.level] or "|cffffffff"
    return string.format("%s[%s] %s[%s] %s:|r %s",
        color,
        date("%H:%M:%S", entry.time),
        color,
        entry.level,
        entry.module,
        entry.message
    )
end

-- Clear log buffer
function Debug:ClearLog()
    logBuffer = {}
    self:Info("Debug", "Log buffer cleared")
end

--[[
    ASSERTIONS & VALIDATION
]]

-- Assert a condition with logging
function Debug:Assert(condition, module, message, ...)
    if not condition then
        self:Error(module, "ASSERTION FAILED: " .. message, ...)
        if debugConfig.level >= LOG_LEVEL.TRACE then
            print(debugstack(2))
        end
    end
    return condition
end

-- Validate data structure
function Debug:ValidateRollSession(session)
    local errors = {}

    if not session then
        table.insert(errors, "Session is nil")
        return false, errors
    end

    if not session.item then
        table.insert(errors, "Missing item")
    end

    if not session.startTime then
        table.insert(errors, "Missing startTime")
    end

    if type(session.rolls) ~= "table" then
        table.insert(errors, "rolls is not a table")
    end

    if session.state and not (session.state == "open" or session.state == "rerolling" or session.state == "closed") then
        table.insert(errors, "Invalid state: " .. tostring(session.state))
    end

    return #errors == 0, errors
end

--[[
    SLASH COMMAND HANDLER
]]

function Debug:HandleCommand(args)
    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "on" then
        debugConfig.enabled = true
        self:SaveState()
        print("|cff00ff00LootTracker Debug:|r Enabled (level " .. debugConfig.level .. ")")

    elseif cmd == "off" then
        debugConfig.enabled = false
        self:SaveState()
        print("|cff00ff00LootTracker Debug:|r Disabled")

    elseif cmd == "level" then
        local level = tonumber(args[2])
        if level and level >= 1 and level <= 4 then
            debugConfig.level = level
            self:SaveState()
            local levelNames = { "ERROR", "WARN", "INFO", "TRACE" }
            print("|cff00ff00LootTracker Debug:|r Level set to " .. level .. " (" .. levelNames[level] .. ")")
        else
            print("|cffff9900Usage:|r /lt debug level [1-4]")
            print("  1=ERROR, 2=WARN, 3=INFO, 4=TRACE")
        end

    elseif cmd == "log" then
        local count = tonumber(args[2]) or 20
        local logs = self:GetLog(count)
        print("|cff00ff00=== LootTracker Debug Log (last " .. #logs .. ") ===|r")
        for i = #logs, 1, -1 do
            print(self:FormatLogEntry(logs[i]))
        end

    elseif cmd == "clear" then
        self:ClearLog()

    elseif cmd == "dump" then
        local module = args[2] or "all"
        local state = self:DumpState(module)
        print("|cff00ff00=== LootTracker State Dump: " .. module .. " ===|r")
        print(self:PrettyPrint(state))

    elseif cmd == "events" then
        debugConfig.traceEvents = not debugConfig.traceEvents
        if debugConfig.traceEvents then
            self:SetupEventTracing()
        elseif self.traceFrame then
            self.traceFrame:UnregisterAllEvents()
        end
        print("|cff00ff00LootTracker Debug:|r Event tracing " ..
            (debugConfig.traceEvents and "enabled" or "disabled"))

    elseif cmd == "perf" then
        local report = self:GetPerfReport()
        print("|cff00ff00=== LootTracker Performance ===|r")
        print("  Uptime: " .. report.uptimeFormatted)
        print("  Rolls processed: " .. report.rollsProcessed)
        print("  Events handled: " .. report.eventsHandled)
        print("  Sync sent/received: " .. report.syncSent .. "/" .. report.syncReceived)
        print("  UI updates: " .. report.uiUpdates)
        print("  Memory: " .. string.format("%.1f KB", report.memoryKB))

    elseif cmd == "validate" then
        local session = LT.DB:GetActiveSession()
        if session then
            local valid, errors = self:ValidateRollSession(session)
            if valid then
                print("|cff00ff00LootTracker:|r Active session is valid")
            else
                print("|cffff0000LootTracker:|r Session validation errors:")
                for _, err in ipairs(errors) do
                    print("  - " .. err)
                end
            end
        else
            print("|cffff9900LootTracker:|r No active session to validate")
        end

    else
        print("|cff00ff00=== LootTracker Debug Commands ===|r")
        print("  /lt debug on|off     - Toggle debug mode")
        print("  /lt debug level [1-4] - Set verbosity (1=ERROR to 4=TRACE)")
        print("  /lt debug log [n]    - Show last n log entries")
        print("  /lt debug clear      - Clear log buffer")
        print("  /lt debug dump [mod] - Dump state (database|events|sync|ui|perf|all)")
        print("  /lt debug events     - Toggle event tracing")
        print("  /lt debug perf       - Show performance metrics")
        print("  /lt debug validate   - Validate active session")
        print("")
        print("  Current: " .. (debugConfig.enabled and "ON" or "OFF") ..
            ", Level=" .. debugConfig.level)
    end
end
