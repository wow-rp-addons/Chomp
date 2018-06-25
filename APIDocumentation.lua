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
	error(("Chomp Message Library (embedded: %s) internals not present, cannot continue loading API documentation."):format((...)))
elseif (__chomp_internal.VERSION or 0) > VERSION then
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
			Name = "RegisterAddonPrefix",
			Type = "Function",

			Arguments =
			{
				{ Name = "prefix", Type = "string or table", Nilable = false, Documentation = { "If table is passed, [0], [1], [2], and [3] indicies must be present. [0] is used for messages that do not need splitting. [1] is used for first of split messages, [2] for middle of split messages, and [3] for last of split messages.", "Maximum length of 16 bytes." } },
				{ Name = "callback", Type = "function", Nilable = true, Documentation = { "Arguments passed are identical to CHAT_MSG_ADDON event." } },
			},
		},
		{
			Name = "SmartAddonWhisper",
			Type = "Function",

			Arguments =
			{
				{ Name = "prefix", Type = "string or table", Nilable = false, Documentation = { "If table is passed, reference must be identical to table originally passed to AddOn_Chomp.RegisterAddonPrefix().", "Maximum length of 16 bytes." } },
				{ Name = "text", Type = "string", Nilable = false, Documentation = { "The outgoing text will be split (based on selected method's maximum message size, encoded (based on selected method's permitted byte sequences), and otherwise transformed as necessary prior to sending." } },
				{ Name = "target", Type = "string", Nilable = false },
				{ Name = "priority", Type = "string", Nilable = true, Documentation = { "Must be one of \"HIGH\", \"MEDIUM\", or \"LOW\"." } },
				{ Name = "queue", Type = "string", Nilable = true },
			},

			Returns = 
			{
				{ Name = "sentBnet", Type = "bool", Nilable = false },
				{ Name = "sentLogged", Type = "bool", Nilable = false },
				{ Name = "sentInGame", Type = "bool", Nilable = false },
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
				{ Name = "encodedText", Type = "string", Nilable = false },
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
				{ Name = "decodedText", Type = "string", Nilable = false },
			},
		},
		-- TODO: Error callbacks, target compatibility, report target.
		{
			Name = "GetBPS",
			Type = "Function",

			Arguments =
			{
				{ Name = "pool", Type = "string", Nilable = false, Documentation = { "Must be one of \"InGame\" or \"BattleNet\"." } },
			},

			Returns = 
			{
				{ Name = "bps", Type = "number", Nilable = false, Documentation = { "Maximum sustained bytes per second allowed for the requested pool." } },
				{ Name = "burst", Type = "number", Nilable = false, Documentation = { "Maximum instantaneous burst bytes allowed for the requested pool." } },
			},
		},
		{
			Name = "SetBPS",
			Type = "Function",

			Arguments =
			{
				{ Name = "pool", Type = "string", Nilable = false, Documentation = { "Must be one of \"InGame\" or \"BattleNet\"." } },
				{ Name = "bps", Type = "number", Nilable = false, Documentation = { "Maximum sustained bytes per second allowed for the requested pool.", "WARNING: This is not constrained and improper settings can cause failures or disconnections." } },
				{ Name = "burst", Type = "number", Nilable = false, Documentation = { "Maximum instantaneous burst bytes allowed for the requested pool.", "WARNING: This is not constrained and improper settings can cause failures or disconnections." } },
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
	-- TODO: Prefix table?
	Tables = 
	{
	},
}

Internal.ChompAPI = ChompAPI
