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

local Chomp = LibStub:GetLibrary("Chomp", true)
local Internal = Chomp and Chomp.Internal or nil

if not Chomp or not Internal or not Internal.LOADING then
	return
end

-- Version 1, using "`" as the escape sequence character. Deprecated and will be removed eventually.
local CodecV1 = {}

CodecV1.DECODE_PATTERN = "`(%x%x)"
CodecV1.ESCAPE_CHAR = "`"
CodecV1.ESCAPE_BYTE = string.byte(CodecV1.ESCAPE_CHAR)
CodecV1.SAFE_BYTES = {
	[10] = true, -- newline
	[92] = true, -- backslash
	[96] = true, -- grave
	[124] = true, -- pipe
}

function CodecV1.DecodeSafeByte(b)
	local byteNum = tonumber(b, 16)
	if CodecV1.SAFE_BYTES[byteNum] then
		return string.char(byteNum)
	else
		return ("`%02X"):format(byteNum)
	end
end

function CodecV1.EncodeCharToQuotedPrintable(c)
	return ("`%02X"):format(c:byte())
end

function CodecV1.EncodeStringToQuotedPrintable(s)
	return (s:gsub(".", CodecV1.EncodeCharToQuotedPrintable))
end

function CodecV1.EncodeTooManyContinuations(s1, s2)
	return s1 .. (s2:gsub(".", CodecV1.EncodeCharToQuotedPrintable))
end

-- Version 2, using "~" as the escape sequence character.
local CodecV2 = {}

CodecV2.DECODE_PATTERN = "~(%x%x)"
CodecV2.ESCAPE_CHAR = "~"
CodecV2.ESCAPE_BYTE = string.byte(CodecV2.ESCAPE_CHAR)
CodecV2.SAFE_BYTES = {
	[10] = true, -- newline
	[92] = true, -- backslash
	[124] = true, -- pipe
	[126] = true, -- tilde
}

function CodecV2.DecodeSafeByte(b)
	local byteNum = tonumber(b, 16)
	if CodecV2.SAFE_BYTES[byteNum] then
		return string.char(byteNum)
	else
		return ("~%02X"):format(byteNum)
	end
end

function CodecV2.EncodeCharToQuotedPrintable(c)
	return ("~%02X"):format(c:byte())
end

function CodecV2.EncodeStringToQuotedPrintable(s)
	return (s:gsub(".", CodecV2.EncodeCharToQuotedPrintable))
end

function CodecV2.EncodeTooManyContinuations(s1, s2)
	return s1 .. (s2:gsub(".", CodecV2.EncodeCharToQuotedPrintable))
end

local CodecsByVersion = {
	[1] = CodecV1,
	[2] = CodecV2,
}

-- Realm part matching is greedy, as realm names will rarely have dashes, but
-- player names will never.
local FULL_PLAYER_SPLIT = FULL_PLAYER_NAME:gsub("-", "%%%%-"):format("^(.-)", "(.+)$")
local FULL_PLAYER_FIND = FULL_PLAYER_NAME:gsub("-", "%%%%-"):format("^.-", ".+$")

function Chomp.NameMergedRealm(name, realm)
	if type(name) ~= "string" then
		error("Chomp.NameMergedRealm: name: expected string, got " .. type(name), 2)
	elseif name == "" then
		error("Chomp.NameMergedRealm: name: expected non-empty string", 2)
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
		error("Chomp.NameMergedRealm: name already has a realm name, but realm name also provided")
	end
	return FULL_PLAYER_NAME:format(name, (realm:gsub("[%s%-]", "")))
end

function Chomp.NameSplitRealm(nameRealm)
	return string.match(nameRealm, FULL_PLAYER_SPLIT)
end

local Serialize = setmetatable({}, {
	__index = function(self) return self["default"] end
})

-- This is a meta-type used as a default handler for unknown value types
-- which always errors; no need to explicitly check types elsewhere.
Serialize["default"] = function(input)
	error("invalid type: " .. type(input))
