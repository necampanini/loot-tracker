--[[
    LootTracker - Main Window UI
    History browser, stats dashboard, and attendance tracking
]]

local _, LT = ...
LT.MainWindow = {}

local MainWindow = LT.MainWindow

-- Frame reference
local frame = nil
local currentTab = "history"

-- Create the main window
function MainWindow:Create()
    if frame then return frame end

    -- Main frame
    frame = CreateFrame("Frame", "LootTrackerMainFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(600, 500)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Make it closeable with Escape
    tinsert(UISpecialFrames, "LootTrackerMainFrame")

    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -3)
    frame.title:SetText("LootTracker")

    -- Tab buttons
    self:CreateTabs()

    -- Content frames (one per tab)
    frame.historyContent = self:CreateHistoryContent()
    frame.statsContent = self:CreateStatsContent()
    frame.attendanceContent = self:CreateAttendanceContent()
    frame.configContent = self:CreateConfigContent()

    -- Show default tab
    self:ShowTab("history")

    return frame
end

-- Create tab buttons
function MainWindow:CreateTabs()
    local tabs = {
        { name = "history", label = "History" },
        { name = "stats", label = "Stats" },
        { name = "attendance", label = "Attendance" },
        { name = "config", label = "Config" },
    }

    frame.tabs = {}
    local xOffset = 10

    for i, tabInfo in ipairs(tabs) do
        local tab = CreateFrame("Button", "LootTrackerTab" .. i, frame, "UIPanelButtonTemplate")
        tab:SetSize(80, 22)
        tab:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", xOffset, 25)
        tab:SetText(tabInfo.label)
        tab.tabName = tabInfo.name

        tab:SetScript("OnClick", function(self)
            MainWindow:ShowTab(self.tabName)
        end)

        frame.tabs[tabInfo.name] = tab
        xOffset = xOffset + 85
    end
end

-- Show a specific tab
function MainWindow:ShowTab(tabName)
    currentTab = tabName

    -- Hide all content frames
    if frame.historyContent then frame.historyContent:Hide() end
    if frame.statsContent then frame.statsContent:Hide() end
    if frame.attendanceContent then frame.attendanceContent:Hide() end
    if frame.configContent then frame.configContent:Hide() end

    -- Update tab button states
    for name, tab in pairs(frame.tabs) do
        if name == tabName then
            tab:SetEnabled(false)
        else
            tab:SetEnabled(true)
        end
    end

    -- Show selected content
    if tabName == "history" then
        frame.historyContent:Show()
        self:UpdateHistory()
    elseif tabName == "stats" then
        frame.statsContent:Show()
        self:UpdateStats()
    elseif tabName == "attendance" then
        frame.attendanceContent:Show()
        self:UpdateAttendance()
    elseif tabName == "config" then
        frame.configContent:Show()
        self:UpdateConfig()
    end
end

--[[
    HISTORY TAB
]]

function MainWindow:CreateHistoryContent()
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 5, -30)
    content:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -5, 5)
    content:Hide()

    -- Header
    content.header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    content.header:SetPoint("TOPLEFT", 5, -5)
    content.header:SetText("Loot History")

    -- Scroll frame for history
    content.scrollFrame = CreateFrame("ScrollFrame", "LootTrackerHistoryScroll", content, "UIPanelScrollFrameTemplate")
    content.scrollFrame:SetPoint("TOPLEFT", content.header, "BOTTOMLEFT", 0, -10)
    content.scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -25, 30)

    content.scrollChild = CreateFrame("Frame", nil, content.scrollFrame)
    content.scrollChild:SetSize(content.scrollFrame:GetWidth(), 1)
    content.scrollFrame:SetScrollChild(content.scrollChild)

    content.entries = {}

    -- Export button
    content.exportButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    content.exportButton:SetSize(100, 22)
    content.exportButton:SetPoint("BOTTOMRIGHT", -5, 5)
    content.exportButton:SetText("Export")
    content.exportButton:SetScript("OnClick", function()
        LT:ShowExportWindow()
    end)

    return content
end

