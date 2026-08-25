setfenv(1, VoiceOver)

---@class Addon : AceAddon, AceAddon-3.0, AceEvent-3.0, AceTimer-3.0
---@field db VoiceOverConfig|AceDBObject-3.0
Addon = LibStub("AceAddon-3.0"):NewAddon("VoiceOver", "AceEvent-3.0", "AceTimer-3.0")

Addon.OnAddonLoad = {}

---@class VoiceOverConfig
local defaults = {
    profile = {
        SoundQueueUI = {
            LockFrame = false,
            FrameScale = 0.7,
            FrameStrata = "HIGH",
            HidePortrait = false,
            HideFrame = false,
        },
        Audio = {
            GossipFrequency = Enums.GossipFrequency.OncePerQuestNPC,
            SoundChannel = Enums.SoundChannel.Master,
            AutoToggleDialog = true,
            StopAudioOnDisengage = false,
        },
        MinimapButton = {
            LibDBIcon = {}, -- Table used by LibDBIcon to store position (minimapPos), dragging lock (lock) and hidden state (hide)
            Commands = {
                -- References keys from Options.table.args.SlashCommands.args table
                LeftButton = "Options",
                MiddleButton = "PlayPause",
                RightButton = "Clear",
            }
        },
        DebugEnabled = false,
    },
    char = {
        IsPaused = false,
        hasSeenGossipForNPC = {},
        RecentQuestTitleToID = {},
    }
}

local lastGossipOptions
local selectedGossipOption
local currentQuestSoundData
local currentGossipSoundData
local QueueQuestSound

