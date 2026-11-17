local addonName = ...
local title = "Quest XP Forecast"
local previewAtlas = "UI-HUD-ExperienceBar-Fill-ArtifactPower"
local shapeAtlas = "UI-HUD-ExperienceBar-Fill-Experience"
local overlays = {}
local readyXP, inProgressXP = 0, 0
local refreshQueued
local atlasInfo
local defaultColor = "FFDBA540"
local settingsControls
local welcomePopup

local function ScanQuestXP()
    local ready, inProgress = 0, 0
    local trackedOnly = ForeverQuestXPDB.trackedOnly
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local entry = C_QuestLog.GetInfo(index)
        if entry and not entry.isHeader and not entry.isHidden and entry.questID > 0 then
            local questID = entry.questID
            if not trackedOnly or C_QuestLog.GetQuestWatchType(questID) ~= nil then
                local reward = GetQuestLogRewardXP(questID)
                if type(reward) == "number" and (not issecretvalue or not issecretvalue(reward)) and reward > 0 then
                    if C_QuestLog.ReadyForTurnIn(questID) then
                        ready = ready + reward
                    else
                        inProgress = inProgress + reward
                    end
                end
            end
        end
    end
    readyXP, inProgressXP = ready, inProgress
end

local function SetSegment(texture, bar, width, height, from, to)
    if to <= from then
        texture:Hide()
        return
    end

    -- Sample the portion of Blizzard's fill that corresponds to this XP range.
    local left, right = atlasInfo.leftTexCoord, atlasInfo.rightTexCoord
    texture:SetTexCoord(left + (right - left) * from, left + (right - left) * to,
        atlasInfo.topTexCoord, atlasInfo.bottomTexCoord)
    texture:SetPoint("TOPLEFT", bar, "TOPLEFT", width * from, 0)
    texture:SetSize(width * (to - from), height)
    texture:Show()
end

local function UpdateOverlay(bar)
    local overlay = overlays[bar]
    local maximum = UnitXPMax("player")
    local width, height = bar:GetSize()
    if not maximum or maximum <= 0 or width <= 0 or height <= 0
        or (IsXPUserDisabled and IsXPUserDisabled()) then
        overlay.ready:Hide()
        overlay.inProgress:Hide()
        return
    end

    local current = math.min(1, UnitXP("player") / maximum)
    local ready = math.min(1, current + readyXP / maximum)
    local total = math.min(1, ready + inProgressXP / maximum)
    SetSegment(overlay.ready, bar, width, height, current, ready)
    SetSegment(overlay.inProgress, bar, width, height, ready, total)
end

local function CreateSegment(bar, mask)
    local texture = bar:CreateTexture(nil, "ARTWORK", nil, -1)
    texture:SetTexture(atlasInfo.file or atlasInfo.filename)
    texture:AddMaskTexture(mask)
    texture:Hide()
    return texture
end

local function ApplyFillAppearance(texture, colorKey, opacityKey, brightness)
    local color = ForeverQuestXPDB[colorKey]
    local r, g, b = brightness, brightness, brightness
    local customColor = color ~= defaultColor
    if customColor then
        r, g, b = CreateColorFromHexString(color):GetRGB()
    end
    texture:SetDesaturated(customColor)
    texture:SetVertexColor(r, g, b, ForeverQuestXPDB[opacityKey])
end

local function ApplyAppearance(overlay)
    ApplyFillAppearance(overlay.ready, "readyColor", "readyOpacity", 0.8)
    ApplyFillAppearance(overlay.inProgress, "inProgressColor", "inProgressOpacity", 0.55)

    local frame = overlay.tracker.OverlayFrame
    local text = frame and frame.Text
    if text then
        local font, size, flags = text:GetFont()
        local desiredSize = ForeverQuestXPDB.fontSize
        if font and size ~= desiredSize then
            text:SetFont(font, desiredSize, flags)
        end
    end
end

local function RefreshAppearance()
    for _, overlay in pairs(overlays) do
        ApplyAppearance(overlay)
    end
end

local function GetXPRemaining(tracker)
    local maximum = UnitXPMax("player")
    if not maximum or maximum <= 0
        or (IsXPUserDisabled and IsXPUserDisabled())
        or (tracker.IsCapped and tracker:IsCapped()) then
        return nil
    end
    return math.max(0, maximum - UnitXP("player"))
end

local function GetRestedXPText()
    local restedXP = GetXPExhaustion()
    if restedXP and restedXP > 0 then
        return BreakUpLargeNumbers(restedXP)
    end
end

