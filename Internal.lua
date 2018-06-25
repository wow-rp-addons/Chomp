--[[
	© Justin Snelgrove

	Permission to use, copy, modify, and distribute this software for any
	purpose with or without fee is hereby granted, provided that the above
	copyright notice and this permission notice appear in all copies.

	THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
	WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
	MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
	SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
	WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
	OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
	CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
]]

local VERSION = 0

if IsLoggedIn() then
	error(("Chomp Message Library (embedded: %s) cannot be loaded after login."):format((...)))
elseif __chomp_internal and (__chomp_internal.VERSION or 0) > VERSION then
	return
elseif not __chomp_internal then
	__chomp_internal = CreateFrame("Frame")
end

local Internal = __chomp_internal

--[[
	8.0 BACKWARDS COMPATIBILITY
]]

local C_ChatInfo = _G.C_ChatInfo
local xpcall = _G.xpcall
if select(4, GetBuildInfo()) < 80000 then

	C_ChatInfo = {
		-- Implementing logged addon messages in 7.3 is pointless, just make it
		-- a no-op.
		SendAddonMessageLogged = function() end,
		SendAddonMessage = _G.SendAddonMessage,
		RegisterAddonMessagePrefix = _G.RegisterAddonMessagePrefix,
		IsAddonMessagePrefixRegistered = _G.IsAddonMessagePrefixRegistered,
	}

	-- This is ugly and has too much overhead, but won't see much public use.
	-- It's essentially a table.pack()/table.unpack() using upvalues to get
	-- around the restrictions on varargs in closures.
	function xpcall(func, errHandler, ...)
		local n = select("#", ...)
		local args = { ... }
		return _G.xpcall(function()
			func(unpack(args, 1, n))
		end, errHandler)
	end

end

--[[
	CONSTANTS
]]

-- Safe instantaneous burst bytes and safe susatined bytes per second.
local INGAME_BURST, INGAME_BPS = 4130, 1475
local BATTLENET_BURST, BATTLENET_BPS = 8196, 4098

local POOL_TICK = 0.2

local PRIORITIES = { "HIGH", "MEDIUM", "LOW" }

local PRIORITY_TO_CTL = { LOW = "BULK",  MEDIUM = "NORMAL", HIGH = "ALERT" }

-- Realm part matching is greedy, as realm names will rarely have dashes, but
-- player names will never.
local FULL_PLAYER_SPLIT = FULL_PLAYER_NAME:gsub("-", "%%%%-"):format("^(.-)", "(.+)$")

local COMMON_EVENTS = {
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_EMOTE",
	"CHAT_MSG_TEXT_EMOTE",
	"GUILD_ROSTER_UPDATE",
	"GUILD_TRADESKILL_UPDATE",
	"GUILD_RANKS_UPDATE",
	"PLAYER_GUILD_UPDATE",
	"COMPANION_UPDATE",
}

--[[
	INTERNAL TABLES
]]

if not Internal.Filter then
	Internal.Filter = {}
end

if not Internal.Pools then
	Internal.Pools = {}
end

if not Internal.Prefixes then
	Internal.Prefixes = {}
end

if not Internal.PrefixMap then
	Internal.PrefixMap = {}
end

if not Internal.ErrorCallbacks then
	Internal.ErrorCallbacks = {}
end

--[[
	HELPER FUNCTIONS
]]

local function NameWithRealm(name, realm)
	if not realm or realm == "" then
		-- Normally you'd just return the full input name without reformatting,
		-- but Blizzard has started returning an occasional "Name-Realm Name"
		-- combination with spaces and hyphens in the realm name.
		local splitName, splitRealm = name:match(FULL_PLAYER_SPLIT)
		if splitName and splitRealm then
			name = splitName
			realm = splitRealm
		else
			realm = GetRealmName()
		end
	end
	return FULL_PLAYER_NAME:format(name, (realm:gsub("%s*%-*", "")))
end

