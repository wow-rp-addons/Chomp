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

local VERSION = 0

if IsLoggedIn() then
	error(("Chomp Message Library (embedded: %s) cannot be loaded after login."):format((...)))
elseif not __chomp_internal then
	error(("Chomp Message Library (embedded: %s) internals not present, cannot continue loading public API."):format((...)))
elseif (__chomp_internal.VERSION or 0) > VERSION then
	return
elseif not AddOn_Chomp then
	AddOn_Chomp = {}
end

local Internal = __chomp_internal

--[[
	START: 8.0 BACKWARDS COMPATIBILITY
]]

local C_ChatInfo = _G.C_ChatInfo
local xpcall = _G.xpcall
local PlayerLocationMixin = _G.PlayerLocationMixin
if select(4, GetBuildInfo()) < 80000 then

	C_ChatInfo = {
		-- Implementing logged addon messages in 7.3 is pointless, just make it
		-- a no-op.
		SendAddonMessageLogged = function() end,
		SendAddonMessage = _G.SendAddonMessage,
		RegisterAddonMessagePrefix = _G.RegisterAddonMessagePrefix,
		IsAddonMessagePrefixRegistered = _G.IsAddonMessagePrefixRegistered,
		CanReportPlayer = function() return false end,
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

	PlayerLocationMixin = {
		SetGUID = function() end,
	}

end

--[[
	END: 8.0 BACKWARDS COMPATIBILITY
]]

local DEFAULT_PRIORITY = "MEDIUM"
local PRIORITIES_HASH = { HIGH = true, MEDIUM = true, LOW = true }
local OVERHEAD = 24

-- Realm part matching is greedy, as realm names will rarely have dashes, but
-- player names will never.
local FULL_PLAYER_SPLIT = FULL_PLAYER_NAME:gsub("-", "%%%%-"):format("^(.-)", "(.+)$")
local FULL_PLAYER_FIND = FULL_PLAYER_NAME:gsub("-", "%%%%-"):format("^.-", ".+$")
function AddOn_Chomp.NameMergedRealm(name, realm)
	if type(name) ~= "string" then
		error("AddOn_Chomp.NameMergedRealm(): name: expected string, got " .. type(name), 2)
	elseif name == "" then
		error("AddOn_Chomp.NameMergedRealm(): name: expected non-empty string", 2)
	elseif not realm or realm == "" then
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
	elseif name:find(FULL_PLAYER_FIND) then
		error("AddOn_Chomp.NameMergedRealm(): name already has a realm name, but realm name also provided")
	end
	return FULL_PLAYER_NAME:format(name, (realm:gsub("%s*%-*", "")))
end

local function QueueMessageOut(func, ...)
	if not Internal.OutgoingQueue then
		Internal.OutgoingQueue = {}
	end
	local q = Internal.OutgoingQueue
	q[#q + 1] = { ..., f = func, n = select("#", ...) }
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
	if not IsLoggedIn() then
		QueueMessageOut("SendAddonMessage", prefix, text, kind, target, priority, queue, callback, callbackArg)
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
	if not IsLoggedIn() then
		QueueMessageOut("SendAddonMessageLogged", prefix, text, kind, target, priority, queue, callback, callbackArg)
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
	if not IsLoggedIn() then
		QueueMessageOut("SendChatMessage", text, kind, language, target, priority, queue, callback, callbackArg)
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

	if not IsLoggedIn() then
		QueueMessageOut("BNSendGameData", bnetIDGameAccount, prefix, text, priority, queue, callback, callbackArg)
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
	if length > 255 then
		error("AddOn_Chomp.BNSendWhisper(): text length cannot exceed 255 bytes", 2)
	end

	if not IsLoggedIn() then
		QueueMessageOut("BNSendWhisper", bnetIDAccount, text, priority, queue, callback, callbackArg)
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

local Serialize = {}

Serialize["nil"] = function(input)
	return "nil"
end

function Serialize.boolean(input)
	return tostring(input)
end

function Serialize.number(input)
	return tostring(input)
end

function Serialize.string(input)
	return ("%q"):format(input)
end

function Serialize.table(input)
	local t = {}
	t[#t + 1] = "{"
	for K, V in pairs(input) do
		local typeK, typeV = type(K), type(V)
		t[#t + 1] = "["
		if not Serialize[typeK] then
			error("invalid type")
		end
		t[#t + 1] = Serialize[typeK](K)
		t[#t + 1] = "]="
		if not Serialize[typeV] then
			error("invalid type")
		end
		t[#t + 1] = Serialize[typeV](V)
		t[#t + 1] = ","
	end
	t[#t + 1] = "}"
	return table.concat(t)
end

function AddOn_Chomp.Serialize(object)
	local objectType = type(object)
	if not Serialize[type(object)] then
		error("AddOn_Chomp.Serialize(): object: expected serializable type, got " .. objectType, 2)
	end
	local success, serialized = pcall(Serialize[objectType], object)
	if not success then
		error("AddOn_Chomp.Serialize(): object: could not be serialized due to finding unserializable type", 2)
	end
	return serialized
end

local EMPTY_ENV = setmetatable({}, {
	__newindex = function() return end,
	__metatable = false,
})

function AddOn_Chomp.Deserialize(text)
	if type(text) ~= "string" then
		error("AddOn_Chomp.Deserialize(): text: expected string, got " .. type(text), 2)
	end
	local success, func = pcall(loadstring, ("return %s"):format(text))
	if not success then
		error("AddOn_Chomp.Deserialize(): text: could not be loaded via loadstring", 2)
	end
	setfenv(func, EMPTY_ENV)
	local retSuccess, ret = pcall(func)
	if not retSuccess then
		error("AddOn_Chomp.Deserialize(): text: error while reading data", 2)
	elseif not Serialize[type(ret)] then
		error("AddOn_Chomp.Deserialize(): text: deserialized to invalid type: " .. type(ret), 2)
	end
	return ret
end

local function CharToQuotedPrintable(c)
	return ("=%02X"):format(c:byte())
end

local function StringToQuotedPrintable(s)
	return (s:gsub(".", CharToQuotedPrintable))
end

local function TooManyContinuations(s1, s2)
	return s1 .. (s2:gsub(".", CharToQuotedPrintable))
end

function AddOn_Chomp.EncodeQuotedPrintable(text, skipAsciiControl)
	if type(text) ~= "string" then
		error("AddOn_Chomp.EncodeQuotedPrintable(): text: expected string, got " .. type(text), 2)
	end

	-- First, the quoted-printable escape character.
	text = text:gsub("=", CharToQuotedPrintable)

	-- ASCII control characters. \009 and \127 are allowed for some reason.
	if skipAsciiControl then
		text = text:gsub("%z", CharToQuotedPrintable)
	else
		text = text:gsub("[%z\001-\008\010-\031]", CharToQuotedPrintable)
	end

	-- Bytes not used in UTF-8 ever.
	text = text:gsub("[\192\193\245-\255]", CharToQuotedPrintable)

	--- Unicode 11.0.0, Table 3-7 malformed UTF-8 byte sequences.
	text = text:gsub("\224[\128-\159][\128-\191]", StringToQuotedPrintable)
	text = text:gsub("\240[\128-\143][\128-\191][\128-\191]", StringToQuotedPrintable)
	text = text:gsub("\244[\143-\191][\128-\191][\128-\191]", StringToQuotedPrintable)

	-- 2-4-byte leading bytes without enough continuation bytes.
	text = text:gsub("[\194-\244]%f[^\128-\191]", CharToQuotedPrintable)
	-- 3-4-byte leading bytes without enough continuation bytes.
	text = text:gsub("[\224-\244][\128-\191]%f[^\128-\191]", StringToQuotedPrintable)
	-- 4-byte leading bytes without enough continuation bytes.
	text = text:gsub("[\240-\244][\128-\191][\128-\191]%f[^\128-\191]", StringToQuotedPrintable)

	-- Continuation bytes without leading bytes.
	text = text:gsub("%f[\128-\191\194-\244][\128-\191]+", StringToQuotedPrintable)

	-- Multiple leading bytes.
	text = text:gsub("[\194-\244]+[\194-\244]", function(s)
		return (s:gsub(".", CharToQuotedPrintable, #s - 1))
	end)

	-- 2-byte character with too many continuation bytes
	text = text:gsub("([\194-\223][\128-\191])([\128-\191]+)", TooManyContinuations)
	-- 3-byte character with too many continuation bytes
	text = text:gsub("([\224-\239][\128-\191][\128-\191])([\128-\191]+)", TooManyContinuations)
	-- 4-byte character with too many continuation bytes
	text = text:gsub("([\240-\244][\128-\191][\128-\191][\128-\191])([\128-\191]+)", TooManyContinuations)

	return text
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

function AddOn_Chomp.SafeSubString(text, first, last, textLen)
	local offset = 0
	if not textLen then
		textLen = #text
	end
	if textLen > last then
		local b3, b2, b1 = text:byte(last - 2, last)
		-- 61 is numeric code for "="
		if b1 == 61 or (b1 >= 194 and b1 <= 244) then
			offset = 1
		elseif b2 == 61 or (b2 >= 224 and b2 <= 244) then
			offset = 2
		elseif b3 >= 240 and b3 <= 244 then
			offset = 3
		end
	end
	return (text:sub(first, last - offset)), offset
end

local DEFAULT_SETTINGS = {
	permitLogged = true,
	permitBattleNet = true,
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
			permitUnlogged = prefixSettings.permitUnlogged,
			permitLogged = prefixSettings.permitLogged,
			permitBattleNet = prefixSettings.permitBattleNet,
		}
		local validTypes = prefixSettings.validTypes or DEFAULT_SETTINGS.validTypes
		prefixData.validTypes = {}
		for dataType, func in pairs(Serialize) do
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
	-- The second conditional checks for appearing offline. This has to run
	-- after PLAYER_LOGIN, hence Chomp queuing outgoing messages until then.
	if not BNConnected() or not BNGetGameAccountInfoByGUID(UnitGUID("player")) then
		return nil
	end
	name = AddOn_Chomp.NameMergedRealm(name)
	if name == AddOn_Chomp.NameMergedRealm(UnitFullName("player")) then
		return (select(16, BNGetGameAccountInfoByGUID(UnitGUID("player"))))
	end
	for i = 1, select(2, BNGetNumFriends()) do
		for j = 1, BNGetNumFriendGameAccounts(i) do
			local active, characterName, client, realmName, realmID, faction, race, class, blank, zoneName, level, gameText, broadcastText, broadcastTime, isConnected, bnetIDGameAccount = BNGetFriendGameAccountInfo(i, j)
			if isConnected and client == BNET_CLIENT_WOW then
				local realm = realmName and realmName ~= "" and (realmName:gsub("%s*%-*", "")) or nil
				if not realm then
					return nil
				elseif (not Internal.SameRealm[realm] or faction ~= UnitFactionGroup("player")) and name == AddOn_Chomp.NameMergedRealm(characterName, realm) then
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
	elseif type(target) ~= "string" then
		error("AddOn_Chomp.SmartAddonMessage(): target: expected string, got " .. type(target), 2)
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

	if not IsLoggedIn() then
		QueueMessageOut("SmartAddonMessage", prefix, data, kind, target, messageOptions)
	end

	local bitField = 0x000
	if messageOptions.serialize then
		bitField = bit.bor(bitField, Internal.BITS.SERIALIZE)
		data = AddOn_Chomp.Serialize(data)
	end

	target = AddOn_Chomp.NameMergedRealm(target)
	local sentBnet, sentLogged, sentInGame = false, false, false

	if (not messageOptions.forceMethod or messageOptions.forceMethod == "BATTLENET") and prefixData.permitBattleNet and kind == "WHISPER" then
		-- BNGetIDGameAccount() only returns an ID for crossfaction and
		-- crossrealm targets.
		local bnetIDGameAccount = BNGetIDGameAccount(target)
		if bnetIDGameAccount then
			ToBattleNet(bitField, prefix, AddOn_Chomp.EncodeQuotedPrintable(data, true), kind, bnetIDGameAccount, messageOptions.priority, messageOptions.queue)
			sentBnet = true
			return sentBnet, sentLogged, sentInGame
		end
	end
	if (not messageOptions.forceMethod or messageOptions.forceMethod == "LOGGED") and prefixData.permitLogged then
		ToInGameLogged(bitField, prefix, AddOn_Chomp.EncodeQuotedPrintable(data, false), kind, target, messageOptions.priority, messageOptions.queue)
		sentLogged = true
		return sentBnet, sentLogged, sentInGame
	end
	if (not messageOptions.forceMethod or messageOptions.forceMethod == "UNLOGGED") and prefixData.permitUnlogged then
		ToInGame(bitField, prefix, data, kind, target, messageOptions.priority, messageOptions.queue)
		sentInGame = true
		return sentBnet, sentLogged, sentInGame
	end
end

local ReportLocation = CreateFromMixins(PlayerLocationMixin)

function AddOn_Chomp.CheckReportGUID(prefix, guid)
	local prefixData = Internal.Prefixes[prefix]
	if type(prefix) ~= "string" then
		error("AddOn_Chomp.ReportTarget(): prefix: expected string, got " .. type(prefix), 2)
	elseif type(guid) ~= "string" then
		error("AddOn_Chomp.ReportTarget(): guid: expected string, got " .. type(guid), 2)
	elseif not prefixData then
		error("AddOn_Chomp.ReportTarget(): prefix: prefix has not been registered with Chomp", 2)
	end
	local success, class, classID, race, raceID, gender, name, realm = pcall(GetPlayerInfoByGUID, guid)
	if not success then
		return false, "UNKNOWN"
	end
	local target = AddOn_Chomp.NameMergedRealm(name, realm)
	if prefixData.permitBattleNet and BNGetIDGameAccount(target) then
		return false, "BATTLENET"
	elseif prefixData.permitLogged then
		ReportLocation:SetGUID(guid)
		local isReportable = C_ChatInfo.CanReportPlayer(ReportLocation)
		return isReportable, "LOGGED"
	end
	return false, "UNLOGGED"
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
		C_ChatInfo.ReportPlayer(PLAYER_REPORT_TYPE_LANGUAGE, ReportLocation, customMessage or "Objectionable content in logged addon messages.")
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
