--[[
	© Justin Snelgrove
	© Morgane Parize

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

local Chomp = LibStub:GetLibrary("Chomp", true)
local Internal = Chomp and Chomp.Internal or nil

if not Chomp or not Internal or not Internal.LOADING then
	return
end

local DEFAULT_PRIORITY = "MEDIUM"
local PRIORITIES_HASH = { HIGH = true, MEDIUM = true, LOW = true }
local PRIORITY_TO_CTL = { LOW = "BULK", MEDIUM = "NORMAL", HIGH = "ALERT" }
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

function Chomp.SendAddonMessage(prefix, text, kind, target, priority, queue, callback, callbackArg)
	if type(prefix) ~= "string" then
		error("Chomp.SendAddonMessage: prefix: expected string, got " .. type(prefix), 2)
	elseif type(text) ~= "string" then
		error("Chomp.SendAddonMessage: text: expected string, got " .. type(text), 2)
	elseif kind == "WHISPER" and type(target) ~= "string" then
		error("Chomp.SendAddonMessage: target: expected string, got " .. type(target), 2)
	elseif kind == "CHANNEL" and type(target) ~= "number" then
		error("Chomp.SendAddonMessage: target: expected number, got " .. type(target), 2)
	elseif priority and not PRIORITIES_HASH[priority] then
		error("Chomp.SendAddonMessage: priority: expected \"HIGH\", \"MEDIUM\", \"LOW\", or nil, got " .. tostring(priority), 2)
	elseif queue and type(queue) ~= "string" then
		error("Chomp.SendAddonMessage: queue: expected string or nil, got " .. type(queue), 2)
	elseif callback and type(callback) ~= "function" then
		error("Chomp.SendAddonMessage: callback: expected function or nil, got " .. type(callback), 2)
	end

	local length = #text
	if length > 255 then
		error("Chomp.SendAddonMessage: text length cannot exceed 255 bytes", 2)
	elseif #prefix > 16 then
		error("Chomp.SendAddonMessage: prefix: length cannot exceed 16 bytes", 2)
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

	if not Internal:HasQueuedData() and length <= Internal:UpdateBytes() then
		Internal.bytes = Internal.bytes - length
		Internal.isSending = true
		local sendResult = select(-1, C_ChatInfo.SendAddonMessage(prefix, text, kind, target))
		sendResult = Internal:MapToSendAddonMessageResult(sendResult)
		Internal.isSending = false
		if not Internal:IsRetryMessageResult(sendResult) then
			if callback then
				xpcall(callback, CallErrorHandler, callbackArg, true)
			end
			return
		end
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

function Chomp.SendAddonMessageLogged(prefix, text, kind, target, priority, queue, callback, callbackArg)
	if type(prefix) ~= "string" then
		error("Chomp.SendAddonMessageLogged: prefix: expected string, got " .. type(prefix), 2)
	elseif type(text) ~= "string" then
		error("Chomp.SendAddonMessageLogged: text: expected string, got " .. type(text), 2)
	elseif kind == "WHISPER" and type(target) ~= "string" then
		error("Chomp.SendAddonMessageLogged: target: expected string, got " .. type(target), 2)
	elseif kind == "CHANNEL" and type(target) ~= "number" then
		error("Chomp.SendAddonMessageLogged: target: expected number, got " .. type(target), 2)
	elseif priority and not PRIORITIES_HASH[priority] then
		error("Chomp.SendAddonMessageLogged: priority: expected \"HIGH\", \"MEDIUM\", \"LOW\", or nil, got " .. tostring(priority), 2)
	elseif queue and type(queue) ~= "string" then
		error("Chomp.SendAddonMessageLogged: queue: expected string or nil, got " .. type(queue), 2)
	elseif callback and type(callback) ~= "function" then
		error("Chomp.SendAddonMessageLogged: callback: expected function or nil, got " .. type(callback), 2)
	end

	local length = #text
	if length > 255 then
		error("Chomp.SendAddonMessageLogged: text length cannot exceed 255 bytes", 2)
	elseif #prefix > 16 then
		error("Chomp.SendAddonMessageLogged: prefix: length cannot exceed 16 bytes", 2)
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

	if Internal.ChatThrottleLib and not ChatThrottleLib.isChomp and ChatThrottleLib.SendAddonMessageLogged then
		-- CTL likes to drop RAID messages, despite the game falling back
		-- automatically to PARTY.
		if kind == "RAID" and not IsInRaid() then
			kind = "PARTY"
		end
		ChatThrottleLib:SendAddonMessageLogged(PRIORITY_TO_CTL[priority] or "NORMAL", prefix, text, kind, target, queue or ("%s%s%s"):format(prefix, kind, tostring(target) or ""), callback, callbackArg)
		return
	end

	if not Internal:HasQueuedData() and length <= Internal:UpdateBytes() then
		Internal.bytes = Internal.bytes - length
		Internal.isSending = true
		local sendResult = select(-1, C_ChatInfo.SendAddonMessageLogged(prefix, text, kind, target))
		sendResult = Internal:MapToSendAddonMessageResult(sendResult)
		Internal.isSending = false
		if not Internal:IsRetryMessageResult(sendResult) then
			if callback then
				xpcall(callback, CallErrorHandler, callbackArg, true)
			end
			return
		end
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

function Chomp.SendChatMessage(text, kind, language, target, priority, queue, callback, callbackArg)
	if type(text) ~= "string" then
		error("Chomp.SendChatMessage: text: expected string, got " .. type(text), 2)
	elseif language and type(language) ~= "string" and type(language) ~= "number" then
		error("Chomp.SendChatMessage: language: expected string or number, got " .. type(language), 2)
	elseif kind == "WHISPER" and type(target) ~= "string" then
		error("Chomp.SendChatMessage: target: expected string, got " .. type(target), 2)
	elseif kind == "CHANNEL" and type(target) ~= "number" then
		error("Chomp.SendChatMessage: target: expected number, got " .. type(target), 2)
	elseif priority and not PRIORITIES_HASH[priority] then
		error("Chomp.SendChatMessage: priority: expected \"HIGH\", \"MEDIUM\", \"LOW\", or nil, got " .. tostring(priority), 2)
	elseif queue and type(queue) ~= "string" then
		error("Chomp.SendChatMessage: queue: expected string or nil, got " .. type(queue), 2)
	elseif callback and type(callback) ~= "function" then
		error("Chomp.SendChatMessage: callback: expected function or nil, got " .. type(callback), 2)
	end

	local length = #text
	if length > 255 then
		error("Chomp.SendChatMessage: text length cannot exceed 255 bytes", 2)
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

	if not Internal:HasQueuedData() and length <= Internal:UpdateBytes() then
		Internal.bytes = Internal.bytes - length
		Internal.isSending = true
		SendChatMessage(text, kind, language, target)
		Internal.isSending = false
		if callback then
			xpcall(callback, CallErrorHandler, callbackArg, true)
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

function Chomp.BNSendGameData(bnetIDGameAccount, prefix, text, priority, queue, callback, callbackArg)
	if type(prefix) ~= "string" then
		error("Chomp.BNSendGameData: prefix: expected string, got " .. type(text), 2)
	elseif type(text) ~= "string" then
		error("Chomp.BNSendGameData: text: expected string, got " .. type(text), 2)
	elseif type(bnetIDGameAccount) ~= "number" then
		error("Chomp.BNSendGameData: bnetIDGameAccount: expected number, got " .. type(bnetIDGameAccount), 2)
	elseif priority and not PRIORITIES_HASH[priority] then
		error("Chomp.BNSendGameData: priority: expected \"HIGH\", \"MEDIUM\", \"LOW\", or nil, got " .. tostring(priority), 2)
	elseif queue and type(queue) ~= "string" then
		error("Chomp.BNSendGameData: queue: expected string or nil, got " .. type(queue), 2)
	elseif callback and type(callback) ~= "function" then
		error("Chomp.BNSendGameData: callback: expected function or nil, got " .. type(callback), 2)
	end

	local length = #text
	if length > 4078 then
		error("Chomp.BNSendGameData: text: length cannot exceed 4078 bytes", 2)
	elseif #prefix > 16 then
		error("Chomp.BNSendGameData: prefix: length cannot exceed 16 bytes", 2)
	end

	if not Internal.isReady then
		QueueMessageOut("BNSendGameData", bnetIDGameAccount, prefix, text, priority, queue, callback, callbackArg)
		return
	end

	length = length + 18 -- 16 byte prefix, 2 byte bnetIDAccount

	if not Internal:HasQueuedData() and length <= Internal:UpdateBytes() then
		Internal.bytes = Internal.bytes - length
		Internal.isSending = true
		BNSendGameData(bnetIDGameAccount, prefix, text)
		Internal.isSending = false
		if callback then
			xpcall(callback, CallErrorHandler, callbackArg, true)
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

function Chomp.BNSendWhisper(bnetIDAccount, text, priority, queue, callback, callbackArg)
	if type(text) ~= "string" then
		error("Chomp.BNSendWhisper: text: expected string, got " .. type(text), 2)
	elseif type(bnetIDAccount) ~= "number" then
		error("Chomp.BNSendWhisper: bnetIDAccount: expected number, got " .. type(bnetIDAccount), 2)
	elseif priority and not PRIORITIES_HASH[priority] then
		error("Chomp.BNSendWhisper: priority: expected \"HIGH\", \"MEDIUM\", \"LOW\", or nil, got " .. tostring(priority), 2)
	elseif queue and type(queue) ~= "string" then
		error("Chomp.BNSendWhisper: queue: expected string or nil, got " .. type(queue), 2)
	elseif callback and type(callback) ~= "function" then
		error("Chomp.BNSendWhisper: callback: expected function or nil, got " .. type(callback), 2)
	end

	local length = #text
	if length > 997 then
		error("Chomp.BNSendWhisper: text length cannot exceed 997 bytes", 2)
	end

	if not Internal.isReady then
		QueueMessageOut("BNSendWhisper", bnetIDAccount, text, priority, queue, callback, callbackArg)
		return
	end

	length = length + 2 -- 2 byte bnetIDAccount

	if not Internal:HasQueuedData() and length <= Internal:UpdateBytes() then
		Internal.bytes = Internal.bytes - length
		Internal.isSending = true
		BNSendWhisper(bnetIDAccount, text)
		Internal.isSending = false
		if callback then
			xpcall(callback, CallErrorHandler, callbackArg, true)
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

function Chomp.IsSending()
	return Internal.isSending
end

local DEFAULT_SETTINGS = {
	fullMsgOnly = true,
	validTypes = {
		["string"] = true,
	},
}
function Chomp.RegisterAddonPrefix(prefix, callback, prefixSettings)
	local prefixType = type(prefix)
	if prefixType ~= "string" then
		error("Chomp.RegisterAddonPrefix: prefix: expected string, got " .. prefixType, 2)
	elseif prefixType == "string" and #prefix > 16 then
		error("Chomp.RegisterAddonPrefix: prefix: length cannot exceed 16 bytes", 2)
	elseif type(callback) ~= "function" then
		error("Chomp.RegisterAddonPrefix: callback: expected function, got " .. type(callback), 2)
	elseif prefixSettings and type(prefixSettings) ~= "table" then
		error("Chomp.RegisterAddonPrefix: prefixSettings: expected table or nil, got " .. type(prefixSettings), 2)
	end
	if not prefixSettings then
		prefixSettings = DEFAULT_SETTINGS
	end
	if prefixSettings.validTypes and type(prefixSettings.validTypes) ~= "table" then
		error("Chomp.RegisterAddonPrefix: prefixSettings.validTypes: expected table or nil, got " .. type(prefixSettings.validTypes), 2)
	elseif prefixSettings.rawCallback and type(prefixSettings.rawCallback) ~= "function" then
		error("Chomp.RegisterAddonPrefix: prefixSettings.rawCallback: expected function or nil, got " .. type(prefixSettings.rawCallback), 2)
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
		error("Chomp.RegisterAddonPrefix: prefix handler already registered, Chomp currently supports only one handler per prefix")
	end
end

function Chomp.IsAddonPrefixRegistered(prefix)
	return Internal.Prefixes[prefix] ~= nil
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
		local msgText, offset = Chomp.SafeSubString(text, position, position + maxSize - 1, textLen)
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
	return SplitAndSend(Chomp.SendAddonMessage, 255, bitField, prefix, text, kind, target, priority, queue)
end

local function ToInGameLogged(bitField, prefix, text, kind, target, priority, queue)
	return SplitAndSend(Chomp.SendAddonMessageLogged, 255, bitField, prefix, text, kind, target, priority, queue)
end

local function BNSendGameDataRearrange(prefix, text, bnetIDGameAccount, ...)
	return Chomp.BNSendGameData(bnetIDGameAccount, prefix, text, ...)
end

local function ToBattleNet(bitField, prefix, text, kind, bnetIDGameAccount, priority, queue)
	return SplitAndSend(BNSendGameDataRearrange, 4078, bitField, prefix, text, bnetIDGameAccount, priority, queue)
end

local DEFAULT_OPTIONS = {}
function Chomp.SmartAddonMessage(prefix, data, kind, target, messageOptions)
	local prefixData = Internal.Prefixes[prefix]
	if not prefixData then
		error("Chomp.SmartAddonMessage: prefix: prefix has not been registered with Chomp", 2)
	elseif type(kind) ~= "string" then
		error("Chomp.SmartAddonMessage: kind: expected string, got " .. type(kind), 2)
	elseif kind == "WHISPER" and type(target) ~= "string" then
		error("Chomp.SmartAddonMessage: target: expected string, got " .. type(target), 2)
	elseif kind == "CHANNEL" and type(target) ~= "number" then
		error("Chomp.SmartAddonMessage: target: expected number, got " .. type(target), 2)
	elseif target and kind ~= "WHISPER" and kind ~= "CHANNEL" then
		error("Chomp.SmartAddonMessage: target: expected nil, got " .. type(target), 2)
	end

	if not messageOptions then
		messageOptions = DEFAULT_OPTIONS
	end

	local dataType = type(data)
	if not prefixData.validTypes[dataType] then
		error("Chomp.SmartAddonMessage: data: type not registered as valid: " .. dataType, 2)
	elseif dataType ~= "string" and not messageOptions.serialize then
		error("Chomp.SmartAddonMessage: data: no serialization requested, but serialization required for type: " .. dataType, 2)
	elseif messageOptions.priority and not PRIORITIES_HASH[messageOptions.priority] then
		error("Chomp.SmartAddonMessage: messageOptions.priority: expected \"HIGH\", \"MEDIUM\", or \"LOW\", got " .. tostring(messageOptions.priority), 2)
	elseif messageOptions.queue and type(messageOptions.queue) ~= "string" then
		error("Chomp.SmartAddonMessage: messageOptions.queue: expected string or nil, got " .. type(messageOptions.queue), 2)
	end

	if not Internal.isReady then
		QueueMessageOut("SmartAddonMessage", prefix, data, kind, target, messageOptions)
		return
	end

	local bitField = 0x000

	-- v20+: Always set the CODECV2 bit. All clients on the network at this
	--       point should support it. Setting this bit unconditionally will
	--       eventually allow us to deprecate receipt of v1 codec data.
	bitField = bit.bor(bitField, Internal.BITS.VERSION16, Internal.BITS.CODECV2)

	if messageOptions.serialize then
		bitField = bit.bor(bitField, Internal.BITS.SERIALIZE)
		data = Chomp.Serialize(data)
	end
	if not messageOptions.binaryBlob then
		local permitted, reason = Chomp.CheckLoggedContents(data)
		if not permitted then
			error(("Chomp.SmartAddonMessage: data: messageOptions.binaryBlob not specified, but disallowed sequences found, code: %s"):format(reason), 2)
		end
	end

	if kind == "WHISPER" then
		target = Chomp.NameMergedRealm(target)
	end

	local queue = ("%s%s%s"):format(prefix, kind, tostring(target) or "")

	if kind == "WHISPER" then
		-- GetBattleNetAccountID() only returns an ID for crossfaction and
		-- crossrealm targets.
		local bnetIDGameAccount = Internal:GetBattleNetAccountID(target)
		if bnetIDGameAccount then
			ToBattleNet(bitField, prefix, Internal.EncodeQuotedPrintable(data, false), kind, bnetIDGameAccount, messageOptions.priority, messageOptions.queue or queue)
			return "BATTLENET"
		end
		local targetUnit = Ambiguate(target, "none")
		-- Swap the commented line for the one following it to force testing of
		-- broadcast whispers.
		--if prefixData.broadcastPrefix and messageOptions.allowBroadcast and UnitInParty(targetUnit) then
		if prefixData.broadcastPrefix and messageOptions.allowBroadcast and UnitRealmRelationship(targetUnit) == LE_REALM_RELATION_COALESCED then
			bitField = bit.bor(bitField, Internal.BITS.BROADCAST)
			kind = UnitInRaid(targetUnit, LE_PARTY_CATEGORY_HOME) and not UnitInSubgroup(targetUnit, LE_PARTY_CATEGORY_HOME) and "RAID" or UnitInParty(targetUnit, LE_PARTY_CATEGORY_HOME) and "PARTY" or "INSTANCE_CHAT"
			data = ("%s\127%s"):format(not messageOptions.universalBroadcast and Chomp.NameMergedRealm(target) or "", data)
			target = nil
			if messageOptions.universalBroadcast then
				queue = nil
			end
		end
	end
	if not messageOptions.binaryBlob then
		ToInGameLogged(bitField, prefix, Internal.EncodeQuotedPrintable(data, true), kind, target, messageOptions.priority, messageOptions.queue or queue)
		return "LOGGED"
	end
	ToInGame(bitField, prefix, data, kind, target, messageOptions.priority, messageOptions.queue or queue)
	return "UNLOGGED"
end

local ReportLocation = CreateFromMixins(PlayerLocationMixin)

function Chomp.CheckReportGUID(prefix, guid)
	local prefixData = Internal.Prefixes[prefix]
	if type(prefix) ~= "string" then
		error("Chomp.CheckReportGUID: prefix: expected string, got " .. type(prefix), 2)
	elseif type(guid) ~= "string" then
		error("Chomp.CheckReportGUID: guid: expected string, got " .. type(guid), 2)
	elseif not prefixData then
		error("Chomp.CheckReportGUID: prefix: prefix has not been registered with Chomp", 2)
	end
	local success, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
	if not success or not name or name == UNKNOWNOBJECT then
		return false, "UNKNOWN"
	end
	local target = Chomp.NameMergedRealm(name, realm)
	if Internal:GetBattleNetAccountID(target) then
		return false, "BATTLENET"
	end
	ReportLocation:SetGUID(guid)
	if C_ReportSystem then
		return C_ReportSystem.CanReportPlayer(ReportLocation), "LOGGED"
	else
		return C_ChatInfo.CanReportPlayer(ReportLocation), "LOGGED"
	end
end

function Chomp.ReportGUID(prefix, guid, customMessage)
	local prefixData = Internal.Prefixes[prefix]
	if type(prefix) ~= "string" then
		error("Chomp.ReportGUID: prefix: expected string, got " .. type(prefix), 2)
	elseif customMessage and type(customMessage) ~= "string" then
		error("Chomp.ReportGUID: customMessage: expected string, got " .. type(customMessage), 2)
	elseif type(guid) ~= "string" then
		error("Chomp.ReportGUID: guid: expected string, got " .. type(guid), 2)
	elseif not prefixData then
		error("Chomp.ReportGUID: prefix: prefix has not been registered with Chomp", 2)
	end
	local canReport, reason = Chomp.CheckReportGUID(prefix, guid)
	if canReport then
		if C_ReportSystem then
			local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(guid)
			if name and realm then
				C_ReportSystem.OpenReportPlayerDialog(PLAYER_REPORT_TYPE_LANGUAGE, name .. "-" .. realm, ReportLocation)
			end
		else
			C_ChatInfo.ReportPlayer(PLAYER_REPORT_TYPE_LANGUAGE, ReportLocation, ("Report for logged addon prefix: %s. %s"):format(prefix, customMessage or "Objectionable content in logged addon messages."))
		end
		return true, reason
	end
	return false, reason
end

Chomp.Event = CopyValuesAsKeys(
	{
		"OnMessageReceived",
		"OnError",
	}
)

function Chomp.RegisterCallback(event, func, owner)
	if type(event) ~= "string" then
		error("Chomp.RegisterCallback: 'event' must be a string")
	elseif not Chomp.Event[event] then
		error(string.format("Chomp.RegisterCallback: event %q does not exist", event))
	elseif type(func) ~= "function" and type(func) ~= "table" then
		error("Chomp.RegisterCallback: 'func' must be callable")
	elseif type(owner) ~= "string" and type(owner) ~= "table" and type(owner) ~= "thread" then
		error("Chomp.RegisterCallback: 'owner' must be string, table, or coroutine")
	end

	Internal.RegisterCallback(owner, event, function(_, ...) return func(owner, ...) end)
end

function Chomp.UnregisterCallback(event, owner)
	if type(event) ~= "string" then
		error("Chomp.UnregisterCallback: 'event' must be a string")
	elseif not Chomp.Event[event] then
		error(string.format("Chomp.UnregisterCallback: event %q does not exist", event))
	elseif type(owner) ~= "string" and type(owner) ~= "table" and type(owner) ~= "thread" then
		error("Chomp.UnregisterCallback: 'owner' must be string, table, or coroutine")
	end

	Internal.UnregisterCallback(owner, event)
end

function Chomp.UnregisterAllCallbacks(owner)
	if type(owner) ~= "string" and type(owner) ~= "table" and type(owner) ~= "thread" then
		error("Chomp.UnregisterAllCallbacks: 'owner' must be string, table, or coroutine")
	end

	Internal.UnregisterAllCallbacks(owner)
end

function Chomp.RegisterErrorCallback(callback)
	-- v18+: RegisterErrorCallback is deprecated in favor of the generic
	--       RegisterCallback system.

	local event = "OnError"
	local func  = function(_, ...) return callback(...) end
	local owner = tostring(callback)

	Chomp.RegisterCallback(event, func, owner)

	return true
end

function Chomp.UnregisterErrorCallback(callback)
	-- v18+: UnregisterErrorCallback is deprecated in favor of the generic
	--       UnregisterCallback system.

	local event = "OnError"
	local owner = tostring(callback)

	Chomp.UnregisterCallback(event, owner)

	return true
end

-- v18+: Deprecated alias for the old typo'd function name.
Chomp.UnegisterErrorCallback = Chomp.UnregisterErrorCallback

function Chomp.GetBPS()
	return Internal.BPS, Internal.BURST
end

function Chomp.SetBPS(bps, burst)
	if type(bps) ~= "number" then
		error("Chomp.SetBPS: bps: expected number, got " .. type(bps), 2)
	elseif type(burst) ~= "number" then
		error("Chomp.SetBPS: burst: expected number, got " .. type(burst), 2)
	end
	Internal.BPS = bps
	Internal.BURST = burst
end

function Chomp.GetVersion()
	return Internal.VERSION
end
