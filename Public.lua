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
elseif not __chomp_internal then
	error(("Chomp Message Library (embedded: %s) internals not present, cannot continue loading public API."):format((...)))
elseif __chomp_internal.VERSION > VERSION then
	return
elseif not AddOn_Chomp then
	AddOn_Chomp = {}
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

local PRIORITIES_HASH = { HIGH = true, MEDIUM = true, LOW = true }

--[[
	HELPER FUNCTIONS
]]

local NameWithRealm = Internal.NameWithRealm

local function BNGetIDGameAccount(name)
	-- The second conditional checks for appearing offline. This has to run
	-- after PLAYER_LOGIN, hence Chomp queuing outgoing messages until then.
	if not BNConnected() or not BNGetGameAccountInfoByGUID(UnitGUID("player")) then
		return nil
	end
	name = NameWithRealm(name)
	for i = 1, select(2, BNGetNumFriends()) do
		for j = 1, BNGetNumFriendGameAccounts(i) do
			local active, characterName, client, realmName, realmID, faction, race, class, blank, zoneName, level, gameText, broadcastText, broadcastTime, isConnected, bnetIDGameAccount = BNGetFriendGameAccountInfo(i, j)
			if isConnected and client == BNET_CLIENT_WOW then
				if not realmName or realmName == "" then
					return nil
				elseif name == NameWithRealm(characterName, realmName) then
					return bnetIDGameAccount
				end
			end
		end
	end
	return nil
end

