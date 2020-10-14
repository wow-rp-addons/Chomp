-- Disable unused self warnings.
self = false

-- Allow unused arguments.
unused_args = false

-- Disable line length limits.
max_line_length = false
max_code_line_length = false
max_string_line_length = false
max_comment_line_length = false

-- Add exceptions for external libraries.
std = "lua51+wow+wowstd+utf8lib"

globals = {
	"__chomp_internal",
	"AddOn_Chomp",
	"ChatThrottleLib",
}

stds.wow = {
	read_globals = {
		C_BattleNet = {
			fields = {
				"GetGameAccountInfoByID",
				"GetFriendNumGameAccounts",
				"GetFriendGameAccountInfo",
			},
		},

		C_Timer = {
			fields = {
				"After",
			},
		},

		APIDocumentation = {
			fields = {
				"AddDocumentationTable",
			},
		},

		"Ambiguate",
		"BNET_CLIENT_WOW",
		"BNFeaturesEnabledAndConnected",
		"BNGetFriendGameAccountInfo",
		"BNGetGameAccountInfo",
		"BNGetNumFriendGameAccounts",
		"BNGetNumFriends",
		"BNSendGameData",
		"BNSendWhisper",
		"C_ChatInfo",
		"C_Club",
		"CallErrorHandler",
		"ChatFrame_AddMessageEventFilter",
		"CreateFrame",
		"CreateFromMixins",
		"ERR_CHAT_PLAYER_NOT_FOUND_S",
		"FULL_PLAYER_NAME",
		"GetAutoCompleteRealms",
		"GetNetStats",
		"GetPlayerInfoByGUID",
		"GetRealmName",
		"GetTime",
		"hooksecurefunc",
		"InCombatLockdown",
		"IsAddOnLoaded",
		"IsInGroup",
		"IsInRaid",
		"IsLoggedIn",
		"LE_PARTY_CATEGORY_HOME",
		"LE_PARTY_CATEGORY_INSTANCE",
		"LE_REALM_RELATION_COALESCED",
		"PLAYER_REPORT_TYPE_LANGUAGE",
		"PlayerLocationMixin",
		"SendChatMessage",
		"UnitFactionGroup",
		"UnitFullName",
		"UnitInParty",
		"UnitInRaid",
		"UnitInSubgroup",
		"UnitName",
		"UnitRealmRelationship",
		"UNKNOWNOBJECT",
	},
}

stds.wowstd = {
	read_globals = {
		bit = {
			fields = {
				"band",
				"bor",
			},
		},

		"wipe",
	},
}

stds.utf8lib = {
	read_globals = {
		string = {
			fields = {
				"utf8lower",
			},
		},
	},
}
