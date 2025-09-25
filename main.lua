local NPCScan = CreateFrame("Frame")
NPCScan:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
NPCScan:RegisterEvent("ADDON_LOADED")
NPCScan:RegisterEvent("PLAYER_LOGIN")
NPCScan:RegisterEvent("PLAYER_TARGET_CHANGED")
NPCScan:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
NPCScan:RegisterEvent("NAME_PLATE_UNIT_ADDED")
NPCScan:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

-- Cache to prevent spam
local foundCache = {}
local scanCache = {}
local lastDynamicScan = 0

-- Settings defaults
local defaults = {
    soundEnabled = true,
    flashEnabled = true,
    printEnabled = true,
    autoTarget = true,
    autoMark = true,
    scanInterval = 0.5,
    dynamicScanRange = 100,
}

-- Alert Frame
local AlertFrame = CreateFrame("Frame", "NPCScanAlertFrame", UIParent)
AlertFrame:SetSize(400, 120)
AlertFrame:SetPoint("TOP", 0, -200)
AlertFrame:Hide()
AlertFrame:SetFrameStrata("HIGH")

AlertFrame.bg = AlertFrame:CreateTexture(nil, "BACKGROUND")
AlertFrame.bg:SetAllPoints()
AlertFrame.bg:SetTexture(0, 0, 0, 0.9)

AlertFrame.border = CreateFrame("Frame", nil, AlertFrame)
AlertFrame.border:SetPoint("TOPLEFT", -3, 3)
AlertFrame.border:SetPoint("BOTTOMRIGHT", 3, -3)
AlertFrame.border:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
})
AlertFrame.border:SetBackdropBorderColor(1, 0.84, 0, 1) -- Gold color for rare

AlertFrame.dragon = AlertFrame:CreateTexture(nil, "ARTWORK")
AlertFrame.dragon:SetSize(32, 32)
AlertFrame.dragon:SetPoint("LEFT", 15, 0)
AlertFrame.dragon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Rare")

AlertFrame.title = AlertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
AlertFrame.title:SetPoint("TOP", 0, -15)
AlertFrame.title:SetTextColor(1, 0.84, 0)
AlertFrame.title:SetText("RARE CREATURE FOUND!")

AlertFrame.text = AlertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
AlertFrame.text:SetPoint("CENTER", 0, -5)
AlertFrame.text:SetTextColor(1, 1, 1)

AlertFrame.subtext = AlertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
AlertFrame.subtext:SetPoint("BOTTOM", 0, 15)
AlertFrame.subtext:SetTextColor(0.7, 0.7, 0.7)

AlertFrame.closeBtn = CreateFrame("Button", nil, AlertFrame, "UIPanelCloseButton")
AlertFrame.closeBtn:SetPoint("TOPRIGHT", 2, 2)

-- Functions
function NPCScan:ADDON_LOADED(addon)
    if addon ~= "NPCScan" then return end
    
    NPCScanDB = NPCScanDB or {}
    for k, v in pairs(defaults) do
        if NPCScanDB[k] == nil then
            NPCScanDB[k] = v
        end
    end
    
    self:CreateOptionsPanel()
    self:SetupKeybinding()
    print("|cFFFFD700NPCScan:|r Addon loaded. Scanning for rare creatures...")
    print("|cFFFFD700NPCScan:|r Type /npcscan for options")
end

function NPCScan:PLAYER_LOGIN()
    -- Start continuous scanning
    self:StartScanning()
end

function NPCScan:StartScanning()
    self.scanTimer = self:CreateAnimationGroup()
    local anim = self.scanTimer:CreateAnimation()
    anim:SetDuration(NPCScanDB.scanInterval or 0.5)
    
    self.scanTimer:SetScript("OnFinished", function()
        NPCScan:ScanForRares()
        self.scanTimer:Play()
    end)
    
    self.scanTimer:Play()
end

