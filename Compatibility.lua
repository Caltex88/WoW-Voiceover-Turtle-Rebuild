setfenv(1, VoiceOver)

if not select then
    function select(index, ...)
        if index == "#" then
            return arg.n
        else
            local result = {}
            for i = index, arg.n do
                table.insert(result, arg[i])
            end
            return unpack(result)
        end
    end
end

if not print then
    function print(...)
        local text = ""
        for i = 1, arg.n do
            text = text .. (i > 1 and " " or "") .. tostring(arg[i])
        end
        DEFAULT_CHAT_FRAME:AddMessage(text)
    end
end

if not strsplit then
    function strsplit(delimiter, text)
        local result = {}
        local from = 1
        local delim_from, delim_to = string.find(text, delimiter, from)
        while delim_from do
            table.insert(result, string.sub(text, from, delim_from - 1))
            from = delim_to + 1
            delim_from, delim_to = string.find(text, delimiter, from)
        end
        table.insert(result, string.sub(text, from))
        return unpack(result)
    end
end

if not string.gmatch then
    string.gmatch = string.gfind
end

if not string.match then
    local function getargs(s, e, ...)
        return unpack(arg)
    end
    function string.match(str, pattern)
        return getargs(string.find(str, pattern))
    end
end

if not string.trim then
    function string.trim(str)
        return (string.match(str, "^%s*(.-)%s*$"))
    end
end

if not table.wipe then
    function table.wipe(tbl)
        for key in next, tbl do
            tbl[key] = nil
        end
    end
end
if not wipe then
    wipe = table.wipe
end

-- Count varargs on both Lua 5.0 (`arg.n`) and Lua 5.1 (`select`).
local function getargn(...)
    if arg and arg.n ~= nil then
        return arg.n
    end
    if _G.select then
        return _G.select("#", ...)
    end
    return 0
end

