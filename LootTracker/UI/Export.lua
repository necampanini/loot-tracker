--[[
    LootTracker - Export UI
    Generates copyable text exports of loot and attendance data
]]

local _, LT = ...
LT.Export = {}

local Export = LT.Export

-- Frame reference
local frame = nil

-- Export formats
local EXPORT_FORMATS = {
    { name = "CSV", func = "GenerateCSV" },
    { name = "Markdown", func = "GenerateMarkdown" },
    { name = "Plain Text", func = "GeneratePlainText" },
    { name = "Discord", func = "GenerateDiscord" },
}

-- Create the export window
function Export:Create()
    if frame then return frame end

    -- Main frame (starts compact, is resizable)
    frame = CreateFrame("Frame", "LootTrackerExportFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(380, 320)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(300, 250, 700, 600)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Resize grip
    frame.resizeGrip = CreateFrame("Button", nil, frame)
    frame.resizeGrip:SetSize(16, 16)
    frame.resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    frame.resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    frame.resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    frame.resizeGrip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    frame.resizeGrip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)

    tinsert(UISpecialFrames, "LootTrackerExportFrame")

    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -3)
    frame.title:SetText("Export Data")

    -- Data type dropdown
    frame.dataTypeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.dataTypeLabel:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 10, -10)
    frame.dataTypeLabel:SetText("Data Type:")

    frame.dataTypeDropdown = CreateFrame("Frame", "LootTrackerDataTypeDropdown", frame, "UIDropDownMenuTemplate")
    frame.dataTypeDropdown:SetPoint("LEFT", frame.dataTypeLabel, "RIGHT", -5, -3)
    UIDropDownMenu_SetWidth(frame.dataTypeDropdown, 120)
    UIDropDownMenu_SetText(frame.dataTypeDropdown, "Loot History")

    UIDropDownMenu_Initialize(frame.dataTypeDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.func = function(self)
            UIDropDownMenu_SetSelectedValue(frame.dataTypeDropdown, self.value)
            UIDropDownMenu_SetText(frame.dataTypeDropdown, self:GetText())
            Export:UpdateExport()
        end

        info.text = "Loot History"
        info.value = "loot"
        UIDropDownMenu_AddButton(info, level)

        info.text = "Player Stats"
        info.value = "stats"
        UIDropDownMenu_AddButton(info, level)

        info.text = "Attendance"
        info.value = "attendance"
        UIDropDownMenu_AddButton(info, level)
    end)
    UIDropDownMenu_SetSelectedValue(frame.dataTypeDropdown, "loot")

    -- Format dropdown
    frame.formatLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.formatLabel:SetPoint("LEFT", frame.dataTypeDropdown, "RIGHT", 20, 3)
    frame.formatLabel:SetText("Format:")

    frame.formatDropdown = CreateFrame("Frame", "LootTrackerFormatDropdown", frame, "UIDropDownMenuTemplate")
    frame.formatDropdown:SetPoint("LEFT", frame.formatLabel, "RIGHT", -5, -3)
    UIDropDownMenu_SetWidth(frame.formatDropdown, 100)
    UIDropDownMenu_SetText(frame.formatDropdown, "CSV")

    UIDropDownMenu_Initialize(frame.formatDropdown, function(self, level)
        for i, format in ipairs(EXPORT_FORMATS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = format.name
            info.value = format.func
            info.func = function(self)
                UIDropDownMenu_SetSelectedValue(frame.formatDropdown, self.value)
                UIDropDownMenu_SetText(frame.formatDropdown, self:GetText())
                Export:UpdateExport()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(frame.formatDropdown, "GenerateCSV")

    -- Text area for export
    frame.scrollFrame = CreateFrame("ScrollFrame", "LootTrackerExportScroll", frame, "UIPanelScrollFrameTemplate")
    frame.scrollFrame:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 10, -50)
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -30, 40)

    frame.editBox = CreateFrame("EditBox", "LootTrackerExportEditBox", frame.scrollFrame)
    frame.editBox:SetMultiLine(true)
    frame.editBox:SetFontObject(GameFontHighlightSmall)
    frame.editBox:SetWidth(frame.scrollFrame:GetWidth())
    frame.editBox:SetAutoFocus(false)
    frame.editBox:EnableMouse(true)
    frame.editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.scrollFrame:SetScrollChild(frame.editBox)

    -- Select all button
    frame.selectAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.selectAllButton:SetSize(100, 22)
    frame.selectAllButton:SetPoint("BOTTOMLEFT", frame.Inset, "BOTTOMLEFT", 10, 10)
    frame.selectAllButton:SetText("Select All")
    frame.selectAllButton:SetScript("OnClick", function()
        frame.editBox:SetFocus()
        frame.editBox:HighlightText()
    end)

    -- Refresh button
    frame.refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.refreshButton:SetSize(100, 22)
    frame.refreshButton:SetPoint("LEFT", frame.selectAllButton, "RIGHT", 10, 0)
    frame.refreshButton:SetText("Refresh")
    frame.refreshButton:SetScript("OnClick", function()
        Export:UpdateExport()
    end)

    -- Instructions
    frame.instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.instructions:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -10, 15)
    frame.instructions:SetText("Ctrl+C to copy after selecting")
    frame.instructions:SetTextColor(0.6, 0.6, 0.6)

    return frame