function MainWindow:UpdateHistory()
    local content = frame.historyContent
    local history = LT.DB:GetRollHistory()

    -- Clear existing entries
    for _, entry in ipairs(content.entries) do
        entry:Hide()
    end

    -- Create entries for each record
    for i, record in ipairs(history) do
        local entry = content.entries[i]
        if not entry then
            entry = CreateFrame("Frame", nil, content.scrollChild)
            entry:SetHeight(35)
            entry:SetPoint("TOPLEFT", content.scrollChild, "TOPLEFT", 0, -(i - 1) * 37)
            entry:SetPoint("TOPRIGHT", content.scrollChild, "TOPRIGHT", 0, -(i - 1) * 37)

            entry.bg = entry:CreateTexture(nil, "BACKGROUND")
            entry.bg:SetAllPoints()
            entry.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

            entry.itemText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            entry.itemText:SetPoint("TOPLEFT", 5, -3)
            entry.itemText:SetWidth(400)
            entry.itemText:SetJustifyH("LEFT")

            entry.winnerText = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            entry.winnerText:SetPoint("TOPLEFT", entry.itemText, "BOTTOMLEFT", 0, -2)

            entry.dateText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            entry.dateText:SetPoint("TOPRIGHT", -5, -3)
            entry.dateText:SetTextColor(0.6, 0.6, 0.6)

            content.entries[i] = entry
        end

        local itemName = LT.Events:GetItemName(record.item) or record.item
        entry.itemText:SetText(itemName)
        entry.winnerText:SetText(string.format("Won by %s (roll: %d)", record.winner, record.winningRoll))
        entry.dateText:SetText(date("%m/%d/%y %H:%M", record.endTime))

        entry:Show()
    end

    content.scrollChild:SetHeight(math.max(1, #history * 37))
end

--[[
    STATS TAB
]]

function MainWindow:CreateStatsContent()
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 5, -30)
    content:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -5, 5)
    content:Hide()

    -- Header
    content.header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    content.header:SetPoint("TOPLEFT", 5, -5)
    content.header:SetText("Player Statistics")

    -- Column headers
    local colHeaders = CreateFrame("Frame", nil, content)
    colHeaders:SetPoint("TOPLEFT", content.header, "BOTTOMLEFT", 0, -15)
    colHeaders:SetPoint("TOPRIGHT", content, "TOPRIGHT", -30, -25)
    colHeaders:SetHeight(20)

    local headers = { "Player", "Wins", "Losses", "Win%", "Avg Roll", "Attendance" }
    local widths = { 120, 50, 50, 60, 70, 80 }
    local xPos = 0

    for i, text in ipairs(headers) do
        local headerText = colHeaders:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("LEFT", xPos, 0)
        headerText:SetWidth(widths[i])
        headerText:SetText(text)
        headerText:SetTextColor(1, 0.8, 0)
        xPos = xPos + widths[i]
    end

    -- Scroll frame for stats
    content.scrollFrame = CreateFrame("ScrollFrame", "LootTrackerStatsScroll", content, "UIPanelScrollFrameTemplate")
    content.scrollFrame:SetPoint("TOPLEFT", colHeaders, "BOTTOMLEFT", 0, -5)
    content.scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -25, 5)

    content.scrollChild = CreateFrame("Frame", nil, content.scrollFrame)
    content.scrollChild:SetSize(content.scrollFrame:GetWidth(), 1)
    content.scrollFrame:SetScrollChild(content.scrollChild)

    content.entries = {}

    return content
end

