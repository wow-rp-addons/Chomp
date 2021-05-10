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

local VERSION = 18

if IsLoggedIn() then
	error(("Chomp Message Library (embedded: %s) cannot be loaded after login."):format((...)))
	return
end

local Chomp = LibStub:NewLibrary("Chomp", VERSION)

if not Chomp then
	return
end

Chomp.Internal = Chomp.Internal or __chomp_internal or CreateFrame("Frame")
Chomp.Internal.LOADING = true

local Internal = Chomp.Internal

Internal.callbacks = LibStub:GetLibrary("CallbackHandler-1.0"):New(Internal)

--[[
	CONSTANTS
]]

-- Safe instantaneous burst bytes and safe susatined bytes per second.
-- Lower rates on non-Retail clients due to aggressive throttling.
local BURST, BPS

if WOW_PROJECT_ID == WOW_PROJECT_RETAIL then
	BURST, BPS = 8192, 2048
else
	BURST, BPS = 4000, 800
end

-- These values were safe on 8.0 beta, but are unsafe on 7.3 live. Normally I'd
-- love to automatically use them if 8.0 is live, but it's not 100% clear if
-- this is a 8.0 thing or a test realm thing.
--local BURST, BPS = 16384, 4096
local OVERHEAD = 27

local POOL_TICK = 0.2

local PRIORITIES = { "HIGH", "MEDIUM", "LOW" }

--[[
	INTERNAL TABLES
]]

if not Internal.Filter then
	Internal.Filter = {}
end

if not Internal.Prefixes then
	Internal.Prefixes = {}
end

if Internal.ErrorCallbacks then
	-- v18+: Use CallbackHandler internally; relocate any registered error
	--       callbacks to the registry.

	for _, callback in ipairs(Internal.ErrorCallbacks) do
		local event = "OnError"
		local func  = function(_, ...) return callback(...) end
		local owner = tostring(callback)

		Internal.RegisterCallback(owner, event, func)
	end

	Internal.ErrorCallbacks = nil
end