function NPCScan:IsRare(unit)
    if not unit or not UnitExists(unit) then return false end
    if UnitIsPlayer(unit) or UnitIsDead(unit) then return false end
    
    -- Check classification (rare, rareelite, worldboss)
    local classification = UnitClassification(unit)
    if classification == "rare" or classification == "rareelite" or classification == "worldboss" then
        return true
end

function NPCScan:CheckUnit(unit)
    if not unit or not UnitExists(unit) then return end
    
    local guid = UnitGUID(unit)
    if not guid then return end
    
    -- Check cache
    if foundCache[guid] then return end
    
    -- Check if it's a rare
    if self:IsRare(unit) then
        local name = UnitName(unit)
        if name then
            foundCache[guid] = true
            self:RareFound(unit, name, guid)
            return true
        end
    end
    
    return false
end

function NPCScan:ScanForRares()
    -- Scan nameplates (most reliable for nearby rares)
    for i = 1, 40 do
        local unit = "nameplate"..i
        if UnitExists(unit) then
            self:CheckUnit(unit)
        end
    end
    
    -- Check mouseover
    if UnitExists("mouseover") then
        self:CheckUnit("mouseover")
    end
    
    -- Check target
    if UnitExists("target") then
        self:CheckUnit("target")
    end
    
    -- Check focus
    if UnitExists("focus") then
        self:CheckUnit("focus")
    end
    
    -- Check party/raid targets
    for i = 1, GetNumPartyMembers() do
        local unit = "party"..i.."target"
        if UnitExists(unit) then
            self:CheckUnit(unit)
        end
    end
    
    for i = 1, GetNumRaidMembers() do
        local unit = "raid"..i.."target"
        if UnitExists(unit) then
            self:CheckUnit(unit)
        end
    end
end

function NPCScan:DynamicTargetScan()
    -- This function cycles through nearby targets quickly
    local now = GetTime()
    if now - lastDynamicScan < 0.5 then return end
    lastDynamicScan = now
    
    -- Store current target
    local hadTarget = UnitExists("target")
    local currentTarget = hadTarget and UnitGUID("target") or nil
    
    -- Clear target and use tab targeting to cycle through nearby enemies
    ClearTarget()
    
    local scanned = 0
    local maxScans = 30 -- Limit to prevent hanging
    
    for i = 1, maxScans do
        TargetNearestEnemy()
        
        if UnitExists("target") then
            local guid = UnitGUID("target")
            
            -- Check if we've cycled back to start
            if scanCache[guid] then
                break
            end
            
            scanCache[guid] = true
            scanned = scanned + 1
            
            -- Check if it's a rare
            if self:CheckUnit("target") then
                -- Found a rare, keep it targeted
                return true
            end
        else
            break
        end
    end
    
    -- Restore original target
    ClearTarget()
    if currentTarget then
        for i = 1, maxScans do
            TargetNearestEnemy()
            if UnitExists("target") and UnitGUID("target") == currentTarget then
                break
            end
        end
    end
    
    -- Clear scan cache for next run
    wipe(scanCache)
    
    return false
end

function NPCScan:PLAYER_TARGET_CHANGED()
    self:CheckUnit("target")
end

function NPCScan:UPDATE_MOUSEOVER_UNIT()
    self:CheckUnit("mouseover")
end

function NPCScan:NAME_PLATE_UNIT_ADDED(unit)
    self:CheckUnit(unit)
end

function NPCScan:NAME_PLATE_UNIT_REMOVED(unit)
    -- Clean up cache for performance
    local guid = UnitGUID(unit)
    if guid and foundCache[guid] then
        -- Keep rare in cache for 5 minutes to prevent spam
        C_Timer.After(300, function()
            foundCache[guid] = nil
        end)
    end
end