local function UpdateXPText(tracker)
    local remaining = GetXPRemaining(tracker)
    if not remaining then return end

    local text = ("%s  -  %s XP to level  -  %s quest XP"):format(
        XP_STATUS_BAR_TEXT:format(UnitXP("player"), UnitXPMax("player")),
        BreakUpLargeNumbers(remaining), BreakUpLargeNumbers(readyXP + inProgressXP))
    local restedXP = GetRestedXPText()
    if restedXP then
        text = text .. "  -  " .. restedXP .. " rested XP"
    end
    tracker:SetBarText(text)
end

local function AppendQuestTooltip(tracker)
    local tooltip = GetAppropriateTooltip()
    local remaining = GetXPRemaining(tracker)
    if not remaining or not tooltip:IsShown() then return end

    local total = readyXP + inProgressXP
    local totalLabel = ForeverQuestXPDB.trackedOnly and "Tracked quest XP" or "Total quest XP"
    local restedXP = GetRestedXPText()
    if restedXP then
        tooltip:AddDoubleLine("Rested XP", restedXP .. " XP", 1, 0.82, 0, 1, 1, 1)
    end
    tooltip:AddDoubleLine("Ready to turn in", BreakUpLargeNumbers(readyXP) .. " XP", 1, 0.82, 0, 1, 1, 1)
    tooltip:AddDoubleLine("In progress", BreakUpLargeNumbers(inProgressXP) .. " XP", 1, 0.82, 0, 1, 1, 1)
    tooltip:AddDoubleLine(totalLabel, BreakUpLargeNumbers(total) .. " XP", 1, 0.82, 0, 1, 1, 1)
    tooltip:AddDoubleLine("XP remaining after quests",
        BreakUpLargeNumbers(math.max(0, remaining - total)) .. " XP", 1, 0.82, 0, 1, 1, 1)
    tooltip:Show()
end

local function HookXPDetails(tracker)
    hooksecurefunc(tracker, "UpdateCurrentText", UpdateXPText)

    local tick = tracker.ExhaustionTick
    if tick and tick.ExhaustionToolTipText then
        -- Blizzard uses this method for both the bar and the rested XP marker.
        hooksecurefunc(tick, "ExhaustionToolTipText", function()
            AppendQuestTooltip(tracker)
        end)
    end
end

local function AttachToXPBars()
    local manager = StatusTrackingBarManager
    if not manager or not manager.barContainers then return end

    atlasInfo = atlasInfo or C_Texture.GetAtlasInfo(previewAtlas)
    if not atlasInfo or not (atlasInfo.file or atlasInfo.filename) then return end

    for _, container in ipairs(manager.barContainers) do
        for _, tracker in pairs(container.bars or {}) do
            local bar = tracker.isExpBar and tracker.StatusBar
            if bar and not overlays[bar] then
                local mask = bar:CreateMaskTexture()
                mask:SetAtlas(shapeAtlas)
                mask:SetAllPoints(bar)
                overlays[bar] = {
                    tracker = tracker,
                    ready = CreateSegment(bar, mask),
                    inProgress = CreateSegment(bar, mask),
                }
                bar:HookScript("OnSizeChanged", UpdateOverlay)
                bar:HookScript("OnShow", UpdateOverlay)
                HookXPDetails(tracker)
                ApplyAppearance(overlays[bar])
            end
        end
    end
end

local function Refresh()
    for bar, overlay in pairs(overlays) do
        UpdateOverlay(bar)
        local tracker = overlay.tracker
        tracker:UpdateCurrentText()

        local tick = tracker.ExhaustionTick
        if tick and tick.ExhaustionToolTipText and GetAppropriateTooltip():IsShown()
            and (tracker:IsMouseMotionFocus() or tick:IsMouseMotionFocus()) then
            tick:ExhaustionToolTipText()
        end
    end
end

local function QueueQuestRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        AttachToXPBars()
        ScanQuestXP()
        Refresh()
    end)
end

local function RegisterSlider(category, key, label, default, minimum, maximum, step, tooltip, formatValue)
    local setting = Settings.RegisterAddOnSetting(category, addonName .. "_" .. key, key,
        ForeverQuestXPDB, Settings.VarType.Number, label, default)
    setting:SetValueChangedCallback(RefreshAppearance)
    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatValue)
    return Settings.CreateSlider(category, setting, options, tooltip)
end