Internal.BITS = {
	SERIALIZE = 0x001,
	CODECV2   = 0x002,  -- Indicates the message should be processed with codec version 2. Relies upon VERSION16.
	UNUSED9   = 0x004,
	VERSION16 = 0x008,  -- Indicates v16+ of Chomp is in use from the sender.
	BROADCAST = 0x010,
	NOTUSED6  = 0x020,  -- This is unused but won't report as such on receipt; use sparingly!
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

	local bitField, sessionID, msgID, msgTotal, userText = text:match("^(%x%x%x)(%x%x%x)(%x%x%x)(%x%x%x)(.*)$")
	bitField = bitField and tonumber(bitField, 16) or 0
	sessionID = sessionID and tonumber(sessionID, 16) or -1
	msgID = msgID and tonumber(msgID, 16) or 1
	msgTotal = msgTotal and tonumber(msgTotal, 16) or 1

	if userText then
		text = userText
	end

	local codecVersion = Internal:GetCodecVersionFromBitfield(bitField)
	local method = channel:match("%:(%u+)$")
	if method == "BATTLENET" or method == "LOGGED" then
		text = Internal.DecodeQuotedPrintable(text, method == "LOGGED", codecVersion)
	end

	if bit.bor(bitField, Internal.KNOWN_BITS) ~= Internal.KNOWN_BITS or bit.band(bitField, Internal.BITS.DEPRECATE) == Internal.BITS.DEPRECATE then
		-- Uh, found an unknown bit, or a bit we're explicitly not to parse.
		if not oneTimeError then
			oneTimeError = true
			error("Chomp: Received an addon message that cannot be parsed, check your addons for updates. (This message will only display once per session, but there may be more unusable addon messages.)")
		end
		return
	end

	if not prefixData[sender] then
		prefixData[sender] = {}
	end

	local hasVersion16 = bit.band(bitField, Internal.BITS.VERSION16) ~= 0
	if hasVersion16 then
		prefixData[sender].supportsCodecV2 = true
	else
		prefixData[sender].supportsCodecV2 = false
	end

	local isBroadcast = bit.band(bitField, Internal.BITS.BROADCAST) == Internal.BITS.BROADCAST
	if isBroadcast then
		if not prefixData.broadcastPrefix then
			-- If the prefix doesn't want broadcast data, don't even parse
			-- further at all.
			return
		end
		if msgID == 1 then
			local broadcastTarget, broadcastText = text:match("^([^\058\127]*)[\058\127](.*)$")
			local ourName = Chomp.NameMergedRealm(UnitFullName("player"))
			if sender == ourName or broadcastTarget ~= "" and broadcastTarget ~= ourName then
				-- Not for us, quit processing.
				return
			else
				target = ourName
				text = broadcastText
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
		xpcall(prefixData.rawCallback, CallErrorHandler, prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID, nil, nil, nil, sessionID, msgID, msgTotal, bitField)
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
					local success, original = pcall(Chomp.Deserialize, handlerData)
					if success then
						handlerData = original
					else
						handlerData = nil
					end
				end
			end
			if prefixData.validTypes[type(handlerData)] then
				xpcall(prefixData.callback, CallErrorHandler, prefix, handlerData, channel, sender, target, zoneChannelID, localID, name, instanceID, nil, nil, nil, sessionID, msgID, msgTotal, bitField)
				Internal:TriggerEvent("OnMessageReceived", prefix, handlerData, channel, sender, target, zoneChannelID, localID, name, instanceID, nil, nil, nil, sessionID, msgID, msgTotal, bitField)
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
		target = Chomp.NameMergedRealm(target)
	end
	return prefix, text, kind, Chomp.NameMergedRealm(sender), target, zoneChannelID, localID, name, instanceID
end

local function ParseInGameMessageLogged(prefix, text, kind, sender, target, zoneChannelID, localID, name, instanceID)
	if kind == "WHISPER" then
		target = Chomp.NameMergedRealm(target)
	end
	return prefix, text, ("%s:LOGGED"):format(kind), Chomp.NameMergedRealm(sender), target, zoneChannelID, localID, name, instanceID
end

local function ParseBattleNetMessage(prefix, text, kind, bnetIDGameAccount)
	local name = Internal:GetBattleNetAccountName(bnetIDGameAccount)

	if not name then
		return
	end

	return prefix, text, ("%s:BATTLENET"):format(kind), name, Chomp.NameMergedRealm(UnitName("player")), 0, 0, "", 0
end

function Internal:TargetSupportsCodecV2(prefix, target)
	local prefixData = self.Prefixes[prefix]
	local targetData = prefixData and prefixData[target] or nil

	return targetData and targetData.supportsCodecV2 or false
end

function Internal:GetCodecVersionFromBitfield(bitField)
	return (bit.band(bitField, Internal.BITS.CODECV2) ~= 0) and 2 or 1
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
		if self[priority].front then -- Priority has queues.
			active[#active + 1] = self[priority]
		end
	end
	local remaining = #active
	local bytes = self.bytes / remaining
	self.bytes = 0
	for i, priority in ipairs(active) do
		priority.bytes = priority.bytes + bytes
		while priority.front and priority.bytes >= priority.front.front.length do
			local queue = priority:PopFront()
			local message = queue:PopFront()
			if queue.front then -- More messages in this queue.
				priority:PushBack(queue)
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
				xpcall(message.callback, CallErrorHandler, message.callbackArg, didSend)
			end
		end
		if not priority.front then
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
	local bps, burst = self.BPS, self.BURST
	if InCombatLockdown() then
		bps = bps * 0.50
		burst = burst * 0.50
	end

	local now = GetTime()
	local newBytes = (now - self.lastByteUpdate) * bps
	local bytes = math.min(burst, self.bytes + newBytes)
	bytes = math.max(bytes, -bps) -- Probably going to fail anyway.
	self.bytes = bytes
	self.lastByteUpdate = now

	return bytes
end

function Internal:Enqueue(priorityName, queueName, message)
	local priority = self[priorityName]
	local queue = priority.byName[queueName]
	if not queue then
		queue = Mixin({ name = queueName }, DoublyLinkedListMixin)
		priority.byName[queueName] = queue
		priority:PushBack(queue)
	end
	queue:PushBack(message)
	self:StartQueue()
end

Internal.bytes = 0
Internal.lastByteUpdate = GetTime()
Internal.BPS = BPS
Internal.BURST = BURST

for i, priority in ipairs(PRIORITIES) do
	Internal[priority] = Mixin({ bytes = 0, byName = {} }, DoublyLinkedListMixin)
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

function Internal:TriggerEvent(event, ...)
	return self.callbacks:Fire(event, ...)
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
	Internal:TriggerEvent("OnError", name)
	return true
end

local function HookSendAddonMessage(prefix, text, kind, target)
	if kind == "WHISPER" and target then
		Internal.Filter[target] = GetTime() + (select(3, GetNetStats()) * 0.001) + 5.000
	end
	if Internal.isSending then return end
	local prefixLength = math.min(#tostring(prefix), 16)
	local length = math.min(#tostring(text), 255)
	Internal.bytes = Internal.bytes - (length + prefixLength + OVERHEAD)
end

local function HookSendAddonMessageLogged(prefix, text, kind, target)
	if kind == "WHISPER" and target then
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
	BATTLE.NET WRAPPER API
]]

local function PackGameAccountInfo(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17, arg18, arg19, arg20, arg21, arg22)
	return {
		hasFocus       = arg1 ~= 0 and arg or nil,
		characterName  = arg2 ~= "" and arg or nil,
		clientProgram  = arg3,
		realmName      = arg4 ~= "" and arg or nil,
		realmID        = arg5 ~= 0 and arg or nil,
		factionName    = arg6 ~= "" and arg or nil,
		raceName       = arg7 ~= "" and arg or nil,
		className      = arg8 ~= "" and arg or nil,
		areaName       = arg10 ~= "" and arg or nil,
		characterLevel = arg11 ~= "" and arg or nil,
		richPresence   = arg12 ~= "" and arg or nil,
		isOnline       = arg15,
		gameAccountID  = arg16 ~= 0 and arg or nil,
		isGameAFK      = arg18,
		isGameBusy     = arg19,
		playerGuid     = arg20 ~= 0 and arg or nil,
		wowProjectID   = arg21 ~= 0 and arg or nil,
		isWowMobile    = arg22,
	}
end

local function GetFriendNumGameAccounts(friendIndex)
	if C_BattleNet then
		return C_BattleNet.GetFriendNumGameAccounts(friendIndex)
	else
		return BNGetNumFriendGameAccounts(friendIndex)
	end
end

local function GetFriendGameAccountInfo(friendIndex, accountIndex)
	if C_BattleNet then
		return C_BattleNet.GetFriendGameAccountInfo(friendIndex, accountIndex)
	else
		return PackGameAccountInfo(BNGetFriendGameAccountInfo(friendIndex, accountIndex))
	end
end

local function EnumerateFriendGameAccounts()
	local friendIndex  = 0
	local friendCount  = BNGetNumFriends()
	local accountIndex = 0
	local accountCount = 0

	local function NextGameAccount()
		repeat
			accountIndex = accountIndex + 1

			if accountIndex > accountCount then
				friendIndex  = friendIndex + 1
				accountIndex = 1
				accountCount = GetFriendNumGameAccounts(friendIndex)
			end
		until accountIndex <= accountCount or friendIndex > friendCount

		if friendIndex <= friendCount and accountIndex <= accountCount then
			return friendIndex, accountIndex, GetFriendGameAccountInfo(friendIndex, accountIndex)
		end
	end

	return NextGameAccount
end

local function NormalizeRealmName(realmName)
	return (string.gsub(realmName, "[%s-]", ""))
end

local function CanExchangeWithGameAccount(account)
	if not account.isOnline then
		return false  -- Friend isn't even online.
	elseif account.clientProgram ~= BNET_CLIENT_WOW then
		return false  -- Friend isn't playing WoW. Imagine.
	end

	local characterName = account.characterName
	local realmName     = account.realmName and NormalizeRealmName(account.realmName) or nil
	local factionName   = account.factionName

	if not characterName or characterName == "" or characterName == UNKNOWNOBJECT then
		return false  -- Character name is invalid.
	elseif not realmName or realmName == "" then
		return false  -- Realm name is invalid.
	elseif Internal.SameRealm[realmName] and factionName == UnitFactionGroup("player") then
		return false  -- This character is on the same faction and realm.
	else
		return true
	end
end

function Internal:UpdateBattleNetAccountData()
	self.bnetGameAccounts = {}

	if not BNFeaturesEnabledAndConnected() then
		return  -- Player isn't connected to Battle.net.
	elseif not IsLoggedIn() then
		return  -- Player hasn't yet logged in.
	end

	for _, _, account in EnumerateFriendGameAccounts() do
		if CanExchangeWithGameAccount(account) then
			local characterName = account.characterName
			local realmName = string.gsub(account.realmName, "[%s*%-*]", "")
			local mergedName = Chomp.NameMergedRealm(characterName, realmName)

			self.bnetGameAccounts[mergedName] = account.gameAccountID
		end
	end
end

function Internal:GetBattleNetAccountName(senderAccountID)
	if not BNFeaturesEnabledAndConnected() then
		return nil  -- Player isn't connected to Battle.net.
	elseif not self.bnetGameAccounts then
		return nil  -- We have no game accounts to search.
	end

	for playerName, gameAccountID in pairs(self.bnetGameAccounts) do
		if gameAccountID == senderAccountID then
			return playerName
		end
	end

	return nil
end

function Internal:GetBattleNetAccountID(targetName)
	if not BNFeaturesEnabledAndConnected() then
		return nil  -- Player isn't connected to Battle.net.
	elseif not self.bnetGameAccounts then
		return nil  -- We have no game accounts to search.
	end

	for playerName, gameAccountID in pairs(self.bnetGameAccounts) do
		if strcmputf8i(playerName, targetName) == 0 then
			return gameAccountID
		end
	end

	return nil
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
Internal:RegisterEvent("BN_CONNECTED")
Internal:RegisterEvent("BN_DISCONNECTED")
Internal:RegisterEvent("BN_FRIEND_ACCOUNT_OFFLINE")
Internal:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
Internal:RegisterEvent("BN_FRIEND_INFO_CHANGED")
Internal:RegisterEvent("BN_INFO_CHANGED")
Internal:RegisterEvent("FRIENDLIST_UPDATE")

Internal:SetScript("OnEvent", function(self, event, ...)
	if event == "CHAT_MSG_ADDON" then
		HandleMessageIn(ParseInGameMessage(...))
	elseif event == "CHAT_MSG_ADDON_LOGGED" then
		HandleMessageIn(ParseInGameMessageLogged(...))
	elseif event == "BN_CHAT_MSG_ADDON" then
		HandleMessageIn(ParseBattleNetMessage(...))
	elseif event == "BN_CONNECTED"
		or event == "BN_DISCONNECTED"
		or event == "BN_FRIEND_ACCOUNT_OFFLINE"
		or event == "BN_FRIEND_ACCOUNT_ONLINE"
		or event == "BN_FRIEND_INFO_CHANGED"
		or event == "FRIENDLIST_UPDATE" then
		Internal:UpdateBattleNetAccountData()
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
				Chomp[q.f](unpack(q, 1, q.n))
			end
			self.OutgoingQueue = nil
		end
		Internal:UpdateBattleNetAccountData()
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
		Internal:UpdateBattleNetAccountData()
	end
end)

Internal.VERSION = VERSION

-- v18+: The future is now old man. These need to exist for compatibility, and
--       to prevent issues where pre-v18 versions would replace newer ones if
--       __chomp_internal were to just disappear.
--
--       Note that we still clear __chomp_internal once PLAYER_LOGIN has
--       fired, but we don't remove  access to it from the library table
--       because being able to inspect it at runtime is nice.

_G.__chomp_internal = Internal
_G.AddOn_Chomp = Chomp