function Addon:OnInitialize()
    local ok, err = pcall(function()
    self.db = LibStub("AceDB-3.0"):New("VoiceOverDB", defaults)
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

    StaticPopupDialogs["VOICEOVER_ERROR"] =
    {
        text = "VoiceOver|n|n%s",
        button1 = OKAY,
        timeout = 0,
        whileDead = 1,
    }

    SoundQueueUI:Initialize()
    DataModules:EnumerateAddons()
    Options:Initialize()

    -- Turtle/ClassicAPI can deliver OnEvent as (self, event) without the 1.12
    -- global `event`, which makes AceEvent silently drop everything. Use a
    -- native frame and accept either calling convention.
    local eventFrame = CreateFrame("Frame", "VoiceOverEventFrame")
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("QUEST_DETAIL")
    eventFrame:RegisterEvent("QUEST_COMPLETE")
    eventFrame:RegisterEvent("QUEST_GREETING")
    eventFrame:RegisterEvent("QUEST_FINISHED")
    eventFrame:RegisterEvent("GOSSIP_SHOW")
    eventFrame:RegisterEvent("GOSSIP_CLOSED")
    eventFrame:SetScript("OnEvent", function(frame, evt, a1)
        evt = evt or event
        a1 = a1 or arg1
        if evt == "ADDON_LOADED" then
            Addon:ADDON_LOADED(evt, a1)
        elseif evt == "QUEST_DETAIL" then
            Addon:QUEST_DETAIL()
        elseif evt == "QUEST_COMPLETE" then
            Addon:QUEST_COMPLETE()
        elseif evt == "QUEST_GREETING" then
            Addon:QUEST_GREETING()
        elseif evt == "QUEST_FINISHED" then
            Addon:QUEST_FINISHED()
        elseif evt == "GOSSIP_SHOW" then
            Addon:GOSSIP_SHOW()
        elseif evt == "GOSSIP_CLOSED" then
            Addon:GOSSIP_CLOSED()
        end
    end)

    if select(5, GetAddOnInfo("VoiceOver")) ~= "MISSING" then
        DisableAddOn("VoiceOver")
        if not self.db.profile.SeenDuplicateDialog then
            StaticPopupDialogs["VOICEOVER_DUPLICATE_ADDON"] =
            {
                text = [[VoiceOver|n|nTo fix the quest autoaccept bugs we had to rename the addon folder. If you're seeing this popup, it means the old one wasn't automatically removed.|n|nYou can safely delete "VoiceOver" from your Addons folder. "AI_VoiceOver" is the new folder.]],
                button1 = OKAY,
                timeout = 0,
                whileDead = 1,
                OnAccept = function()
                    self.db.profile.SeenDuplicateDialog = true
                end,
            }
            StaticPopup_Show("VOICEOVER_DUPLICATE_ADDON")
        end
    end

    if select(5, GetAddOnInfo("AI_VoiceOver_112")) ~= "MISSING" then
        DisableAddOn("AI_VoiceOver_112")
        if not self.db.profile.SeenDuplicateDialog112 then
            StaticPopupDialogs["VOICEOVER_DUPLICATE_ADDON_112"] =
            {
                text = [[VoiceOver|n|nThe old "AI_VoiceOver_112" folder is no longer used.|n|nYou can safely delete "AI_VoiceOver_112" from your Addons folder. "AI_VoiceOver" is the current folder.]],
                button1 = OKAY,
                timeout = 0,
                whileDead = 1,
                OnAccept = function()
                    self.db.profile.SeenDuplicateDialog112 = true
                end,
            }
            StaticPopup_Show("VOICEOVER_DUPLICATE_ADDON_112")
        end
    end

    if not DataModules:HasRegisteredModules() then
        StaticPopupDialogs["VOICEOVER_NO_REGISTERED_DATA_MODULES"] =
        {
            text = [[VoiceOver|n|nNo sound packs were found.|n|nUse the "/vo options" command and go to the DataModules tab for information on where to download sound packs.]],
            button1 = OKAY,
            timeout = 0,
            whileDead = 1,
        }
        StaticPopup_Show("VOICEOVER_NO_REGISTERED_DATA_MODULES")
    end

    local function MakeAbandonQuestHook(field, getFieldData)
        return function()
            local data = getFieldData()
            local soundsToRemove = {}
            for _, soundData in pairs(SoundQueue.sounds) do
                if Enums.SoundEvent:IsQuestEvent(soundData.event) and soundData[field] == data then
                    table.insert(soundsToRemove, soundData)
                end
            end

            for _, soundData in pairs(soundsToRemove) do
                SoundQueue:RemoveSoundFromQueue(soundData)
            end
        end
    end
    if AbandonQuest then
        hooksecurefunc("AbandonQuest", MakeAbandonQuestHook("questName", function() return GetAbandonQuestName() end))
    end

    if QuestLog_Update then
        hooksecurefunc("QuestLog_Update", function()
            local updateOk, updateErr = pcall(QuestOverlayUI.Update, QuestOverlayUI)
            if not updateOk then
                ReportError("QuestLog_Update", updateErr)
            end
        end)
    end

    if SelectGossipOption then
        hooksecurefunc("SelectGossipOption", function(index)
            if lastGossipOptions then
                selectedGossipOption = lastGossipOptions[1 + (index - 1) * 2]
                lastGossipOptions = nil
            end
        end)
    end

    -- QuestHaste and similar auto-accept addons call AcceptQuest() immediately.
    -- Play the accept line from the quest frame even if QUEST_DETAIL was skipped.
    if AcceptQuest then
        hooksecurefunc("AcceptQuest", function()
            local questTitle = GetTitleText and GetTitleText() or ""
            if questTitle == "" then
                return
            end
            local questText = GetQuestText and GetQuestText() or ""
            local targetName = Utils:GetNPCName()
            local questID = DataModules:GetQuestID("accept", questTitle, targetName or "", questText or "")
            QueueQuestSound(Enums.SoundEvent.QuestAccept, questID, questTitle, questText, Utils:GetNPCGUID(), targetName)
        end)
    end

    local moduleCount = 0
    for _ in DataModules:GetModules() do
        moduleCount = moduleCount + 1
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00VoiceOver loaded.|r Sound packs: " .. moduleCount)
    if moduleCount == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555VoiceOver: AI_VoiceOverData_Vanilla did not load. Voiceovers will be silent.|r")
    end
    end)
    if not ok then
        ReportError("OnInitialize", err)
    end