end

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
	-- These functions are called in loops, so upvalue them eagerly.
	local floor     = math.floor
	local strformat = string.format
	local strfind   = string.find
	local type      = type

	local output = {}

	-- Handle array parts of tables first from `t[1] .. t[n]` where `n` is
	-- the last index before the first nil value.
	local numArray = 0
	for i, v in ipairs(input) do
		output[i] = Serialize[type(v)](v)
		numArray = i
	end

	-- `n` is our current offset for additional entries in the table.
	local n = numArray

	-- Handle the remaining key/value pairs. We want to skip any integral keys
	-- that are within the `t[1] .. t[numArray]` range.
	for k, v in pairs(input) do
		local typeK, typeV = type(k), type(v)
		if typeK ~= "number" or k > numArray or k < 1 or k ~= floor(k) then
			n = n + 1

			if typeK == "string" and strfind(k, "^[a-zA-Z_][a-zA-Z0-9_]*$") then
				-- Optimization for identifier-like string keys (no braces!).
				output[n] = strformat("%s=%s", k, Serialize[typeV](v))
			else
				output[n] = strformat("[%s]=%s", Serialize[typeK](k), Serialize[typeV](v))
			end
		end
	end

	return strformat("{%s}", table.concat(output, ","))
end

Internal.Serialize = Serialize

function Chomp.Serialize(object)
	local objectType = type(object)
	if not rawget(Serialize, type(object)) then
		error("Chomp.Serialize: object: expected serializable type, got " .. objectType, 2)
	end
	local success, serialized = pcall(Serialize[objectType], object)
	if not success then
		error("Chomp.Serialize: object: could not be serialized due to finding unserializable type", 2)
	end
	return serialized
end

local IsTableSafe
function IsTableSafe(t)
	for k,v in pairs(t) do
		local typeK, typeV = type(k), type(v)
		if not Serialize[typeK] or not Serialize[typeV] then
			return false
		elseif typeK == "table" and not IsTableSafe(k) then
			return false
		elseif typeV == "table" and not IsTableSafe(v) then
			return false
		end
	end
	return true
end