end

-- Update the export text
function Export:UpdateExport()
    if not frame then return end

    local dataType = UIDropDownMenu_GetSelectedValue(frame.dataTypeDropdown) or "loot"
    local formatFunc = UIDropDownMenu_GetSelectedValue(frame.formatDropdown) or "GenerateCSV"

    local text = ""
    if dataType == "loot" then
        text = self[formatFunc](self, "loot")
    elseif dataType == "stats" then
        text = self[formatFunc](self, "stats")
    elseif dataType == "attendance" then
        text = self[formatFunc](self, "attendance")
    end

    frame.editBox:SetText(text)

    -- Adjust editbox height to content
    local numLines = select(2, text:gsub("\n", "\n")) + 1
    frame.editBox:SetHeight(numLines * 14)
end

--[[
    EXPORT GENERATORS
]]

-- CSV format
function Export:GenerateCSV(dataType)
    local lines = {}

    if dataType == "loot" then
        table.insert(lines, "Date,Item,Winner,Roll,Started By")
        local history = LT.DB:GetRollHistory()
        for _, record in ipairs(history) do
            local itemName = LT.Events:GetItemName(record.item) or record.item
            -- Escape quotes and commas
            itemName = '"' .. itemName:gsub('"', '""') .. '"'
            table.insert(lines, string.format("%s,%s,%s,%d,%s",
                date("%Y-%m-%d %H:%M", record.endTime),
                itemName,
                record.winner,
                record.winningRoll,
                record.startedBy or "Unknown"
            ))
        end

    elseif dataType == "stats" then
        table.insert(lines, "Player,Wins,Losses,Win Rate,Avg Roll,Total Rolls")
        local stats = LT.DB:GetAllPlayerStats()
        for _, stat in ipairs(stats) do
            table.insert(lines, string.format("%s,%d,%d,%.1f%%,%.1f,%d",
                stat.name,
                stat.wins,
                stat.losses,
                stat.winRate,
                stat.avgRoll,
                stat.totalRolls
            ))
        end

    elseif dataType == "attendance" then
        table.insert(lines, "Date,Raid,Attendees,Count")
        local raids = LT.DB:GetAttendanceHistory()
        for _, raid in ipairs(raids) do
            local attendeeList = table.concat(raid.attendees, "; ")
            attendeeList = '"' .. attendeeList:gsub('"', '""') .. '"'
            table.insert(lines, string.format("%s,%s,%s,%d",
                raid.date,
                raid.name,
                attendeeList,
                #raid.attendees
            ))
        end
    end

    return table.concat(lines, "\n")
end