end

function Addon:RefreshConfig()
    SoundQueueUI:RefreshConfig()
end

function Addon:ADDON_LOADED(event, addon)
    addon = addon or arg1 -- Thanks, Ace3v...
    local hook = self.OnAddonLoad[addon]
    if hook then
        hook()
    end
end

local function GossipSoundDataAdded(soundData)
    Utils:CreateNPCModelFrame(soundData)

    -- Save current gossip sound data for dialog/frame sync option
    currentGossipSoundData = soundData
end

local function QuestSoundDataAdded(soundData)
    Utils:CreateNPCModelFrame(soundData)

    -- Save current quest sound data for dialog/frame sync option
    currentQuestSoundData = soundData
end

local GetTitleText = GetTitleText -- Store original function before EQL3 (Extended Quest Log 3) overrides it and starts prepending quest level
function Addon:QUEST_DETAIL()
    local ok, err = pcall(Addon._QUEST_DETAIL, self)
    if not ok then
        ReportError("QUEST_DETAIL", err)
    end
end
function QueueQuestSound(eventType, questID, questTitle, questText, guid, targetName)
    if not questID or questID == 0 then
        return
    end
    if not targetName then
        local _, id = DataModules:GetQuestLogQuestGiverTypeAndID(questID)
        targetName = (id and DataModules:GetObjectName(Enums.GUID.Creature, id)) or "Unknown Name"
    end
    if Addon.db.char.RecentQuestTitleToID then
        Addon.db.char.RecentQuestTitleToID[questTitle or ""] = questID
    end
    SoundQueue:AddSoundToQueue({
        event = eventType,
        questID = questID,
        name = targetName,
        title = questTitle,
        text = questText,
        unitGUID = guid,
        unitIsObjectOrItem = Utils:IsNPCObjectOrItem(),
        addedCallback = QuestSoundDataAdded,
    })
end

function Addon:_QUEST_DETAIL()
    local questTitle = GetTitleText and GetTitleText() or ""
    local questText = GetQuestText and GetQuestText() or ""
    local guid = Utils:GetNPCGUID()
    local targetName = Utils:GetNPCName()
    local questID = GetQuestID()
    if (not questID or questID == 0) and questTitle ~= "" then
        questID = DataModules:GetQuestID("accept", questTitle, targetName or "", questText or "")
    end

    if not questID or questID == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00VoiceOver: could not resolve quest ID for \"" .. tostring(questTitle) .. "\"|r")
        return
    end

    QueueQuestSound(Enums.SoundEvent.QuestAccept, questID, questTitle, questText, guid, targetName)
end

function Addon:QUEST_COMPLETE()
    local ok, err = pcall(Addon._QUEST_COMPLETE, self)
    if not ok then
        ReportError("QUEST_COMPLETE", err)
    end
end
function Addon:_QUEST_COMPLETE()
    local questTitle = GetTitleText and GetTitleText() or ""
    local questText = GetRewardText and GetRewardText() or ""
    local guid = Utils:GetNPCGUID()
    local targetName = Utils:GetNPCName()
    local questID = GetQuestID()
    if (not questID or questID == 0) and questTitle ~= "" then
        questID = DataModules:GetQuestID("complete", questTitle, targetName or "", questText or "")
    end
    QueueQuestSound(Enums.SoundEvent.QuestComplete, questID, questTitle, questText, guid, targetName)
end