local function HandleMessageIn(prefix, text, channel, sender, needsBuffering)
	if not IsLoggedIn() then
		if not Internal.IncomingQueue then
			Internal.IncomingQueue = {}
		end
		local q = Internal.IncomingQueue
		q[#q + 1] = { prefix, text, channel, sender, needsBuffering }
		return
	end

	if not Internal.Prefixes[prefix] then
		return
	end

	local prefixData = Internal.Prefixes[prefix]
	if needsBuffering then
		local sessionID, msgID, msgTotal, userText = text:match("^(%x%x%x%x)(%x%x%x%x)(%x%x%x%x)(.*)$")
		sessionID = tonumber(sessionID, 16) or -1
		msgID = tonumber(msgID, 16) or 1
		msgTotal = tonumber(msgTotal, 16) or 1
		if userText then
			text = userText
		end
		if msgTotal > 1 then
			if not prefixData[sender] then
				prefixData[sender] = {}
			end
			if not prefixData[sender][sessionID] then
				prefixData[sender][sessionID] = {}
				local buffer = prefixData[sender][sessionID]
				for i = 1, msgTotal do
					-- true means a message is expected to fill this sequence.
					buffer[i] = true
				end
			end
			local buffer = prefixData[sender][sessionID]
			local callbacks = prefixData.Callbacks
			buffer[msgID] = text
			for i = 1, msgTotal do
				if buffer[i] == true then
					-- Need to hold this message until we're ready to process.
					return
				elseif buffer[i] then
					-- This message is ready for processing.
					for j, func in ipairs(prefixData.Callbacks) do
						xpcall(func, geterrorhandler(), prefix, buffer[i], channel, sender)
					end
					buffer[i] = false
					if i == msgTotal then
						-- Tidy up the garbage when we've processed the last
						-- pending message.
						prefixData[sender][sessionID] = nil
					end
				end
			end
			-- If we have a multi-message sequence, end here.
			return
		end
	end

	for i, func in ipairs(prefixData.Callbacks) do
		xpcall(func, geterrorhandler(), prefix, text, channel, sender)
	end
end

local function ParseInGameMessage(prefix, text, kind, sender)
	return prefix, text, kind, NameWithRealm(sender)
end

local function ParseInGameMessageLogged(prefix, text, kind, sender)
	local name = NameWithRealm(sender)
	if Internal.Prefixes[prefix] then
		Internal.Prefixes[prefix].Logged[name] = true
	end
	return prefix, AddOn_Chomp.DecodeQuotedPrintable(text), ("%s:LOGGED"):format(kind), name
end

local function ParseBattleNetMessage(prefix, text, kind, bnetIDGameAccount)
	local active, characterName, client, realmName = BNGetGameAccountInfo(bnetIDGameAccount)
	local name = NameWithRealm(characterName, realmName)
	if Internal.Prefixes[prefix] then
		Internal.Prefixes[prefix].BattleNet[name] = true
	end
	return prefix, text, ("%s:BATTLENET"):format(kind), name, true
end

--[[
	POOLS (INGAME/BATTLENET)
]]

local function PoolRun(self)
	if self:Update() <= 0 then
		return
	end
	local active = {}
	for i, priority in ipairs(PRIORITIES) do
		if self[priority][1] then -- Priority has queues.
			active[#active + 1] = self[priority]
		end
	end
	local remaining = #active
	local bytes = self.bytes / remaining
	self.bytes = 0
	for i, priority in ipairs(active) do
		priority.bytes = priority.bytes + bytes
		while priority[1] and priority.bytes >= priority[1][1].length do
			local queue = priority:Remove(1)
			local message = queue:Remove(1)
			if queue[1] then -- More messages in this queue.
				priority[#priority + 1] = queue
			else -- No more messages in this queue.
				priority.byName[queue.name] = nil
			end
			local didSend = false
			if (message.kind ~= "RAID" and message.kind ~= "PARTY" or IsInGroup(LE_PARTY_CATEGORY_HOME)) and (message.kind ~= "INSTANCE_CHAT" or IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) then
				priority.bytes = priority.bytes - message.length
				Internal.isSending = true
				didSend = message.f(unpack(message, 1, 4)) ~= false
				Internal.isSending = false
			end
			if message.callback then
				xpcall(message.callback, geterrorhandler(), message.callbackArg, didSend)
			end
		end
		if not priority[1] then
			remaining = remaining - 1
			self.bytes = self.bytes + priority.bytes
			priority.bytes = 0
		end
	end
	if remaining == 0 then
		self.hasQueue = nil
	end
end

local function PoolBytesUpdate(self)
	local BPS, BURST = self.BPS, self.BURST
	if InCombatLockdown() then
		BPS = BPS * 0.50
		BURST = BURST * 0.50
	end

	local now = GetTime()
	local newBytes = (now - self.lastByteUpdate) * BPS
	local bytes = math.min(BURST, self.bytes + newBytes)
	bytes = math.max(bytes, -BPS) -- Probably going to fail anyway.
	self.bytes = bytes
	self.lastByteUpdate = now

	return bytes
end

local function PoolEnqueue(self, priorityName, queueName, message)
	local priority = self[priorityName]
	local queue = priority.byName[queueName]
	if not queue then
		queue = {
			name = queueName,
			Remove = table.remove,
		}
		priority.byName[queueName] = queue
		priority[#priority + 1] = queue
	end
	queue[#queue + 1] = message
	self.hasQueue = true
	Internal.Pools:Start()
end

local function CreatePool(burst, bps)
	local pool = {
		bytes = 0,
		lastByteUpdate = GetTime(),
		BPS = bps,
		BURST = burst,
		Run = PoolRun,
		Update = PoolBytesUpdate,
		Enqueue = PoolEnqueue,
	}
	for i, priority in ipairs(PRIORITIES) do
		pool[priority] = { bytes = 0, byName = {}, Remove = table.remove, }
	end
	return pool
end

function Internal.Pools:Start()
	if not self.isActive then
		self.isActive = true
		C_Timer.After(POOL_TICK, self.OnTick)
	end
end

function Internal.Pools:RunPool(poolName)
	if self[poolName].hasQueue then
		self[poolName]:Run()
		if self[poolName].hasQueue then
			self.isActive = true
		end
	end
end

function Internal.Pools.OnTick()
	local self = Internal.Pools
	if not self.isActive then
		return
	end
	self.isActive = false
	self:RunPool("InGame")
	self:RunPool("BattleNet")
	if self.isActive then
		C_Timer.After(POOL_TICK, self.OnTick)
	end
end

--[[
	FUNCTION HOOKS
]]

-- Hooks don't trigger if the hooked function errors, so there's no need to
-- check parameters.

local function MessageEventFilter_SYSTEM (self, event, text)
	local name = text:match(ERR_CHAT_PLAYER_NOT_FOUND_S:format("(.+)"))
	if not name then
		return false
	elseif not Internal.Filter[name] or Internal.Filter[name] < GetTime() then
		Internal.Filter[name] = nil
		return false
	end
	for i, func in ipairs(Internal.ErrorCallbacks) do
		xpcall(func, geterrorhandler(), name)
	end
	return true
end

local function HookRestartGx()
	if GetCVar("gxWindow") == "0" then
		for i, event in ipairs(COMMON_EVENTS) do
			Internal:RegisterEvent(event)
		end
		Internal:Show()
	else
		for i, event in ipairs(COMMON_EVENTS) do
			Internal:UnregisterEvent(event)
		end
		Internal:Hide()
	end
end

local function HookSendAddonMessage(prefix, text, kind, target)
	if kind == "WHISPER" then
		Internal.Filter[target] = GetTime() + (select(3, GetNetStats()) * 0.001) + 5.000
	end
	if Internal.isSending then return end
	Internal.Pools.InGame.bytes = Internal.Pools.InGame.bytes - (#tostring(text) + #kind + 16 + (target and #tostring(target) or 0))
end

local function HookSendAddonMessageLogged(prefix, text, kind, target)
	if kind == "WHISPER" then
		Internal.Filter[target] = GetTime() + (select(3, GetNetStats()) * 0.001) + 5.000
	end
	if Internal.isSending then return end
	Internal.Pools.InGame.bytes = Internal.Pools.InGame.bytes - (#tostring(text) + #kind + 16 + (target and #tostring(target) or 0))
end

local function HookSendChatMessage(text, kind, language, target)
	if Internal.isSending then return end
	Internal.Pools.InGame.bytes = Internal.Pools.InGame.bytes - (#tostring(text) + (kind and #kind or 0) + (target and #tostring(target) or 0))
end

local function HookBNSendGameData(bnetIDGameAccount, prefix, text)
	if Internal.isSending then return end
	Internal.Pools.BattleNet.bytes = Internal.Pools.BattleNet.bytes - (#tostring(text) + 18)
end

local function HookBNSendWhisper(bnetIDAccount, text)
	if Internal.isSending then return end
	Internal.Pools.BattleNet.bytes = Internal.Pools.BattleNet.bytes - (#tostring(text) + 2)
end

--[[
	FRAME SCRIPTS
]]

Internal:Hide()
Internal:RegisterEvent("CHAT_MSG_ADDON")
Internal:RegisterEvent("CHAT_MSG_ADDON_LOGGED")
Internal:RegisterEvent("BN_CHAT_MSG_ADDON")
Internal:RegisterEvent("PLAYER_LOGIN")
Internal:RegisterEvent("PLAYER_LEAVING_WORLD")
Internal:RegisterEvent("PLAYER_ENTERING_WORLD")

Internal:SetScript("OnEvent", function(self, event, ...)
	if event == "CHAT_MSG_ADDON" then
		HandleMessageIn(ParseInGameMessage(...))
	elseif event == "CHAT_MSG_ADDON_LOGGED" then
		HandleMessageIn(ParseInGameMessageLogged(...))
	elseif event == "BN_CHAT_MSG_ADDON" then
		HandleMessageIn(ParseBattleNetMessage(...))
	elseif event == "PLAYER_LOGIN" then
		_G.__chomp_internal = nil
		hooksecurefunc(C_ChatInfo, "SendAddonMessage", HookSendAddonMessage)
		hooksecurefunc(C_ChatInfo, "SendAddonMessageLogged", HookSendAddonMessageLogged)
		hooksecurefunc("SendChatMessage", HookSendChatMessage)
		hooksecurefunc("BNSendGameData", HookBNSendGameData)
		hooksecurefunc("BNSendWhisper", HookBNSendWhisper)
		ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", MessageEventFilter_SYSTEM)
		hooksecurefunc("RestartGx", HookRestartGx)
		HookRestartGx()
		self.Pools.InGame = CreatePool(INGAME_BURST, INGAME_BPS)
		self.Pools.BattleNet = CreatePool(BATTLENET_BURST, BATTLENET_BPS)
		if self.IncomingQueue then
			for i, q in ipairs(self.IncomingQueue) do
				HandleMessageIn(table.unpack(q, 1, 4))
			end
			self.IncomingQueue = nil
		end
		if self.OutgoingQueue then
			for i, q in ipairs(self.OutgoingQueue) do
				AddOn_Chomp[q.f](table.unpack(q, 1, q.n))
			end
			self.OutgoingQueue = nil
		end
		if self.ChompAPIDoc then
			if IsAddOnLoaded("Blizzard_APIDocumentation") then
				APIDocumentation:AddDocumentationTable(self.ChompAPIDoc)
			else
				self:RegisterEvent("ADDON_LOADED")
			end
		end
	elseif event == "ADDON_LOADED" and ... == "Blizzard_APIDocumentation" then
		APIDocumentation:AddDocumentationTable(self.ChompAPIDoc)
	elseif event == "PLAYER_LEAVING_WORLD" then
		self.unloadTime = GetTime()
	elseif event == "PLAYER_ENTERING_WORLD" and self.unloadTime then
		local loadTime = GetTime() - self.unloadTime
		for name, filterTime in pairs(self.Filter) do
			if filterTime >= self.unloadTime then
				self.Filter[name] = filterTime + loadTime
			else
				self.Filter[name] = nil
			end
		end
		self.unloadTime = nil
	end
	if self:IsVisible() and self.lastDraw < GetTime() - 5 then
		if self.Pools.isActive then
			self.Pools.OnTick()
		end
		if self.ChatThrottleLib then
			local f = ChatThrottleLib.Frame
			if f:IsVisible() then
				f:GetScript("OnUpdate")(f, 0.10)
			end
		end
	end
end)

Internal:SetScript("OnUpdate", function(self, elapsed)
	self.lastDraw = self.lastDraw + elapsed
end)

Internal:SetScript("OnShow", function(self)
	self.lastDraw = GetTime()
end)

Internal.NameWithRealm = NameWithRealm
Internal.VERSION = VERSION
