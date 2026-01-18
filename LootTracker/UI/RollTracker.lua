--[[
    LootTracker - Roll Tracker UI
    Shows active roll session with real-time roll updates
]]

local _, LT = ...
LT.RollTracker = {}

local RollTracker = LT.RollTracker

-- Frame reference
local frame = nil

-- Create the roll tracker frame
function RollTracker:Create()
    if frame then return frame end

    -- Main frame (starts small, is resizable)
    frame = CreateFrame("Frame", "LootTrackerRollFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(250, 300)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(200, 200, 500, 600)
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

    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -3)
    frame.title:SetText("Roll Tracker")

    -- Item display
    frame.itemFrame = CreateFrame("Frame", nil, frame)
    frame.itemFrame:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 8, -8)
    frame.itemFrame:SetPoint("TOPRIGHT", frame.Inset, "TOPRIGHT", -8, -8)
    frame.itemFrame:SetHeight(40)

    frame.itemText = frame.itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.itemText:SetPoint("LEFT", 5, 0)
    frame.itemText:SetPoint("RIGHT", -5, 0)
    frame.itemText:SetJustifyH("CENTER")
    frame.itemText:SetText("No active session")

    -- Status text
    frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.statusText:SetPoint("TOPLEFT", frame.itemFrame, "BOTTOMLEFT", 0, -5)
    frame.statusText:SetTextColor(0.7, 0.7, 0.7)
    frame.statusText:SetText("Status: Waiting")

    -- Roll list scroll frame
    frame.scrollFrame = CreateFrame("ScrollFrame", "LootTrackerRollScrollFrame", frame, "UIPanelScrollFrameTemplate")
    frame.scrollFrame:SetPoint("TOPLEFT", frame.statusText, "BOTTOMLEFT", 0, -10)
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -28, 50)

    frame.scrollChild = CreateFrame("Frame", nil, frame.scrollFrame)
    frame.scrollChild:SetSize(frame.scrollFrame:GetWidth(), 1)
    frame.scrollFrame:SetScrollChild(frame.scrollChild)

    -- Roll entry template
    frame.rollEntries = {}

    -- Buttons
    frame.endButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.endButton:SetSize(80, 22)
    frame.endButton:SetPoint("BOTTOMLEFT", frame.Inset, "BOTTOMLEFT", 10, 10)
    frame.endButton:SetText("End Roll")
    frame.endButton:SetScript("OnClick", function()
        LT:EndRollSession()
    end)

    frame.rerollButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.rerollButton:SetSize(80, 22)
    frame.rerollButton:SetPoint("LEFT", frame.endButton, "RIGHT", 10, 0)
    frame.rerollButton:SetText("Reroll")
    frame.rerollButton:SetScript("OnClick", function()
        LT:InitiateReroll()
    end)

    frame.cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.cancelButton:SetSize(80, 22)
    frame.cancelButton:SetPoint("LEFT", frame.rerollButton, "RIGHT", 10, 0)
    frame.cancelButton:SetText("Cancel")
    frame.cancelButton:SetScript("OnClick", function()
        LT:CancelRollSession()
    end)

    -- Update timer for auto-refresh
    frame.elapsed = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= 0.5 then
            RollTracker:Update()
            self.elapsed = 0
        end
    end)

    return frame
end

-- Create a roll entry row (clickable to remove joke rolls)
function RollTracker:CreateRollEntry(parent, index)
    local entry = CreateFrame("Button", nil, parent)
    entry:SetHeight(20)
    entry:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * 22)
    entry:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(index - 1) * 22)

    -- Background (alternating colors)
    entry.bg = entry:CreateTexture(nil, "BACKGROUND")
    entry.bg:SetAllPoints()
    entry.baseColor = (index % 2 == 0) and {0.1, 0.1, 0.1, 0.5} or {0.15, 0.15, 0.15, 0.5}
    entry.bg:SetColorTexture(unpack(entry.baseColor))

    -- Highlight on hover
    entry:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.3, 0.1, 0.1, 0.7)  -- Red tint on hover
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Click to remove (joke roll)", 1, 0.5, 0.5)
        GameTooltip:AddLine("Right-click for options", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    entry:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(unpack(self.baseColor))
        GameTooltip:Hide()
    end)

    -- Left-click to remove
    entry:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    entry:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and self.rollData then
            local success = LT.DB:RemoveRoll(self.rollData.player, self.rollData.round, self.rollData.timestamp)
            if success then
                print(string.format("|cffff9900LootTracker:|r Removed roll from %s (%d)",
                    self.rollData.player, self.rollData.value))
                RollTracker:UpdateRollList()
            end
        end
    end)

    -- Player name
    entry.playerText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    entry.playerText:SetPoint("LEFT", 5, 0)
    entry.playerText:SetWidth(100)
    entry.playerText:SetJustifyH("LEFT")

    -- Roll value
    entry.rollText = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    entry.rollText:SetPoint("LEFT", entry.playerText, "RIGHT", 5, 0)
    entry.rollText:SetWidth(35)
    entry.rollText:SetJustifyH("CENTER")

    -- Round indicator
    entry.roundText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    entry.roundText:SetPoint("LEFT", entry.rollText, "RIGHT", 5, 0)
    entry.roundText:SetTextColor(0.5, 0.5, 0.5)

    -- Remove icon (X)
    entry.removeIcon = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    entry.removeIcon:SetPoint("RIGHT", -5, 0)
    entry.removeIcon:SetText("×")
    entry.removeIcon:SetTextColor(0.6, 0.3, 0.3)

    return entry