function NPCScan:RareFound(unit, name, guid)
    -- Get creature info
    local level = UnitLevel(unit)
    local levelStr = level == -1 and "??" or tostring(level)
    local classification = UnitClassification(unit)
    local creatureType = UnitCreatureType(unit)
    
    -- Classification display
    local classStr = ""
    if classification == "rare" then
        classStr = "|cFF0080FFRare|r"
    elseif classification == "rareelite" then
        classStr = "|cFFFF8000Rare Elite|r"
    elseif classification == "worldboss" then
        classStr = "|cFFFF0000World Boss|r"
    elseif classification == "elite" then
        classStr = "|cFFFFD700Elite|r"
    end
    
    -- Zone info
    local zone = GetRealZoneText() or "Unknown"
    local subzone = GetSubZoneText() or ""
    
    -- Alert in chat
    if NPCScanDB.printEnabled then
        print(string.format("|cFFFFD700NPCScan:|r |cFF00FF00RARE FOUND!|r"))
        print(string.format("  |cFFFFFFFF%s|r - Level %s %s", name, levelStr, classStr))
        print(string.format("  Type: %s", creatureType or "Unknown"))
        print(string.format("  Location: %s%s", zone, subzone ~= "" and " - "..subzone or ""))
        
        if UnitExists(unit) then
            local health = UnitHealth(unit)
            local maxHealth = UnitHealthMax(unit)
            if maxHealth > 0 then
                local percent = (health/maxHealth)*100
                print(string.format("  Health: %d/%d (%.1f%%)", health, maxHealth, percent))
            end
        end
    end
    
    -- Sound Alert
    if NPCScanDB.soundEnabled then
        PlaySound("PVPWARNINGALLIANCE")
        PlaySound("RaidWarning")
        PlaySoundFile("Sound\\Creature\\Ragnaros\\RagnarosSpecialAttack01.wav")
    end
    
    -- Visual Alert
    if NPCScanDB.flashEnabled then
        self:ShowAlert(name, levelStr.." "..classStr, zone)
        UIFrameFlash(AlertFrame.border, 0.5, 0.5, 6, false, 0, 0)
        UIFrameFlash(AlertFrame.dragon, 0.5, 0.5, 6, false, 0.2, 0)
    end
    
    -- Auto-target
    if NPCScanDB.autoTarget and not UnitIsUnit("target", unit) then
        TargetUnit(unit)
    end
    
    -- Auto-mark with diamond
    if NPCScanDB.autoMark and UnitExists(unit) then
        SetRaidTarget(unit, 3) -- 3 = Diamond
    end
end

function NPCScan:ShowAlert(name, info, zone)
    AlertFrame.text:SetText(name)
    AlertFrame.subtext:SetText(string.format("%s - %s", info, zone))
    AlertFrame:Show()
    
    -- Auto-hide after 15 seconds
    C_Timer.After(15, function()
        if AlertFrame:IsShown() then
            UIFrameFadeOut(AlertFrame, 1, 1, 0)
            C_Timer.After(1, function()
                AlertFrame:Hide()
                AlertFrame:SetAlpha(1)
            end)
        end
    end)
end

