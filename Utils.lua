setfenv(1, VoiceOver)
Utils = {}

local SUPERWOW_GUID_TYPE = {
    [tonumber("0000", 16)] = "Player",
    [tonumber("4000", 16)] = "Item",
    [tonumber("F130", 16)] = "Creature",
    [tonumber("F150", 16)] = "Vehicle",
    [tonumber("F110", 16)] = "GameObject",
}

--- SuperWoW uses the 2.4-style 0xF130... GUID. Modern clients use Type-realm-id.
---@param guid string
---@return GUID|nil guid
function Utils:GetGUIDType(guid)
    if not guid or type(guid) ~= "string" then
        return
    end
    if string.find(guid, "-") then
        return Enums.GUID[select(1, strsplit("-", guid, 2))]
    end
    local name = SUPERWOW_GUID_TYPE[tonumber(string.sub(guid, 3, 6), 16)]
    return name and Enums.GUID[name]
end

---@param guid string
---@return number|nil id
function Utils:GetIDFromGUID(guid)
    if not guid or type(guid) ~= "string" then
        return
    end
    if string.find(guid, "-") then
        local rest
        _, rest = strsplit("-", guid, 2)
        return tonumber((select(5, strsplit("-", rest))))
    end
    return tonumber(string.sub(guid, 7, 12), 16)
end

---@param type GUID
---@param id number
---@return string|nil guid
function Utils:MakeGUID(type, id)
    if not Enums.GUID:CanHaveID(type) or not id then
        return
    end
    return format("0x%04X%06X%06X", type, id, 0)
end

--- Returns the name of the NPC that's being interacted with while a GossipFrame or QuestFrame is visible.
---@return string|nil name
function Utils:GetNPCName()
    local name = UnitName("npc")
    if name then
        return name
    end
    local ok, questName = pcall(UnitName, "questnpc")
    if ok then
        return questName
    end
end

--- SuperWoW / some 1.12 clients provide UnitGUID; stock 1.12 does not.
---@return string|nil guid
function Utils:GetNPCGUID()
    if not UnitGUID then
        return nil
    end
    local guid = UnitGUID("npc")
    if guid then
        return guid
    end
    local ok, questGUID = pcall(UnitGUID, "questnpc")
    if ok then
        return questGUID
    end
end

--- Returns whether the NPC that's being interacted with while a GossipFrame or QuestFrame is visible is a GameObject or Item.
---@return boolean isObjectOrItem
function Utils:IsNPCObjectOrItem()
    return not UnitExists("npc")
end

--- Returns whether the NPC that's being interacted with while a GossipFrame or QuestFrame is visible is a Player.
---@return boolean isPlayer
function Utils:IsNPCPlayer()
    return UnitIsPlayer("npc")
end

local function HasMasterSoundEffects()
    return GetCVar("MasterSoundEffects") ~= nil
end

--- Returns whether the player's sound options will allow the playback of sound files.
---@return boolean enabled
function Utils:IsSoundEnabled()
    if HasMasterSoundEffects() then
        return tonumber(GetCVar("MasterSoundEffects")) == 1
    end
    if tonumber(GetCVar("Sound_EnableAllSound")) == 0 then
        return false
    end
    return tonumber(GetCVar("Sound_EnableSFX")) ~= 0
end

--- 1.12 cannot reliably test or stop individual sound files.
---@param soundData SoundData
---@return boolean willPlay
function Utils:TestSound(soundData)
    return true
end

--- Plays the sound from SoundData. Optionally interrupts generic NPC greeting voicelines first.
---@param soundData SoundData
function Utils:PlaySound(soundData)
    if Addon.db.profile.Audio.AutoToggleDialog and HasMasterSoundEffects() then
        SetCVar("MasterSoundEffects", 0)
        SetCVar("MasterSoundEffects", 1)
    end

    PlaySoundFile(soundData.filePath)
    soundData.handle = 1 -- Flag the sound as stoppable
end

--- Stops the current voiceover by toggling the master sound effects CVar.
---@param soundData SoundData
function Utils:StopSound(soundData)
    if HasMasterSoundEffects() then
        SetCVar("MasterSoundEffects", 0)
        SetCVar("MasterSoundEffects", 1)
    end
    soundData.handle = nil
end

