-- luacheck: allow defined

UNKNOWNOBJECT = "Unknown"
BNET_CLIENT_WOW = "WoW"
ERR_CHAT_PLAYER_NOT_FOUND_S = "Player not found: %s"

Constants = {
	CharacterNameSeparatorConsts = {
		CHARACTERNAME_REALMNAME_SEPARATOR = "-",
		CHARACTERNAME_SURNAME_SEPARATOR = " ",
	},
}

local source = debug.getinfo(1, "S").source:sub(2)
local TESTS_DIRECTORY = source:match("^(.*[/\\])") or "./"
local ROOT_DIRECTORY = TESTS_DIRECTORY:gsub("Tests[/\\]$", "")

-- luacheck: ignore
function table.wipe(tbl)
	for key in pairs(tbl) do
		tbl[key] = nil
	end
	return tbl
end

-- luacheck: ignore
function string.contains(str, substring)
	return string.find(str, substring, 1, true) ~= nil
end

-- luacheck: ignore
function string.split(separator, value)
	local separatorStart, separatorEnd = string.find(value, separator, 1, true)
	if not separatorStart then
		return value
	end
	return value:sub(1, separatorStart - 1), value:sub(separatorEnd + 1)
end

-- luacheck: ignore
function string.join(separator, ...)
	return table.concat({...}, separator)
end

bit = {}

function bit.band(a, b)
	local result, place = 0, 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then
			result = result + place
		end
		a = math.floor(a / 2)
		b = math.floor(b / 2)
		place = place * 2
	end
	return result
end

function bit.bor(a, b)
	local result, place = 0, 1
	while a > 0 or b > 0 do
		if a % 2 == 1 or b % 2 == 1 then
			result = result + place
		end
		a = math.floor(a / 2)
		b = math.floor(b / 2)
		place = place * 2
	end
	return result
end

C_ChatInfo = {}

function C_ChatInfo.IsAddonMessagePrefixRegistered()
	return false
end

function C_ChatInfo.RegisterAddonMessagePrefix()
end

C_BattleNet = {}

function C_BattleNet.GetFriendNumGameAccounts()
	return 0
end

function C_BattleNet.GetFriendGameAccountInfo()
end

ChatThrottleLib = {}

function ChatThrottleLib.SendAddonMessage()
end

function ChatThrottleLib.SendAddonMessageLogged()
end

function ChatThrottleLib.BNSendGameData()
end

LibStub = {
	libs = {},
}

function LibStub:NewLibrary(name)
	local library = {}
	self.libs[name] = library
	return library
end

function LibStub:GetLibrary(name)
	return self.libs[name]
end

LibStub.libs["CallbackHandler-1.0"] = {
	New = function()
		return {}
	end,
}

local function LoadFile(path, ...)
	local chunk = assert(loadfile(ROOT_DIRECTORY .. path))
	return chunk(...)
end

local function CreateFrameStub()
	local frame = {}

	function frame:Hide()
	end

	function frame:RegisterEvent()
	end

	function frame:SetScript(_, handler)
		self.handler = handler
	end

	return frame
end

-- luacheck: ignore
function strmatch(...)
	return string.match(...)
end

function securecallfunction(func, ...)
	return func(...)
end

function tInvert(values)
	local inverted = {}
	for _, value in ipairs(values) do
		inverted[value] = true
	end
	return inverted
end

function CreateFrame()
	return CreateFrameStub()
end

function IsLoggedIn()
	return false
end

function hooksecurefunc()
end

function ChatFrame_AddMessageEventFilter()
end

function GetRealmName()
	return "Test Realm"
end

function GetAutoCompleteRealms()
	return {}
end

function GetTime()
	return 0
end

function GetNetStats()
	return 0, 0, 0
end

function UnitName()
	return "Test"
end

function UnitFullName()
	return "Test", "Realm"
end

function UnitFactionGroup()
	return "Alliance"
end

function UnitExists()
	return false
end

function Ambiguate(name)
	return name
end

function BNFeaturesEnabledAndConnected()
	return false
end

function BNGetNumFriends()
	return 0
end

function RegionalUniqueNamesEnabled()
	return false
end

LoadFile("Internal.lua", "Chomp")
LoadFile("Public.lua")
LoadFile("StringManip.lua")

local Chomp = LibStub:GetLibrary("Chomp")
Chomp.Internal.LOADING = nil

return Chomp