local function RegisterFillSettings(category, key, label, opacity)
    local colorKey = key .. "Color"
    local setting = Settings.RegisterAddOnSetting(category, addonName .. "_" .. colorKey, colorKey,
        ForeverQuestXPDB, Settings.VarType.String, label .. " color", defaultColor)
    setting:SetValueChangedCallback(RefreshAppearance)
    local color = Settings.CreateColorSwatch(category, setting, "Choose the color of this quest XP fill.")
    local alpha = RegisterSlider(category, key .. "Opacity", label .. " opacity", opacity, 0, 1, 0.05,
        "Adjust how much of the default XP bar shows through this fill.",
        function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end)
    return color, alpha
end

local function RegisterSettings()
    if not ForeverQuestXPDB then
        ForeverQuestXPDB = { firstRunPending = true }
    end
    local category = Settings.RegisterVerticalLayoutCategory(title)
    local setting = Settings.RegisterAddOnSetting(category, "ForeverQuestXP_TrackedOnly", "trackedOnly",
        ForeverQuestXPDB, Settings.VarType.Boolean, "Tracked quests only", false)
    setting:SetValueChangedCallback(QueueQuestRefresh)
    local trackedOnly = Settings.CreateCheckbox(category, setting,
        "Only preview XP from quests tracked in the objective tracker.")
    local readyColor, readyOpacity = RegisterFillSettings(category, "ready", "Ready to turn in", 0.55)
    local inProgressColor, inProgressOpacity = RegisterFillSettings(category, "inProgress", "In progress", 0.40)
    local fontSize = RegisterSlider(category, "fontSize", "XP bar font size", 12, 8, 24, 1,
        "Change the size of the text shown on the XP bar.", function(value) return tostring(value) end)
    settingsControls = { trackedOnly, readyColor, readyOpacity, inProgressColor, inProgressOpacity, fontSize }
    Settings.RegisterAddOnCategory(category)
end

local function ShowFirstRunPopup()
    if not ForeverQuestXPDB or not ForeverQuestXPDB.firstRunPending or InCombatLockdown() then return end

    if welcomePopup then
        welcomePopup:Show()
        ForeverQuestXPDB.firstRunPending = nil
        return
    end

    local popup = CreateFrame("Frame", addonName .. "WelcomePopup", UIParent, "BasicFrameTemplateWithInset")
    welcomePopup = popup
    popup:SetSize(620, 360)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("HIGH")
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup.TitleText:SetText(title)
    tinsert(UISpecialFrames, popup:GetName())

    local titleBar = CreateFrame("Frame", nil, popup)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", -28, 0)
    titleBar:SetHeight(22)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() popup:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() popup:StopMovingOrSizing() end)
    popup:HookScript("OnHide", function() popup:StopMovingOrSizing() end)

    local description = popup:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    description:SetPoint("TOPLEFT", 24, -44)
    description:SetPoint("TOPRIGHT", -24, -44)
    description:SetJustifyH("LEFT")
    description:SetText("Customize how quest rewards appear on your XP bar. Changes apply immediately.\n"
        .. "Hover over your XP bar for the quest XP breakdown.")

    for index, initializer in ipairs(settingsControls) do
        local control = CreateFrame("Frame", nil, popup, initializer:GetTemplate())
        control:SetPoint("TOPLEFT", 12, -88 - (index - 1) * 34)
        control:SetPoint("TOPRIGHT", -12, -88 - (index - 1) * 34)
        -- The Options list normally supplies this accessor through its ScrollBox.
        control.GetElementData = function() return initializer end
        control:Init(initializer)
    end

    local done = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    done:SetSize(100, 24)
    done:SetPoint("BOTTOM", 0, 18)
    done:SetText("Done")
    done:SetScript("OnClick", function() popup:Hide() end)

    popup:Show()
    ForeverQuestXPDB.firstRunPending = nil
end

SLASH_QUESTXPFORECASTCONFIG1 = "/qxfconfig"
SlashCmdList.QUESTXPFORECASTCONFIG = function()
    if not ForeverQuestXPDB then return end
    ForeverQuestXPDB.firstRunPending = true
    ShowFirstRunPopup()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
events:RegisterEvent("UPDATE_EXHAUSTION")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            RegisterSettings()
            QueueQuestRefresh()
        elseif arg1 == "Blizzard_StatusTrackingBar" and ForeverQuestXPDB then
            QueueQuestRefresh()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        QueueQuestRefresh()
        if ForeverQuestXPDB and ForeverQuestXPDB.firstRunPending then
            C_Timer.After(0, ShowFirstRunPopup)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        ShowFirstRunPopup()
    elseif event == "PLAYER_XP_UPDATE" or event == "UPDATE_EXHAUSTION" then
        Refresh()
    elseif ForeverQuestXPDB then
        QueueQuestRefresh()
    end
end)