--- Returns the button index offset of the Quest Log scroll frame.
---@return number offset
function Utils:GetQuestLogScrollOffset()
    local scroll = QuestLogListScrollFrame
    if not scroll then
        return 0
    end
    return FauxScrollFrame_GetOffset(scroll) or 0
end

--- Returns the `Button` that represents the quest in the Quest Log frame.
---@return Button button
function Utils:GetQuestLogTitleFrame(index)
    return _G["QuestLogTitle" .. index]
end

--- Returns the title `FontString` of the button that represents the quest in the Quest Log frame.
---@return FontString title
function Utils:GetQuestLogTitleNormalText(index)
    return _G["QuestLogTitle" .. index .. "NormalText"]
end

--- Returns the quest tracking check mark `Texture` of the button that represents the quest in the Quest Log frame.
---@return Texture check
function Utils:GetQuestLogTitleCheck(index)
    return _G["QuestLogTitle" .. index .. "Check"]
end

--- Returns the provided text enclosed in the provided color tag.
---@param text string
---@param color string Color tag in "|cAARRGGBB" format
---@return string colorizedText
function Utils:ColorizeText(text, color)
    return color .. text .. "|r"
end

--- Returns an iterator to the table sorted with the provided function, or sorted by value if no function was provided.
---@generic K, V
---@param tbl table<K, V>
---@param sorter fun(valueA: V, valueB: V, keyA: K, keyB: K): boolean Should return whether A should precede B
---@return function iterator
---@return table tbl
---@return nil
function Utils:Ordered(tbl, sorter)
    local orderedIndex = {}
    for key in pairs(tbl) do
        table.insert(orderedIndex, key)
    end
    if sorter then
        table.sort(orderedIndex, function(a, b)
            return sorter(tbl[a], tbl[b], a, b)
        end)
    else
        table.sort(orderedIndex)
    end

    local i = 0
    local function orderedNext(t)
        i = i + 1
        return orderedIndex[i], t[orderedIndex[i]]
    end

    return orderedNext, tbl, nil
end

