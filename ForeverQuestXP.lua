local addonName = ...
local title = "Quest XP Forecast"
local questFillAtlas = "UI-HUD-ExperienceBar-Fill-ArtifactPower"
local xpBarMaskAtlas = "UI-HUD-ExperienceBar-Fill-Experience"
local overlaysByBar = {}
local readyXP, inProgressXP = 0, 0
local questRefreshQueued
local questFillAtlasInfo
local defaultFillColor = "FFDBA540"
local setupControlInitializers
local welcomePopup

local function ScanQuestXP()
    local readyTotal, inProgressTotal = 0, 0
    local trackedOnly = ForeverQuestXPDB.trackedOnly
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local entry = C_QuestLog.GetInfo(index)
        if entry and not entry.isHeader and not entry.isHidden and entry.questID > 0 then
            local questID = entry.questID
            if not trackedOnly or C_QuestLog.GetQuestWatchType(questID) ~= nil then
                local reward = GetQuestLogRewardXP(questID)
                if type(reward) == "number" and (not issecretvalue or not issecretvalue(reward)) and reward > 0 then
                    if C_QuestLog.ReadyForTurnIn(questID) then
                        readyTotal = readyTotal + reward
                    else
                        inProgressTotal = inProgressTotal + reward
                    end
                end
            end
        end
    end
    readyXP, inProgressXP = readyTotal, inProgressTotal
end

local function SetQuestFillSegment(texture, bar, width, height, startFraction, endFraction)
    if endFraction <= startFraction then
        texture:Hide()
        return
    end

    -- Sample the portion of Blizzard's fill that corresponds to this XP range.
    local left, right = questFillAtlasInfo.leftTexCoord, questFillAtlasInfo.rightTexCoord
    texture:SetTexCoord(left + (right - left) * startFraction, left + (right - left) * endFraction,
        questFillAtlasInfo.topTexCoord, questFillAtlasInfo.bottomTexCoord)
    texture:SetPoint("TOPLEFT", bar, "TOPLEFT", width * startFraction, 0)
    texture:SetSize(width * (endFraction - startFraction), height)
    texture:Show()
end

local function UpdateQuestFillOverlay(bar)
    local overlay = overlaysByBar[bar]
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
    SetQuestFillSegment(overlay.ready, bar, width, height, current, ready)
    SetQuestFillSegment(overlay.inProgress, bar, width, height, ready, total)
end

local function CreateQuestFillTexture(bar, mask)
    local texture = bar:CreateTexture(nil, "ARTWORK", nil, -1)
    texture:SetTexture(questFillAtlasInfo.file or questFillAtlasInfo.filename)
    texture:AddMaskTexture(mask)
    texture:Hide()
    return texture
end

local function ApplyFillAppearance(texture, colorKey, opacityKey, brightness)
    local color = ForeverQuestXPDB[colorKey]
    local r, g, b = brightness, brightness, brightness
    local customColor = color ~= defaultFillColor
    if customColor then
        r, g, b = CreateColorFromHexString(color):GetRGB()
    end
    texture:SetDesaturated(customColor)
    texture:SetVertexColor(r, g, b, ForeverQuestXPDB[opacityKey])
end

local function ApplyOverlayAppearance(overlay)
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

local function RefreshOverlayAppearance()
    for _, overlay in pairs(overlaysByBar) do
        ApplyOverlayAppearance(overlay)
    end
end

local function GetXPToNextLevel(tracker)
    local maximum = UnitXPMax("player")
    if not maximum or maximum <= 0
        or (IsXPUserDisabled and IsXPUserDisabled())
        or (tracker.IsCapped and tracker:IsCapped()) then
        return nil
    end
    return math.max(0, maximum - UnitXP("player"))
end

local function GetFormattedRestedXP()
    local restedXP = GetXPExhaustion()
    if restedXP and restedXP > 0 then
        return BreakUpLargeNumbers(restedXP)
    end
end

local function UpdateXPBarText(tracker)
    local remaining = GetXPToNextLevel(tracker)
    if not remaining then return end

    local text = ("%s  -  %s XP to level  -  %s quest XP"):format(
        XP_STATUS_BAR_TEXT:format(UnitXP("player"), UnitXPMax("player")),
        BreakUpLargeNumbers(remaining), BreakUpLargeNumbers(readyXP + inProgressXP))
    local restedXP = GetFormattedRestedXP()
    if restedXP then
        text = text .. "  -  " .. restedXP .. " rested XP"
    end
    tracker:SetBarText(text)