-- Markdown format
function Export:GenerateMarkdown(dataType)
    local lines = {}

    if dataType == "loot" then
        table.insert(lines, "# Loot History")
        table.insert(lines, "")
        table.insert(lines, "| Date | Item | Winner | Roll |")
        table.insert(lines, "|------|------|--------|------|")

        local history = LT.DB:GetRollHistory()
        for _, record in ipairs(history) do
            local itemName = LT.Events:GetItemName(record.item) or record.item
            table.insert(lines, string.format("| %s | %s | %s | %d |",
                date("%Y-%m-%d", record.endTime),
                itemName,
                record.winner,
                record.winningRoll
            ))
        end

    elseif dataType == "stats" then
        table.insert(lines, "# Player Statistics")
        table.insert(lines, "")
        table.insert(lines, "| Player | Wins | Losses | Win% | Avg Roll |")
        table.insert(lines, "|--------|------|--------|------|----------|")

        local stats = LT.DB:GetAllPlayerStats()
        for _, stat in ipairs(stats) do
            table.insert(lines, string.format("| %s | %d | %d | %.1f%% | %.1f |",
                stat.name,
                stat.wins,
                stat.losses,
                stat.winRate,
                stat.avgRoll
            ))
        end

    elseif dataType == "attendance" then
        table.insert(lines, "# Raid Attendance")
        table.insert(lines, "")

        local raids = LT.DB:GetAttendanceHistory()
        for _, raid in ipairs(raids) do
            table.insert(lines, string.format("## %s - %s", raid.date, raid.name))
            table.insert(lines, string.format("**Attendees:** %d", #raid.attendees))
            table.insert(lines, "")
            for _, player in ipairs(raid.attendees) do
                table.insert(lines, "- " .. player)
            end
            table.insert(lines, "")
        end
    end

    return table.concat(lines, "\n")
end

-- Plain text format
function Export:GeneratePlainText(dataType)
    local lines = {}

    if dataType == "loot" then
        table.insert(lines, "=== LOOT HISTORY ===")
        table.insert(lines, "")

        local history = LT.DB:GetRollHistory()
        for _, record in ipairs(history) do
            local itemName = LT.Events:GetItemName(record.item) or record.item
            table.insert(lines, string.format("[%s] %s - Won by %s (roll: %d)",
                date("%Y-%m-%d %H:%M", record.endTime),
                itemName,
                record.winner,
                record.winningRoll
            ))
        end

    elseif dataType == "stats" then
        table.insert(lines, "=== PLAYER STATISTICS ===")
        table.insert(lines, "")
        table.insert(lines, string.format("%-20s %6s %6s %8s %8s",
            "Player", "Wins", "Losses", "Win%", "AvgRoll"))
        table.insert(lines, string.rep("-", 52))

        local stats = LT.DB:GetAllPlayerStats()
        for _, stat in ipairs(stats) do
            table.insert(lines, string.format("%-20s %6d %6d %7.1f%% %8.1f",
                stat.name,
                stat.wins,
                stat.losses,
                stat.winRate,
                stat.avgRoll
            ))
        end

    elseif dataType == "attendance" then
        table.insert(lines, "=== RAID ATTENDANCE ===")
        table.insert(lines, "")

        local raids = LT.DB:GetAttendanceHistory()
        for _, raid in ipairs(raids) do
            table.insert(lines, string.format("%s - %s (%d players)",
                raid.date, raid.name, #raid.attendees))
            table.insert(lines, "  " .. table.concat(raid.attendees, ", "))
            table.insert(lines, "")
        end
    end

    return table.concat(lines, "\n")
end

-- Discord format (with emoji and formatting)
function Export:GenerateDiscord(dataType)
    local lines = {}

    if dataType == "loot" then
        table.insert(lines, "**__Loot History__**")
        table.insert(lines, "```")

        local history = LT.DB:GetRollHistory()
        for i, record in ipairs(history) do
            if i > 25 then
                table.insert(lines, "... and " .. (#history - 25) .. " more entries")
                break
            end
            local itemName = LT.Events:GetItemName(record.item) or record.item
            table.insert(lines, string.format("%s: %s won %s (%d)",
                date("%m/%d", record.endTime),
                record.winner,
                itemName,
                record.winningRoll
            ))
        end
        table.insert(lines, "```")

    elseif dataType == "stats" then
        table.insert(lines, "**__Player Statistics__**")
        table.insert(lines, "```")
        table.insert(lines, string.format("%-15s %5s %5s %7s %6s",
            "Player", "Wins", "Loss", "Win%", "Avg"))

        local stats = LT.DB:GetAllPlayerStats()
        for i, stat in ipairs(stats) do
            if i > 20 then break end
            table.insert(lines, string.format("%-15s %5d %5d %6.1f%% %6.1f",
                stat.name:sub(1, 15),
                stat.wins,
                stat.losses,
                stat.winRate,
                stat.avgRoll
            ))
        end
        table.insert(lines, "```")

    elseif dataType == "attendance" then
        table.insert(lines, "**__Recent Raids__**")

        local raids = LT.DB:GetAttendanceHistory()
        for i, raid in ipairs(raids) do
            if i > 5 then break end
            table.insert(lines, string.format("**%s** - %s", raid.date, raid.name))
            table.insert(lines, string.format("> %d attendees", #raid.attendees))
        end
    end

    return table.concat(lines, "\n")
end

--[[
    PUBLIC API
]]

function Export:Show()
    if not frame then
        self:Create()
    end
    frame:Show()
    self:UpdateExport()
end

function Export:Hide()
    if frame then
        frame:Hide()
    end
end

function Export:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
