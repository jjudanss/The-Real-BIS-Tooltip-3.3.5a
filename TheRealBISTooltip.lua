-- The Real BIS-Tooltip 3.3.5a
-- Version 1.0.0
-- BiS source: uploaded workbook "BiS_List_by_Kama_Corrected-v2.xlsx".
-- Item IDs are in TheRealBISTooltip_ItemIDs.lua and are queried independently of bags.

local ADDON_FOLDER = "TheRealBISTooltip"
local ADDON_TITLE = "The Real BIS-Tooltip 3.3.5a"
local CLASS_ORDER = { "Shaman", "Rogue", "Hunter", "Priest", "Warlock", "Warrior", "Mage", "DeathKnight", "Paladin", "Druid" }
local CLASS_TOKEN_TO_NAME = {
    SHAMAN = "Shaman", ROGUE = "Rogue", HUNTER = "Hunter", PRIEST = "Priest",
    WARLOCK = "Warlock", WARRIOR = "Warrior", MAGE = "Mage",
    DEATHKNIGHT = "DeathKnight", PALADIN = "Paladin", DRUID = "Druid",
}

local BIS_INDEX = {}
local playerClassName
local playerClassToken
local activeTalentTree
local activeTalentTreeIndex
local activeTalentTreeStatus = "Talent data unavailable"
local autoClassSelection = true
local autoSpecSelection = true
local onlyMyClass = false
local browserFrame
local selectedClass
local selectedSpec
local classDropdown
local specDropdown
local scrollContent
local scrollFrame
local browserRows = {}
local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local itemQueryQueue = {}
local itemQueryQueued = {}
local itemQueryCursor = 1
local itemQueryFrame
local itemQueryTooltip
local itemQueryElapsed = 0
local ITEM_QUERY_INTERVAL = 0.35
local catalogItemIDs = {}
local catalogSuccessIDs = {}
local catalogFailureIDs = {}
local catalogInFlightIDs = {}
local catalogRequestTimes = {}
local catalogQueueInitialized = false
local itemQueryAttempts = 0
local ITEM_QUERY_TIMEOUT = 20
local candidateCount = 0
local mappedCandidateCount = 0
local workbookItemIDs = {}
local catalogStatusText
local retryButton
local minimapButton
local pendingDressUpItemID
local pendingDressUpItemName

local function Trim(text)
    if not text then return "" end
    return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Normalize(text)
    text = Trim(text or "")
    text = text:gsub("\r", " "):gsub("\n", " ")
    text = text:gsub("’", "'")
    text = text:lower()
    text = text:gsub("%s+", " ")
    return text
end

local function CanonicalKey(itemName)
    local key = Normalize(itemName)
    if TRBIS_ItemAliases and TRBIS_ItemAliases[key] then
        key = TRBIS_ItemAliases[key]
    end
    return key
end

local function AddIndexEntry(itemName, className, specName, slotName)
    local key = CanonicalKey(itemName)
    if key == "" or key == "-" then return end
    BIS_INDEX[key] = BIS_INDEX[key] or {}
    local entries = BIS_INDEX[key]
    local identity = className .. "|" .. specName .. "|" .. slotName
    for _, existing in ipairs(entries) do
        if existing.identity == identity then return end
    end
    table.insert(entries, {
        className = className,
        specName = specName,
        slotName = slotName,
        identity = identity,
    })
end

-- Split workbook alternatives into distinct names. A slash in a name is not expected
-- in this source; plus signs and line breaks indicate separate choices.
local function IndexCandidates(cellText, className, specName, slotName)
    if not cellText then return end
    cellText = tostring(cellText):gsub("\r", "")
    for line in string.gmatch(cellText .. "\n", "(.-)\n") do
        for slashPart in string.gmatch(line .. "/", "(.-)/") do
            slashPart = Trim(slashPart)
            if slashPart ~= "" and slashPart ~= "-" then
                for plusPart in string.gmatch(slashPart .. "+", "(.-)%+") do
                    local candidate = Trim(plusPart)
                    if candidate ~= "" and candidate ~= "-" then
                        AddIndexEntry(candidate, className, specName, slotName)
                        local base = Trim(candidate:gsub("%s*%b()%s*$", ""))
                        if base ~= candidate then AddIndexEntry(base, className, specName, slotName) end
                    end
                end
            end
        end
    end
end

local function GetDisplayCandidates(cellText)
    local candidates = {}
    cellText = tostring(cellText or ""):gsub("\r", "")
    for line in string.gmatch(cellText .. "\n", "(.-)\n") do
        for slashPart in string.gmatch(line .. "/", "(.-)/") do
            slashPart = Trim(slashPart)
            if slashPart ~= "" and slashPart ~= "-" then
                for plusPart in string.gmatch(slashPart .. "+", "(.-)%+") do
                    local displayName = Trim(plusPart)
                    if displayName ~= "" and displayName ~= "-" then
                        local lookupName = Trim(displayName:gsub("%s*%b()%s*$", ""))
                        if lookupName == "" then lookupName = displayName end
                        table.insert(candidates, { display = displayName, lookup = lookupName })
                    end
                end
            end
        end
    end
    if #candidates == 0 then
        candidates[1] = { display = tostring(cellText or ""), lookup = tostring(cellText or "") }
    end
    return candidates
end

-- Expands the workbook's source shorthand through TheRealBISTooltip_GlyphIDs.lua.
local function GetGlyphCandidates(cellText)
    local candidates = {}
    local seen = {}
    local source = tostring(cellText or "")
    -- Commas separate the workbook's normal glyph slots. Slashes and the word
    -- "or" represent alternatives within a slot, which are shown individually.
    for slotText in string.gmatch(source .. ",", "(.-),") do
        slotText = Trim(slotText)
        slotText = slotText:gsub("%s+[Oo][Rr]%s+", "/")
        local optionIndex = 0
        for optionText in string.gmatch(slotText .. "/", "(.-)/") do
            local raw = Trim(optionText)
            if raw ~= "" and raw ~= "-" then
                optionIndex = optionIndex + 1
                local note = string.match(raw, "%((.-)%)%s*$")
                if not note and optionIndex > 1 then note = "alternative" end
                local token = Trim(raw:gsub("%s*%b()%s*$", ""))
                token = token:gsub("^%(%s*[Ll]esser%s*%)%s*", "Lesser ")
                local key = Normalize(token)
                local record = TRBIS_GlyphMap and TRBIS_GlyphMap[key]
                if record then
                    local identity = tostring(record.itemID)
                    if not seen[identity] then
                        seen[identity] = true
                        table.insert(candidates, {
                            display = record.name,
                            lookup = record.name,
                            itemID = record.itemID,
                            note = note,
                        })
                    end
                elseif key ~= "" then
                    -- Preserve source wording and clearly expose any unmapped glyph.
                    local display = "Glyph of " .. token
                    table.insert(candidates, { display = display, lookup = display, itemID = nil, note = note })
                end
            end
        end
    end
    return candidates