end

local function AppendQuestXPDetails(tracker)
    local tooltip = GetAppropriateTooltip()
    local remaining = GetXPToNextLevel(tracker)
    if not remaining or not tooltip:IsShown() then return end

    local total = readyXP + inProgressXP
    local totalLabel = ForeverQuestXPDB.trackedOnly and "Tracked quest XP" or "Total quest XP"
    local restedXP = GetFormattedRestedXP()
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

local function HookXPBarTextAndTooltip(tracker)
    hooksecurefunc(tracker, "UpdateCurrentText", UpdateXPBarText)

    local tick = tracker.ExhaustionTick
    if tick and tick.ExhaustionToolTipText then
        -- Blizzard uses this method for both the bar and the rested XP marker.
        hooksecurefunc(tick, "ExhaustionToolTipText", function()
            AppendQuestXPDetails(tracker)
        end)
    end
end

local function AttachToXPBars()
    local manager = StatusTrackingBarManager
    if not manager or not manager.barContainers then return end

    questFillAtlasInfo = questFillAtlasInfo or C_Texture.GetAtlasInfo(questFillAtlas)
    if not questFillAtlasInfo or not (questFillAtlasInfo.file or questFillAtlasInfo.filename) then return end

    for _, container in ipairs(manager.barContainers) do
        for _, tracker in pairs(container.bars or {}) do
            local bar = tracker.isExpBar and tracker.StatusBar
            if bar and not overlaysByBar[bar] then
                local mask = bar:CreateMaskTexture()
                mask:SetAtlas(xpBarMaskAtlas)
                mask:SetAllPoints(bar)
                overlaysByBar[bar] = {
                    tracker = tracker,
                    ready = CreateQuestFillTexture(bar, mask),
                    inProgress = CreateQuestFillTexture(bar, mask),
                }
                bar:HookScript("OnSizeChanged", UpdateQuestFillOverlay)
                bar:HookScript("OnShow", UpdateQuestFillOverlay)
                HookXPBarTextAndTooltip(tracker)
                ApplyOverlayAppearance(overlaysByBar[bar])
            end
        end
    end
end

local function RefreshXPBars()
    for bar, overlay in pairs(overlaysByBar) do
        UpdateQuestFillOverlay(bar)
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
    if questRefreshQueued then return end
    questRefreshQueued = true
    C_Timer.After(0, function()
        questRefreshQueued = false
        AttachToXPBars()
        ScanQuestXP()
        RefreshXPBars()
    end)
end

local function RegisterAppearanceSlider(category, key, label, default, minimum, maximum, step, tooltip, formatValue)
    local setting = Settings.RegisterAddOnSetting(category, addonName .. "_" .. key, key,
        ForeverQuestXPDB, Settings.VarType.Number, label, default)
    setting:SetValueChangedCallback(RefreshOverlayAppearance)
    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatValue)
    return Settings.CreateSlider(category, setting, options, tooltip)
end

local function RegisterFillSettings(category, key, label, opacity)
    local colorKey = key .. "Color"
    local setting = Settings.RegisterAddOnSetting(category, addonName .. "_" .. colorKey, colorKey,
        ForeverQuestXPDB, Settings.VarType.String, label .. " color", defaultFillColor)
    setting:SetValueChangedCallback(RefreshOverlayAppearance)
    local color = Settings.CreateColorSwatch(category, setting, "Choose the color of this quest XP fill.")
    local alpha = RegisterAppearanceSlider(category, key .. "Opacity", label .. " opacity", opacity, 0, 1, 0.05,
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
    local fontSize = RegisterAppearanceSlider(category, "fontSize", "XP bar font size", 12, 8, 24, 1,
        "Change the size of the text shown on the XP bar.", function(value) return tostring(value) end)
    setupControlInitializers = { trackedOnly, readyColor, readyOpacity, inProgressColor, inProgressOpacity, fontSize }
    Settings.RegisterAddOnCategory(category)
end

local function ShowPendingSetupPopup()
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

    for index, initializer in ipairs(setupControlInitializers) do
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
    ShowPendingSetupPopup()
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
            C_Timer.After(0, ShowPendingSetupPopup)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        ShowPendingSetupPopup()
    elseif event == "PLAYER_XP_UPDATE" or event == "UPDATE_EXHAUSTION" then
        RefreshXPBars()
    elseif ForeverQuestXPDB then
        QueueQuestRefresh()
    end
end)
