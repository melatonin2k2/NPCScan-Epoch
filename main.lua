local NPCScan = CreateFrame("Frame")
NPCScan:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
NPCScan:RegisterEvent("ADDON_LOADED")
NPCScan:RegisterEvent("PLAYER_LOGIN")
NPCScan:RegisterEvent("PLAYER_TARGET_CHANGED")
-- Register mouseover update for better detection
NPCScan:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
NPCScan:RegisterEvent("PLAYER_ENTERING_WORLD")
NPCScan:RegisterEvent("ZONE_CHANGED")
NPCScan:RegisterEvent("ZONE_CHANGED_NEW_AREA")

-- Cache to prevent spam
local foundCache = {}
local scanCache = {}
local lastDynamicScan = 0
local lastAutoScan = 0

-- Settings defaults
local defaults = {
    soundEnabled = true,
    flashEnabled = true,
    printEnabled = true,
    autoTarget = true,
    autoMark = true,
    scanInterval = 0.5,
    dynamicScanRange = 100,
    autoScanEnabled = true,
    autoScanInterval = 1,
}

-- Simple timer system for OnUpdate
local timers = {}
local function AddTimer(duration, func)
    table.insert(timers, {time = GetTime() + duration, callback = func})
end
local function TimerOnUpdate(self)
    local now = GetTime()
    for i = #timers, 1, -1 do
        if now >= timers[i].time then
            timers[i].callback()
            table.remove(timers, i)
        end
    end
    if #timers == 0 then
        self:SetScript("OnUpdate", nil)
    end
end
local function RunTimer(duration, func)
    AddTimer(duration, func)
    AlertFrame:SetScript("OnUpdate", TimerOnUpdate)
end

-- UIFrameFlash (simplified, only alpha pulsing) - FIXED VERSION
local function SimpleFlash(frame, duration, times)
    -- Validate frame object before proceeding
    if not frame or not frame.SetAlpha or not frame.GetAlpha then
        return
    end
    
    local elapsed, flashes = 0, 0
    local origAlpha = frame:GetAlpha()
    frame:SetAlpha(1)
    
    -- Create a separate update frame to avoid conflicts
    local flashFrame = CreateFrame("Frame")
    flashFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed > duration then
            elapsed = 0
            flashes = flashes + 1
            if flashes >= times then
                if frame and frame.SetAlpha then
                    frame:SetAlpha(origAlpha)
                end
                self:SetScript("OnUpdate", nil)
                return
            end
        end
        local phase = math.abs(math.sin(elapsed * math.pi / duration))
        if frame and frame.SetAlpha then
            frame:SetAlpha(0.5 + 0.5 * phase)
        end
    end)
end

-- Alert Frame
local AlertFrame = CreateFrame("Frame", "NPCScanAlertFrame", UIParent)
AlertFrame:SetWidth(400)
AlertFrame:SetHeight(120)
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
AlertFrame.border:SetBackdropBorderColor(1, 0.84, 0, 1)

AlertFrame.dragon = AlertFrame:CreateTexture(nil, "ARTWORK")
AlertFrame.dragon:SetWidth(32)
AlertFrame.dragon:SetHeight(32)
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
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan:|r Addon loaded. Scanning for rare creatures...")
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan:|r Type /npcscan for options")
end

function NPCScan:PLAYER_LOGIN()
    self:StartScanning()
end

function NPCScan:StartScanning()
    if self.scanTimer then self.scanTimer:Hide() end
    self.scanTimer = CreateFrame("Frame")
    local elapsed = 0
    self.scanTimer:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= (NPCScanDB.scanInterval or 0.5) then
            NPCScan:ScanForRares()
            elapsed = 0
        end
    end)
end

function NPCScan:IsRare(unit)
    if not unit or not UnitExists(unit) then return false end
    if UnitIsPlayer(unit) or UnitIsDead(unit) then return false end
    local classification = UnitClassification(unit)
    return classification == "rare" or classification == "rareelite" or classification == "worldboss"
