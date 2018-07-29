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

if not __chomp_internal or not __chomp_internal.LOADING then
	return
end

local Internal = __chomp_internal

local ChompAPI =
{
	Name = "Chomp",
	Type = "System",
	Namespace = "AddOn_Chomp",

	Functions = 
	{
		{
			Name = "NameMergedRealm",
			Type = "Function",

			Arguments =
			{
				{ Name = "name", Type = "string", Nilable = false },
				{ Name = "realmName", Type = "bool", Nilable = true },
			},

			Returns = 
			{
				{ Name = "fullName", Type = "string", Nilable = false },
			},
		},
		{
			Name = "SendAddonMessage",
			Type = "Function",

			Arguments =
			{
				{ Name = "prefix", Type = "string", Nilable = false, Documentation = { "Maximum length of 16 bytes." } },
				{ Name = "text", Type = "string", Nilable = false, Documentation = { "Maximum length of 255 bytes." } },
				{ Name = "kind", Type = "string", Nilable = true, Documentation = { "Defaults to PARTY." } },
				{ Name = "target", Type = "string or number", Nilable = true, Documentation = { "String required if kind is WHISPER.", "Number required if kind is CHANNEL." } },
				{ Name = "priority", Type = "string", Nilable = true, Documentation = { "Must be one of \"HIGH\", \"MEDIUM\", or \"LOW\"." } },
				{ Name = "queue", Type = "string", Nilable = true },
				{ Name = "callback", Type = "function", Nilable = true, Documentation = { "Arguments passed are: (bool) success, (any) callbackArg." } },
				{ Name = "callbackArg", Type = "any", Nilable = true , Documentation = { "Arbitrary argument passed to the callback function." } },
			},
		},
		{
			Name = "SendAddonMessageLogged",
			Type = "Function",

			Arguments =
			{
				{ Name = "prefix", Type = "string", Nilable = false, Documentation = { "Maximum length of 16 bytes." } },
				{ Name = "text", Type = "string", Nilable = false, Documentation = { "Maximum length of 255 bytes.", "Note: This will NOT be automatically encoded quoted-printable, do it first if necessary when using this function." } },
				{ Name = "kind", Type = "string", Nilable = true, Documentation = { "Defaults to PARTY." } },
				{ Name = "target", Type = "string or number", Nilable = true, Documentation = { "String required if kind is WHISPER.", "Number required if kind is CHANNEL." } },
				{ Name = "priority", Type = "string", Nilable = true, Documentation = { "Must be one of \"HIGH\", \"MEDIUM\", or \"LOW\"." } },
				{ Name = "queue", Type = "string", Nilable = true },
				{ Name = "callback", Type = "function", Nilable = true, Documentation = { "Arguments passed are: (bool) success, (any) callbackArg." } },
				{ Name = "callbackArg", Type = "any", Nilable = true , Documentation = { "Arbitrary argument passed to the callback function." } },
			},
		},
		{
			Name = "SendChatMessage",
			Type = "Function",

			Arguments =
			{
				{ Name = "text", Type = "string", Nilable = false, Documentation = { "Maximum length of 255 bytes." } },
				{ Name = "kind", Type = "string", Nilable = true, Documentation = { "Defaults to SAY." } },
				{ Name = "language", Type = "string or number", Nilable = false, Documentation = { "Language name or language ID are both permissable." } },
				{ Name = "target", Type = "string or number", Nilable = true, Documentation = { "String required if kind is WHISPER.", "Number required if kind is CHANNEL." } },
				{ Name = "priority", Type = "string", Nilable = true, Documentation = { "Must be one of \"HIGH\", \"MEDIUM\", or \"LOW\"." } },
				{ Name = "queue", Type = "string", Nilable = true },
				{ Name = "callback", Type = "function", Nilable = true, Documentation = { "Arguments passed are: (bool) success, (any) callbackArg." } },
				{ Name = "callbackArg", Type = "any", Nilable = true , Documentation = { "Arbitrary argument passed to the callback function." } },
			},
		},
		{
			Name = "BNSendGameData",
			Type = "Function",

			Arguments =
			{
				{ Name = "bnIDGameAccount", Type = "number", Nilable = false },
				{ Name = "prefix", Type = "string", Nilable = false, Documentation = { "Maximum length of 16 bytes." } },
				{ Name = "text", Type = "string", Nilable = false, Documentation = { "Maximum length of 4078 bytes." } },
				{ Name = "priority", Type = "string", Nilable = true, Documentation = { "Must be one of \"HIGH\", \"MEDIUM\", or \"LOW\"." } },
				{ Name = "queue", Type = "string", Nilable = true },
				{ Name = "callback", Type = "function", Nilable = true, Documentation = { "Arguments passed are: (bool) success, (any) callbackArg." } },
				{ Name = "callbackArg", Type = "any", Nilable = true , Documentation = { "Arbitrary argument passed to the callback function." } },
			},
		},
		{
			Name = "BNSendWhisper",
			Type = "Function",

			Arguments =
			{
				{ Name = "bnIDGameAccount", Type = "number", Nilable = false },
				{ Name = "text", Type = "string", Nilable = false, Documentation = { "Maximum length of 255 bytes." } },
				{ Name = "priority", Type = "string", Nilable = true, Documentation = { "Must be one of \"HIGH\", \"MEDIUM\", or \"LOW\"." } },
				{ Name = "queue", Type = "string", Nilable = true },
				{ Name = "callback", Type = "function", Nilable = true, Documentation = { "Arguments passed are: (bool) success, (any) callbackArg." } },
				{ Name = "callbackArg", Type = "any", Nilable = true , Documentation = { "Arbitrary argument passed to the callback function." } },
			},
		},
		{
			Name = "IsSending",
			Type = "Function",

			Returns = 
			{
				{ Name = "isSending", Type = "bool", Nilable = false, Documentation = { "Returns true if Chomp is in the process of sending a message." } },
			},
		},
		{
			Name = "Serialize",
			Type = "Function",

			Arguments =
			{
				{ Name = "object", Type = "boolean, number, string, or table", Nilable = true },
			},

			Returns = 
			{
				{ Name = "serializedText", Type = "string", Nilable = false },
			},
		},
		{
			Name = "Deserialize",
			Type = "Function",

			Arguments =
			{
				{ Name = "serializedText", Type = "string", Nilable = false },
			},

			Returns = 
			{
				{ Name = "object", Type = "boolean, number, string, or table", Nilable = true },
			},
		},
		{
			Name = "CheckLoggedContents",
			Type = "Function",

			Arguments =
			{
				{ Name = "text", Type = "string", Nilable = false },
			},

			Returns = 
			{
				{ Name = "permitted", Type = "bool", Nilable = false },
				{ Name = "reason", Type = "string", Nilable = true },
			},
		},
		{
			Name = "EncodeQuotedPrintable",
			Type = "Function",

			Arguments =
			{
				{ Name = "text", Type = "string", Nilable = false },
			},

			Returns = 
			{
				{ Name = "encodedText", Type = "string", Nilable = false, Documentation = { "WARNING: This function encodes EVERYTHING known to be potentially problematic in any chat type. It should let you send arbitrary binary over logged messages, but it explicitly circumvents some Blizzard protections on glyphs considered abusive. Use at your own risk." } },
			},
		},
		{
			Name = "DecodeQuotedPrintable",
			Type = "Function",

			Arguments =
			{
				{ Name = "text", Type = "string", Nilable = false },
			},

			Returns = 
			{
				{ Name = "decodedText", Type = "string", Nilable = false, Documentation = { "WARNING: This function encodes EVERYTHING known to be potentially problematic in any chat type. It should let you send arbitrary binary over logged messages, but it explicitly circumvents some Blizzard protections on glyphs considered abusive. Use at your own risk." } },
			},
		},
		{
			Name = "SafeSubString",
			Type = "Function",

			Arguments =
			{
				{ Name = "text", Type = "string", Nilable = false },
				{ Name = "first", Type = "number", Nilable = false },
				{ Name = "last", Type = "number", Nilable = false },
				{ Name = "textLen", Type = "number", Nilable = true, Documentation = { "Optional, saves a bit of computation time if chopping a single string multiple times." } },
			},

			Returns = 
			{
				{ Name = "subString", Type = "string", Nilable = false, Documentation = { "A substring that is equal to or less than the requested substring, never splitting UTF-8 byte sequences and quoted-printable byte sequences." } },
				{ Name = "offset", Type = "number", Nilable = false, Documentation = { "The number of characters shorter the substring is, compared to the requested.", "Always positive." } },
			},
		},
		{
			Name = "RegisterAddonPrefix",
			Type = "Function",

			Arguments =
			{
				{ Name = "prefix", Type = "string", Nilable = false, Documentation = { "Maximum length of 16 bytes." } },
				{ Name = "callback", Type = "function", Nilable = false, Documentation = { "Arguments passed are identical to CHAT_MSG_ADDON event." } },
				{ Name = "prefixSettings", Type = "ChompPrefixOptions", Nilable = true, Documentation = { "If omitted, defaults to permitting only strings and returning only complete message sequences." } },
			},
		},
		{
			Name = "SmartAddonMessage",
			Type = "Function",

			Arguments =
			{
				{ Name = "prefix", Type = "string", Nilable = false, Documentation = { "Maximum length of 16 bytes." } },
				{ Name = "data", Type = "any", Nilable = false, Documentation = { "String required unless the message has been set to require serialization.", "Only types registered as valid for the prefix may be used.", "The outgoing text will be split (based on selected method's maximum message size, encoded (based on selected method's permitted byte sequences), and otherwise transformed as necessary prior to sending." } },
				{ Name = "target", Type = "string", Nilable = false },
				{ Name = "messageOptions", Type = "ChompMessageOptions", Nilable = true }
			},

			Returns = 
			{
				{ Name = "sentMethod", Type = "string", Nilable = false },
			},
		},
		{
			Name = "CheckReportGUID",
			Type = "Function",

			Arguments =
			{
				{ Name = "prefix", Type = "string", Nilable = false, Documentation = { "Maximum length of 16 bytes." } },
				{ Name = "guid", Type = "string", Nilable = false, Documentation = { "GUID must be used due to Blizzard constraints on reporting." } },
			},

			Returns = 
			{
				{ Name = "canReport", Type = "bool", Nilable = false },
				{ Name = "reason", Type = "string", Nilable = false, Documentation = { "One of UNKOWN, BATTLENET, or UNLOGGED if canReport is false; always LOGGED if canReport is true." } },
			},
		},
		{
			Name = "ReportGUID",
			Type = "Function",

			Arguments =
			{
				{ Name = "prefix", Type = "string", Nilable = false, Documentation = { "Maximum length of 16 bytes." } },
				{ Name = "guid", Type = "string", Nilable = false, Documentation = { "GUID must be used due to Blizzard constraints on reporting." } },
				{ Name = "customMessage", Type = "string", Nilable = true, Documentation = { "Custom message to pass to Blizzard GMs, regarding reported content." } },
			},

			Returns = 
			{
				{ Name = "didReport", Type = "bool", Nilable = false },
				{ Name = "reason", Type = "string", Nilable = false, Documentation = { "UNKOWN, BATTLENET, or UNLOGGED if didReport is false; always LOGGED if didReport is true." } },
			},
		},
		{
			Name = "RegisterErrorCallback",
			Type = "Function",

			Arguments =
			{
				{ Name = "callback", Type = "function", Nilable = false },
			},

			Returns = 
			{
				{ Name = "didRegister", Type = "bool", Nilable = false },
			},
		},
		{
			Name = "UnregisterErrorCallback",
			Type = "Function",

			Arguments =
			{
				{ Name = "callback", Type = "function", Nilable = false },
			},

			Returns = 
			{
				{ Name = "didUnregister", Type = "bool", Nilable = false },
			},
		},
		{
			Name = "GetBPS",
			Type = "Function",

			Returns = 
			{
				{ Name = "bps", Type = "number", Nilable = false, Documentation = { "Maximum sustained bytes per second allowed." } },
				{ Name = "burst", Type = "number", Nilable = false, Documentation = { "Maximum instantaneous burst bytes allowed." } },
			},
		},
		{
			Name = "SetBPS",
			Type = "Function",

			Arguments =
			{
				{ Name = "bps", Type = "number", Nilable = false, Documentation = { "Maximum sustained bytes per second allowed.", "WARNING: This is not constrained and improper settings can cause failures or disconnections." } },
				{ Name = "burst", Type = "number", Nilable = false, Documentation = { "Maximum instantaneous burst bytes allowed.", "WARNING: This is not constrained and improper settings can cause failures or disconnections." } },
			},
		},
		{
			Name = "GetVersion",
			Type = "Function",

			Returns = 
			{
				{ Name = "version", Type = "number", Nilable = false, Documentation = { "Version number of the active instance of Chomp Message Library." } },
			},
		},
	},
	Events = 
	{
	},
	Tables = 
	{
		{
			Name = "ChompMessageOptions",
			Type = "Structure",
			Fields =
			{
				{ Name = "priority", Type = "string", Nilable = true },
				{ Name = "queue", Type = "string", Nilable = true },
				{ Name = "serialize", Type = "bool", Nilable = true },
				{ Name = "binaryBlob", Type = "bool", Nilable = true, Documentation = { "Messages marked as a binary blob will never be sent over logged channels." } },
				{ Name = "allowBroadcast", Type = "bool", Nilable = true, Documentation = { "Broadcast messages may be sent over semi-public group channels (PARTY/RAID/INSTANCE_CHAT) when their target is a crossrealm player not available through BattleTag." } },
				{ Name = "universalBroadcast", Type = "bool", Nilable = true, Documentation = { "This marks messages as 'universal' when broadcast, meaning they're able to be used by any listener." } },
			},
		},
		{
			Name = "ChompPrefixOptions",
			Type = "Structure",
			Fields =
			{
				{ Name = "fullMsgOnly", Type = "bool", Nilable = true, Documentation = { "Defaults to true." } },
				{ Name = "broadcastPrefix", Type = "bool", Nilable = true, Documentation = { "Must be true to use broadcast whispers.", "This has potential privacy implications, as broadcasts are sent over group addon channels and may be monitored by others in group." } },
				{ Name = "rawCallback", Type = "function", Nilable = true, Documentation = { "Provides all raw message data, as they are received and even if fullMsgOnly is set, to the provided callback.", "May be used to monitor incoming status of serialized data, for example." } },
				{ Name = "validTypes", Type = "ChompValidTypes", Nilable = true, Documentation = { "Defaults to permitting strings only." } },
			},
		},
		{
			Name = "ChompValidTypes",
			Type = "Structure",
			Fields =
			{
				{ Name = "string", Type = "bool", Nilable = true },
				{ Name = "boolean", Type = "bool", Nilable = true },
				{ Name = "number", Type = "bool", Nilable = true },
				{ Name = "table", Type = "bool", Nilable = true, Documentation = { "Tables are serialized with all non-forbidden types included -- function, userdata, thread are forbidden." } },
				{ Name = "nil", Type = "bool", Nilable = true },
			},
		},
	},
}

Internal.ChompAPI = ChompAPI
