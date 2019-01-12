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

local VERSION = 8

if IsLoggedIn() then
	error(("Chomp Message Library (embedded: %s) cannot be loaded after login."):format((...)))
elseif __chomp_internal and (__chomp_internal.VERSION or 0) >= VERSION then
	return
end

if not __chomp_internal then
	__chomp_internal = CreateFrame("Frame")
end

if not AddOn_Chomp then
	AddOn_Chomp = {}
end

__chomp_internal.LOADING = true

local Internal = __chomp_internal

--[[
	CONSTANTS
]]

-- Safe instantaneous burst bytes and safe susatined bytes per second.
local BURST, BPS = 8192, 2048
-- These values were safe on 8.0 beta, but are unsafe on 7.3 live. Normally I'd
-- love to automatically use them if 8.0 is live, but it's not 100% clear if
-- this is a 8.0 thing or a test realm thing.
--local BURST, BPS = 16384, 4096
local OVERHEAD = 27

local POOL_TICK = 0.2

local PRIORITIES = { "HIGH", "MEDIUM", "LOW" }

local PRIORITY_TO_CTL = { LOW = "BULK",  MEDIUM = "NORMAL", HIGH = "ALERT" }

--[[
	INTERNAL TABLES
]]

if not Internal.Filter then
	Internal.Filter = {}
end

if not Internal.Prefixes then
	Internal.Prefixes = {}
end

if not Internal.ErrorCallbacks then
	Internal.ErrorCallbacks = {}
end

Internal.BITS = {
	SERIALIZE = 0x001,
	UNUSEDA   = 0x002,
	UNUSED9   = 0x004,
	UNUSES8   = 0x008,
	BROADCAST = 0x010,
	UNUSED6   = 0x020,
	UNUSED5   = 0x040,
	UNUSED4   = 0x080,
	UNUSED3   = 0x100,
	UNUSED2   = 0x200,
	UNUSED1   = 0x400,
	DEPRECATE = 0x800,
}

Internal.KNOWN_BITS = 0

for purpose, bits in pairs(Internal.BITS) do
	if not purpose:find("UNUSED", nil, true) then
		Internal.KNOWN_BITS = bit.bor(Internal.KNOWN_BITS, bits)
	end
end

--[[
	HELPER FUNCTIONS
]]