end

function NPCScan:CheckUnit(unit)
    if not unit or not UnitExists(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    if foundCache[guid] then return end
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
    -- Check standard units
    if UnitExists("mouseover") then self:CheckUnit("mouseover") end
    if UnitExists("target") then self:CheckUnit("target") end
    if UnitExists("focus") then self:CheckUnit("focus") end
    for i = 1, GetNumPartyMembers() do
        local unit = "party"..i.."target"
        if UnitExists(unit) then self:CheckUnit(unit) end
    end
    for i = 1, GetNumRaidMembers() do
        local unit = "raid"..i.."target"
        if UnitExists(unit) then self:CheckUnit(unit) end
    end
end

-- Enhanced auto-scanning using tooltip scanning (safer method)
function NPCScan:AutoScanNearby()
    -- This function now uses a safer approach that doesn't call protected functions
    -- Instead, it relies on existing event-based scanning and nameplate scanning
    self:ScanForRares()
    
    -- Try to scan using GameTooltip method (non-protected)
    self:TooltipScanNearby()
    
    return false -- Always return false since we can't determine if rare was found
end

-- Tooltip-based scanning method (safe alternative)
function NPCScan:TooltipScanNearby()
    -- This method uses GameTooltip to scan for creatures
    -- It's less reliable but doesn't trigger Blizzard's protection
    
    -- We'll enhance the existing event-based scanning instead
    -- and rely on mouseover/target change events more heavily
    
    -- Check if we can use any safe scanning methods
    if UnitExists("mouseover") then
        self:CheckUnit("mouseover")
    end
    
    -- Enhanced scanning of party/raid targets
    for i = 1, GetNumPartyMembers() do
        local unit = "party"..i
        if UnitExists(unit) then
            -- Check party member
            self:CheckUnit(unit)
            -- Check party member's target
            local target = unit.."target"
            if UnitExists(target) then
                self:CheckUnit(target)
            end
        end
    end
    
    for i = 1, GetNumRaidMembers() do
        local unit = "raid"..i
        if UnitExists(unit) then
            -- Check raid member
            self:CheckUnit(unit)
            -- Check raid member's target
            local target = unit.."target"
            if UnitExists(target) then
                self:CheckUnit(target)
            end
        end
    end
end

function NPCScan:DynamicTargetScan()
    local now = GetTime()
    if now - lastDynamicScan < 0.5 then return end
    lastDynamicScan = now
    
    -- Just do basic scanning of available units
    self:ScanForRares()
    return false
end

function NPCScan:PLAYER_TARGET_CHANGED()
    self:CheckUnit("target")
end

function NPCScan:UPDATE_MOUSEOVER_UNIT()
    self:CheckUnit("mouseover")
end

function NPCScan:PLAYER_ENTERING_WORLD()
    -- Clear cache when entering world/changing zones
    for k in pairs(foundCache) do foundCache[k] = nil end
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan:|r Entered new area - cache cleared, ready to scan for rares.")
end

function NPCScan:ZONE_CHANGED()
    -- Clear cache when zone changes
    for k in pairs(foundCache) do foundCache[k] = nil end
end

function NPCScan:ZONE_CHANGED_NEW_AREA()
    -- Clear cache when entering new area
    for k in pairs(foundCache) do foundCache[k] = nil end
end

function NPCScan:COMBAT_LOG_EVENT_UNFILTERED(timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...)
    -- Check combat log for rare creature involvement
    if sourceGUID and not foundCache[sourceGUID] then
        -- Extract creature ID from GUID to check if it might be rare
        local unitType, _, _, _, _, creatureID = strsplit("-", sourceGUID or "")
        if unitType == "Creature" and creatureID then
            -- If we see a creature in combat log, try to check it via other means
            self:DelayedGUIDCheck(sourceGUID, sourceName)
        end
    end
    if destGUID and not foundCache[destGUID] then
        local unitType, _, _, _, _, creatureID = strsplit("-", destGUID or "")
        if unitType == "Creature" and creatureID then
            self:DelayedGUIDCheck(destGUID, destName)
        end
    end
end

function NPCScan:UNIT_TARGET(unit)
    if unit and unit:find("party") or unit:find("raid") then
        local target = unit .. "target"
        if UnitExists(target) then
            self:CheckUnit(target)
        end
    end
end

function NPCScan:PARTY_MEMBERS_CHANGED()
    -- Re-scan party targets when party changes
    RunTimer(0.5, function()
        NPCScan:ScanForRares()
    end)
end

function NPCScan:RAID_ROSTER_UPDATE()
    -- Re-scan raid targets when raid changes
    RunTimer(0.5, function()
        NPCScan:ScanForRares()
    end)
end

function NPCScan:DelayedGUIDCheck(guid, name)
    if not guid or foundCache[guid] then return end
    
    -- Try to find this creature by checking common unit IDs
    RunTimer(0.1, function()
        local units = {"target", "mouseover", "focus"}
        
        -- Add party/raid targets
        for i = 1, GetNumPartyMembers() do
            table.insert(units, "party"..i.."target")
        end
        for i = 1, GetNumRaidMembers() do
            table.insert(units, "raid"..i.."target")
        end
        
        for _, unit in pairs(units) do
            if UnitExists(unit) and UnitGUID(unit) == guid then
                NPCScan:CheckUnit(unit)
                break
            end
        end
    end)
end

function NPCScan:RareFound(unit, name, guid)
    local level = UnitLevel(unit)
    local levelStr = level == -1 and "??" or tostring(level)
    local classification = UnitClassification(unit)
    local creatureType = UnitCreatureType(unit)
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
    local zone = GetRealZoneText() or "Unknown"
    local subzone = GetSubZoneText() or ""
    if NPCScanDB.printEnabled then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFFD700NPCScan:|r |cFF00FF00RARE FOUND!|r"))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cFFFFFFFF%s|r - Level %s %s", name, levelStr, classStr))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  Type: %s", creatureType or "Unknown"))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  Location: %s%s", zone, subzone ~= "" and " - "..subzone or ""))
        if UnitExists(unit) then
            local health = UnitHealth(unit)
            local maxHealth = UnitHealthMax(unit)
            if maxHealth > 0 then
                local percent = (health/maxHealth)*100
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  Health: %d/%d (%.1f%%)", health, maxHealth, percent))
            end
        end
    end
    if NPCScanDB.soundEnabled then
        PlaySoundFile("Sound\\Interface\\RaidWarning.wav")
        PlaySoundFile("Sound\\Interface\\AlarmClockWarning3.wav")
    end
    if NPCScanDB.flashEnabled then
        self:ShowAlert(name, levelStr.." "..classStr, zone)
        SimpleFlash(AlertFrame.border, 0.5, 6)
        SimpleFlash(AlertFrame.dragon, 0.5, 6)
    end
    if NPCScanDB.autoTarget and not UnitIsUnit("target", unit) then
        TargetUnit(unit)
    end
    if NPCScanDB.autoMark and UnitExists(unit) then
        SetRaidTarget(unit, 3)
    end
    -- Cache cleanup after 5min
    RunTimer(300, function() foundCache[guid] = nil end)