local function QueueMessageOut(func, ...)
	if not Internal.OutgoingQueue then
		Internal.OutgoingQueue = {}
	end
	local q = Internal.OutgoingQueue
	q[#q + 1] = { ..., f = func, n = select("#", ...) }
end

local function SplitAndSend(isEncoded, sendFunc, maxSize, prefix, text, ...)
	local prefixType = type(prefix)
	local textLen = #text
	if textLen <= maxSize then
		local outPrefix = prefixType == "table" and prefix[0] or prefix
		return sendFunc(outPrefix, text, ...)
	end
	local position = 1
	while position <= textLen do
		local offset = 0
		local lastByte, secondLastByte
		if isEncoded then
			lastByte = text:byte(position + maxSize - 1)
			secondLastByte = text:byte(position + maxSize - 2)
			-- 61 is numeric code for "="
			if lastByte == 61 then
				offset = 1
			elseif secondLastByte == 61 then
				offset = 2
			end
		end
		local outPrefix = prefix
		if prefixType == "table" then
			if position == 1 then
				outPrefix = prefix[1]
			elseif position + maxSize - offset > textLen then
				outPrefix = prefix[3]
			else
				outPrefix = prefix[2]
			end
		end
		sendFunc(outPrefix, text:sub(position, position + maxSize - offset - 1), ...)
		position = position + maxSize - offset
	end
end

-- TODO: add pre-send manipulation functions.
local function ToInGame(prefix, text, target, priority, queue)
	return SplitAndSend(false, AddOn_Chomp.SendAddonMessage, 255, prefix, text, "WHISPER", target, priority, queue)
end

local function ToInGameLogged(prefix, text, target, priority, queue)
	return SplitAndSend(true, AddOn_Chomp.SendAddonMessageLogged, 255, prefix, AddOn_Chomp.EncodeQuotedPrintable(text), "WHISPER", target, priority, queue)
end

local function BNSendGameDataRearrange(prefix, text, bnetIDGameAccount, ...)
	return AddOn_Chomp.BNSendGameData(bnetIDGameAccount, prefix, text, ...)
end

local function ToBattleNet(prefix, text, bnetIDGameAccount, priority)
	return SplitAndSend(false, BNSendGameDataRearrange, 4078, prefix, text, bnetIDGameAccount, priority, queue)
end

--[[
	API FUNCTIONS
]]

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

	kind = not kind and "PARTY" or kind:upper()

	local length = #text
	if length > 255 then
		error("AddOn_Chomp.SendAddonMessage(): text length cannot exceed 255 bytes", 2)
	elseif #prefix > 16 then
		error("AddOn_Chomp.SendAddonMessage(): prefix: length cannot exceed 16 bytes", 2)
	end
	if not IsLoggedIn() then
		QueueMessageOut("SendAddonMessage", prefix, text, kind, target, priority, queue, callback, callbackArg)
	end
	
	if target then
		if kind == "WHISPER" then
			target = Ambiguate(target, "none")
		end
		length = length + #tostring(target)
	end
	length = length + 16 + #kind

	if Internal.ChatThrottleLib and not ChatThrottleLib.isChomp then
		-- CTL likes to drop RAID messages, despite the game falling back
		-- automatically to PARTY.
		if kind == "RAID" and not IsInRaid() then
			kind = "PARTY"
		end
		ChatThrottleLib:SendAddonMessage(PRIORITY_TO_CTL[priority] or "NORMAL", prefix, text, kind, target, queue or ("%s%s%s"):format(prefix, kind, tostring(target) or ""), callback, callbackArg)
		return
	end

	local InGame = Internal.Pools.InGame
	if not InGame.hasQueue and length <= InGame:Update() then
		InGame.bytes = InGame.bytes - length
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

	return InGame:Enqueue(priority or DEFAULT_PRIORITY, queue or ("%s%s%s"):format(prefix, kind, (tostring(target) or "")), message)
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

	kind = not kind and "PARTY" or kind:upper()

	local length = #text
	if length > 255 then
		error("AddOn_Chomp.SendAddonMessageLogged(): text length cannot exceed 255 bytes", 2)
	elseif #prefix > 16 then
		error("AddOn_Chomp.SendAddonMessageLogged(): prefix: length cannot exceed 16 bytes", 2)
	end
	if not IsLoggedIn() then
		QueueMessageOut("SendAddonMessageLogged", prefix, text, kind, target, priority, queue, callback, callbackArg)
	end
	
	if target then
		if kind == "WHISPER" then
			target = Ambiguate(target, "none")
		end
		length = length + #tostring(target)
	end
	length = length + 16 + #kind

	if Internal.ChatThrottleLib and not ChatThrottleLib.isChomp then
		-- CTL likes to drop RAID messages, despite the game falling back
		-- automatically to PARTY.
		if kind == "RAID" and not IsInRaid() then
			kind = "PARTY"
		end
		ChatThrottleLib:SendAddonMessageLogged(PRIORITY_TO_CTL[priority] or "NORMAL", prefix, text, kind, target, queue or ("%s%s%s"):format(prefix, kind, tostring(target) or ""), callback, callbackArg)
		return
	end

	local InGame = Internal.Pools.InGame
	if not InGame.hasQueue and length <= InGame:Update() then
		InGame.bytes = InGame.bytes - length
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

	return InGame:Enqueue(priority or DEFAULT_PRIORITY, queue or ("%s%s%s"):format(prefix, kind, (tostring(target) or "")), message)
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
	if not IsLoggedIn() then
		QueueMessageOut("SendChatMessage", text, kind, language, target, priority, queue, callback, callbackArg)
	end
	if kind then
		length = length + #kind
		kind = kind:upper()
	end
	if target then
		if kind == "WHISPER" then
			target = Ambiguate(target, "none")
		end
		length = length + #tostring(target)
	end

	if Internal.ChatThrottleLib and not ChatThrottleLib.isChomp then
		-- CTL likes to drop RAID messages, despite the game falling back
		-- automatically to PARTY.
		if kind == "RAID" and not IsInRaid() then
			kind = "PARTY"
		end
		ChatThrottleLib:SendChatMessage(PRIORITY_TO_CTL[priority] or "NORMAL", "Chomp", text, kind, language, target, queue or kind .. (target or ""), callback, callbackArg)
		return
	end

	local InGame = Internal.Pools.InGame
	if not InGame.hasQueue and length <= InGame:Update() then
		InGame.bytes = InGame.bytes - length
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

	return InGame:Enqueue(priority or DEFAULT_PRIORITY, queue or kind .. (target or ""), message)
end

function AddOn_Chomp.BNSendGameData(bnetIDGameAccount, prefix, text, priority, queue, callback, callbackArg)
	if type(prefix) ~= "string" then
		error("AddOn_Chomp.BNSendGameData(): prefix: expected string, got " .. type(text), 2)
	elseif type(text) ~= "string" then
		error("AddOn_Chomp.BNSendGameData(): text: expected string, got " .. type(text), 2)
	elseif type(bnetIDAccount) ~= "string" then
		error("AddOn_Chomp.BNSendGameData(): bnetIDAccount: expected number, got " .. type(bnetIDAccount), 2)
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

	if not IsLoggedIn() then
		QueueMessageOut("BNSendGameData", bnetIDGameAccount, prefix, text, priority, queue, callback, callbackArg)
	end

	length = length + 18 -- 16 byte prefix, 2 byte bnetIDAccount

	local BattleNet = Internal.Pools.BattleNet
	if not BattleNet.hasQueue and length <= BattleNet:Update() then
		BattleNet.bytes = BattleNet.bytes - length
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

	return BattleNet:Enqueue(priority or DEFAULT_PRIORITY, queue or ("%s%d"):format(prefix, bnetIDGameAccount), message)
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
	if length > 255 then
		error("AddOn_Chomp.BNSendWhisper(): text length cannot exceed 255 bytes", 2)
	end

	if not IsLoggedIn() then
		QueueMessageOut("BNSendWhisper", bnetIDAccount, text, priority, queue, callback, callbackArg)
	end

	length = length + 2 -- 2 byte bnetIDAccount

	local BattleNet = Internal.Pools.BattleNet
	if not BattleNet.hasQueue and length <= BattleNet:Update() then
		BattleNet.bytes = BattleNet.bytes - length
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

	return BattleNet:Enqueue(priority or DEFAULT_PRIORITY, queue or tostring(bnetIDAccount), message)
end

function AddOn_Chomp.EncodeQuotedPrintable(text)
	if type(text) ~= "string" then
		error("AddOn_Chomp.EncodeQuotedPrintable(): text: expected string, got " .. type(text), 2)
	end
	local encodedText = text:gsub("([%c\128-\255=])", function(c)
		return ("=%02X"):format(string.byte(c))
	end)
	return encodedText
end

function AddOn_Chomp.DecodeQuotedPrintable(text)
	if type(text) ~= "string" then
		error("AddOn_Chomp.DecodeQuotedPrintable(): text: expected string, got " .. type(text), 2)
	end
	local decodedText = text:gsub("=(%x%x)", function(b)
		return string.char(tonumber(b, 16))
	end)
	return decodedText
end

function AddOn_Chomp.RegisterAddonPrefix(prefix, callback)
	local prefixType = type(prefix)
	if prefixType ~= "string" and prefixType ~= "table" then
		error("AddOn_Chomp.RegisterAddonPrefix(): prefix: expected string or table, got " .. prefixType, 2)
	elseif prefixType == "table" and not (prefix[0] and prefix[1] and prefix[2] and prefix[3]) then
		error("AddOn_Chomp.RegisterAddonPrefix(): prefix: indicies [0], [1], [2], and [3] required, but some are missing", 2)
	elseif prefixType == "string" and #prefix > 16 then
		error("AddOn_Chomp.RegisterAddonPrefix(): prefix: length cannot exceed 16 bytes", 2)
	elseif prefixType == "table" and (#prefix[0] > 16 or #prefix[1] > 16 or #prefix[2] > 16 or #prefix[3] > 16) then
		error("AddOn_Chomp.RegisterAddonPrefix(): prefix: length of indicies [0], [1], [2], and [3] cannot exceed 16 bytes each", 2)
	elseif type(callback) ~= "function" then
		error("AddOn_Chomp.RegisterAddonPrefix(): callback: expected function, got " .. type(callback), 2)
	end
	local prefixID = prefix
	if prefixType == "table" then
		prefixID = prefix[0]
	end
	local prefixData = Internal.Prefixes[prefixID]
	if not prefixData then
		prefixData = {
			BattleNet = {},
			Logged = {},
			Callbacks = {},
		}
		Internal.Prefixes[prefixID] = prefixData
		if not C_ChatInfo.IsAddonMessagePrefixRegistered(prefixID) then
			C_ChatInfo.RegisterAddonMessagePrefix(prefixID)
		end
	end
	if prefixType == "table" then
		for i = 1, 3 do
			Internal.Prefixes[prefix[i]] = prefixData
			if not C_ChatInfo.IsAddonMessagePrefixRegistered(prefix[i]) then
				C_ChatInfo.RegisterAddonMessagePrefix(prefix[i])
			end
		end
	end
	Internal.PrefixMap[prefix] = prefixData
	prefixData.Callbacks[#prefixData.Callbacks + 1] = callback
end

function AddOn_Chomp.SmartAddonWhisper(prefix, text, target, priority, queue)
	local prefixType = type(prefix)
	local prefixData = Internal.PrefixMap[prefix]
	if prefixType ~= "string" and prefixType ~= "table" then
		error("AddOn_Chomp.SmartAddonWhisper(): prefix: expected string or table, got " .. prefixType, 2)
	elseif type(text) ~= "string" then
		error("AddOn_Chomp.SmartAddonWhisper(): text: expected string, got " .. type(text), 2)
	elseif type(target) ~= "string" then
		error("AddOn_Chomp.SmartAddonWhisper(): target: expected string, got " .. type(target), 2)
	elseif priority and not PRIORITIES_HASH[priority] then
		error("AddOn_Chomp.SmartAddonWhisper(): priority: expected \"HIGH\", \"MEDIUM\", or \"LOW\", got " .. tostring(priority), 2)
	elseif queue and type(queue) ~= "string" then
		error("AddOn_Chomp.SmartAddonWhisper(): queue: expected string or nil, got " .. type(queue), 2)
	elseif not prefixData then
		error("AddOn_Chomp.SmartAddonWhisper(): prefix: prefix has not been registered with Chomp", 2)
	end

	if not IsLoggedIn() then
		QueueMessageOut("SmartAddonWhisper", prefix, text, target, priority, queue)
	end

	target = NameWithRealm(target)
	local bnetCapable = prefixData.BattleNet[target]
	local loggedCapable = prefixData.Logged[target]
	local sentBnet, sentLogged, sentInGame = false, false, false

	local bnetIDGameAccount = BNGetIDGameAccount(target)
	if bnetIDGameAccount and bnetCapable ~= false then
		ToBattleNet(prefix, text, bnetIDGameAccount, priority, queue)
		sentBnet = true
		if bnetCapable == true then
			return sentBnet, false, false
		end
	end
	if loggedCapable ~= false then
		ToInGameLogged(prefix, text, target, priority, queue)
		sentLogged = true
		if loggedCapable == true then
			return sentBnet, sentLogged, false
		end
	end
	ToInGame(prefix, text, target, priority, queue)
	sentInGame = true
	return sentBnet, sentLogged, sentInGame
end

function AddOn_Chomp.GetTargetCapability(prefix, target)
	local prefixType = type(prefix)
	local prefixData = Internal.PrefixMap[prefix]
	if prefixType ~= "string" and prefixType ~= "table" then
		error("AddOn_Chomp.GetTargetCapability(): prefix: expected string or table, got " .. prefixType, 2)
	elseif type(target) ~= "string" then
		error("AddOn_Chomp.GetTargetCapability(): target: expected string, got " .. type(target), 2)
	elseif not prefixData then
		error("AddOn_Chomp.GetTargetCapability(): prefix: prefix has not been registered with Chomp", 2)
	end
	if prefixData.BattleNet[target] then
		return "BattleNet"
	elseif prefixData.Logged[target] then
		return "Logged"
	end
	return "InGame"
end

function AddOn_Chomp.ReportTarget(prefix, target)
	local prefixType = type(prefix)
	local prefixData = Internal.PrefixMap[prefix]
	if prefixType ~= "string" and prefixType ~= "table" then
		error("AddOn_Chomp.ReportTarget(): prefix: expected string or table, got " .. prefixType, 2)
	elseif type(target) ~= "string" then
		error("AddOn_Chomp.ReportTarget(): target: expected string, got " .. type(target), 2)
	elseif not prefixData then
		error("AddOn_Chomp.ReportTarget(): prefix: prefix has not been registered with Chomp", 2)
	elseif prefixData.BattleNet[target] then
		error("AddOn_Chomp.ReportTarget(): target uses BattleNet messages and cannot be reported", 2)
	elseif not prefixData.Logged[target] then
		error("AddOn_Chomp.ReportTarget(): target uses unlogged messages and cannot be reported", 2)
	end
	-- TODO: Report here.
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

function AddOn_Chomp.GetBPS(pool)
	if not Internal.Pools[pool] then
		error("AddOn_Chomp.GetBPS(): pool: expected \"InGame\" or \"BattleNet\", got " .. tostring(pool), 2)
	end
	return Internal.Pools[pool].BPS, Internal.Pools[pool].BURST
end

function AddOn_Chomp.SetBPS(pool, bps, burst)
	if not Internal.Pools[pool] then
		error("AddOn_Chomp.GetBPS(): pool: expected \"InGame\" or \"BattleNet\", got " .. tostring(pool), 2)
	elseif type(bps) ~= "number" then
		error("AddOn_Chomp.SetBPS(): bps: expected number, got " .. type(bps), 2)
	elseif type(burst) ~= "number" then
		error("AddOn_Chomp.SetBPS(): burst: expected number, got " .. type(burst), 2)
	end
	Internal.Pools[pool].BPS = bps
	Internal.Pools[pool].BURST = burst
end

function AddOn_Chomp.GetVersion()
	return Internal.VERSION
end
