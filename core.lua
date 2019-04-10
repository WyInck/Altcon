------------------------------------------------------------
-- Core.lua
--
-- Abin
-- 2016-10-20
------------------------------------------------------------

local type = type
local pairs = pairs
local ipairs = ipairs
local strmatch = strmatch
local wipe = wipe
local time = time
local format = format
local IsAddOnLoaded = IsAddOnLoaded
local GetContainerNumSlots = GetContainerNumSlots
local GetContainerItemID = GetContainerItemID
local strfind = strfind
local tonumber = tonumber
local IsResting = IsResting
local GetContainerItemLink = GetContainerItemLink
local ClearCursor = ClearCursor
local GetContainerNumSlots = GetContainerNumSlots
local PickupContainerItem = PickupContainerItem
local CursorHasItem = CursorHasItem
local strmatch = strmatch
local GetAverageItemLevel = GetAverageItemLevel

local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local C_Garrison = C_Garrison
local C_ChallengeMode = C_ChallengeMode

local addon = LibAddonManager:CreateAddon(...)
local L = addon.L

addon.RESOURCE_WATCH = {
	{ id = 1580, key = "coin" }, -- 战痕命运印记
	{ id = 1560, key = "resource" }, -- 战争物资
	{ id = 1717, key = "resource2" }, -- 第七军团服役勋章
	{ id = 1718, key = "resource3" }, -- 泰坦残血精华
}

addon:RegisterDB("AltconDB", 1)
addon:RegisterSlashCmd("altcon")

function addon:OnInitialize(db, dbNew, chardb, chardbNew)
	if type(chardb.challenge) ~= "table" then
		chardb.challenge = {}
	end

	chardb.profile = self:GetCurProfileName()
	chardb.class = self.class

	db.currentResetTime = nil
	if not db.weeklyReset then
		db.weeklyReset = LibServerResetTime:GetNextWeeklyResetTime()
	elseif db.weeklyReset <= time() then
		db.weeklyReset = LibServerResetTime:GetNextWeeklyResetTime()
		self:EmptyWeeklyData()
	end

	self:BroadcastEvent("OnInitialize", db, dbNew, chardb, chardbNew)

	LibServerResetTime:RegisterNotify(self)
	self:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
	self:RegisterEvent("BAG_UPDATE", "DelayCheckKeystone")
	self:RegisterEvent("CHALLENGE_MODE_START", "DelayCheckKeystone")
	self:RegisterEvent("CHALLENGE_MODE_COMPLETED")
	self:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
	self:RegisterEvent("CHALLENGE_MODE_MEMBER_INFO_UPDATED", "CHALLENGE_MODE_MAPS_UPDATE")
	self:RegisterEvent("CHALLENGE_MODE_LEADERS_UPDATE", "CHALLENGE_MODE_MAPS_UPDATE")
	self:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED")
	self:RequestChallengeData()
	self:CURRENCY_DISPLAY_UPDATE()
	self:DelayCheckKeystone()
end

function addon:RequestChallengeData()
	C_MythicPlus.RequestRewards()
	C_MythicPlus.RequestMapInfo()
end

function addon:IsDataEmpty(data)
	return not data.research.start and not data.challenge.completed and not data.challenge.key and not data.resource and data ~= self.chardb
end

function addon:CHALLENGE_MODE_MAPS_UPDATE()
	local highest = C_MythicPlus.GetWeeklyChestRewardLevel()
	if highest == 0 then
		highest = nil
	end

	if highest ~= self.chardb.challenge.completed then
		self.chardb.challenge.completed = highest
		self:BroadcastEvent("OnDataUpdate", self.chardb)
	end

	self.chardb.recordedLevel = nil
end

function addon:CHALLENGE_MODE_COMPLETED()
	local _, level = C_ChallengeMode.GetCompletionInfo()
	if level and level > (self.chardb.challenge.completed or 0) then
		self.chardb.challenge.completed = level
		self:BroadcastEvent("OnDataUpdate", self.chardb)
	end
	self:DelayCheckKeystone()
end

function addon:PLAYER_EQUIPMENT_CHANGED()
	local level = GetAverageItemLevel()
	self.chardb.ilevel = format("%.1f", level or 0)
end

function addon:DelayCheckKeystone()
	self:RegisterTick(1)
end

function addon:OnTick()
	self:UnregisterTick()
	self:UpdateKeystone()
end

function addon:CURRENCY_DISPLAY_UPDATE(...)
	local _, data
	for _, data in ipairs(self.RESOURCE_WATCH) do
		local _, amount = GetCurrencyInfo(data.id)
		if amount and amount > 0 then
			self.chardb[data.key] = amount
		else
			self.chardb[data.key] = nil
		end

	end
end

-- Automatically slot the keystone
function addon:CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN()
	local name, level, link, bag, slot = self:GetKeystoneInfo()
	if not name then
		return
	end

	ClearCursor()
	PickupContainerItem(bag, slot)
	if CursorHasItem() then
		C_ChallengeMode.SlotKeystone()
  	end
end

function addon:EmptyWeeklyData(notify)
	--self:Print("Weekly reset time occurred.")
	local profile, data
	for profile, data in pairs(self.db.profiles) do
		if type(data.challenge) == "table" and data.challenge.completed then
			data.recordedLevel = data.challenge.completed
		end
		data.challenge = {}
		self:BroadcastEvent("OnDataUpdate", data)
	end
end

function addon:OnServerReset(key)
	if key == "weekly" then
		self:EmptyWeeklyData(1)
	end
end

function addon:GetDisplayName(profile)
	local name, realm = strmatch(profile, "(.+) %- (.+)")
	if realm == self.realm then
		return name
	end
	return profile
end

function addon:GetDisplayColor(class)
	local data = RAID_CLASS_COLORS[class]
	if data then
		return data.r, data.g, data.b
	end
end

local KEY_PATTERN = "Hkeystone:(%d+):(%d+):(%d+):(.+)%["..gsub(CHALLENGE_MODE_KEYSTONE_NAME, "%%s", "(.+)").."%]"

function addon:GetKeystoneInfo()
	local bag, slot
	for bag = 0, 4 do
    		for slot = 1, GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local _, _, level, _, name = strmatch(link, KEY_PATTERN)
				if level then
					return name, tonumber(level), link, bag, slot
				end
			end
    		end
  	end
end

function addon:UpdateKeystone()
	self.needUpdateKeystone = nil
	local challenge = self.chardb.challenge
	local key, level, link = self:GetKeystoneInfo()
	if key ~= challenge.key or level ~= challenge.level or link ~= challenge.link then
		challenge.key, challenge.level, challenge.link = key, level, link
		self:BroadcastEvent("OnDataUpdate", self.chardb)
		addon:RequestChallengeData()
	end
end