local function IsStringLoadSafe(str)
	local strbyte = string.byte
	local strfind = string.find

	local offset = 1
	local length = #str

	local inQuotedString = false

	repeat
		offset = strfind(str, [=[["\(]]=], offset)

		if not offset then
			break
		end

		local byte = strbyte(str, offset, offset)

		if byte == 0x22 then
			inQuotedString = not inQuotedString
		elseif inQuotedString and byte == 0x5c then
			-- Found backslash inside a string, skip next if it's a quote or
			-- another backslash.
			local next = strbyte(str, offset + 1, offset + 1)
			if next == 0x22 or next == 0x5c then
				offset = offset + 1
			end
		elseif not inQuotedString then
			-- Found either a backslash or left-paren outside a string.
			return false, string.format("unexpected character \"%1$s\" at offset %2$d", string.char(byte), offset)
		end

		offset = offset + 1
	until offset > length

	return true
end

local EMPTY_ENV = setmetatable({}, {
	__newindex = function() end,
	__metatable = false,
})

function Chomp.Deserialize(text)
	if type(text) ~= "string" then
		error("Chomp.Deserialize: text: expected string, got " .. type(text), 2)
	end

	local isSafe, reason = IsStringLoadSafe(text)
	if not isSafe then
		error("Chomp.Deserialize: text: " .. reason, 2)
	end

	local func, loadError = loadstring(("return %s"):format(text))
	if not func then
		error("Chomp.Deserialize: text: could not be deserialized: " .. tostring(loadError), 2)
	end

	setfenv(func, EMPTY_ENV)

	local retSuccess, ret = pcall(func)
	local retType = type(ret)

	if not retSuccess then
		error("Chomp.Deserialize: text: error while reading data", 2)
	elseif not Serialize[retType] then
		error("Chomp.Deserialize: text: deserialized to invalid type: " .. type(ret), 2)
	elseif retType == "table" and text:find("function", nil, true) and not IsTableSafe(ret) then
		error("Chomp.Deserialize: text: deserialized table included forbidden type", 2)
	end

	return ret
end

function Chomp.CheckLoggedContents(text)
	if type(text) ~= "string" then
		error("Chomp.CheckLoggedContents: text: expected string, got " .. type(text), 2)
	end
	if text:find("[%z\001-\009\011-\031\127]") then
		return false, "ASCII_CONTROL"
	elseif text:find("\229\141[\141\144]") then
		return false, "BLIZZ_ABUSIVE"
	elseif text:find("[\192\193\245-\255]") then
		return false, "UTF8_UNUSED_BYTE"
	elseif text:find("[\194-\244]+[\194-\244]") then
		return false, "UTF8_MULTIPLE_LEADING"
	elseif text:find("\224[\128-\159][\128-\191]") or text:find("\240[\128-\143][\128-\191][\128-\191]") or text:find("\244[\143-\191][\128-\191][\128-\191]") then
		return false, "UTF8_MALFORMED"
	elseif text:find("\237\158[\154-\191]") or text:find("\237[\159-\191][\128-\191]") then
		return false, "UTF16_RESERVED"
	elseif text:find("[\194-\244]%f[^\128-\191\194-\244]") or text:find("[\224-\244][\128-\191]%f[^\128-\191]") or text:find("[\240-\244][\128-\191][\128-\191]%f[^\128-\191]") then
		return false, "UTF8_MISSING_CONTINUATION"
	elseif text:find("%f[\128-\191\194-\244][\128-\191]+") then
		return false, "UTF8_MISSING_LEADING"
	elseif text:find("[\194-\223][\128-\191][\128-\191]+") or text:find("[\224-\239][\128-\191][\128-\191][\128-\191]+") or text:find("[\240-\244][\128-\191][\128-\191][\128-\191][\128-\191]+") then
		return false, "UTF8_EXTRA_CONTINUATION"
	elseif text:find("\239\191[\190\191]") then
		return false, "UNICODE_INVALID"
	end
	return true, nil
end

function Internal.EncodeQuotedPrintable(text, restrictBinary, codecVersion)
	local codec = CodecsByVersion[codecVersion]

	-- First, the quoted-printable escape character.
	text = text:gsub(codec.ESCAPE_CHAR, codec.EncodeCharToQuotedPrintable)

	if not restrictBinary then
		-- Just NUL, which never works normally.
		text = text:gsub("%z", codec.EncodeCharToQuotedPrintable)

		-- Bytes not used in UTF-8 ever.
		text = text:gsub("[\192\193\245-\255]", codec.EncodeCharToQuotedPrintable)

		-- Multiple leading bytes.
		text = text:gsub("[\194-\244]+[\194-\244]", function(s)
			return (s:gsub(".", codec.EncodeCharToQuotedPrintable, #s - 1))
		end)

		--- Unicode 11.0.0, Table 3-7 malformed UTF-8 byte sequences.
		text = text:gsub("\224[\128-\159][\128-\191]", codec.EncodeStringToQuotedPrintable)
		text = text:gsub("\240[\128-\143][\128-\191][\128-\191]", codec.EncodeStringToQuotedPrintable)
		text = text:gsub("\244[\143-\191][\128-\191][\128-\191]", codec.EncodeStringToQuotedPrintable)

		-- UTF-16 reserved codepoints
		text = text:gsub("\237\158[\154-\191]", codec.EncodeStringToQuotedPrintable)
		text = text:gsub("\237[\159-\191][\128-\191]", codec.EncodeStringToQuotedPrintable)

		-- Unicode invalid codepoints
		text = text:gsub("\239\191[\190\191]", codec.EncodeStringToQuotedPrintable)

		-- 2-4-byte leading bytes without enough continuation bytes.
		text = text:gsub("[\194-\244]%f[^\128-\191\194-\244]", codec.EncodeCharToQuotedPrintable)
		-- 3-4-byte leading bytes without enough continuation bytes.
		text = text:gsub("[\224-\244][\128-\191]%f[^\128-\191]", codec.EncodeStringToQuotedPrintable)
		-- 4-byte leading bytes without enough continuation bytes.
		text = text:gsub("[\240-\244][\128-\191][\128-\191]%f[^\128-\191]", codec.EncodeStringToQuotedPrintable)

		-- Continuation bytes without leading bytes.
		text = text:gsub("%f[\128-\191\194-\244][\128-\191]+", codec.EncodeStringToQuotedPrintable)

		-- 2-byte character with too many continuation bytes
		text = text:gsub("([\194-\223][\128-\191])([\128-\191]+)", codec.EncodeTooManyContinuations)
		-- 3-byte character with too many continuation bytes
		text = text:gsub("([\224-\239][\128-\191][\128-\191])([\128-\191]+)", codec.EncodeTooManyContinuations)
		-- 4-byte character with too many continuation bytes
		text = text:gsub("([\240-\244][\128-\191][\128-\191][\128-\191])([\128-\191]+)", codec.EncodeTooManyContinuations)
	else
		-- Binary-restricted messages don't permit UI escape sequences.
		text = text:gsub("|", codec.EncodeCharToQuotedPrintable)
		-- They're also picky about backslashes -- ex. \\n (literal \n) fails.
		text = text:gsub("\\", codec.EncodeCharToQuotedPrintable)
		-- Newlines are truly necessary but not permitted.
		text = text:gsub("\010", codec.EncodeCharToQuotedPrintable)
	end

	return text
end

function Chomp.EncodeQuotedPrintable(text, codecVersion)
	if type(text) ~= "string" then
		error("Chomp.EncodeQuotedPrintable: text: expected string, got " .. type(text), 2)
	elseif codecVersion ~= nil then
		if type(codecVersion) ~= "number" then
			error("Chomp.EncodeQuotedPrintable: codecVersion: expected number or nil, got " .. type(codecVersion), 2)
		elseif not CodecsByVersion[codecVersion] then
			error("Chomp.EncodeQuotedPrintable: codecVersion: unsupported codec version " .. type(codecVersion), 2)
		end
	end

	local codec = CodecsByVersion[codecVersion or 1]

	-- First, the quoted-printable escape character.
	text = text:gsub(codec.ESCAPE_CHAR, codec.EncodeCharToQuotedPrintable)

	-- Logged messages don't permit UI escape sequences.
	text = text:gsub("|", codec.EncodeCharToQuotedPrintable)
	-- They're also picky about backslashes -- ex. \\n (literal \n) fails.
	text = text:gsub("\\", codec.EncodeCharToQuotedPrintable)
	-- Some characters are considered abusive-by-default by Blizzard.
	text = text:gsub("\229\141[\141\144]", codec.EncodeStringToQuotedPrintable)
	-- ASCII control characters. \009 and \127 are allowed for some reason.
	text = text:gsub("[%z\001-\008\010-\031]", codec.EncodeCharToQuotedPrintable)

	-- Bytes not used in UTF-8 ever.
	text = text:gsub("[\192\193\245-\255]", codec.EncodeCharToQuotedPrintable)

	-- Multiple leading bytes.
	text = text:gsub("[\194-\244]+[\194-\244]", function(s)
		return (s:gsub(".", codec.EncodeCharToQuotedPrintable, #s - 1))
	end)

	--- Unicode 11.0.0, Table 3-7 malformed UTF-8 byte sequences.
	text = text:gsub("\224[\128-\159][\128-\191]", codec.EncodeStringToQuotedPrintable)
	text = text:gsub("\240[\128-\143][\128-\191][\128-\191]", codec.EncodeStringToQuotedPrintable)
	text = text:gsub("\244[\143-\191][\128-\191][\128-\191]", codec.EncodeStringToQuotedPrintable)

	-- UTF-16 reserved codepoints
	text = text:gsub("\237\158[\154-\191]", codec.EncodeStringToQuotedPrintable)
	text = text:gsub("\237[\159-\191][\128-\191]", codec.EncodeStringToQuotedPrintable)

	-- Unicode invalid codepoints
	text = text:gsub("\239\191[\190\191]", codec.EncodeStringToQuotedPrintable)

	-- 2-4-byte leading bytes without enough continuation bytes.
	text = text:gsub("[\194-\244]%f[^\128-\191\194-\244]", codec.EncodeCharToQuotedPrintable)
	-- 3-4-byte leading bytes without enough continuation bytes.
	text = text:gsub("[\224-\244][\128-\191]%f[^\128-\191]", codec.EncodeStringToQuotedPrintable)
	-- 4-byte leading bytes without enough continuation bytes.
	text = text:gsub("[\240-\244][\128-\191][\128-\191]%f[^\128-\191]", codec.EncodeStringToQuotedPrintable)

	-- Continuation bytes without leading bytes.
	text = text:gsub("%f[\128-\191\194-\244][\128-\191]+", codec.EncodeStringToQuotedPrintable)

	-- 2-byte character with too many continuation bytes
	text = text:gsub("([\194-\223][\128-\191])([\128-\191]+)", codec.EncodeTooManyContinuations)
	-- 3-byte character with too many continuation bytes
	text = text:gsub("([\224-\239][\128-\191][\128-\191])([\128-\191]+)", codec.EncodeTooManyContinuations)
	-- 4-byte character with too many continuation bytes
	text = text:gsub("([\240-\244][\128-\191][\128-\191][\128-\191])([\128-\191]+)", codec.EncodeTooManyContinuations)

	return text
end

local function DecodeAnyByte(b)
	return string.char(tonumber(b, 16))
end

function Internal.DecodeQuotedPrintable(text, restrictBinary, codecVersion)
	local codec = CodecsByVersion[codecVersion]
	local decodedText = text:gsub(codec.DECODE_PATTERN, not restrictBinary and DecodeAnyByte or codec.DecodeSafeByte)
	return decodedText
end

function Chomp.DecodeQuotedPrintable(text, codecVersion)
	if type(text) ~= "string" then
		error("Chomp.DecodeQuotedPrintable: text: expected string, got " .. type(text), 2)
	elseif codecVersion ~= nil then
		if type(codecVersion) ~= "number" then
			error("Chomp.DecodeQuotedPrintable: codecVersion: expected number or nil, got " .. type(codecVersion), 2)
		elseif not CodecsByVersion[codecVersion] then
			error("Chomp.DecodeQuotedPrintable: codecVersion: unsupported codec version " .. type(codecVersion), 2)
		end
	end

	local codec = CodecsByVersion[codecVersion or 1]

	local decodedText = text:gsub(codec.DECODE_PATTERN, DecodeAnyByte)
	return decodedText
end

function Chomp.SafeSubString(text, first, last, textLen, codecVersion)
	if type(text) ~= "string" then
		error("Chomp.SafeSubString: text: expected string, got " .. type(text), 2)
	elseif type(first) ~= "number" then
		error("Chomp.SafeSubString: first: expected number, got " .. type(first), 2)
	elseif type(last) ~= "number" then
		error("Chomp.SafeSubString: last: expected number, got " .. type(last), 2)
	elseif textLen and type(textLen) ~= "number" then
		error("Chomp.SafeSubString: textLen: expected number or nil, got " .. type(textLen), 2)
	elseif codecVersion ~= nil then
		if type(codecVersion) ~= "number" then
			error("Chomp.SafeSubstring: codecVersion: expected number or nil, got " .. type(codecVersion), 2)
		elseif not CodecsByVersion[codecVersion] then
			error("Chomp.SafeSubstring: codecVersion: unsupported codec version " .. type(codecVersion), 2)
		end
	end

	local codec = CodecsByVersion[codecVersion or 1]

	local offset = 0
	if not textLen then
		textLen = #text
	end
	if first > textLen then
		error("Chomp.SafeSubString: first: starting index exceeds text length", 2)
	end
	if textLen > last then
		local b3, b2, b1 = text:byte(last - 2, last)
		if b1 == codec.ESCAPE_BYTE or (b1 >= 194 and b1 <= 244) then
			offset = 1
		elseif b2 == codec.ESCAPE_BYTE or (b2 >= 224 and b2 <= 244) then
			offset = 2
		elseif b3 >= 240 and b3 <= 244 then
			offset = 3
		end
	end
	return (text:sub(first, last - offset)), offset
end

function Chomp.InsensitiveStringEquals(a, b)
	if a == b then
		return true
	end

	if type(a) ~= "string" or type(b) ~= "string" then
		return false
	end

	return strcmputf8i(a, b) == 0
end