local oneTimeError
local function HandleMessageIn(prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID)
	if not Internal.isReady then
		if not Internal.IncomingQueue then
			Internal.IncomingQueue = {}
		end
		local q = Internal.IncomingQueue
		q[#q + 1] = { prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID }
		return
	end

	local prefixData = Internal.Prefixes[prefix]
	if not prefixData then
		return
	end

	local method = channel:match("%:(%u+)$")
	if method == "BATTLENET" or method == "LOGGED" then
		text = Internal.DecodeQuotedPrintable(text, method == "LOGGED")
	end

	local bitField, sessionID, msgID, msgTotal, userText = text:match("^(%x%x%x)(%x%x%x)(%x%x%x)(%x%x%x)(.*)$")
	bitField = bitField and tonumber(bitField, 16) or 0
	sessionID = sessionID and tonumber(sessionID, 16) or -1
	msgID = msgID and tonumber(msgID, 16) or 1
	msgTotal = msgTotal and tonumber(msgTotal, 16) or 1
	if userText then
		text = userText
	end

	if bit.bor(bitField, Internal.KNOWN_BITS) ~= Internal.KNOWN_BITS or bit.band(bitField, Internal.BITS.DEPRECATE) == Internal.BITS.DEPRECATE then
		-- Uh, found an unknown bit, or a bit we're explicitly not to parse.
		if not oneTimeError then
			oneTimeError = true
			error("AddOn_Chomp: Recieved an addon message that cannot be parsed, check your addons for updates. (This message will only display once per session, but there may be more unusable addon messages.)")
		end
		return
	end

	if not prefixData[sender] then
		prefixData[sender] = {}
	end

	local isBroadcast = bit.band(bitField, Internal.BITS.BROADCAST) == Internal.BITS.BROADCAST
	if isBroadcast then
		if not prefixData.broadcastPrefix then
			-- If the prefix doesn't want broadcast data, don't even parse
			-- further at all.
			return
		end
		if msgID == 1 then
			local broadcastTarget, userText = text:match("^([^\058\127]*)[\058\127](.*)$")
			local ourName = AddOn_Chomp.NameMergedRealm(UnitFullName("player"))
			if sender == ourName or broadcastTarget ~= "" and broadcastTarget ~= ourName then
				-- Not for us, quit processing.
				return
			else
				target = ourName
				text = userText
			end
		elseif not prefixData[sender][sessionID] then
			-- Already determined this session ID is not for us, or we came in
			-- somewhere in the middle (and can't determine if it was for us).
			return
		else
			target = prefixData[sender][sessionID].broadcastTarget
		end
		-- Last but not least, fake the channel type.
		channel = channel:gsub("^[^%:]+", "WHISPER")
	end

	if prefixData.rawCallback then
		xpcall(prefixData.rawCallback, geterrorhandler(), prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID, nil, nil, nil, sessionID, msgID, msgTotal, bitField)
	end

	local deserialize = bit.band(bitField, Internal.BITS.SERIALIZE) == Internal.BITS.SERIALIZE
	local fullMsgOnly = prefixData.fullMsgOnly or deserialize

	if not prefixData[sender][sessionID] then
		prefixData[sender][sessionID] = {}
		if isBroadcast then
			prefixData[sender][sessionID].broadcastTarget = target
		end
	end
	local buffer = prefixData[sender][sessionID]
	buffer[msgID] = text

	local runHandler = true
	for i = 1, msgTotal do
		if buffer[i] == nil then
			-- msgTotal has changed, either by virtue of being the first
			-- message or by correction in other side's calculations.
			buffer[i] = true
			runHandler = false
		elseif buffer[i] == true then
			-- Need to hold this message until we're ready to process.
			runHandler = false
		elseif runHandler and buffer[i] and (not fullMsgOnly or i == msgTotal) then
			local handlerData = buffer[i]
			-- This message is ready for processing.
			if fullMsgOnly then
				handlerData = table.concat(buffer)
				if deserialize then
					local success, original = pcall(AddOn_Chomp.Deserialize, handlerData)
					if success then
						handlerData = original
					else
						handlerData = nil
					end
				end
			end
			if prefixData.validTypes[type(handlerData)] then
				xpcall(prefixData.callback, geterrorhandler(), prefix, handlerData, channel, sender, target, zoneChannelID, localID, name, instanceID, nil, nil, nil, sessionID, msgID, msgTotal, bitField)
			end
			buffer[i] = false
			if i == msgTotal then
				-- Tidy up the garbage when we've processed the last
				-- pending message.
				prefixData[sender][sessionID] = nil
			end
		end
	end
end

local function ParseInGameMessage(prefix, text, kind, sender, target, zoneChannelID, localID, name, instanceID)
	if kind == "WHISPER" then
		target = AddOn_Chomp.NameMergedRealm(target)
	end
	return prefix, text, kind, AddOn_Chomp.NameMergedRealm(sender), target, zoneChannelID, localID, name, instanceID
end

local function ParseInGameMessageLogged(prefix, text, kind, sender, target, zoneChannelID, localID, name, instanceID)
	if kind == "WHISPER" then
		target = AddOn_Chomp.NameMergedRealm(target)
	end
	return prefix, text, ("%s:LOGGED"):format(kind), AddOn_Chomp.NameMergedRealm(sender), target, zoneChannelID, localID, name, instanceID
end

local function ParseBattleNetMessage(prefix, text, kind, bnetIDGameAccount)
	local active, characterName, client, realmName = BNGetGameAccountInfo(bnetIDGameAccount)
	-- Build 27144: This can now be nil after removing someone from BattleTag.
	-- Build 28807: This can be an empty string when someone is sending a message when they're offline.
	if not characterName or characterName == "" then
		return
	end
	local name = AddOn_Chomp.NameMergedRealm(characterName, realmName)
	return prefix, text, ("%s:BATTLENET"):format(kind), name, AddOn_Chomp.NameMergedRealm(UnitName("player")), 0, 0, "", 0
end

--[[
	INTERNAL BANDWIDTH POOL
]]

function Internal:RunQueue()
	if self:UpdateBytes() <= 0 then
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
				self.isSending = true
				didSend = message.f(unpack(message, 1, 4)) ~= false
				self.isSending = false
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

function Internal:UpdateBytes()
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

function Internal:Enqueue(priorityName, queueName, message)
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
	self:StartQueue()
end

Internal.bytes = 0
Internal.lastByteUpdate = GetTime()
Internal.BPS = BPS
Internal.BURST = BURST

for i, priority in ipairs(PRIORITIES) do
	Internal[priority] = { bytes = 0, byName = {}, Remove = table.remove, }
end

function Internal:StartQueue()
	if not self.hasQueue then
		self.hasQueue = true
		C_Timer.After(POOL_TICK, self.OnTick)
	end
end

function Internal.OnTick()
	local self = Internal
	if not self.hasQueue then
		return
	end
	self:RunQueue()
	if self.hasQueue then
		C_Timer.After(POOL_TICK, self.OnTick)
	end
end

--[[
	FUNCTION HOOKS
]]

-- Hooks don't trigger if the hooked function errors, so there's no need to
-- check parameters, if those parameters cause errors (which most don't now).

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

local function HookSendAddonMessage(prefix, text, kind, target)
	if kind == "WHISPER" then
		Internal.Filter[target] = GetTime() + (select(3, GetNetStats()) * 0.001) + 5.000
	end
	if Internal.isSending then return end
	local prefixLength = math.min(#tostring(prefix), 16)
	local length = math.min(#tostring(text), 255)
	Internal.bytes = Internal.bytes - (length + prefixLength + OVERHEAD)
end

local function HookSendAddonMessageLogged(prefix, text, kind, target)
	if kind == "WHISPER" then
		Internal.Filter[target] = GetTime() + (select(3, GetNetStats()) * 0.001) + 5.000
	end
	if Internal.isSending then return end
	local prefixLength = math.min(#tostring(prefix), 16)
	local length = math.min(#tostring(text), 255)
	Internal.bytes = Internal.bytes - (length + prefixLength + OVERHEAD)
end

local function HookSendChatMessage(text, kind, language, target)
	if Internal.isSending then return end
	Internal.bytes = Internal.bytes - (#tostring(text) + OVERHEAD)
end

local function HookBNSendGameData(bnetIDGameAccount, prefix, text)
	if Internal.isSending then return end
	local prefixLength = math.min(#tostring(prefix), 16)
	local length = math.min(#tostring(text), 4093 - prefixLength)
	Internal.bytes = Internal.bytes - (length + prefixLength + OVERHEAD)
end

local function HookBNSendWhisper(bnetIDAccount, text)
	if Internal.isSending then return end
	local length = math.min(#tostring(text), 997)
	Internal.bytes = Internal.bytes - (length + OVERHEAD)
end

local function HookC_ClubSendMessage(clubID, streamID, text)
	if Internal.isSending then return end
	local length = #tostring(text)
	Internal.bytes = Internal.bytes - (length + OVERHEAD)
end

local function HookC_ClubEditMessage(clubID, streamID, messageID, text)
	if Internal.isSending then return end
	local length = #tostring(text)
	Internal.bytes = Internal.bytes - (length + OVERHEAD)
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
		hooksecurefunc(C_Club, "SendMessage", HookC_ClubSendMessage)
		hooksecurefunc(C_Club, "EditMessage", HookC_ClubEditMessage)
		ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", MessageEventFilter_SYSTEM)
		self.SameRealm = {}
		self.SameRealm[(GetRealmName():gsub("[%s%-]", ""))] = true
		for i, realm in ipairs(GetAutoCompleteRealms()) do
			self.SameRealm[(realm:gsub("[%s%-]", ""))] = true
		end
		Internal.isReady = true
		if self.IncomingQueue then
			for i, q in ipairs(self.IncomingQueue) do
				HandleMessageIn(unpack(q, 1, 4))
			end
			self.IncomingQueue = nil
		end
		if self.OutgoingQueue then
			for i, q in ipairs(self.OutgoingQueue) do
				AddOn_Chomp[q.f](unpack(q, 1, q.n))
			end
			self.OutgoingQueue = nil
		end
		if self.ChompAPI then
			if IsAddOnLoaded("Blizzard_APIDocumentation") then
				APIDocumentation:AddDocumentationTable(self.ChompAPI)
			else
				self:RegisterEvent("ADDON_LOADED")
			end
		end
	elseif event == "ADDON_LOADED" and ... == "Blizzard_APIDocumentation" then
		APIDocumentation:AddDocumentationTable(self.ChompAPI)
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
end)

Internal.VERSION = VERSION