function MainWindow:UpdateStats()
    local content = frame.statsContent
    local allStats = LT.DB:GetAllPlayerStats()

    -- Clear existing entries
    for _, entry in ipairs(content.entries) do
        entry:Hide()
    end

    local widths = { 120, 50, 50, 60, 70, 80 }

    for i, stats in ipairs(allStats) do
        local entry = content.entries[i]
        if not entry then
            entry = CreateFrame("Frame", nil, content.scrollChild)
            entry:SetHeight(18)
            entry:SetPoint("TOPLEFT", content.scrollChild, "TOPLEFT", 0, -(i - 1) * 20)
            entry:SetPoint("TOPRIGHT", content.scrollChild, "TOPRIGHT", 0, -(i - 1) * 20)

            if i % 2 == 0 then
                entry.bg = entry:CreateTexture(nil, "BACKGROUND")
                entry.bg:SetAllPoints()
                entry.bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
            end

            entry.texts = {}
            local xPos = 0
            for j = 1, 6 do
                local text = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                text:SetPoint("LEFT", xPos, 0)
                text:SetWidth(widths[j])
                text:SetJustifyH(j == 1 and "LEFT" or "CENTER")
                entry.texts[j] = text
                xPos = xPos + widths[j]
            end

            content.entries[i] = entry
        end

        local attendance = LT.DB:GetAttendanceRate(stats.name)

        entry.texts[1]:SetText(stats.name)
        entry.texts[2]:SetText(tostring(stats.wins))
        entry.texts[3]:SetText(tostring(stats.losses))
        entry.texts[4]:SetText(string.format("%.1f%%", stats.winRate))
        entry.texts[5]:SetText(string.format("%.1f", stats.avgRoll))
        entry.texts[6]:SetText(string.format("%.0f%%", attendance))

        entry:Show()
    end

    content.scrollChild:SetHeight(math.max(1, #allStats * 20))
end

--[[
    ATTENDANCE TAB
]]

function MainWindow:CreateAttendanceContent()
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 5, -30)
    content:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -5, 5)
    content:Hide()

    -- Header
    content.header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    content.header:SetPoint("TOPLEFT", 5, -5)
    content.header:SetText("Raid Attendance")

    -- Active session indicator
    content.activeSession = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    content.activeSession:SetPoint("TOPLEFT", content.header, "BOTTOMLEFT", 0, -10)
    content.activeSession:SetTextColor(0, 1, 0)

    -- Scroll frame
    content.scrollFrame = CreateFrame("ScrollFrame", "LootTrackerAttendanceScroll", content, "UIPanelScrollFrameTemplate")
    content.scrollFrame:SetPoint("TOPLEFT", content.activeSession, "BOTTOMLEFT", 0, -10)
    content.scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -25, 40)

    content.scrollChild = CreateFrame("Frame", nil, content.scrollFrame)
    content.scrollChild:SetSize(content.scrollFrame:GetWidth(), 1)
    content.scrollFrame:SetScrollChild(content.scrollChild)

    content.entries = {}

    -- Control buttons
    content.startButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    content.startButton:SetSize(100, 22)
    content.startButton:SetPoint("BOTTOMLEFT", 5, 5)
    content.startButton:SetText("Start Raid")
    content.startButton:SetScript("OnClick", function()
        StaticPopup_Show("LOOTTRACKER_RAID_NAME")
    end)

    content.syncButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    content.syncButton:SetSize(100, 22)
    content.syncButton:SetPoint("LEFT", content.startButton, "RIGHT", 10, 0)
    content.syncButton:SetText("Sync Roster")
    content.syncButton:SetScript("OnClick", function()
        LT:SyncRaidRoster()
        MainWindow:UpdateAttendance()
    end)

    content.endButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    content.endButton:SetSize(100, 22)
    content.endButton:SetPoint("LEFT", content.syncButton, "RIGHT", 10, 0)
    content.endButton:SetText("End Raid")
    content.endButton:SetScript("OnClick", function()
        LT:EndRaidSession()
        MainWindow:UpdateAttendance()
    end)

    -- Popup for raid name
    StaticPopupDialogs["LOOTTRACKER_RAID_NAME"] = {
        text = "Enter raid name:",
        button1 = "Start",
        button2 = "Cancel",
        hasEditBox = true,
        editBoxWidth = 200,
        OnAccept = function(self)
            local name = self.editBox:GetText()
            if name and name ~= "" then
                LT:StartRaidSession(name)
                MainWindow:UpdateAttendance()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    return content
end

function MainWindow:UpdateAttendance()
    local content = frame.attendanceContent
    local activeRaid = LT.DB:GetActiveRaid()
    local history = LT.DB:GetAttendanceHistory()

    -- Update active session display
    if activeRaid then
        content.activeSession:SetText(string.format("Active: %s (%d attendees)",
            activeRaid.name, #activeRaid.attendees))
        content.activeSession:SetTextColor(0, 1, 0)
        content.startButton:Disable()
        content.syncButton:Enable()
        content.endButton:Enable()
    else
        content.activeSession:SetText("No active raid session")
        content.activeSession:SetTextColor(0.5, 0.5, 0.5)
        content.startButton:Enable()
        content.syncButton:Disable()
        content.endButton:Disable()
    end

    -- Clear existing entries
    for _, entry in ipairs(content.entries) do
        entry:Hide()
    end

    -- Show raid history
    for i, raid in ipairs(history) do
        local entry = content.entries[i]
        if not entry then
            entry = CreateFrame("Frame", nil, content.scrollChild)
            entry:SetHeight(30)
            entry:SetPoint("TOPLEFT", content.scrollChild, "TOPLEFT", 0, -(i - 1) * 32)
            entry:SetPoint("TOPRIGHT", content.scrollChild, "TOPRIGHT", 0, -(i - 1) * 32)

            entry.bg = entry:CreateTexture(nil, "BACKGROUND")
            entry.bg:SetAllPoints()
            entry.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

            entry.nameText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            entry.nameText:SetPoint("TOPLEFT", 5, -3)

            entry.detailText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            entry.detailText:SetPoint("TOPLEFT", entry.nameText, "BOTTOMLEFT", 0, -2)
            entry.detailText:SetTextColor(0.6, 0.6, 0.6)

            content.entries[i] = entry
        end

        entry.nameText:SetText(raid.name)
        entry.detailText:SetText(string.format("%s | %d attendees",
            raid.date, #raid.attendees))

        entry:Show()
    end

    content.scrollChild:SetHeight(math.max(1, #history * 32))
end

--[[
    CONFIG TAB
]]

function MainWindow:CreateConfigContent()
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 5, -30)
    content:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -5, 5)
    content:Hide()

    -- Header
    content.header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    content.header:SetPoint("TOPLEFT", 5, -5)
    content.header:SetText("Configuration")

    local yOffset = -30

    -- Announce winner checkbox
    content.announceCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    content.announceCheck:SetPoint("TOPLEFT", 10, yOffset)
    content.announceCheck.text = content.announceCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    content.announceCheck.text:SetPoint("LEFT", content.announceCheck, "RIGHT", 5, 0)
    content.announceCheck.text:SetText("Announce winner to raid")
    content.announceCheck:SetScript("OnClick", function(self)
        LT.DB:SetConfig("announceWinner", self:GetChecked())
    end)

    yOffset = yOffset - 30

    -- Auto reroll checkbox
    content.autoRerollCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    content.autoRerollCheck:SetPoint("TOPLEFT", 10, yOffset)
    content.autoRerollCheck.text = content.autoRerollCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    content.autoRerollCheck.text:SetPoint("LEFT", content.autoRerollCheck, "RIGHT", 5, 0)
    content.autoRerollCheck.text:SetText("Auto-prompt reroll on ties")
    content.autoRerollCheck:SetScript("OnClick", function(self)
        LT.DB:SetConfig("autoReroll", self:GetChecked())
    end)

    yOffset = yOffset - 40

    -- Priority weight slider
    content.priorityLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    content.priorityLabel:SetPoint("TOPLEFT", 10, yOffset)
    content.priorityLabel:SetText("Priority Weight (attendance influence):")

    yOffset = yOffset - 25

    content.prioritySlider = CreateFrame("Slider", "LootTrackerPrioritySlider", content, "OptionsSliderTemplate")
    content.prioritySlider:SetPoint("TOPLEFT", 15, yOffset)
    content.prioritySlider:SetWidth(200)
    content.prioritySlider:SetMinMaxValues(0, 1)
    content.prioritySlider:SetValueStep(0.1)
    content.prioritySlider:SetObeyStepOnDrag(true)
    content.prioritySlider.Low:SetText("0")
    content.prioritySlider.High:SetText("1")
    content.prioritySlider:SetScript("OnValueChanged", function(self, value)
        LT.DB:SetConfig("priorityWeight", value)
        self.Text:SetText(string.format("%.1f", value))
    end)

    return content
end

function MainWindow:UpdateConfig()
    local content = frame.configContent
    local config = LT.DB:GetConfig()

    content.announceCheck:SetChecked(config.announceWinner)
    content.autoRerollCheck:SetChecked(config.autoReroll)
    content.prioritySlider:SetValue(config.priorityWeight)
    content.prioritySlider.Text:SetText(string.format("%.1f", config.priorityWeight))
end

--[[
    PUBLIC API
]]

function MainWindow:Show()
    if not frame then
        self:Create()
    end
    frame:Show()
    self:ShowTab(currentTab)
end

function MainWindow:Hide()
    if frame then
        frame:Hide()
    end
end

function MainWindow:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
