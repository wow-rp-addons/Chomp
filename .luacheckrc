self = false
unused_args = false
max_line_length = false
max_code_line_length = false
max_string_line_length = false
max_comment_line_length = false

exclude_files = {
    ".release",
    "Libs/*",
}

std = "lua51"

globals = {
	"__chomp_internal",
	"AddOn_Chomp",
	"ChatThrottleLib.MSG_OVERHEAD",
	"ChatThrottleLib.BURST",
	"ChatThrottleLib.MAX_CPS",
}

read_globals = {
	-- LibStub
	"LibStub.GetLibrary",
	"LibStub.NewLibrary",

	-- ChatThrottleLib
	"ChatThrottleLib.BNSendGameData",
	"ChatThrottleLib.SendAddonMessage",
	"ChatThrottleLib.SendAddonMessageLogged",
	"ChatThrottleLib.SendChatMessage",

	-- Global APIs
	"Ambiguate",
	"bit.band",
	"bit.bor",
	"BNET_CLIENT_WOW",
	"BNFeaturesEnabledAndConnected",
	"BNGetNumFriends",
	"C_BattleNet.GetFriendGameAccountInfo",
	"C_BattleNet.GetFriendNumGameAccounts",
	"C_BattleNet.GetGameAccountInfoByID",
	"C_ChatInfo.IsAddonMessagePrefixRegistered",
	"C_ChatInfo.RegisterAddonMessagePrefix",
	"C_Intl.FoldCase",
	"ChatFrame_AddMessageEventFilter",
	"Constants.CharacterNameSeparatorConsts.CHARACTERNAME_REALMNAME_SEPARATOR",
	"Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR",
	"CreateFrame",
	"ERR_CHAT_PLAYER_NOT_FOUND_S",
	"GetAutoCompleteRealms",
	"GetNetStats",
	"GetRealmName",
	"GetServerTime",
	"GetTime",
	"hooksecurefunc",
	"IsLoggedIn",
	"RegionalUniqueNamesEnabled",
	"securecallfunction",
	"strcmputf8i",
	"string.contains",
	"string.join",
	"string.split",
	"tInvert",
	"UnitExists",
	"UnitFactionGroup",
	"UnitFullName",
	"UnitInParty",
	"UnitName",
	"UNKNOWNOBJECT",
	"WOW_PROJECT_ID",
	"WOW_PROJECT_MAINLINE",
}