end

local function BuildIndex()
    BIS_INDEX = {}
    if type(TRBIS_Data) ~= "table" then return end
    candidateCount = 0
    mappedCandidateCount = 0
    workbookItemIDs = {}
    local uniqueCandidates = {}
    for className, specs in pairs(TRBIS_Data) do
        for specName, rows in pairs(specs) do
            for _, row in ipairs(rows) do
                if row.slot ~= "Glyphs" then
                    IndexCandidates(row.item, className, specName, row.slot)
                    for _, candidate in ipairs(GetDisplayCandidates(row.item)) do
                        local key = CanonicalKey(candidate.lookup)
                        if key ~= "" then uniqueCandidates[key] = true end
                    end
                else
                    for _, glyph in ipairs(GetGlyphCandidates(row.item)) do
                        if glyph.itemID then workbookItemIDs[glyph.itemID] = true end
                    end
                end
            end
        end
    end
    for key in pairs(uniqueCandidates) do
        candidateCount = candidateCount + 1
        local itemID = TRBIS_ItemIDs and tonumber(TRBIS_ItemIDs[key])
        if itemID then
            mappedCandidateCount = mappedCandidateCount + 1
            workbookItemIDs[itemID] = true
        end
    end
end

local function PrintMessage(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[The Real BIS-Tooltip]|r " .. tostring(message))
    end
end

local function GetPlayerClassName()
    if not UnitClass then return nil, nil end
    local localizedName, classToken = UnitClass("player")
    return CLASS_TOKEN_TO_NAME[classToken], classToken
end

local function GetSpecsForClass(className)
    local result = {}
    local specs = TRBIS_Data and TRBIS_Data[className]
    if specs then
        if TRBIS_SpecOrder and TRBIS_SpecOrder[className] then
            for _, specName in ipairs(TRBIS_SpecOrder[className]) do
                if specs[specName] then table.insert(result, specName) end
            end
        else
            for specName in pairs(specs) do table.insert(result, specName) end
            table.sort(result)
        end
    end
    return result
end

-- Talent-tab order is fixed by each class in Wrath 3.3.5a. Using the tab
-- index avoids failures on non-English clients where tree names are localized.
-- Workbook profiles are more specific than talent trees, so dropdown variants
-- remain available even when one profile can be suggested automatically.
local TREE_INDEX_PROFILE = {
    Shaman = { [1] = "ELEMENTAL HASTE", [2] = "ENHANCEMENT SINGLE TARGET", [3] = "RESTORATION" },
    Rogue = { [1] = "ASSASSINATION", [2] = "COMBAT 2P" },
    Hunter = { [2] = "MARKSMANSHIP" },
    Priest = { [1] = "DISCIPLINE", [2] = "HOLY (Hybrid Healing)", [3] = "SHADOW (Single Target)" },
    Warlock = { [1] = "AFFLICTION", [2] = "DEMONOLOGY", [3] = "DESTRUCTION" },
    Warrior = { [2] = "FURY", [3] = "PROTECTION" },
    Mage = { [1] = "ARCANE", [2] = "TORMENT OF THE WEAK" },
    DeathKnight = { [1] = "BLOOD", [2] = "FROST ARP", [3] = "UNHOLY" },
    Paladin = { [1] = "HOLY", [2] = "PROT", [3] = "RET AGILITY" },
    Druid = { [1] = "BALANCE", [2] = "STR CAT", [3] = "RESTORATION" },
}

local function DetectTalentTree()
    activeTalentTree = nil
    activeTalentTreeIndex = nil
    activeTalentTreeStatus = "Talent tree unavailable"
    if not GetTalentTabInfo then return nil end

    local group = 1
    if GetActiveTalentGroup then
        local active = GetActiveTalentGroup()
        if active and active > 0 then group = active end
    end

    local tabCount = 3
    if GetNumTalentTabs then
        local count = GetNumTalentTabs(false, false)
        if count and count > 0 then tabCount = count end
    end

    local bestPoints = 0
    local bestTab, bestName
    local tied = false
    for tab = 1, tabCount do
        -- In Wrath: name, texture, pointsSpent, background, ...
        local treeName, _, pointsSpent = GetTalentTabInfo(tab, false, false, group)
        pointsSpent = tonumber(pointsSpent) or 0
        if pointsSpent > bestPoints then
            bestPoints = pointsSpent
            bestTab = tab
            bestName = treeName
            tied = false
        elseif pointsSpent > 0 and pointsSpent == bestPoints then
            tied = true
        end
    end

    if bestPoints <= 0 then
        activeTalentTreeStatus = "No talent points spent"
        return nil
    end
    if tied then
        activeTalentTreeStatus = "Talent trees tied; select a build manually"
        return nil
    end

    activeTalentTree = bestName
    activeTalentTreeIndex = bestTab
    activeTalentTreeStatus = tostring(bestName or ("Talent tree " .. tostring(bestTab))) .. " (" .. tostring(bestPoints) .. " points)"
    return activeTalentTree
end

local function GetRecommendedSpec(className)
    if not className then return nil, "Player class unavailable" end
    local specs = GetSpecsForClass(className)
    local classProfiles = TREE_INDEX_PROFILE[className]
    local preferred = classProfiles and activeTalentTreeIndex and classProfiles[activeTalentTreeIndex]
    if preferred and TRBIS_Data[className] and TRBIS_Data[className][preferred] then
        return preferred, "matched to active talent tree"
    end
    if #specs == 1 then
        return specs[1], "only workbook build available for this class"
    end
    return nil, "no exact workbook build for this talent tree"
end

local function CompletePendingDressUp(itemID)
    if not itemID or pendingDressUpItemID ~= itemID then return end
    local itemName, itemLink
    if GetItemInfo then itemName, itemLink = GetItemInfo(itemID) end
    local displayName = pendingDressUpItemName or itemName or ("Item " .. tostring(itemID))
    pendingDressUpItemID = nil
    pendingDressUpItemName = nil
    if not itemLink then
        itemLink = "|Hitem:" .. tostring(itemID) .. "|h[" .. tostring(displayName) .. "]|h"
    end
    if DressUpItemLink then
        DressUpItemLink(itemLink)
    else
        PrintMessage("This client does not expose DressUpItemLink; the item could not be previewed.")
    end
end

local function MarkCatalogLoaded(itemID)
    itemID = tonumber(itemID)
    if not itemID then return end
    catalogSuccessIDs[itemID] = true
    catalogFailureIDs[itemID] = nil
    catalogInFlightIDs[itemID] = nil
    catalogRequestTimes[itemID] = nil
    itemQueryQueued[itemID] = nil
    CompletePendingDressUp(itemID)
end

local function GetCatalogStats()
    local loaded, pending, failed, total = 0, 0, 0, 0
    for itemID in pairs(workbookItemIDs) do
        total = total + 1
        -- The client may have received this item from another addon or game UI.
        -- Count it as loaded without sending another request.
        if not catalogSuccessIDs[itemID] and GetItemInfo and GetItemInfo(itemID) then
            MarkCatalogLoaded(itemID)
        end
        if catalogSuccessIDs[itemID] then
            loaded = loaded + 1
        elseif catalogFailureIDs[itemID] then
            failed = failed + 1
        else
            pending = pending + 1
        end
    end
    return loaded, pending, failed, total
end

local function UpdatePlayerStatus()
    -- Character/viewing labels are intentionally omitted from the browser UI.
    -- Keep the background item-catalog progress and retry status visible.
    if catalogStatusText then
        local loaded, pending, failed, total = GetCatalogStats()
        catalogStatusText:SetText("Gear/glyphs: " .. tostring(loaded) .. "/" .. tostring(total) .. " loaded | " .. tostring(pending) .. " pending | " .. tostring(failed) .. " failed")
        if retryButton then
            if failed > 0 then retryButton:Enable() else retryButton:Disable() end
        end
    end
end

local function UpdatePlayerProfile(updateSelection)
    playerClassName, playerClassToken = GetPlayerClassName()
    activeTalentTree = DetectTalentTree()
    local suggested, suggestionReason = GetRecommendedSpec(playerClassName)

    if updateSelection and playerClassName then
        selectedClass = playerClassName
        selectedSpec = suggested or (GetSpecsForClass(selectedClass)[1])
        autoClassSelection = true
        autoSpecSelection = true
        if classDropdown then
            UIDropDownMenu_SetSelectedValue(classDropdown, selectedClass)
            UIDropDownMenu_SetText(classDropdown, selectedClass)
        end
        if specDropdown then UpdateSpecDropdown(selectedSpec) end
    elseif not selectedClass and playerClassName then
        selectedClass = playerClassName
        selectedSpec = suggested or (GetSpecsForClass(selectedClass)[1])
        if specDropdown then UpdateSpecDropdown(selectedSpec) end
    elseif autoClassSelection and playerClassName and selectedClass ~= playerClassName then
        selectedClass = playerClassName
        selectedSpec = suggested or (GetSpecsForClass(selectedClass)[1])
        if classDropdown then
            UIDropDownMenu_SetSelectedValue(classDropdown, selectedClass)
            UIDropDownMenu_SetText(classDropdown, selectedClass)
        end
        if specDropdown then UpdateSpecDropdown(selectedSpec) end
    elseif autoSpecSelection and selectedClass == playerClassName then
        local autoBuild = suggested or (GetSpecsForClass(selectedClass)[1])
        if autoBuild and selectedSpec ~= autoBuild then
            selectedSpec = autoBuild
            if specDropdown then UpdateSpecDropdown(selectedSpec) end
        end
    end

    UpdatePlayerStatus()
    return suggested, suggestionReason
end

local function QueueItemID(itemID, retryFailed)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return false end
    catalogItemIDs[itemID] = true
    if catalogSuccessIDs[itemID] then return false end
    if GetItemInfo and GetItemInfo(itemID) then
        MarkCatalogLoaded(itemID)
        return false
    end
    if itemQueryQueued[itemID] or catalogInFlightIDs[itemID] then return false end
    if catalogFailureIDs[itemID] and not retryFailed then return false end

    catalogFailureIDs[itemID] = nil
    itemQueryQueued[itemID] = true
    table.insert(itemQueryQueue, itemID)
    return true
end

local function HasInFlightItemQueries()
    return next(catalogInFlightIDs) ~= nil
end

local function StartItemQueryQueue()
    if not itemQueryTooltip then
        itemQueryTooltip = CreateFrame("GameTooltip", "TRBISItemQueryTooltip", UIParent, "GameTooltipTemplate")
        itemQueryTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    if not itemQueryFrame then itemQueryFrame = CreateFrame("Frame") end

    itemQueryFrame:SetScript("OnUpdate", function(self, elapsed)
        local timedOut = false
        local now = GetTime and GetTime() or 0
        if now > 0 then
            for itemID, requestedAt in pairs(catalogRequestTimes) do
                if (now - requestedAt) >= ITEM_QUERY_TIMEOUT then
                    if GetItemInfo and GetItemInfo(itemID) then
                        MarkCatalogLoaded(itemID)
                    else
                        catalogRequestTimes[itemID] = nil
                        catalogInFlightIDs[itemID] = nil
                        catalogFailureIDs[itemID] = true
                        if pendingDressUpItemID == itemID then
                            pendingDressUpItemID = nil
                            pendingDressUpItemName = nil
                            PrintMessage("Item data did not arrive in time; its Dressing Room preview is unavailable on this realm right now.")
                        end
                    end
                    timedOut = true
                end
            end
        end

        itemQueryElapsed = itemQueryElapsed + elapsed
        if itemQueryElapsed >= ITEM_QUERY_INTERVAL then
            itemQueryElapsed = 0
            local itemID = itemQueryQueue[itemQueryCursor]
            if itemID then
                itemQueryCursor = itemQueryCursor + 1
                itemQueryQueued[itemID] = nil

                if GetItemInfo and GetItemInfo(itemID) then
                    MarkCatalogLoaded(itemID)
                else
                    catalogInFlightIDs[itemID] = true
                    catalogRequestTimes[itemID] = now
                    itemQueryAttempts = itemQueryAttempts + 1
                    if itemQueryTooltip then
                        itemQueryTooltip:ClearLines()
                        local ok = pcall(function()
                            itemQueryTooltip:SetHyperlink("item:" .. tostring(itemID))
                        end)
                        if not ok then
                            catalogRequestTimes[itemID] = nil
                            catalogInFlightIDs[itemID] = nil
                            catalogFailureIDs[itemID] = true
                        end
                    end
                    if GetItemInfo and GetItemInfo(itemID) then
                        MarkCatalogLoaded(itemID)
                    end
                    if itemQueryTooltip then itemQueryTooltip:Hide() end
                end
                if browserFrame and browserFrame:IsShown() then RefreshBrowser() end
                UpdatePlayerStatus()
            end
        end

        if timedOut then UpdatePlayerStatus() end
        if itemQueryCursor > #itemQueryQueue and not HasInFlightItemQueries() then
            self:SetScript("OnUpdate", nil)
            UpdatePlayerStatus()
        end
    end)
end

local function QueueAllCatalogItems(retryFailures)
    if not TRBIS_ItemIDs then return 0 end
    local added = 0
    for itemID in pairs(workbookItemIDs) do
        itemID = tonumber(itemID)
        if itemID then
            catalogItemIDs[itemID] = true
            if QueueItemID(itemID, retryFailures) then added = added + 1 end
        end
    end
    catalogQueueInitialized = true
    if itemQueryCursor <= #itemQueryQueue then StartItemQueryQueue() end
    UpdatePlayerStatus()
    return added
end

local function RetryFailedCatalogItems()
    local failedIDs = {}
    for itemID in pairs(catalogFailureIDs) do table.insert(failedIDs, itemID) end
    local added = 0
    for _, itemID in ipairs(failedIDs) do
        if QueueItemID(itemID, true) then added = added + 1 end
    end
    if added > 0 then StartItemQueryQueue() end
    UpdatePlayerStatus()
    return added
end

local function RememberItemLink(itemName, itemLink)
    if not itemName or itemName == "" or not itemLink then return end
    if not string.find(itemLink, "|Hitem:%d+", 1) then return end
    if not TheRealBISTooltipDB then TheRealBISTooltipDB = {} end
    if not TheRealBISTooltipDB.itemLinks then TheRealBISTooltipDB.itemLinks = {} end
    local key = CanonicalKey(itemName)
    if key == "" or not BIS_INDEX[key] then return end
    TheRealBISTooltipDB.itemLinks[key] = itemLink
end

local function GetItemCacheInfo(itemName)
    local key = CanonicalKey(itemName)
    local savedLink
    if TheRealBISTooltipDB and TheRealBISTooltipDB.itemLinks then
        savedLink = TheRealBISTooltipDB.itemLinks[key]
    end
    local itemID = TRBIS_ItemIDs and tonumber(TRBIS_ItemIDs[key])
    local cachedName, itemLink, itemQuality, itemLevel, itemMinLevel,
          itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture

    -- If the bundled catalogue now points to a corrected (for example, Heroic)
    -- variant, discard an older SavedVariables hyperlink for the same display name.
    -- Otherwise an older saved normal-mode item link could override the bundled item ID.
    if savedLink and itemID then
        local savedLinkID = tonumber(string.match(savedLink, "|Hitem:(%d+)"))
        if savedLinkID and savedLinkID ~= itemID then
            savedLink = nil
            if TheRealBISTooltipDB and TheRealBISTooltipDB.itemLinks then
                TheRealBISTooltipDB.itemLinks[key] = nil
            end
        end
    end

    if GetItemInfo and savedLink then
        cachedName, itemLink, itemQuality, itemLevel, itemMinLevel,
        itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(savedLink)
    end
    if GetItemInfo and not itemLink and itemID then
        QueueItemID(itemID)
        cachedName, itemLink, itemQuality, itemLevel, itemMinLevel,
        itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(itemID)
    end
    if GetItemInfo and not itemLink and not itemID then
        cachedName, itemLink, itemQuality, itemLevel, itemMinLevel,
        itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(itemName)
    end

    if itemLink then
        RememberItemLink(itemName, itemLink)
    elseif savedLink then
        itemLink = savedLink
    end
    return itemLink, itemTexture, itemQuality, cachedName, itemID
end

local function GetMatchingEntries(itemName)
    local entries = BIS_INDEX[CanonicalKey(itemName)]
    if not entries then return {} end
    local matches = {}
    for _, entry in ipairs(entries) do
        if (not onlyMyClass) or (entry.className == playerClassName) then
            table.insert(matches, entry)
        end
    end
    return matches
end

local function AddBiSLines(tooltip)
    if not tooltip or not tooltip.GetItem then return end
    local itemName, itemLink = tooltip:GetItem()
    if not itemName and itemLink and GetItemInfo then itemName = GetItemInfo(itemLink) end
    if not itemName or itemName == "" then return end
    if itemLink then RememberItemLink(itemName, itemLink) end

    local cacheKey = CanonicalKey(itemName) .. "|" .. tostring(itemLink or "")
    if tooltip.__TRBIS_LastKey == cacheKey then return end
    tooltip.__TRBIS_LastKey = cacheKey
    local matches = GetMatchingEntries(itemName)
    if #matches == 0 then return end

    tooltip:AddLine(" ")
    tooltip:AddLine("The Real BIS-Tooltip 3.3.5a", 1.00, 0.82, 0.20)
    tooltip:AddLine("Listed as BiS for:", 0.95, 0.95, 0.95)
    local shown = 0
    local maxShown = 12
    for _, entry in ipairs(matches) do
        if shown >= maxShown then break end
        local prefix = (entry.className == playerClassName) and "[Your class] " or ""
        local text = prefix .. entry.className .. " - " .. entry.specName .. " (" .. entry.slotName .. ")"
        if entry.className == playerClassName then
            tooltip:AddLine(text, 0.30, 1.00, 0.35, true)
        else
            tooltip:AddLine(text, 0.85, 0.88, 0.95, true)
        end
        shown = shown + 1
    end
    if #matches > shown then tooltip:AddLine("...and " .. tostring(#matches - shown) .. " more listing(s)", 1.00, 0.82, 0.20, true) end
    tooltip:Show()
end

local function HookTooltip(tooltip)
    if not tooltip or tooltip.__TRBIS_Hooked then return end
    tooltip.__TRBIS_Hooked = true
    tooltip:HookScript("OnTooltipSetItem", AddBiSLines)
    tooltip:HookScript("OnTooltipCleared", function(self) self.__TRBIS_LastKey = nil end)
end

local function ShowBrowserItemTooltip(button)
    if button.glyphItemID then
        local glyphID = tonumber(button.glyphItemID)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        local glyphName, glyphLink, glyphQuality, glyphLevel, glyphMinLevel,
              glyphType, glyphSubType, glyphStack, glyphEquipLoc, glyphTexture
        if GetItemInfo and glyphID then
            glyphName, glyphLink, glyphQuality, glyphLevel, glyphMinLevel,
            glyphType, glyphSubType, glyphStack, glyphEquipLoc, glyphTexture = GetItemInfo(glyphID)
        end
        if glyphLink then
            GameTooltip:SetHyperlink(glyphLink)
        elseif glyphID then
            QueueItemID(glyphID)
            StartItemQueryQueue()
            pcall(function() GameTooltip:SetHyperlink("item:" .. tostring(glyphID)) end)
            if not GameTooltip:NumLines() or GameTooltip:NumLines() == 0 then
                GameTooltip:SetText(button.displayName or "Glyph", 1, 1, 1)
                GameTooltip:AddLine("Requesting glyph item details from the 3.3.5a client...", 1.00, 0.82, 0.20, true)
            end
        else
            GameTooltip:SetText(button.displayName or "Glyph", 1, 1, 1)
            GameTooltip:AddLine("No Wrath item ID is mapped for this glyph yet.", 1.00, 0.45, 0.35, true)
        end
        if button.glyphNote then
            GameTooltip:AddLine("Workbook note: " .. tostring(button.glyphNote), 1.00, 0.82, 0.20, true)
        end
        GameTooltip:Show()
        return
    end

    local itemName = button.itemName
    if not itemName or itemName == "" then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local itemLink, itemTexture, itemQuality, cachedName, itemID = GetItemCacheInfo(itemName)
    if itemLink then
        GameTooltip:SetHyperlink(itemLink)
        AddBiSLines(GameTooltip)
        GameTooltip:Show()
    elseif itemID then
        -- SetHyperlink with a valid numeric item link asks the client for that item directly.
        pcall(function() GameTooltip:SetHyperlink("item:" .. tostring(itemID)) end)
        if not GameTooltip:NumLines() or GameTooltip:NumLines() == 0 then
            GameTooltip:SetText(itemName, 1, 1, 1)
            GameTooltip:AddLine("Requesting item data from the 3.3.5a client...", 1.00, 0.82, 0.20, true)
            GameTooltip:AddLine("The full item tooltip will appear when the client returns the item record.", 0.85, 0.88, 0.95, true)
        end
        GameTooltip:Show()
    else
        GameTooltip:SetText(itemName, 1, 1, 1)
        GameTooltip:AddLine("No confirmed numeric ID is bundled for this name yet.", 1.00, 0.45, 0.35, true)
        GameTooltip:AddLine("If you encounter or link the item once, its real tooltip can still be remembered for later.", 0.85, 0.88, 0.95, true)
        GameTooltip:Show()
    end
end

local function GetBrowserItemLink(button)
    local itemName = button.itemName
    if not itemName or itemName == "" then return nil end
    local itemLink, itemTexture, itemQuality, cachedName, itemID = GetItemCacheInfo(itemName)
    if itemLink then return itemLink, tonumber(itemID) end
    itemID = tonumber(itemID) or (TRBIS_ItemIDs and tonumber(TRBIS_ItemIDs[CanonicalKey(itemName)]))
    if itemID then
        -- A minimal hyperlink is sufficient for the native modified-item-click handler;
        -- DressUpItemLink can resolve the item by ID even when its tooltip is not cached.
        local displayName = button.displayName or itemName
        displayName = displayName:gsub("%[", ""):gsub("%]", ""):gsub("|", "")
        return "|Hitem:" .. tostring(itemID) .. "|h[" .. displayName .. "]|h", itemID
    end
    return nil, nil
end

local function HandleBrowserItemClick(button, mouseButton)
    if mouseButton ~= "LeftButton" or not button.itemName then return end
    local itemLink, itemID = GetBrowserItemLink(button)
    if not itemLink then return end

    local chatLinkClick = IsModifiedClick and IsModifiedClick("CHATLINK")
    local dressUpClick = IsModifiedClick and IsModifiedClick("DRESSUP")
    -- If the user previews an uncached catalog item, wait for the current item query
    -- rather than sending an unresolved hyperlink to the Dressing Room.
    if dressUpClick and not chatLinkClick and itemID and not (GetItemInfo and GetItemInfo(itemID)) then
        pendingDressUpItemID = itemID
        pendingDressUpItemName = button.displayName or button.itemName
        QueueItemID(itemID, true)
        StartItemQueryQueue()
        PrintMessage("That item's data is still loading. The Dressing Room will open when the client receives it.")
        return
    end

    -- Match Blizzard's 3.3.5a behavior and the player's configured key bindings:
    -- CHATLINK inserts the hyperlink, while DRESSUP opens the Dressing Room.
    if HandleModifiedItemClick then
        HandleModifiedItemClick(itemLink)
    else
        if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            if ChatEdit_InsertLink(itemLink) then return end
        end
        if IsModifiedClick and IsModifiedClick("DRESSUP") and DressUpItemLink then
            DressUpItemLink(itemLink)
        end
    end
end

local function CreateBrowserItemLine(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(28)
    button:EnableMouse(true)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(22); icon:SetHeight(22)
    icon:SetPoint("LEFT", button, "LEFT", 2, 0)
    icon:SetTexture(QUESTION_MARK_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    label:SetPoint("RIGHT", button, "RIGHT", -2, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    button.icon = icon; button.label = label; button.itemName = nil; button.glyphItemID = nil; button.glyphNote = nil
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnEnter", ShowBrowserItemTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", HandleBrowserItemClick)
    return button
end

local function RefreshBrowser()
    if not scrollContent or not selectedClass or not selectedSpec then return end
    local specs = TRBIS_Data[selectedClass]
    local rows = specs and specs[selectedSpec] or {}
    local y = -8
    local lineHeight = 28
    for index, row in ipairs(rows) do
        local rowFrames = browserRows[index]
        if not rowFrames then
            rowFrames = { slot = scrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormal"), lines = {} }
            browserRows[index] = rowFrames
        end
        local isGlyphRow = (row.slot == "Glyphs")
        local candidates = isGlyphRow and GetGlyphCandidates(row.item) or GetDisplayCandidates(row.item)
        local rowHeight = math.max(30, #candidates * lineHeight + 4)

        local slotText = rowFrames.slot
        slotText:ClearAllPoints(); slotText:SetPoint("TOPLEFT", 10, y)
        slotText:SetWidth(102); slotText:SetHeight(rowHeight)
        slotText:SetJustifyH("LEFT"); slotText:SetJustifyV("TOP")
        slotText:SetText(row.slot); slotText:SetTextColor(1.00, 0.82, 0.20); slotText:Show()

        for candidateIndex, candidate in ipairs(candidates) do
            local lineButton = rowFrames.lines[candidateIndex]
            if not lineButton then lineButton = CreateBrowserItemLine(scrollContent); rowFrames.lines[candidateIndex] = lineButton end
            lineButton:ClearAllPoints()
            lineButton:SetPoint("TOPLEFT", 120, y - ((candidateIndex - 1) * lineHeight))
            lineButton:SetWidth(395); lineButton:SetHeight(lineHeight)
            lineButton.icon:ClearAllPoints(); lineButton.icon:SetPoint("LEFT", lineButton, "LEFT", 2, 0)
            lineButton.icon:SetWidth(22); lineButton.icon:SetHeight(22)
            lineButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            lineButton.label:ClearAllPoints(); lineButton.label:SetPoint("LEFT", lineButton.icon, "RIGHT", 6, 0)
            lineButton.label:SetPoint("RIGHT", lineButton, "RIGHT", -2, 0)
            lineButton.label:SetHeight(lineHeight); lineButton.label:SetWordWrap(false)

            if isGlyphRow then
                lineButton.itemName = nil
                lineButton.glyphItemID = tonumber(candidate.itemID)
                lineButton.glyphNote = candidate.note
                lineButton.displayName = candidate.display
                local glyphName, glyphLink, glyphQuality, glyphLevel, glyphMinLevel,
                      glyphType, glyphSubType, glyphStack, glyphEquipLoc, glyphTexture
                if lineButton.glyphItemID and GetItemInfo then
                    glyphName, glyphLink, glyphQuality, glyphLevel, glyphMinLevel,
                    glyphType, glyphSubType, glyphStack, glyphEquipLoc, glyphTexture = GetItemInfo(lineButton.glyphItemID)
                end
                lineButton.icon:SetTexture(glyphTexture or QUESTION_MARK_ICON)
                lineButton.icon:Show()
                lineButton.label:SetText(candidate.display .. (candidate.note and (" (" .. candidate.note .. ")") or ""))
                if glyphQuality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[glyphQuality] then
                    local color = ITEM_QUALITY_COLORS[glyphQuality]
                    lineButton.label:SetTextColor(color.r, color.g, color.b)
                else
                    lineButton.label:SetTextColor(0.85, 0.88, 0.95)
                end
            else
                lineButton.itemName = candidate.lookup
                lineButton.glyphItemID = nil
                lineButton.glyphNote = nil
                lineButton.displayName = candidate.display
                lineButton.icon:Show()
                local itemLink, itemTexture, itemQuality = GetItemCacheInfo(candidate.lookup)
                lineButton.icon:SetTexture(itemTexture or QUESTION_MARK_ICON)
                if itemQuality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[itemQuality] then
                    local color = ITEM_QUALITY_COLORS[itemQuality]
                    lineButton.label:SetTextColor(color.r, color.g, color.b)
                else
                    lineButton.label:SetTextColor(0.85, 0.88, 0.95)
                end
                lineButton.label:SetText(candidate.display)
            end
            lineButton:Show()
        end
        for lineIndex = #candidates + 1, #rowFrames.lines do
            local stale = rowFrames.lines[lineIndex]
            stale:Hide(); stale.itemName = nil; stale.displayName = nil; stale.glyphItemID = nil; stale.glyphNote = nil
        end
        y = y - rowHeight - 5
    end
    for index = #rows + 1, #browserRows do
        local rowFrames = browserRows[index]
        rowFrames.slot:Hide()
        for _, lineButton in ipairs(rowFrames.lines) do
            lineButton:Hide(); lineButton.itemName = nil; lineButton.displayName = nil
            lineButton.glyphItemID = nil; lineButton.glyphNote = nil
        end
    end
    scrollContent:SetHeight(math.max(1, -y + 8))
    scrollContent:Show()
end

function UpdateSpecDropdown(preferredSpec)
    if not specDropdown then return end
    local specs = GetSpecsForClass(selectedClass)
    if preferredSpec and TRBIS_Data[selectedClass] and TRBIS_Data[selectedClass][preferredSpec] then
        selectedSpec = preferredSpec
    elseif not selectedSpec or not TRBIS_Data[selectedClass] or not TRBIS_Data[selectedClass][selectedSpec] then
        selectedSpec = specs[1]
    end
    UIDropDownMenu_Initialize(specDropdown, function(self, level)
        for _, specName in ipairs(specs) do
            local optionSpec = specName
            local info = UIDropDownMenu_CreateInfo()
            info.text = optionSpec; info.value = optionSpec; info.checked = (selectedSpec == optionSpec)
            info.func = function()
                selectedSpec = optionSpec
                autoSpecSelection = false
                UIDropDownMenu_SetSelectedValue(specDropdown, optionSpec)
                UIDropDownMenu_SetText(specDropdown, optionSpec)
                RefreshBrowser()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    if selectedSpec then UIDropDownMenu_SetSelectedValue(specDropdown, selectedSpec); UIDropDownMenu_SetText(specDropdown, selectedSpec)
    else UIDropDownMenu_SetText(specDropdown, "No builds") end
    RefreshBrowser()
end

local function CreateBrowser()
    if browserFrame then return end
    browserFrame = CreateFrame("Frame", "TRBISBrowserFrame", UIParent)
    browserFrame:SetWidth(590); browserFrame:SetHeight(650)
    browserFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    browserFrame:SetFrameStrata("DIALOG"); browserFrame:SetMovable(true); browserFrame:EnableMouse(true)
    browserFrame:RegisterForDrag("LeftButton")
    browserFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    browserFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    browserFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    browserFrame:Hide()

    -- Branded header: the packaged transparent TGA is the WoW 3.3.5a-safe
    -- Wrath-client-compatible version of the supplied transparent BIS medallion artwork.
    local headerIcon = browserFrame:CreateTexture(nil, "ARTWORK")
    headerIcon:SetTexture("Interface\\AddOns\\TheRealBISTooltip\\TheRealBISTooltip_Icon")
    headerIcon:SetWidth(50); headerIcon:SetHeight(50)
    headerIcon:SetPoint("TOPLEFT", browserFrame, "TOPLEFT", 18, -14)
    headerIcon:SetTexCoord(0.02, 0.98, 0.02, 0.98)

    local title = browserFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", browserFrame, "TOP", 0, -29)
    title:SetWidth(470); title:SetJustifyH("CENTER")
    title:SetText(ADDON_TITLE)

    local close = CreateFrame("Button", nil, browserFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -7, -7)

    local classLabel = browserFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    classLabel:SetPoint("TOPLEFT", 24, -78); classLabel:SetText("CLASS")
    local specLabel = browserFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specLabel:SetPoint("TOPLEFT", 282, -78); specLabel:SetText("SPEC / BUILD")

    classDropdown = CreateFrame("Frame", "TRBISClassDropdown", browserFrame, "UIDropDownMenuTemplate")
    classDropdown:SetPoint("TOPLEFT", 8, -103); UIDropDownMenu_SetWidth(classDropdown, 185)
    specDropdown = CreateFrame("Frame", "TRBISSpecDropdown", browserFrame, "UIDropDownMenuTemplate")
    specDropdown:SetPoint("TOPLEFT", 260, -103); UIDropDownMenu_SetWidth(specDropdown, 255)

    -- Only catalog progress is shown; player/viewing status is hidden to keep
    -- the browser clean and leave more room for the equipment and glyph lists.
    catalogStatusText = browserFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    catalogStatusText:SetPoint("TOPLEFT", 24, -145); catalogStatusText:SetWidth(405); catalogStatusText:SetJustifyH("LEFT")

    retryButton = CreateFrame("Button", nil, browserFrame, "UIPanelButtonTemplate")
    retryButton:SetWidth(112); retryButton:SetHeight(22)
    retryButton:SetPoint("TOPRIGHT", -36, -137)
    retryButton:SetText("Retry Failed")
    retryButton:SetScript("OnClick", function()
        local retried = RetryFailedCatalogItems()
        PrintMessage("Retry queued for " .. tostring(retried) .. " failed item lookup(s). Already-loaded items were not requested again.")
    end)

    -- No instructional hover text is displayed. Native equipment and glyph
    -- tooltips remain active on the rows themselves.
    scrollFrame = CreateFrame("ScrollFrame", "TRBISBrowserScrollFrame", browserFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -177); scrollFrame:SetPoint("BOTTOMRIGHT", -42, 23)
    scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetWidth(520); scrollContent:SetHeight(1); scrollFrame:SetScrollChild(scrollContent)

    if not selectedClass then UpdatePlayerProfile(true) end
    selectedClass = selectedClass or playerClassName or CLASS_ORDER[1]
    local specs = GetSpecsForClass(selectedClass)
    if not selectedSpec then selectedSpec = GetRecommendedSpec(selectedClass) or specs[1] end
    UIDropDownMenu_SetSelectedValue(classDropdown, selectedClass); UIDropDownMenu_SetText(classDropdown, selectedClass)
    UIDropDownMenu_Initialize(classDropdown, function(self, level)
        for _, className in ipairs(CLASS_ORDER) do
            local optionClass = className
            local info = UIDropDownMenu_CreateInfo()
            info.text = optionClass; info.value = optionClass; info.checked = (selectedClass == optionClass)
            info.func = function()
                selectedClass = optionClass
                autoClassSelection = false
                autoSpecSelection = false
                UIDropDownMenu_SetSelectedValue(classDropdown, optionClass)
                UIDropDownMenu_SetText(classDropdown, optionClass)
                local preferred = (optionClass == playerClassName) and GetRecommendedSpec(optionClass) or nil
                selectedSpec = nil
                UpdateSpecDropdown(preferred)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UpdateSpecDropdown(selectedSpec)
    UpdatePlayerProfile(false)
    UpdatePlayerStatus()
end

local function ToggleBrowser()
    CreateBrowser()
    if browserFrame:IsShown() then browserFrame:Hide() else browserFrame:Show(); RefreshBrowser() end
end

local function UpdateMinimapButtonPosition()
    if not minimapButton or not Minimap then return end
    local angle = tonumber(TheRealBISTooltipDB and TheRealBISTooltipDB.minimapAngle) or 220
    local radius = 80
    local radians = math.rad(angle)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

local function CreateMinimapButton()
    if minimapButton or not Minimap then return end
    if not TheRealBISTooltipDB then TheRealBISTooltipDB = {} end
    if TheRealBISTooltipDB.minimapAngle == nil then TheRealBISTooltipDB.minimapAngle = 220 end

    minimapButton = CreateFrame("Button", "TheRealBISTooltipMinimapButton", Minimap)
    minimapButton:SetWidth(36)
    minimapButton:SetHeight(36)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    minimapButton:EnableMouse(true)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")

    -- The medallion artwork already contains a complete circular rim. Do not
    -- overlay the stock MiniMap-TrackingBorder: it creates a second inner circle
    -- and makes the custom artwork look shrunken/nested in-game.
    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\TheRealBISTooltip\\TheRealBISTooltip_Icon")
    icon:SetAllPoints(minimapButton)
    minimapButton.icon = icon

    minimapButton:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            onlyMyClass = not onlyMyClass
            if TheRealBISTooltipDB then
                TheRealBISTooltipDB.filter = onlyMyClass and "mine" or "all"
            end
            PrintMessage(onlyMyClass and "Minimap button: tooltip matches restricted to your class." or "Minimap button: tooltip matches for all classes.")
            if browserFrame and browserFrame:IsShown() then RefreshBrowser() end
        else
            ToggleBrowser()
        end
    end)
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(ADDON_TITLE, 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: open BiS browser", 1, 1, 1)
        GameTooltip:AddLine("Right-click: toggle all-class / your-class filter", 1, 1, 1)
        GameTooltip:AddLine("Drag: move minimap button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    minimapButton:SetScript("OnDragStart", function(self)
        self.isDragging = true
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self.isDragging = false
        UpdateMinimapButtonPosition()
    end)
    minimapButton:SetScript("OnUpdate", function(self)
        if not self.isDragging then return end
        local scale = UIParent:GetEffectiveScale()
        local cursorX, cursorY = GetCursorPosition()
        cursorX, cursorY = cursorX / scale, cursorY / scale
        local centerX, centerY = Minimap:GetCenter()
        local angle = math.deg(math.atan2(cursorY - centerY, cursorX - centerX))
        TheRealBISTooltipDB.minimapAngle = angle
        UpdateMinimapButtonPosition()
    end)

    UpdateMinimapButtonPosition()
end

local function CountRememberedItemLinks()
    local count = 0
    if TheRealBISTooltipDB and TheRealBISTooltipDB.itemLinks then
        for _ in pairs(TheRealBISTooltipDB.itemLinks) do count = count + 1 end
    end
    return count
end

local function HandleSlashCommand(message)
    message = string.lower(Trim(message or ""))
    if message == "mine" then
        onlyMyClass = true
        if TheRealBISTooltipDB then TheRealBISTooltipDB.filter = "mine" end
        PrintMessage("Tooltip matches are now restricted to " .. tostring(playerClassName or "your class") .. ".")
    elseif message == "all" then
        onlyMyClass = false
        if TheRealBISTooltipDB then TheRealBISTooltipDB.filter = "all" end
        PrintMessage("Tooltip matches for all classes are now shown.")
    elseif message == "refresh" then
        RefreshBrowser()
        local queued = QueueAllCatalogItems(true)
        PrintMessage("Catalog refreshed. " .. tostring(queued) .. " unresolved/failed lookup(s) queued; loaded items were not requested again.")
    elseif message == "retry" then
        local retried = RetryFailedCatalogItems()
        PrintMessage("Retry queued for " .. tostring(retried) .. " failed item lookup(s).")
    elseif message == "auto" then
        UpdatePlayerProfile(true)
        if browserFrame and browserFrame:IsShown() then RefreshBrowser() end
        PrintMessage("Automatic character class and talent-tree build selection restored.")
    elseif message == "status" then
        local suggested, reason = GetRecommendedSpec(playerClassName)
        PrintMessage("Character: " .. tostring(playerClassName or "unknown") .. "; talent tree: " .. tostring(activeTalentTreeStatus) .. "; suggested build: " .. tostring(suggested or "manual selection") .. " (" .. tostring(reason) .. ").")
        local loaded, pending, failed, total = GetCatalogStats()
        PrintMessage("Item data: " .. tostring(loaded) .. "/" .. tostring(total) .. " loaded; " .. tostring(pending) .. " pending; " .. tostring(failed) .. " failed; " .. tostring(itemQueryAttempts) .. " requests sent.")
        PrintMessage("Mapped workbook item names: " .. tostring(mappedCandidateCount) .. "/" .. tostring(candidateCount) .. "; remembered links: " .. tostring(CountRememberedItemLinks()) .. ".")
    elseif message == "help" then
        PrintMessage("/trbis - open the BiS browser")
        PrintMessage("/trbis mine - restrict added item-tooltip matches to your class")
        PrintMessage("/trbis all - show added item-tooltip matches for all classes")
        PrintMessage("/trbis refresh - queue unresolved lookups and retry failures without re-requesting loaded items")
        PrintMessage("/trbis retry - retry failed item lookups only")
        PrintMessage("/trbis auto - restore your character's detected class and suggested build")
        PrintMessage("/trbis status - show detected class/tree and item-catalog progress")
        PrintMessage("Minimap button: left-click opens the browser; right-click toggles class filter; drag to reposition")
    elseif message == "" then ToggleBrowser()
    else PrintMessage("Unknown command. Type /trbis help.") end
end

SLASH_TRBIS1 = "/trbis"
SlashCmdList["TRBIS"] = HandleSlashCommand

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_FOLDER then return end
        if not TheRealBISTooltipDB then TheRealBISTooltipDB = {} end
        if TheRealBISTooltipDB.filter == "mine" then onlyMyClass = true else onlyMyClass = false end
        if not TheRealBISTooltipDB.itemLinks then TheRealBISTooltipDB.itemLinks = {} end
        CreateMinimapButton()
        BuildIndex()
        HookTooltip(GameTooltip); HookTooltip(ItemRefTooltip)
        HookTooltip(ShoppingTooltip1); HookTooltip(ShoppingTooltip2)
        HookTooltip(ItemRefShoppingTooltip1); HookTooltip(ItemRefShoppingTooltip2)
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        PrintMessage("Loaded. Your character class and active talent tree will be detected at login. Type /trbis to browse.")
    elseif event == "PLAYER_LOGIN" then
        UpdatePlayerProfile(true)
        if not catalogQueueInitialized then QueueAllCatalogItems() end
        if playerClassName then
            PrintMessage("Detected " .. playerClassName .. " / " .. tostring(activeTalentTreeStatus) .. ".")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not selectedClass or autoClassSelection then UpdatePlayerProfile(true) else UpdatePlayerProfile(false) end
        if not catalogQueueInitialized then QueueAllCatalogItems() end
    elseif event == "CHARACTER_POINTS_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        UpdatePlayerProfile(false)
        if browserFrame and browserFrame:IsShown() and selectedClass == playerClassName and autoSpecSelection then
            local suggested = GetRecommendedSpec(playerClassName)
            if suggested then UpdateSpecDropdown(suggested) end
        end
        UpdatePlayerStatus()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = tonumber(arg1), arg2
        if itemID and catalogItemIDs[itemID] then
            if success or (GetItemInfo and GetItemInfo(itemID)) then
                MarkCatalogLoaded(itemID)
            elseif catalogInFlightIDs[itemID] then
                catalogInFlightIDs[itemID] = nil
                catalogRequestTimes[itemID] = nil
                catalogFailureIDs[itemID] = true
                if pendingDressUpItemID == itemID then
                    pendingDressUpItemID = nil
                    pendingDressUpItemName = nil
                    PrintMessage("The realm did not return item data, so this item's Dressing Room preview is unavailable.")
                end
            end
            if browserFrame and browserFrame:IsShown() then RefreshBrowser() end
            UpdatePlayerStatus()
        end
    end
end)