-- Options Panel
function NPCScan:CreateOptionsPanel()
    local panel = CreateFrame("Frame", "NPCScanOptionsPanel", UIParent)
    panel.name = "NPCScan"
    InterfaceOptions_AddCategory(panel)
    
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("NPCScan - Dynamic Rare Scanner")
    
    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Automatically detects rare creatures by their silver dragon portrait")
    desc:SetTextColor(0.7, 0.7, 0.7)
    
    local y = -60
    
    -- Sound checkbox
    local soundCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    soundCheck:SetPoint("TOPLEFT", 16, y)
    soundCheck.text = soundCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    soundCheck.text:SetPoint("LEFT", soundCheck, "RIGHT", 5, 0)
    soundCheck.text:SetText("Enable Sound Alerts")
    soundCheck:SetChecked(NPCScanDB.soundEnabled)
    soundCheck:SetScript("OnClick", function(self)
        NPCScanDB.soundEnabled = self:GetChecked()
    end)
    
    y = y - 30
    
    -- Flash checkbox
    local flashCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    flashCheck:SetPoint("TOPLEFT", 16, y)
    flashCheck.text = flashCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    flashCheck.text:SetPoint("LEFT", flashCheck, "RIGHT", 5, 0)
    flashCheck.text:SetText("Enable Visual Alerts (Screen Flash)")
    flashCheck:SetChecked(NPCScanDB.flashEnabled)
    flashCheck:SetScript("OnClick", function(self)
        NPCScanDB.flashEnabled = self:GetChecked()
    end)
    
    y = y - 30
    
    -- Print checkbox
    local printCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    printCheck:SetPoint("TOPLEFT", 16, y)
    printCheck.text = printCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    printCheck.text:SetPoint("LEFT", printCheck, "RIGHT", 5, 0)
    printCheck.text:SetText("Enable Chat Messages")
    printCheck:SetChecked(NPCScanDB.printEnabled)
    printCheck:SetScript("OnClick", function(self)
        NPCScanDB.printEnabled = self:GetChecked()
    end)
    
    y = y - 30
    
    -- Auto-target checkbox
    local targetCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    targetCheck:SetPoint("TOPLEFT", 16, y)
    targetCheck.text = targetCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    targetCheck.text:SetPoint("LEFT", targetCheck, "RIGHT", 5, 0)
    targetCheck.text:SetText("Automatically Target Rare Creatures")
    targetCheck:SetChecked(NPCScanDB.autoTarget)
    targetCheck:SetScript("OnClick", function(self)
        NPCScanDB.autoTarget = self:GetChecked()
    end)
    
    y = y - 30
    
    -- Auto-mark checkbox
    local markCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    markCheck:SetPoint("TOPLEFT", 16, y)
    markCheck.text = markCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    markCheck.text:SetPoint("LEFT", markCheck, "RIGHT", 5, 0)
    markCheck.text:SetText("Automatically Mark with Diamond {rt3}")
    markCheck:SetChecked(NPCScanDB.autoMark)
    markCheck:SetScript("OnClick", function(self)
        NPCScanDB.autoMark = self:GetChecked()
    end)
    
    y = y - 40
    
    -- Test button
    local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testBtn:SetPoint("TOPLEFT", 16, y)
    testBtn:SetSize(120, 25)
    testBtn:SetText("Test Alert")
    testBtn:SetScript("OnClick", function()
        NPCScan:ShowAlert("Time-Lost Proto-Drake", "Level ?? |cFFFF8000Rare Elite|r", "The Storm Peaks")
        if NPCScanDB.soundEnabled then
            PlaySound("PVPWARNINGALLIANCE")
            PlaySound("RaidWarning")
        end
        print("|cFFFFD700NPCScan:|r Test alert triggered")
    end)
    
    -- Reset cache button
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetPoint("LEFT", testBtn, "RIGHT", 10, 0)
    resetBtn:SetSize(120, 25)
    resetBtn:SetText("Reset Cache")
    resetBtn:SetScript("OnClick", function()
        wipe(foundCache)
        wipe(scanCache)
        print("|cFFFFD700NPCScan:|r Cache cleared. Will re-alert for previously found rares.")
    end)
    
    y = y - 35
    
    -- Keybinding info
    local keybindTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    keybindTitle:SetPoint("TOPLEFT", 16, y)
    keybindTitle:SetText("Dynamic Targeting Scan")
    
    y = y - 20
    
    local keybindDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    keybindDesc:SetPoint("TOPLEFT", 16, y)
    keybindDesc:SetText("Set a keybind in: ESC > Key Bindings > NPCScan > Dynamic Target Scan")
    keybindDesc:SetTextColor(0.7, 0.7, 0.7)
    
    y = y - 15
    
    local keybindDesc2 = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    keybindDesc2:SetPoint("TOPLEFT", 16, y)
    keybindDesc2:SetText("This will rapidly cycle through nearby targets to find rares.")
    keybindDesc2:SetTextColor(0.7, 0.7, 0.7)
end