end

-- Update the roll list display
function RollTracker:UpdateRollList()
    local session = LT.DB:GetActiveSession()
    if not session then return end

    -- Sort rolls by value descending, then by round
    local sortedRolls = {}
    for _, roll in ipairs(session.rolls) do
        table.insert(sortedRolls, roll)
    end

    table.sort(sortedRolls, function(a, b)
        if a.round ~= b.round then
            return a.round > b.round  -- Most recent round first
        end
        return a.value > b.value  -- Highest roll first
    end)

    -- Get highest value in current round for highlighting
    local highestValue = 0
    local currentRound = session.rerollRound
    for _, roll in ipairs(sortedRolls) do
        if roll.round == currentRound and roll.value > highestValue then
            highestValue = roll.value
        end
    end

    -- Update or create entries
    for i, roll in ipairs(sortedRolls) do
        local entry = frame.rollEntries[i]
        if not entry then
            entry = self:CreateRollEntry(frame.scrollChild, i)
            frame.rollEntries[i] = entry
        end

        -- Store roll data for removal
        entry.rollData = roll

        entry.playerText:SetText(roll.player)
        entry.rollText:SetText(tostring(roll.value))

        if roll.round > 0 then
            entry.roundText:SetText("(R" .. roll.round .. ")")
        else
            entry.roundText:SetText("")
        end

        -- Highlight highest roller(s) in current round
        if roll.round == currentRound and roll.value == highestValue then
            entry.playerText:SetTextColor(0, 1, 0)  -- Green
            entry.rollText:SetTextColor(0, 1, 0)
        else
            entry.playerText:SetTextColor(1, 1, 1)
            entry.rollText:SetTextColor(1, 0.8, 0)
        end

        entry:Show()
    end

    -- Hide unused entries
    for i = #sortedRolls + 1, #frame.rollEntries do
        frame.rollEntries[i]:Hide()
    end

    -- Update scroll child height
    frame.scrollChild:SetHeight(math.max(1, #sortedRolls * 22))
end

-- Update the entire UI
function RollTracker:Update()
    if not frame or not frame:IsShown() then return end

    local session = LT.DB:GetActiveSession()
    if not session then
        frame.itemText:SetText("No active session")
        frame.statusText:SetText("Status: Inactive")
        frame.endButton:Disable()
        frame.rerollButton:Disable()
        return
    end

    -- Update item display
    local itemName = LT.Events:GetItemName(session.item) or session.item
    frame.itemText:SetText(itemName)

    -- Update status
    local statusText = "Status: "
    if session.state == "open" then
        statusText = statusText .. "Waiting for rolls"
    elseif session.state == "rerolling" then
        statusText = statusText .. "Reroll Round " .. session.rerollRound
    else
        statusText = statusText .. session.state
    end
    statusText = statusText .. " | Rolls: " .. #session.rolls
    frame.statusText:SetText(statusText)

    -- Update button states
    frame.endButton:Enable()

    local winners = LT.DB:GetHighestRollers()
    if winners and #winners > 1 then
        frame.rerollButton:Enable()
    else
        frame.rerollButton:Disable()
    end

    -- Update roll list
    self:UpdateRollList()
end

-- Show the roll tracker
function RollTracker:Show()
    if not frame then
        self:Create()
    end
    frame:Show()
    self:Update()
end

-- Hide the roll tracker
function RollTracker:Hide()
    if frame then
        frame:Hide()
    end
end

-- Toggle visibility
function RollTracker:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Called when a reroll completes with a winner
function RollTracker:OnRerollComplete(winner)
    if not frame then return end

    frame.statusText:SetText("Winner: " .. winner.player .. " (" .. winner.value .. ")")
    frame.statusText:SetTextColor(0, 1, 0)

    -- Flash the winner entry briefly
    self:Update()
end

-- Called when a tie is detected during reroll
function RollTracker:OnTieDetected(winners)
    if not frame then return end

    local names = {}
    for _, roll in ipairs(winners) do
        table.insert(names, roll.player)
    end

    frame.statusText:SetText("TIE: " .. table.concat(names, ", "))
    frame.statusText:SetTextColor(1, 0.5, 0)

    self:Update()
end