local animationDurations = {
    ["Original"] = {
        [130737]  = { [60] = 1533 }, -- interface/buttons/talktomequestion_white

        [116921]  = { [60] = 4000 }, -- character/bloodelf/female/bloodelffemale
        [1100258] = { [60] = 4000 }, -- character/bloodelf/female/bloodelffemale_hd
        [117170]  = { [60] = 2000 }, -- character/bloodelf/male/bloodelfmale
        [1100087] = { [60] = 2000 }, -- character/bloodelf/male/bloodelfmale_hd
        [117400]  = { [60] = 2934 }, -- character/broken/female/brokenfemale
        [117412]  = { [60] = 2934 }, -- character/broken/male/brokenmale
        [117437]  = { [60] = 3000 }, -- character/draenei/female/draeneifemale
        [1022598] = { [60] = 3000 }, -- character/draenei/female/draeneifemale_hd
        [117721]  = { [60] = 3334 }, -- character/draenei/male/draeneimale
        [1005887] = { [60] = 3334 }, -- character/draenei/male/draeneimale_hd
        [118135]  = { [60] = 2000 }, -- character/dwarf/female/dwarffemale
        [950080]  = { [60] = 2000 }, -- character/dwarf/female/dwarffemale_hd
        [118355]  = { [60] = 2000 }, -- character/dwarf/male/dwarfmale
        [878772]  = { [60] = 2000 }, -- character/dwarf/male/dwarfmale_hd
        [118652]  = { [60] = 2000 }, -- character/felorc/female/felorcfemale
        [118653]  = { [60] = 2000 }, -- character/felorc/male/felorcmale
        [118654]  = { [60] = 2000 }, -- character/felorc/male/felorcmaleaxe
        [118667]  = { [60] = 2000 }, -- character/felorc/male/felorcmalesword
        [118798]  = { [60] = 2500 }, -- character/foresttroll/male/foresttrollmale
        [119063]  = { [60] = 4000 }, -- character/gnome/female/gnomefemale
        [940356]  = { [60] = 4000 }, -- character/gnome/female/gnomefemale_hd
        [119159]  = { [60] = 4000 }, -- character/gnome/male/gnomemale
        [900914]  = { [60] = 4000 }, -- character/gnome/male/gnomemale_hd
        [119369]  = { [60] = 1800 }, -- character/goblin/female/goblinfemale
        [119376]  = { [60] = 1800 }, -- character/goblin/male/goblinmale
        [119563]  = { [60] = 2667 }, -- character/human/female/humanfemale
        [1000764] = { [60] = 2667 }, -- character/human/female/humanfemale_hd
        [119940]  = { [60] = 2000 }, -- character/human/male/humanmale
        [1011653] = { [60] = 2000 }, -- character/human/male/humanmale_hd
        [232863]  = { [60] = 2500 }, -- character/icetroll/male/icetrollmale
        [120263]  = { [60] = 3000 }, -- character/naga_/female/naga_female
        [120294]  = { [60] = 3000 }, -- character/naga_/male/naga_male
        [120590]  = { [60] = 2100 }, -- character/nightelf/female/nightelffemale
        [921844]  = { [60] = 2100 }, -- character/nightelf/female/nightelffemale_hd
        [120791]  = { [60] = 2000 }, -- character/nightelf/male/nightelfmale
        [974343]  = { [60] = 2000 }, -- character/nightelf/male/nightelfmale_hd
        [233367]  = { [60] = 3600 }, -- character/northrendskeleton/male/northrendskeletonmale
        [121087]  = { [60] = 2000 }, -- character/orc/female/orcfemale
        [949470]  = { [60] = 2000 }, -- character/orc/female/orcfemale_hd
        [121287]  = { [60] = 2000 }, -- character/orc/male/orcmale
        [917116]  = { [60] = 2000 }, -- character/orc/male/orcmale_hd
        [121608]  = { [60] = 2000 }, -- character/scourge/female/scourgefemale
        [997378]  = { [60] = 2467 }, -- character/scourge/female/scourgefemale_hd
        [121768]  = { [60] = 2667 }, -- character/scourge/male/scourgemale
        [959310]  = { [60] = 2667 }, -- character/scourge/male/scourgemale_hd
        [121942]  = { [60] = 2667 }, -- character/skeleton/male/skeletonmale
        [233878]  = { [60] = 2934 }, -- character/taunka/male/taunkamale
        [121961]  = { [60] = 2934 }, -- character/tauren/female/taurenfemale
        [986648]  = { [60] = 2934 }, -- character/tauren/female/taurenfemale_hd
        [122055]  = { [60] = 2934 }, -- character/tauren/male/taurenmale
        [968705]  = { [60] = 2934 }, -- character/tauren/male/taurenmale_hd
        [122414]  = { [60] = 2500 }, -- character/troll/female/trollfemale
        [1018060] = { [60] = 2500 }, -- character/troll/female/trollfemale_hd
        [122560]  = { [60] = 2500 }, -- character/troll/male/trollmale
        [1022938] = { [60] = 2500 }, -- character/troll/male/trollmale_hd
        [122738]  = { [60] = 3000 }, -- character/tuskarr/male/tuskarrmale
        [122815]  = { [60] = 3600 }, -- character/vrykul/male/vrykulmale
    },
}
-- Goblin models on 1.12 lack the talk animation; 0 makes them fall back to idle
animationDurations["Original"][119369][60] = 0
animationDurations["Original"][119376][60] = 0

--- Returns the model set used by `Utils:GetModelAnimationDuration(model, animation)`.
---@return string|"Original"|"HD"
function Utils:GetCurrentModelSet()
    return "Original"
end

--- Returns the duration in milliseconds of the provided animation in the provided 3D model.
---@param model number Model's FileDataID
---@param animation number Animation ID
---@return number|nil duration Animation duration in milliseconds, 0 if the model is known to lack the animation, or nil if no model is loaded or the animation duration is unknown
function Utils:GetModelAnimationDuration(model, animation)
    if not model or model == 123 then return end
    local models = animationDurations[Utils:GetCurrentModelSet()] or animationDurations["Original"]
    local animations = models[model] or animationDurations["Original"][model]
    local duration = animations and animations[animation]
    return duration and duration / 1000
end

--- Stores a `PlayerModel` in `SoundData.modelFrame` that's meant to represent the unit speaking.
--- Overridden in Compatibility.lua because 1.12 cannot display an arbitrary creature ID in a `DressUpModel`.
---@param soundData SoundData
function Utils:CreateNPCModelFrame(soundData)
end

--- Frees the `PlayerModel` stored in `SoundData.modelFrame` by `Utils:CreateNPCModelFrame(soundData)` back to the model pool once it's no longer needed.
---@param soundData SoundData
function Utils:FreeNPCModelFrame(soundData)
end