-- Setup keybinding
function NPCScan:SetupKeybinding()
    -- Create a button for keybinding
    local btn = CreateFrame("Button", "NPCScanDynamicScanButton", UIParent, "SecureActionButtonTemplate")
    btn:RegisterForClicks("AnyDown")
    btn:Hide()
    
    -- Set up the keybinding in the bindings
    _G["BINDING_HEADER_NPCSCAN"] = "NPCScan"
    _G["BINDING_NAME_CLICK NPCScanDynamicScanButton:LeftButton"] = "Dynamic Target Scan"
    
    btn:SetScript("OnClick", function()
        NPCScan:DynamicTargetScan()
    end)
end

-- Slash Commands
SLASH_NPCSCAN1 = "/npcscan"
SlashCmdList["NPCSCAN"] = function(msg)
    local cmd = msg:lower()
    
    if cmd == "test" then
        NPCScan:ShowAlert("Test Rare Creature", "Level 80 |cFF0080FFRare|r", GetRealZoneText() or "Unknown")
        if NPCScanDB.soundEnabled then
            PlaySound("PVPWARNINGALLIANCE")
            PlaySound("RaidWarning")
        end
        print("|cFFFFD700NPCScan:|r Test alert triggered")
    elseif cmd == "reset" then
        wipe(foundCache)
        wipe(scanCache)
        print("|cFFFFD700NPCScan:|r Cache cleared. Will re-alert for previously found rares.")
    elseif cmd == "scan" then
        if NPCScan:DynamicTargetScan() then
            print("|cFFFFD700NPCScan:|r Rare found during dynamic scan!")
        else
            print("|cFFFFD700NPCScan:|r No rares found in immediate vicinity.")
        end
    elseif cmd == "status" then
        print("|cFFFFD700NPCScan Status:|r")
        print("  Sound Alerts: " .. (NPCScanDB.soundEnabled and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
        print("  Visual Alerts: " .. (NPCScanDB.flashEnabled and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
        print("  Chat Messages: " .. (NPCScanDB.printEnabled and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
        print("  Auto-Target: " .. (NPCScanDB.autoTarget and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
        print("  Auto-Mark: " .. (NPCScanDB.autoMark and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
    else
        InterfaceOptionsFrame_OpenToCategory("NPCScan")
        print("|cFFFFD700NPCScan Commands:|r")
        print("  /npcscan - Open options panel")
        print("  /npcscan test - Test the alert system")
        print("  /npcscan reset - Clear the found cache")
        print("  /npcscan scan - Manually trigger dynamic scan")
        print("  /npcscan status - Show current settings")
    end
end

-- Minimap Button
local MinimapButton = CreateFrame("Button", "NPCScanMinimapButton", Minimap)
MinimapButton:SetSize(32, 32)
MinimapButton:SetFrameStrata("MEDIUM")
MinimapButton:SetFrameLevel(8)
MinimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = MinimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 0, 0)
icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Rare")

MinimapButton.border = MinimapButton:CreateTexture(nil, "OVERLAY")
MinimapButton.border:SetSize(52, 52)
MinimapButton.border:SetPoint("CENTER", 0, 0)
MinimapButton.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

MinimapButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        if IsShiftKeyDown() then
            NPCScan:DynamicTargetScan()
        else
            InterfaceOptionsFrame_OpenToCategory("NPCScan")
        end
    elseif button == "RightButton" then
        SlashCmdList["NPCSCAN"]("status")
    end
end)

MinimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("|cFFFFD700NPCScan|r")
    GameTooltip:AddLine("Dynamic Rare Scanner", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: Open options", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift + Left-click: Dynamic scan", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: Show status", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

MinimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Position minimap button
local function UpdateMinimapButtonPosition()
    local angle = math.rad(135) -- Default position
    local x = math.cos(angle) * 80
    local y = math.sin(angle) * 80
    MinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

UpdateMinimapButtonPosition()

-- Initial message
print("|cFFFFD700NPCScan|r loaded - Dynamically scanning for rare creatures")
print("|cFFFFD700NPCScan|r Use /npcscan for options or click the minimap button")