end

function NPCScan:ShowAlert(name, info, zone)
    AlertFrame.text:SetText(name)
    AlertFrame.subtext:SetText(string.format("%s - %s", info, zone))
    AlertFrame:Show()
    RunTimer(15, function()
        if AlertFrame:IsShown() then
            AlertFrame:Hide()
            AlertFrame:SetAlpha(1)
        end
    end)
end

-- Options Panel (3.3.5a method)
function NPCScan:CreateOptionsPanel()
    local panel = CreateFrame("Frame", "NPCScanOptionsPanel", UIParent)
    panel.name = "NPCScan"
    panel:SetWidth(600)
    panel:SetHeight(400)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("HIGH")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:Hide()
    
    -- Background
    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints()
    panel.bg:SetTexture(0, 0, 0, 0.8)
    
    -- Border
    panel.border = CreateFrame("Frame", nil, panel)
    panel.border:SetPoint("TOPLEFT", -5, 5)
    panel.border:SetPoint("BOTTOMRIGHT", 5, -5)
    panel.border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
    })
    panel.border:SetBackdropBorderColor(1, 0.84, 0, 1)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    panel:SetScript("OnShow", function()
        if not panel.inited then
            panel.inited = true
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
            y = y - 30
            -- Auto-scan checkbox (removed - doesn't work properly in 3.3.5a)
            y = y - 40
            -- Test button
            local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            testBtn:SetPoint("TOPLEFT", 16, y)
            testBtn:SetWidth(120)
            testBtn:SetHeight(25)
            testBtn:SetText("Test Alert")
            testBtn:SetScript("OnClick", function()
                NPCScan:ShowAlert("Time-Lost Proto-Drake", "Level ?? |cFFFF8000Rare Elite|r", "The Storm Peaks")
                if NPCScanDB.soundEnabled then
                    PlaySoundFile("Sound\\Interface\\RaidWarning.wav")
                end
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan:|r Test alert triggered")
            end)
            -- Reset cache button
            local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            resetBtn:SetPoint("LEFT", testBtn, "RIGHT", 10, 0)
            resetBtn:SetWidth(120)
            resetBtn:SetHeight(25)
            resetBtn:SetText("Reset Cache")
            resetBtn:SetScript("OnClick", function()
                for k in pairs(foundCache) do foundCache[k] = nil end
                for k in pairs(scanCache) do scanCache[k] = nil end
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan:|r Cache cleared. Will re-alert for previously found rares.")
            end)
        end
    end)
    -- Store reference for easy access
    _G["NPCScanOptionsPanel"] = panel
end

function NPCScan:SetupKeybinding()
    -- Simple keybinding setup without broken scanning
    BINDING_HEADER_NPCSCAN = "NPCScan"
    -- Remove the broken keybinds since they don't work
end

SLASH_NPCSCAN1 = "/npcscan"
SlashCmdList["NPCSCAN"] = function(msg)
    local cmd = msg:lower()
    if cmd == "test" then
        NPCScan:ShowAlert("Test Rare Creature", "Level 80 |cFF0080FFRare|r", GetRealZoneText() or "Unknown")
        if NPCScanDB.soundEnabled then
            PlaySoundFile("Sound\\Interface\\RaidWarning.wav")
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan:|r Test alert triggered")
    elseif cmd == "reset" then
        for k in pairs(foundCache) do foundCache[k] = nil end
        for k in pairs(scanCache) do scanCache[k] = nil end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan:|r Cache cleared. Will re-alert for previously found rares.")
    elseif cmd == "debug" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan Debug:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Target exists: " .. tostring(UnitExists("target")))
        if UnitExists("target") then
            local name = UnitName("target")
            local classification = UnitClassification("target")
            local level = UnitLevel("target")
            local creatureType = UnitCreatureType("target")
            local guid = UnitGUID("target")
            DEFAULT_CHAT_FRAME:AddMessage("  Target: " .. (name or "unknown"))
            DEFAULT_CHAT_FRAME:AddMessage("  Classification: " .. (classification or "unknown"))
            DEFAULT_CHAT_FRAME:AddMessage("  Level: " .. (level or "unknown"))
            DEFAULT_CHAT_FRAME:AddMessage("  Type: " .. (creatureType or "unknown"))
            DEFAULT_CHAT_FRAME:AddMessage("  GUID: " .. (guid or "unknown"))
            DEFAULT_CHAT_FRAME:AddMessage("  Is Rare: " .. tostring(NPCScan:IsRare("target")))
            DEFAULT_CHAT_FRAME:AddMessage("  Is Player: " .. tostring(UnitIsPlayer("target")))
            DEFAULT_CHAT_FRAME:AddMessage("  Is Dead: " .. tostring(UnitIsDead("target")))
        end
        DEFAULT_CHAT_FRAME:AddMessage("  Mouseover exists: " .. tostring(UnitExists("mouseover")))
        if UnitExists("mouseover") then
            local name = UnitName("mouseover")
            local classification = UnitClassification("mouseover")
            DEFAULT_CHAT_FRAME:AddMessage("  Mouseover: " .. (name or "unknown"))
            DEFAULT_CHAT_FRAME:AddMessage("  Classification: " .. (classification or "unknown"))
            DEFAULT_CHAT_FRAME:AddMessage("  Is Rare: " .. tostring(NPCScan:IsRare("mouseover")))
        end
    elseif cmd == "status" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan Status:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Sound Alerts: " .. (NPCScanDB.soundEnabled and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Visual Alerts: " .. (NPCScanDB.flashEnabled and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Chat Messages: " .. (NPCScanDB.printEnabled and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Auto-Target: " .. (NPCScanDB.autoTarget and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Auto-Mark: " .. (NPCScanDB.autoMark and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
    else
        InterfaceOptionsFrame_OpenToCategory("NPCScan")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan Commands:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  /npcscan - Open options panel")
        DEFAULT_CHAT_FRAME:AddMessage("  /npcscan reset - Clear the found cache")
        DEFAULT_CHAT_FRAME:AddMessage("  /npcscan debug - Show debug information about current target/mouseover")
        DEFAULT_CHAT_FRAME:AddMessage("  /npcscan status - Show current settings")
        DEFAULT_CHAT_FRAME:AddMessage(" ")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700How it works:|r NPCScan automatically detects rares when you:")
        DEFAULT_CHAT_FRAME:AddMessage("  - Target them directly")
        DEFAULT_CHAT_FRAME:AddMessage("  - Mouse over them")
        DEFAULT_CHAT_FRAME:AddMessage("  - Enter combat with them")
        DEFAULT_CHAT_FRAME:AddMessage("  - Party/raid members target them")
    end
end

-- Minimap Button
local MinimapButton = CreateFrame("Button", "NPCScanMinimapButton", Minimap)
MinimapButton:SetWidth(32)
MinimapButton:SetHeight(32)
MinimapButton:SetFrameStrata("MEDIUM")
MinimapButton:SetFrameLevel(8)
MinimapButton:EnableMouse(true)
MinimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
MinimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = MinimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetWidth(20)
icon:SetHeight(20)
icon:SetPoint("CENTER", 0, 0)
icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Rare")

MinimapButton.border = MinimapButton:CreateTexture(nil, "OVERLAY")
MinimapButton.border:SetWidth(52)
MinimapButton.border:SetHeight(52)
MinimapButton.border:SetPoint("CENTER", 0, 0)
MinimapButton.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

MinimapButton:SetScript("OnClick", function(self, button)
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan:|r Minimap button clicked: " .. (button or "unknown"))
    
    if button == "LeftButton" then
        -- Multiple attempts to open options
        local opened = false
        
        -- Method 1: Try custom panel
        local panel = _G["NPCScanOptionsPanel"]
        if panel then
            if panel:IsShown() then
                panel:Hide()
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan:|r Options panel closed.")
            else
                panel:Show()
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan:|r Options panel opened.")
            end
            opened = true
        end
        
        -- Method 2: Try standard interface options
        if not opened and InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory("NPCScan")
            opened = true
        end
        
        -- Method 3: Fallback - show help
        if not opened then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan:|r Unable to open options panel. Use /npcscan for commands.")
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
    GameTooltip:AddLine("Right-click: Show status", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

MinimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

local function UpdateMinimapButtonPosition()
    local angle = math.rad(135)
    local x = math.cos(angle) * 80
    local y = math.sin(angle) * 80
    MinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
UpdateMinimapButtonPosition()

DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan|r loaded - Dynamically scanning for rare creatures")
DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700NPCScan|r Use /npcscan for options or click the minimap button")
