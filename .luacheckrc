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
	"ChatThrottleLib",
}

read_globals = {
	-- UTF8 library (optional dependency)
	"string.utf8lower",

	-- LibStub
	"LibStub.GetLibrary",

	-- Global APIs
	"Ambiguate",
	"bit.band",
	"bit.bor",
	"BNET_CLIENT_WOW",
	"BNFeaturesEnabledAndConnected",
	"BNGetFriendGameAccountInfo",
	"BNGetGameAccountInfo",
	"BNGetNumFriendGameAccounts",
	"BNGetNumFriends",
	"BNSendGameData",
	"BNSendWhisper",
	"C_BattleNet.GetFriendGameAccountInfo",
	"C_BattleNet.GetFriendNumGameAccounts",
	"C_BattleNet.GetGameAccountInfoByID",
	"C_ChatInfo",
	"C_Club",
	"C_ReportSystem.CanReportPlayer",
	"C_ReportSystem.OpenReportPlayerDialog",
	"C_Timer.After",
	"CallErrorHandler",
	"ChatFrame_AddMessageEventFilter",
	"CreateFrame",
	"CreateFromMixins",
	"DoublyLinkedListMixin",
	"ERR_CHAT_PLAYER_NOT_FOUND_S",
	"FULL_PLAYER_NAME",
	"GetAutoCompleteRealms",
	"GetNetStats",
	"GetPlayerInfoByGUID",
	"GetRealmName",
	"GetTime",
	"hooksecurefunc",
	"InCombatLockdown",
	"IsInGroup",
	"IsInRaid",
	"IsLoggedIn",
	"LE_PARTY_CATEGORY_HOME",
	"LE_PARTY_CATEGORY_INSTANCE",
	"LE_REALM_RELATION_COALESCED",
	"Mixin",
	"PLAYER_REPORT_TYPE_LANGUAGE",
	"PlayerLocationMixin",
	"SendChatMessage",
	"strcmputf8i",
	"UnitFactionGroup",
	"UnitFullName",
	"UnitInParty",
	"UnitInRaid",
	"UnitInSubgroup",
	"UnitName",
	"UnitRealmRelationship",
	"UNKNOWNOBJECT",
	"wipe",
	"WOW_PROJECT_ID",
	"WOW_PROJECT_RETAIL",
}