function Addon:ShouldPlayGossip(guid, text)
    local npcKey = guid or "unknown"

    local gossipSeenForNPC = self.db.char.hasSeenGossipForNPC[npcKey]

    if self.db.profile.Audio.GossipFrequency == Enums.GossipFrequency.OncePerQuestNPC then
        local numActiveQuests = GetNumGossipActiveQuests()
        local numAvailableQuests = GetNumGossipAvailableQuests()
        local npcHasQuests = (numActiveQuests > 0 or numAvailableQuests > 0)
        if npcHasQuests and gossipSeenForNPC then
            return
        end
    elseif self.db.profile.Audio.GossipFrequency == Enums.GossipFrequency.OncePerNPC then
        if gossipSeenForNPC then
            return
        end
    elseif self.db.profile.Audio.GossipFrequency == Enums.GossipFrequency.Never then
        return
    end

    return true, npcKey
end

function Addon:QUEST_GREETING()
    local guid = Utils:GetNPCGUID()
    local targetName = Utils:GetNPCName()
    local greetingText = GetGreetingText()

    -- Can happen if the player interacted with an NPC while having main menu or options opened
    if not guid and not targetName then
        return
    end

    local play, npcKey = self:ShouldPlayGossip(guid, greetingText)
    if not play then
        return
    end

    -- Play the gossip sound
    ---@type SoundData
    local soundData = {
        event = Enums.SoundEvent.QuestGreeting,
        name = targetName,
        text = greetingText,
        unitGUID = guid,
        unitIsObjectOrItem = Utils:IsNPCObjectOrItem(),
        addedCallback = GossipSoundDataAdded,
        startCallback = function()
            self.db.char.hasSeenGossipForNPC[npcKey] = true
        end
    }
    SoundQueue:AddSoundToQueue(soundData)
end

function Addon:GOSSIP_SHOW()
    local ok, err = pcall(Addon._GOSSIP_SHOW, self)
    if not ok then
        ReportError("GOSSIP_SHOW", err)
    end
end
function Addon:_GOSSIP_SHOW()
    local guid = Utils:GetNPCGUID()
    local targetName = Utils:GetNPCName()
    local gossipText
    if GetGossipText then
        gossipText = GetGossipText()
    elseif C_GossipInfo and C_GossipInfo.GetText then
        gossipText = C_GossipInfo.GetText()
    end

    -- QuestHaste often selects a quest during GOSSIP_SHOW, closing gossip before we run.
    if not gossipText or gossipText == "" then
        return
    end

    -- Can happen if the player interacted with an NPC while having main menu or options opened
    if not guid and not targetName then
        return
    end

    local play, npcKey = self:ShouldPlayGossip(guid, gossipText)
    if not play then
        return
    end

    -- Play the gossip sound
    ---@type SoundData
    local soundData = {
        event = Enums.SoundEvent.Gossip,
        name = targetName,
        title = selectedGossipOption and format([["%s"]], selectedGossipOption),
        text = gossipText,
        unitGUID = guid,
        unitIsObjectOrItem = Utils:IsNPCObjectOrItem(),
        addedCallback = GossipSoundDataAdded,
        startCallback = function()
            self.db.char.hasSeenGossipForNPC[npcKey] = true
        end
    }
    SoundQueue:AddSoundToQueue(soundData)

    selectedGossipOption = nil
    lastGossipOptions = nil
    if GetGossipOptions then
        lastGossipOptions = { GetGossipOptions() }
    end
end

function Addon:QUEST_FINISHED()
    if Addon.db.profile.Audio.StopAudioOnDisengage and currentQuestSoundData then
        SoundQueue:RemoveSoundFromQueue(currentQuestSoundData)
    end
    currentQuestSoundData = nil
end

function Addon:GOSSIP_CLOSED()
    if Addon.db.profile.Audio.StopAudioOnDisengage and currentGossipSoundData then
        SoundQueue:RemoveSoundFromQueue(currentGossipSoundData)
    end
    currentGossipSoundData = nil

    selectedGossipOption = nil
end
