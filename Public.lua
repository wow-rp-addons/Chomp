--[[
	© Justin Snelgrove
	© Renaud Parize

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

if not __chomp_internal or not __chomp_internal.LOADING then
	return
end

local Internal = __chomp_internal

local DEFAULT_PRIORITY = "MEDIUM"
local PRIORITIES_HASH = { HIGH = true, MEDIUM = true, LOW = true }
local OVERHEAD = 27

local function QueueMessageOut(func, ...)
	if not Internal.OutgoingQueue then
		Internal.OutgoingQueue = {}
	end
	local t = { ... }
	t.f = func
	t.n = select("#", ...)
	local q = Internal.OutgoingQueue
	q[#q + 1] = t
end

function AddOn_Chomp.SendAddonMessage(prefix, text, kind, target, priority, queue, callback, callbackArg)
	if type(prefix) ~= "string" then
		error("AddOn_Chomp.SendAddonMessage(): prefix: expected string, got " .. type(prefix), 2)
	elseif type(text) ~= "string" then
		error("AddOn_Chomp.SendAddonMessage(): text: expected string, got " .. type(text), 2)
	elseif kind == "WHISPER" and type(target) ~= "string" then
		error("AddOn_Chomp.SendAddonMessage(): target: expected string, got " .. type(target), 2)
	elseif kind == "CHANNEL" and type(target) ~= "number" then
		error("AddOn_Chomp.SendAddonMessage(): target: expected number, got " .. type(target), 2)
	elseif target and kind ~= "WHISPER" and kind ~= "CHANNEL" then
		error("AddOn_Chomp.SendAddonMessage(): target: expected nil, got " .. type(target), 2)
	elseif priority and not PRIORITIES_HASH[priority] then
		error("AddOn_Chomp.SendAddonMessage(): priority: expected \"HIGH\", \"MEDIUM\", \"LOW\", or nil, got " .. tostring(priority), 2)
	elseif queue and type(queue) ~= "string" then
		error("AddOn_Chomp.SendAddonMessage(): queue: expected string or nil, got " .. type(queue), 2)
	elseif callback and type(callback) ~= "function" then
		error("AddOn_Chomp.SendAddonMessage(): callback: expected function or nil, got " .. type(callback), 2)
	end

	local length = #text
	if length > 255 then
		error("AddOn_Chomp.SendAddonMessage(): text length cannot exceed 255 bytes", 2)
	elseif #prefix > 16 then
		error("AddOn_Chomp.SendAddonMessage(): prefix: length cannot exceed 16 bytes", 2)
	end
	if not Internal.isReady then
		QueueMessageOut("SendAddonMessage", prefix, text, kind, target, priority, queue, callback, callbackArg)
		return
	end

	if not kind then
		kind = "PARTY"
	else
		kind = kind:upper()
	end
	if target and kind == "WHISPER" then
		target = Ambiguate(target, "none")
	end
	length = length + #prefix + OVERHEAD

	if Internal.ChatThrottleLib and not ChatThrottleLib.isChomp then
		-- CTL likes to drop RAID messages, despite the game falling back
		-- automatically to PARTY.
		if kind == "RAID" and not IsInRaid() then
			kind = "PARTY"
		end
		ChatThrottleLib:SendAddonMessage(PRIORITY_TO_CTL[priority] or "NORMAL", prefix, text, kind, target, queue or ("%s%s%s"):format(prefix, kind, tostring(target) or ""), callback, callbackArg)
		return
	end

	if not Internal.hasQueue and length <= Internal:UpdateBytes() then
		Internal.bytes = Internal.bytes - length
		Internal.isSending = true
		C_ChatInfo.SendAddonMessage(prefix, text, kind, target)
		Internal.isSending = false
		if callback then
			xpcall(callback, geterrorhandler(), callbackArg, true)
		end
		return
	end

	local message = {
		f = C_ChatInfo.SendAddonMessage,
		[1] = prefix,
		[2] = text,
		[3] = kind,
		[4] = target,
		kind = kind,
		length = length,
		callback = callback,
		callbackArg = callbackArg,
	}

	return Internal:Enqueue(priority or DEFAULT_PRIORITY, queue or ("%s%s%s"):format(prefix, kind, (tostring(target) or "")), message)
end

function AddOn_Chomp.SendAddonMessageLogged(prefix, text, kind, target, priority, queue, callback, callbackArg)
	if type(prefix) ~= "string" then
		error("AddOn_Chomp.SendAddonMessageLogged(): prefix: expected string, got " .. type(prefix), 2)
	elseif type(text) ~= "string" then
		error("AddOn_Chomp.SendAddonMessageLogged(): text: expected string, got " .. type(text), 2)
	elseif kind == "WHISPER" and type(target) ~= "string" then
		error("AddOn_Chomp.SendAddonMessageLogged(): target: expected string, got " .. type(target), 2)
	elseif kind == "CHANNEL" and type(target) ~= "number" then
		error("AddOn_Chomp.SendAddonMessageLogged(): target: expected number, got " .. type(target), 2)
	elseif target and kind ~= "WHISPER" and kind ~= "CHANNEL" then
		error("AddOn_Chomp.SendAddonMessageLogged(): target: expected nil, got " .. type(target), 2)
	elseif priority and not PRIORITIES_HASH[priority] then
		error("AddOn_Chomp.SendAddonMessageLogged(): priority: expected \"HIGH\", \"MEDIUM\", \"LOW\", or nil, got " .. tostring(priority), 2)
	elseif queue and type(queue) ~= "string" then
		error("AddOn_Chomp.SendAddonMessageLogged(): queue: expected string or nil, got " .. type(queue), 2)
	elseif callback and type(callback) ~= "function" then
		error("AddOn_Chomp.SendAddonMessageLogged(): callback: expected function or nil, got " .. type(callback), 2)
	end

	local length = #text
	if length > 255 then
		error("AddOn_Chomp.SendAddonMessageLogged(): text length cannot exceed 255 bytes", 2)
	elseif #prefix > 16 then
		error("AddOn_Chomp.SendAddonMessageLogged(): prefix: length cannot exceed 16 bytes", 2)
	end
	if not Internal.isReady then
		QueueMessageOut("SendAddonMessageLogged", prefix, text, kind, target, priority, queue, callback, callbackArg)
		return
	end
	
	if not kind then
		kind = "PARTY"
	else
		kind = kind:upper()
	end
	if target and kind == "WHISPER" then
		target = Ambiguate(target, "none")
	end
	length = length + #prefix + OVERHEAD

	if Internal.ChatThrottleLib and not ChatThrottleLib.isChomp then
		-- CTL likes to drop RAID messages, despite the game falling back
		-- automatically to PARTY.
		if kind == "RAID" and not IsInRaid() then
			kind = "PARTY"
		end
		ChatThrottleLib:SendAddonMessageLogged(PRIORITY_TO_CTL[priority] or "NORMAL", prefix, text, kind, target, queue or ("%s%s%s"):format(prefix, kind, tostring(target) or ""), callback, callbackArg)
		return
	end

	if not Internal.hasQueue and length <= Internal:UpdateBytes() then
		Internal.bytes = Internal.bytes - length
		Internal.isSending = true
		C_ChatInfo.SendAddonMessageLogged(prefix, text, kind, target)
		Internal.isSending = false
		if callback then
			xpcall(callback, geterrorhandler(), callbackArg, true)
		end
		return
	end

	local message = {
		f = C_ChatInfo.SendAddonMessageLogged,
		[1] = prefix,
		[2] = text,
		[3] = kind,
		[4] = target,
		kind = kind,
		length = length,
		callback = callback,
		callbackArg = callbackArg,
	}

	return Internal:Enqueue(priority or DEFAULT_PRIORITY, queue or ("%s%s%s"):format(prefix, kind, (tostring(target) or "")), message)
end

function AddOn_Chomp.SendChatMessage(text, kind, language, target, priority, queue, callback, callbackArg)
	if type(text) ~= "string" then
		error("AddOn_Chomp.SendChatMessage(): text: expected string, got " .. type(text), 2)
	elseif language and type(language) ~= "string" and type(language) ~= "number" then
		error("AddOn_Chomp.SendChatMessage(): language: expected string or number, got " .. type(language), 2)
	elseif kind == "WHISPER" and type(target) ~= "string" then
		error("AddOn_Chomp.SendChatMessage(): target: expected string, got " .. type(target), 2)
	elseif kind == "CHANNEL" and type(target) ~= "number" then
		error("AddOn_Chomp.SendChatMessage(): target: expected number, got " .. type(target), 2)
	elseif target and kind ~= "WHISPER" and kind ~= "CHANNEL" then
		error("AddOn_Chomp.SendChatMessage(): target: expected nil, got " .. type(target), 2)
	elseif priority and not PRIORITIES_HASH[priority] then
		error("AddOn_Chomp.SendChatMessage(): priority: expected \"HIGH\", \"MEDIUM\", \"LOW\", or nil, got " .. tostring(priority), 2)
	elseif queue and type(queue) ~= "string" then
		error("AddOn_Chomp.SendChatMessage(): queue: expected string or nil, got " .. type(queue), 2)
	elseif callback and type(callback) ~= "function" then
		error("AddOn_Chomp.SendChatMessage(): callback: expected function or nil, got " .. type(callback), 2)
	end

	local length = #text
	if length > 255 then
		error("AddOn_Chomp.SendChatMessage(): text length cannot exceed 255 bytes", 2)
	end
	if not Internal.isReady then
		QueueMessageOut("SendChatMessage", text, kind, language, target, priority, queue, callback, callbackArg)
		return
	end

	if not kind then
		kind = "SAY"
	else
		kind = kind:upper()
	end
	if target and kind == "WHISPER" then
		target = Ambiguate(target, "none")
	end
	length = length + OVERHEAD

	if Internal.ChatThrottleLib and not ChatThrottleLib.isChomp then
		-- CTL likes to drop RAID messages, despite the game falling back
		-- automatically to PARTY.
		if kind == "RAID" and not IsInRaid() then
			kind = "PARTY"
		end
		ChatThrottleLib:SendChatMessage(PRIORITY_TO_CTL[priority] or "NORMAL", "Chomp", text, kind, language, target, queue or kind .. (target or ""), callback, callbackArg)
		return
	end

	if not Internal.hasQueue and length <= Internal:UpdateBytes() then
		Internal.bytes = Internal.bytes - length
		Internal.isSending = true
		SendChatMessage(text, kind, language, target)
		Internal.isSending = false
		if callback then
			xpcall(callback, geterrorhandler(), callbackArg, true)
		end
		return
	end

	local message = {
		f = SendChatMessage,
		[1] = text,
		[2] = kind,
		[3] = language,
		[4] = target,
		kind = kind,
		length = length,
		callback = callback,
		callbackArg = callbackArg,
	}

	return Internal:Enqueue(priority or DEFAULT_PRIORITY, queue or kind .. (target or ""), message)
end

function AddOn_Chomp.BNSendGameData(bnetIDGameAccount, prefix, text, priority, queue, callback, callbackArg)
	if type(prefix) ~= "string" then
		error("AddOn_Chomp.BNSendGameData(): prefix: expected string, got " .. type(text), 2)
	elseif type(text) ~= "string" then
		error("AddOn_Chomp.BNSendGameData(): text: expected string, got " .. type(text), 2)
	elseif type(bnetIDGameAccount) ~= "number" then
		error("AddOn_Chomp.BNSendGameData(): bnetIDGameAccount: expected number, got " .. type(bnetIDGameAccount), 2)
	elseif priority and not PRIORITIES_HASH[priority] then
		error("AddOn_Chomp.BNSendGameData(): priority: expected \"HIGH\", \"MEDIUM\", \"LOW\", or nil, got " .. tostring(priority), 2)
	elseif queue and type(queue) ~= "string" then
		error("AddOn_Chomp.BNSendGameData(): queue: expected string or nil, got " .. type(queue), 2)
	elseif callback and type(callback) ~= "function" then
		error("AddOn_Chomp.BNSendGameData(): callback: expected function or nil, got " .. type(callback), 2)
	end

	local length = #text
	if length > 4078 then
		error("AddOn_Chomp.BNSendGameData(): text: length cannot exceed 4078 bytes", 2)
	elseif #prefix > 16 then
		error("AddOn_Chomp.BNSendGameData(): prefix: length cannot exceed 16 bytes", 2)
	end

	if not Internal.isReady then
		QueueMessageOut("BNSendGameData", bnetIDGameAccount, prefix, text, priority, queue, callback, callbackArg)
		return
	end

	length = length + 18 -- 16 byte prefix, 2 byte bnetIDAccount

	if not Internal.hasQueue and length <= Internal:UpdateBytes() then
		Internal.bytes = Internal.bytes - length
		Internal.isSending = true
		BNSendGameData(bnetIDGameAccount, prefix, text)
		Internal.isSending = false
		if callback then
			xpcall(callback, geterrorhandler(), callbackArg, didSend)
		end
		return
	end

	local message = {
		f = BNSendGameData,
		[1] = bnetIDGameAccount,
		[2] = prefix,
		[3] = text,
		length = length,
		callback = callback,
		callbackArg = callbackArg,
	}

	return Internal:Enqueue(priority or DEFAULT_PRIORITY, queue or ("%s%d"):format(prefix, bnetIDGameAccount), message)
end

function AddOn_Chomp.BNSendWhisper(bnetIDAccount, text, priority, queue, callback, callbackArg)
	if type(text) ~= "string" then
		error("AddOn_Chomp.BNSendWhisper(): text: expected string, got " .. type(text), 2)
	elseif type(bnetIDAccount) ~= "number" then
		error("AddOn_Chomp.BNSendWhisper(): bnetIDAccount: expected number, got " .. type(bnetIDAccount), 2)
	elseif priority and not PRIORITIES_HASH[priority] then
		error("AddOn_Chomp.BNSendWhisper(): priority: expected \"HIGH\", \"MEDIUM\", \"LOW\", or nil, got " .. tostring(priority), 2)
	elseif queue and type(queue) ~= "string" then
		error("AddOn_Chomp.BNSendWhisper(): queue: expected string or nil, got " .. type(queue), 2)
	elseif callback and type(callback) ~= "function" then
		error("AddOn_Chomp.BNSendWhisper(): callback: expected function or nil, got " .. type(callback), 2)
	end

	local length = #text
	if length > 997 then
		error("AddOn_Chomp.BNSendWhisper(): text length cannot exceed 997 bytes", 2)
	end

	if not Internal.isReady then
		QueueMessageOut("BNSendWhisper", bnetIDAccount, text, priority, queue, callback, callbackArg)
		return
	end

	length = length + 2 -- 2 byte bnetIDAccount

	if not Internal.hasQueue and length <= Internal:UpdateBytes() then
		Internal.bytes = Internal.bytes - length
		Internal.isSending = true
		BNSendWhisper(bnetIDAccount, text)
		Internal.isSending = false
		if callback then
			xpcall(callback, geterrorhandler(), callbackArg, didSend)
		end
		return
	end

	local message = {
		f = BNSendWhisper,
		[1] = bnetIDAccount,
		[2] = text,
		length = length,
		callback = callback,
		callbackArg = callbackArg,
	}

	return Internal:Enqueue(priority or DEFAULT_PRIORITY, queue or tostring(bnetIDAccount), message)
end

function AddOn_Chomp.IsSending()
	return Internal.isSending
end

local DEFAULT_SETTINGS = {
	fullMsgOnly = true,
	validTypes = {
		["string"] = true,
	},
}
function AddOn_Chomp.RegisterAddonPrefix(prefix, callback, prefixSettings)
	local prefixType = type(prefix)
	if prefixType ~= "string" then
		error("AddOn_Chomp.RegisterAddonPrefix(): prefix: expected string, got " .. prefixType, 2)
	elseif prefixType == "string" and #prefix > 16 then
		error("AddOn_Chomp.RegisterAddonPrefix(): prefix: length cannot exceed 16 bytes", 2)
	elseif type(callback) ~= "function" then
		error("AddOn_Chomp.RegisterAddonPrefix(): callback: expected function, got " .. type(callback), 2)
	elseif prefixSettings and type(prefixSettings) ~= "table" then
		error("AddOn_Chomp.RegisterAddonPrefix(): prefixSettings: expected table or nil, got " .. type(prefixSettings), 2)
	end
	if not prefixSettings then
		prefixSettings = DEFAULT_SETTINGS
	end
	if prefixSettings.validTypes and type(prefixSettings.validTypes) ~= "table" then
		error("AddOn_Chomp.RegisterAddonPrefix(): prefixSettings.validTypes: expected table or nil, got " .. type(prefixSettings.validTypes), 2)
	elseif prefixSettings.rawCallback and type(prefixSettings.rawCallback) ~= "function" then
		error("AddOn_Chomp.RegisterAddonPrefix(): prefixSettings.rawCallback: expected function or nil, got " .. type(prefixSettings.rawCallback), 2)
	end
	local prefixData = Internal.Prefixes[prefix]
	if not prefixData then
		prefixData = {
			callback = callback,
			rawCallback = prefixSettings.rawCallback,
			fullMsgOnly = prefixSettings.fullMsgOnly,
			broadcastPrefix = prefixSettings.broadcastPrefix,
		}
		local validTypes = prefixSettings.validTypes or DEFAULT_SETTINGS.validTypes
		prefixData.validTypes = {}
		for dataType, func in pairs(Internal.Serialize) do
			if validTypes[dataType] then
				prefixData.validTypes[dataType] = true
			end
		end
		Internal.Prefixes[prefix] = prefixData
		if not C_ChatInfo.IsAddonMessagePrefixRegistered(prefix) then
			C_ChatInfo.RegisterAddonMessagePrefix(prefix)
		end
	else
		error("AddOn_Chomp.RegisterAddonPrefix(): prefix handler already registered, Chomp currently supports only one handler per prefix")
	end
end

local function BNGetIDGameAccount(name)
	if not BNFeaturesEnabledAndConnected() then
		return nil
	end
	name = AddOn_Chomp.NameMergedRealm(name)
	for i = 1, select(2, BNGetNumFriends()) do
		for j = 1, BNGetNumFriendGameAccounts(i) do
			local active, characterName, client, realmName, realmID, faction, race, class, blank, zoneName, level, gameText, broadcastText, broadcastTime, isConnected, bnetIDGameAccount = BNGetFriendGameAccountInfo(i, j)
			if isConnected and client == BNET_CLIENT_WOW then
				local realm = realmName and realmName ~= "" and (realmName:gsub("%s*%-*", "")) or nil
				if realm and (not Internal.SameRealm[realm] or faction ~= UnitFactionGroup("player")) and name == AddOn_Chomp.NameMergedRealm(characterName, realm) then
					return bnetIDGameAccount
				end
			end
		end
	end
	return nil
end

local nextSessionID = math.random(0, 4095)
local function SplitAndSend(sendFunc, maxSize, bitField, prefix, text, ...)
	local textLen = #text
	-- Subtract Chomp metadata from maximum size.
	maxSize = maxSize - 12
	local totalOffset = 0
	local msgID = 0
	local totalMsg = math.ceil(textLen / maxSize)
	local sessionID = nextSessionID
	nextSessionID = (nextSessionID + 1) % 4096
	local position = 1
	while position <= textLen do
		-- Only *need* to do a safe substring for encoded channels, but doing so
		-- always shouldn't hurt.
		local msgText, offset = AddOn_Chomp.SafeSubString(text, position, position + maxSize - 1, textLen)
		if offset > 0 then
			-- Update total offset and total message number if needed.
			totalOffset = totalOffset + offset
			totalMsg = math.ceil((textLen + totalOffset) / maxSize)
		end
		msgID = msgID + 1
		msgText = ("%03X%03X%03X%03X%s"):format(bitField, sessionID, msgID, totalMsg, msgText)
		sendFunc(prefix, msgText, ...)
		position = position + maxSize - offset
	end
end

local function ToInGame(bitField, prefix, text, kind, target, priority, queue)
	return SplitAndSend(AddOn_Chomp.SendAddonMessage, 255, bitField, prefix, text, kind, target, priority, queue)
end

local function ToInGameLogged(bitField, prefix, text, kind, target, priority, queue)
	return SplitAndSend(AddOn_Chomp.SendAddonMessageLogged, 255, bitField, prefix, text, kind, target, priority, queue)
end

local function BNSendGameDataRearrange(prefix, text, bnetIDGameAccount, ...)
	return AddOn_Chomp.BNSendGameData(bnetIDGameAccount, prefix, text, ...)
end

local function ToBattleNet(bitField, prefix, text, kind, bnetIDGameAccount, priority)
	return SplitAndSend(BNSendGameDataRearrange, 4078, bitField, prefix, text, bnetIDGameAccount, priority, queue)
end

local DEFAULT_OPTIONS = {}
function AddOn_Chomp.SmartAddonMessage(prefix, data, kind, target, messageOptions)
	local prefixData = Internal.Prefixes[prefix]
	if not prefixData then
		error("AddOn_Chomp.SmartAddonMessage(): prefix: prefix has not been registered with Chomp", 2)
	elseif type(kind) ~= "string" then
		error("AddOn_Chomp.SmartAddonMessage(): kind: expected string, got " .. type(kind), 2)
	elseif kind == "WHISPER" and type(target) ~= "string" then
		error("AddOn_Chomp.SmartAddonMessage(): target: expected string, got " .. type(target), 2)
	elseif kind == "CHANNEL" and type(target) ~= "number" then
		error("AddOn_Chomp.SmartAddonMessage(): target: expected number, got " .. type(target), 2)
	elseif target and kind ~= "WHISPER" and kind ~= "CHANNEL" then
		error("AddOn_Chomp.SmartAddonMessage(): target: expected nil, got " .. type(target), 2)
	end

	if not messageOptions then
		messageOptions = DEFAULT_OPTIONS
	end

	local dataType = type(data)
	if not prefixData.validTypes[dataType] then
		error("AddOn_Chomp.SmartAddonMessage(): data: type not registered as valid: " .. dataType, 2)
	elseif dataType ~= "string" and not messageOptions.serialize then
		error("AddOn_Chomp.SmartAddonMessage(): data: no serialization requested, but serialization required for type: " .. dataType, 2)
	elseif messageOptions.priority and not PRIORITIES_HASH[messageOptions.priority] then
		error("AddOn_Chomp.SmartAddonMessage(): messageOptions.priority: expected \"HIGH\", \"MEDIUM\", or \"LOW\", got " .. tostring(priority), 2)
	elseif messageOptions.queue and type(messageOptions.queue) ~= "string" then
		error("AddOn_Chomp.SmartAddonMessage(): messageOptions.queue: expected string or nil, got " .. type(queue), 2)
	end

	if not Internal.isReady then
		QueueMessageOut("SmartAddonMessage", prefix, data, kind, target, messageOptions)
		return
	end

	local bitField = 0x000
	if messageOptions.serialize then
		bitField = bit.bor(bitField, Internal.BITS.SERIALIZE)
		data = AddOn_Chomp.Serialize(data)
	end
	if not messageOptions.binaryBlob then
		local permitted, reason = AddOn_Chomp.CheckLoggedContents(data)
		if not permitted then
			error(("AddOn_Chomp.SmartAddonMessage(): data: messageOptions.binaryBlob not specified, but disallowed sequences found, code: %s"):format(reason), 2)
		end
	end

	if kind == "WHISPER" then
		target = AddOn_Chomp.NameMergedRealm(target)
	end
	local queue = ("%s%s%s"):format(prefix, kind, tostring(target) or "")

	if kind == "WHISPER" then
		-- BNGetIDGameAccount() only returns an ID for crossfaction and
		-- crossrealm targets.
		local bnetIDGameAccount = BNGetIDGameAccount(target)
		if bnetIDGameAccount then
			ToBattleNet(bitField, prefix, Internal.EncodeQuotedPrintable(data, false), kind, bnetIDGameAccount, messageOptions.priority, messageOptions.queue or queue)
			sentBnet = true
			return "BATTLENET"
		end
		local targetUnit = Ambiguate(target, "none")
		-- Swap the commented line for the one following it to force testing of
		-- broadcast whispers.
		--if prefixData.broadcastPrefix and messageOptions.allowBroadcast and UnitInParty(targetUnit) then
		if prefixData.broadcastPrefix and messageOptions.allowBroadcast and UnitRealmRelationship(targetUnit) == LE_REALM_RELATION_COALESCED then
			bitField = bit.bor(bitField, Internal.BITS.BROADCAST)
			kind = UnitInRaid(targetUnit, LE_PARTY_CATEGORY_HOME) and not UnitInSubgroup(targetUnit, LE_PARTY_CATEGORY_HOME) and "RAID" or UnitInParty(targetUnit, LE_PARTY_CATEGORY_HOME) and "PARTY" or "INSTANCE_CHAT"
			data = ("%s\127%s"):format(not messageOptions.universalBroadcast and AddOn_Chomp.NameMergedRealm(target) or "", data)
			target = nil
			if messageOptions.universalBroadcast then
				queue = nil
			end
		end
	end
	if not messageOptions.binaryBlob then
		ToInGameLogged(bitField, prefix, Internal.EncodeQuotedPrintable(data, true), kind, target, messageOptions.priority, messageOptions.queue or queue)
		sentLogged = true
		return "LOGGED"
	end
	ToInGame(bitField, prefix, data, kind, target, messageOptions.priority, messageOptions.queue or queue)
	sentInGame = true
	return "UNLOGGED"
end

local ReportLocation = CreateFromMixins(PlayerLocationMixin)

function AddOn_Chomp.CheckReportGUID(prefix, guid)
	local prefixData = Internal.Prefixes[prefix]
	if type(prefix) ~= "string" then
		error("AddOn_Chomp.CheckReportGUID(): prefix: expected string, got " .. type(prefix), 2)
	elseif type(guid) ~= "string" then
		error("AddOn_Chomp.CheckReportGUID(): guid: expected string, got " .. type(guid), 2)
	elseif not prefixData then
		error("AddOn_Chomp.CheckReportGUID(): prefix: prefix has not been registered with Chomp", 2)
	end
	local success, class, classID, race, raceID, gender, name, realm = pcall(GetPlayerInfoByGUID, guid)
	if not success or not name or name == UNKNOWN then
		return false, "UNKNOWN"
	end
	local target = AddOn_Chomp.NameMergedRealm(name, realm)
	if BNGetIDGameAccount(target) then
		return false, "BATTLENET"
	end
	ReportLocation:SetGUID(guid)
	local isReportable = C_ChatInfo.CanReportPlayer(ReportLocation)
	return isReportable, "LOGGED"
end

function AddOn_Chomp.ReportGUID(prefix, guid, customMessage)
	local prefixData = Internal.Prefixes[prefix]
	if type(prefix) ~= "string" then
		error("AddOn_Chomp.ReportGUID(): prefix: expected string, got " .. type(prefix), 2)
	elseif customMessage and type(customMessage) ~= "string" then
		error("AddOn_Chomp.ReportGUID(): customMessage: expected string, got " .. type(customMessage), 2)
	elseif type(guid) ~= "string" then
		error("AddOn_Chomp.ReportGUID(): guid: expected string, got " .. type(guid), 2)
	elseif not prefixData then
		error("AddOn_Chomp.ReportGUID(): prefix: prefix has not been registered with Chomp", 2)
	end
	local canReport, reason = AddOn_Chomp.CheckReportGUID(prefix, guid)
	if canReport then
		C_ChatInfo.ReportPlayer(PLAYER_REPORT_TYPE_LANGUAGE, ReportLocation, ("Report for logged addon prefix: %s. %s"):format(prefix, customMessage or "Objectionable content in logged addon messages."))
		return true, reason
	end
	return false, reason
end

function AddOn_Chomp.RegisterErrorCallback(callback)
	if type(callback) ~= "function" then
		error("AddOn_Chomp.RegisterErrorCallback(): callback: expected function, got " .. type(callback), 2)
	end
	for i, checkCallback in ipairs(Internal.ErrorCallbacks) do
		if callback == checkCallback then
			return false
		end
	end
	Internal.ErrorCallbacks[#Internal.ErrorCallbacks + 1] = callback
	return true
end

function AddOn_Chomp.UnegisterErrorCallback(callback)
	if type(callback) ~= "function" then
		error("AddOn_Chomp.UnegisterErrorCallback(): callback: expected function, got " .. type(callback), 2)
	end
	for i, checkCallback in ipairs(Internal.ErrorCallbacks) do
		if callback == checkCallback then
			table.remove(i)
			return true
		end
	end
	return false
end

function AddOn_Chomp.GetBPS()
	return Internal.BPS, Internal.BURST
end

function AddOn_Chomp.SetBPS(bps, burst)
	if type(bps) ~= "number" then
		error("AddOn_Chomp.SetBPS(): bps: expected number, got " .. type(bps), 2)
	elseif type(burst) ~= "number" then
		error("AddOn_Chomp.SetBPS(): burst: expected number, got " .. type(burst), 2)
	end
	Internal.BPS = bps
	Internal.BURST = burst
end

function AddOn_Chomp.GetVersion()
	return Internal.VERSION
end