if not hooksecurefunc then
    ---@overload fun(name, hook)
    function hooksecurefunc(tbl, name, hook)
        if not hook then
            name, hook = tbl, name
            tbl = _G
        end

        local old = tbl[name]
        assert(type(old) == "function")
        -- Numbered args so this works on Lua 5.0 (no `...` forwarding) and Lua 5.1 (no automatic `arg`).
        tbl[name] = function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            local r1, r2, r3, r4, r5, r6, r7, r8, r9 = old(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            hook(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            return r1, r2, r3, r4, r5, r6, r7, r8, r9
        end
    end
end

if not GetAddOnEnableState then
    ---@overload fun(addon)
    function GetAddOnEnableState(character, addon)
        addon = addon or character
        local name, _, _, _, loadable, reason = _G.GetAddOnInfo(addon)
        if not name or not loadable and reason == "DISABLED" then
            return 0
        end
        return 2
    end

    function GetAddOnInfo(indexOrName)
        local name, title, notes, enabled, loadable, reason, security, newVersion = _G.GetAddOnInfo(indexOrName)
        return name, title, notes, loadable, reason, security, newVersion
    end
end

local nativeGetQuestID = GetQuestID
local source, text
local old_QUEST_DETAIL = Addon.QUEST_DETAIL
local old_QUEST_PROGRESS = Addon.QUEST_PROGRESS
local old_QUEST_COMPLETE = Addon.QUEST_COMPLETE
local GetTitleText = GetTitleText -- Store original function before EQL3 (Extended Quest Log 3) overrides it and starts prepending quest level
function Addon:QUEST_DETAIL()   source = "accept"   text = GetQuestText and GetQuestText() or ""       old_QUEST_DETAIL(self) end
function Addon:QUEST_PROGRESS() source = "progress" text = GetProgressText and GetProgressText() or "" old_QUEST_PROGRESS(self) end
function Addon:QUEST_COMPLETE() source = "complete" text = GetRewardText and GetRewardText() or ""     old_QUEST_COMPLETE(self) end
function GetQuestID()
    -- Turtle/ClassicAPI may define GetQuestID via C_QuestLog, which is nil here and errors.
    if nativeGetQuestID then
        local ok, id = pcall(nativeGetQuestID)
        if ok and id and id ~= 0 then
            return id
        end
    end
    local npcName = Utils:GetNPCName()
    if Utils:IsNPCPlayer() then
        return 0
    end
    local title = GetTitleText and GetTitleText() or ""
    return DataModules:GetQuestID(source, title, npcName, text) or 0
end

if not QUESTS_DISPLAYED then
    if QuestLogScrollFrame then
        QUESTS_DISPLAYED = getn(QuestLogScrollFrame.buttons)
    end
end

if not SOUNDKIT then
    SOUNDKIT =
    {
        U_CHAT_SCROLL_BUTTON = "uChatScrollButton",
        IG_MAINMENU_OPEN = "igMainMenuOpen",
        IG_MAINMENU_CLOSE = "igMainMenuClose",
    }
end

if not SetCursor then
    function SetCursor() end
end

local dummyQuestIDMap = { NEXT = -1 }
local oldGetQuestLogTitle = GetQuestLogTitle -- Store original function before BEQL (Bayi's Extended Questlog) overrides it and starts prepending quest level
function GetQuestLogTitle(questIndex)
    local title, level, questTag, isHeader, isCollapsed, isComplete = oldGetQuestLogTitle(questIndex)
    if not title then
        return title, level, nil, isHeader, isCollapsed, isComplete, 1, 0
    end
    local questID = DataModules:GetQuestID("accept", title, "", "")
    if not questID and Addon.db and Addon.db.char.RecentQuestTitleToID then
        -- Try assuming that the last quest with the same title that the player has accepted is the quest that's currently in the quest log
        questID = Addon.db.char.RecentQuestTitleToID[title]
    end
    if not questID then
        -- Return a dummy quest ID unique per quest title, just to support having multiple quest log buttons in their current implementation (i.e. keyed by quest ID instead of button index)
        questID = dummyQuestIDMap[title]
        if not questID then
            questID = dummyQuestIDMap.NEXT
            dummyQuestIDMap.NEXT = dummyQuestIDMap.NEXT - 1
            dummyQuestIDMap[title] = questID
        end
    end
    return title, level, nil, isHeader, isCollapsed, isComplete, 1, questID
end

local RegionMixins = {}
local RegionOverrides = {}
local FrameMixins = {}
local FrameOverrides = {}
local FontStringMixins = {}
local ModelMixins = {}
local function ApplyMixinsAndOverrides(self, mixins, overrides)
    if mixins then
        for k, v in pairs(mixins) do
            if not self[k] then
                self[k] = v
            end
        end
    end
    if overrides then
        for k, v in pairs(overrides) do
            if self[k] then
                self["_" .. k], self[k] = self[k], v
            end
        end
    end
end
local hookFrame
local hookModel
function CreateFrame(frameType, name, parent, template)
    if UIParent.SetBackdrop and template == "BackdropTemplate" then
        template = nil
    end

    local frame = _G.CreateFrame(frameType, name, parent, template)
    ApplyMixinsAndOverrides(frame, RegionMixins, RegionOverrides)
    ApplyMixinsAndOverrides(frame, FrameMixins, FrameOverrides)
    if hookFrame then
        hookFrame(frame)
    end
    if frameType == "Model" or frameType == "PlayerModel" or frameType == "DressUpModel" then
        ApplyMixinsAndOverrides(frame, ModelMixins)
        if hookModel then
            hookModel(frame)
        end
    end
    return frame
end

function RegionMixins:SetShown(shown)
    if shown then
        self:Show()
    else
        self:Hide()
    end
end
function RegionMixins:SetSize(width, height)
    self:SetWidth(width)
    self:SetHeight(height)
end
function FrameMixins:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    self:SetMinResize(minWidth, minHeight)
    if maxWidth and maxHeight then
        self:SetMaxResize(maxWidth, maxHeight)
    end
end
function ModelMixins:SetAnimation(animation)
    self:SetSequence(animation)
end
function ModelMixins:SetCustomCamera(camera)
    self:SetCamera(camera)
end

local modelToFileID = {
    ["Original"] = {
        ["interface/buttons/talktomequestion_white"]                = 130737,

        ["character/bloodelf/female/bloodelffemale"]                = 116921,
        ["character/bloodelf/male/bloodelfmale"]                    = 117170,
        ["character/broken/female/brokenfemale"]                    = 117400,
        ["character/broken/male/brokenmale"]                        = 117412,
        ["character/draenei/female/draeneifemale"]                  = 117437,
        ["character/draenei/male/draeneimale"]                      = 117721,
        ["character/dwarf/female/dwarffemale"]                      = 118135,
        ["character/dwarf/female/dwarffemale_hd"]                   = 950080,
        ["character/dwarf/female/dwarffemale_npc"]                  = 950080,
        ["character/dwarf/male/dwarfmale"]                          = 118355,
        ["character/dwarf/male/dwarfmale_hd"]                       = 878772,
        ["character/dwarf/male/dwarfmale_npc"]                      = 878772,
        ["character/felorc/female/felorcfemale"]                    = 118652,
        ["character/felorc/male/felorcmale"]                        = 118653,
        ["character/felorc/male/felorcmaleaxe"]                     = 118654,
        ["character/felorc/male/felorcmalesword"]                   = 118667,
        ["character/foresttroll/male/foresttrollmale"]              = 118798,
        ["character/gnome/female/gnomefemale"]                      = 119063,
        ["character/gnome/female/gnomefemale_hd"]                   = 940356,
        ["character/gnome/female/gnomefemale_npc"]                  = 940356,
        ["character/gnome/male/gnomemale"]                          = 119159,
        ["character/gnome/male/gnomemale_hd"]                       = 900914,
        ["character/gnome/male/gnomemale_npc"]                      = 900914,
        ["character/goblin/female/goblinfemale"]                    = 119369,
        ["character/goblin/male/goblinmale"]                        = 119376,
        ["character/goblinold/male/goblinoldmale"]                  = 119376,
        ["character/human/female/humanfemale"]                      = 119563,
        ["character/human/female/humanfemale_hd"]                   = 1000764,
        ["character/human/female/humanfemale_npc"]                  = 1000764,
        ["character/human/male/humanmale"]                          = 119940,
        ["character/human/male/humanmale_cata"]                     = 119940,
        ["character/human/male/humanmale_hd"]                       = 1011653,
        ["character/human/male/humanmale_npc"]                      = 1011653,
        ["character/icetroll/male/icetrollmale"]                    = 232863,
        ["character/naga_/female/naga_female"]                      = 120263,
        ["character/naga_/male/naga_male"]                          = 120294,
        ["character/nightelf/female/nightelffemale"]                = 120590,
        ["character/nightelf/female/nightelffemale_hd"]             = 921844,
        ["character/nightelf/female/nightelffemale_npc"]            = 921844,
        ["character/nightelf/male/nightelfmale"]                    = 120791,
        ["character/nightelf/male/nightelfmale_hd"]                 = 974343,
        ["character/nightelf/male/nightelfmale_npc"]                = 974343,
        ["character/northrendskeleton/male/northrendskeletonmale"]  = 233367,
        ["character/orc/female/orcfemale"]                          = 121087,
        ["character/orc/female/orcfemale_npc"]                      = 121087,
        ["character/orc/male/orcmale"]                              = 121287,
        ["character/orc/male/orcmale_hd"]                           = 917116,
        ["character/orc/male/orcmale_npc"]                          = 917116,
        ["character/scourge/female/scourgefemale"]                  = 121608,
        ["character/scourge/female/scourgefemale_hd"]               = 997378,
        ["character/scourge/female/scourgefemale_npc"]              = 997378,
        ["character/scourge/male/scourgemale"]                      = 121768,
        ["character/scourge/male/scourgemale_hd"]                   = 959310,
        ["character/scourge/male/scourgemale_npc"]                  = 959310,
        ["character/skeleton/male/skeletonmale"]                    = 121942,
        ["character/taunka/male/taunkamale"]                        = 233878,
        ["character/tauren/female/taurenfemale"]                    = 121961,
        ["character/tauren/female/taurenfemale_hd"]                 = 986648,
        ["character/tauren/female/taurenfemale_npc"]                = 986648,
        ["character/tauren/male/taurenmale"]                        = 122055,
        ["character/tauren/male/taurenmale_hd"]                     = 968705,
        ["character/tauren/male/taurenmale_npc"]                    = 968705,
        ["character/troll/female/trollfemale"]                      = 122414,
        ["character/troll/female/trollfemale_hd"]                   = 1018060,
        ["character/troll/female/trollfemale_npc"]                  = 1018060,
        ["character/troll/male/trollmale"]                          = 122560,
        ["character/troll/male/trollmale_hd"]                       = 1022938,
        ["character/troll/male/trollmale_npc"]                      = 1022938,
        ["character/tuskarr/male/tuskarrmale"]                      = 122738,
        ["character/vrykul/male/vrykulmale"]                        = 122815,
    },
    ["HD"] = {
        ["character/scourge/female/scourgefemale"]                  = 997378,
    },
}
local function CleanupModelName(model)
    model = string.lower(model)
    model = string.gsub(model, "\\", "/")
    model = string.gsub(model, "%.m2", "")
    model = string.gsub(model, "%.mdx", "")
    return model
end
function ModelMixins:GetModelFileID()
    local model = self:GetModel()
    if model and type(model) == "string" then
        model = CleanupModelName(model)
        local models = modelToFileID[Utils:GetCurrentModelSet()] or modelToFileID["Original"]
        return models[model] or modelToFileID["Original"][model]
    end
end

LibStub("AceConfig-3.0"):Embed(Addon)

-- Turtle WoW / ClassicAPI expose C_GossipInfo. Map it back to the 1.12 gossip APIs.
if C_GossipInfo then
    if not GetGossipText and C_GossipInfo.GetText then
        GetGossipText = function()
            return C_GossipInfo.GetText()
        end
    end
    if C_GossipInfo.GetNumActiveQuests then
        GetNumGossipActiveQuests = function()
            return C_GossipInfo.GetNumActiveQuests() or 0
        end
    elseif C_GossipInfo.GetActiveQuests then
        GetNumGossipActiveQuests = function()
            local quests = C_GossipInfo.GetActiveQuests()
            return quests and getn(quests) or 0
        end
    end
    if C_GossipInfo.GetNumAvailableQuests then
        GetNumGossipAvailableQuests = function()
            return C_GossipInfo.GetNumAvailableQuests() or 0
        end
    elseif C_GossipInfo.GetAvailableQuests then
        GetNumGossipAvailableQuests = function()
            local quests = C_GossipInfo.GetAvailableQuests()
            return quests and getn(quests) or 0
        end
    end
end

if not GetNumGossipActiveQuests then
    function GetNumGossipActiveQuests()
        if GetGossipActiveQuests then
            return getargn(GetGossipActiveQuests())
        end
        return 0
    end
end
if not GetNumGossipAvailableQuests then
    function GetNumGossipAvailableQuests()
        if GetGossipAvailableQuests then
            return getargn(GetGossipAvailableQuests())
        end
        return 0
    end
end

function RegionOverrides:SetPoint(point, region, relativeFrame, offsetX, offsetY)
    if region == nil and relativeFrame == nil and offsetX == nil and offsetY == nil then
        self:_SetPoint(point, 0, 0)
    else
        self:_SetPoint(point, region, relativeFrame, offsetX, offsetY)
    end
end
function FrameOverrides:SetScript(script, handler)
    if not handler then
        self:_SetScript(script, nil)
        return
    end
    -- Support both 1.12 globals (`this`/`arg1`) and clients that pass (self, ...) as arguments.
    self:_SetScript(script, script == "OnEvent"
        and function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            handler(this or a1, event or a2, arg1 or a3, arg2 or a4, arg3 or a5, arg4 or a6, arg5 or a7, arg6 or a8, arg7 or a9)
        end
        or  function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            handler(this or a1, arg1 or a2, arg2 or a3, arg3 or a4, arg4 or a5, arg5 or a6, arg6 or a7, arg7 or a8, arg8 or a9)
        end)
end
function FrameMixins:HookScript(script, handler)
    local old = self:GetScript(script)
    self:SetScript(script, script == "OnEvent"
        and function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            if old then old(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
            handler(this or a1, event or a2, arg1 or a3, arg2 or a4, arg3 or a5, arg4 or a6, arg5 or a7, arg6 or a8, arg7 or a9)
        end
        or  function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            if old then old(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
            handler(this or a1, arg1 or a2, arg2 or a3, arg3 or a4, arg4 or a5, arg5 or a6, arg6 or a7, arg7 or a8, arg8 or a9)
        end)
end

hooksecurefunc(GameTooltip, "SetOwner", function(self, owner, anchor)
    self = self or this
    if self then
        self._owner = owner
    end
end)
if not GameTooltip.GetOwner then
    function GameTooltip:GetOwner()
        return self._owner
    end
end

function Addon.OnAddonLoad.EQL3() -- Extended Quest Log 3
    QUESTS_DISPLAYED = EQL3_QUESTS_DISPLAYED

    QuestLogFrame = EQL3_QuestLogFrame
    QuestLogListScrollFrame = EQL3_QuestLogListScrollFrame

    function Utils:GetQuestLogTitleFrame(index)
        return _G["EQL3_QuestLogTitle" .. index]
    end

    function Utils:GetQuestLogTitleNormalText(index)
        return _G["EQL3_QuestLogTitle" .. index .. "NormalText"]
    end

    function Utils:GetQuestLogTitleCheck(index)
        return _G["EQL3_QuestLogTitle" .. index .. "Check"]
    end

    -- Hook the new function created by EQL3
    hooksecurefunc("QuestLog_Update", function()
        QuestOverlayUI:Update()
    end)
end

local modelFramePool = {}
function Utils:CreateNPCModelFrame(soundData)
    if soundData.modelFrame then
        return
    end

    local frame
    for _, pooled in ipairs(modelFramePool) do
        if not pooled._inUse then
            frame = pooled
            break
        end
    end

    if not frame then
        frame = CreateFrame("PlayerModel", nil, SoundQueueUI.frame.portrait)
        table.insert(modelFramePool, frame)
    end

    frame._inUse = true
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT")
    frame:SetSize(1, 1)
    frame:Show()
    frame:SetUnit("npc")

    soundData.modelFrame = frame
end
function Utils:FreeNPCModelFrame(soundData)
    local frame = soundData.modelFrame
    if not frame then
        return
    end
    soundData.modelFrame = nil

    if SoundQueueUI.frame.portrait.model == frame then
        SoundQueueUI.frame.portrait.model = SoundQueueUI.frame.portrait.defaultModel
    end

    frame:Hide()
    frame:ClearModel()
    frame._inUse = false
end

function hookModel(self)
    self._sequence = 0
    hooksecurefunc(self, "ClearModel", function(self)
        self._sequence = 0
        self._sequenceStart = nil
    end)
    hooksecurefunc(self, "SetSequence", function(self, sequence)
        self._sequence = sequence
        self._sequenceStart = GetTime()
    end)
    self:HookScript("OnUpdate", function(model, elapsed)
        model = model or this
        if not model then return end
        if model._sequence ~= 0 and model._sequenceStart and model.SetSequenceTime then
            model:SetSequenceTime(model._sequence, (GetTime() - model._sequenceStart) * 1000)
        end
    end)
end

function FrameOverrides:HookScript(script, handler)
    if self:GetScript(script) then
        self:_HookScript(script, handler)
    else
        self:SetScript(script, handler)
    end
end
function FrameOverrides:CreateTexture(name, layer)
    local region = self:_CreateTexture(name, layer)
    ApplyMixinsAndOverrides(region, RegionMixins, RegionOverrides)
    return region
end
function FrameOverrides:CreateFontString(name, layer, template)
    local region = self:_CreateFontString(name, layer, template)
    ApplyMixinsAndOverrides(region, RegionMixins, RegionOverrides)
    ApplyMixinsAndOverrides(region, FontStringMixins)
    return region
end
function FrameOverrides:SetNormalTexture(file)
    local texture = self:CreateTexture(nil, "ARTWORK")
    local success = texture:SetTexture(file)
    texture:SetAllPoints()
    self._normalTexture = texture
    self:_SetNormalTexture(texture)
    return success
end
function FrameMixins:GetNormalTexture()
    return self._normalTexture
end
function FrameOverrides:SetPushedTexture(file)
    local texture = self:CreateTexture(nil, "ARTWORK")
    local success = texture:SetTexture(file)
    texture:SetAllPoints()
    self._pushedTexture = texture
    self:_SetPushedTexture(texture)
    return success
end
function FrameMixins:GetPushedTexture()
    return self._pushedTexture
end
function FrameOverrides:SetDisabledTexture(file)
    local texture = self:CreateTexture(nil, "ARTWORK")
    local success = texture:SetTexture(file)
    texture:SetAllPoints()
    self._disabledTexture = texture
    self:_SetDisabledTexture(texture)
    return success
end
function FrameMixins:GetDisabledTexture()
    return self._disabledTexture
end
function FrameOverrides:SetHighlightTexture(file)
    local texture = self:CreateTexture(nil, "HIGHLIGHT")
    local success = texture:SetTexture(file)
    texture:SetAllPoints()
    self._highlightTexture = texture
    self:_SetHighlightTexture(texture)
    return success
end
function FrameMixins:GetHighlightTexture()
    return self._highlightTexture
end
function FontStringMixins:SetWordWrap(wrap)
    if not wrap then
        self:SetHeight((select(2, self:GetFont())))
    end
end
function ModelMixins:SetCreature()
end

-- Only apply 1.12 workarounds when the client is missing the later Frame API.
-- Overriding SetNormalTexture/SetScript on clients that already have GetNormalTexture/HookScript
-- makes GetNormalTexture() return nil and produces "attempt to index a nil value".
do
    local probe = _G.CreateFrame("Button")
    probe:Hide()
    if probe.GetNormalTexture then
        FrameOverrides.SetNormalTexture = nil
        FrameOverrides.SetPushedTexture = nil
        FrameOverrides.SetDisabledTexture = nil
        FrameOverrides.SetHighlightTexture = nil
        FrameMixins.GetNormalTexture = nil
        FrameMixins.GetPushedTexture = nil
        FrameMixins.GetDisabledTexture = nil
        FrameMixins.GetHighlightTexture = nil
    end
    if probe.HookScript then
        FrameOverrides.SetScript = nil
        FrameOverrides.HookScript = nil
        FrameMixins.HookScript = nil
    end
end

function GameTooltip_Hide()
    -- Used for XML OnLeave handlers
    GameTooltip:Hide()
end
