-- luacheck: globals describe it before_each after_each mock stub
-- luacheck: read globals assert.same

local Chomp = require("SpecHelper")
local Internal = Chomp.Internal

describe("Chomp", function()
	it("loads the addon Lua files", function()
		assert(type(Chomp) == "table")
		assert(type(Chomp.Internal) == "table")
		assert(type(Chomp.Serialize) == "function")
		assert(type(Chomp.Deserialize) == "function")
	end)
end)

describe("Chomp logged whisper delivery", function()
	local prefix = "ChompTest"
	local sessionID = 0x4C6
	local wasReady
	local raw, delivered, received

	local function Record(into, _, text, ...)
		-- Skip the remaining event arguments to reach the Chomp chunk metadata.
		local streamID, msgID, msgTotal = select(11, ...)
		into[#into + 1] = { text, streamID, msgID, msgTotal }
	end

	local function DeliverChunk(msgID, text)
		-- Replay the logged whisper event with a Chomp header for a three-chunk session.
		local packet = ("%03X%03X%03X%03X%s"):format(0x00A, sessionID, msgID, 3, text)
		Internal:handler("CHAT_MSG_ADDON_LOGGED", prefix, packet, "WHISPER", "Sender", "Test")
	end

	local function RegisterPrefix(fullMsgOnly)
		Chomp.RegisterAddonPrefix(prefix, function(...)
			Record(delivered, ...)
		end, {
			fullMsgOnly = fullMsgOnly,
			rawCallback = function(...) Record(raw, ...) end,
		})
	end

	before_each(function()
		wasReady = Internal.isReady
		Internal.isReady = true
		raw, delivered, received = {}, {}, {}
		stub(Internal, "TriggerEvent", function(_, event, ...)
			if event == "OnMessageReceived" then
				Record(received, ...)
			end
		end)
	end)

	after_each(function()
		Internal.isReady = wasReady
		Internal.Prefixes[prefix] = nil
	end)

	it("reports each delivered chunk's ID in incremental mode", function()
		RegisterPrefix(false)
		local first = { "first", sessionID, 1, 3 }
		local middle = { "middle", sessionID, 2, 3 }
		local last = { "last", sessionID, 3, 3 }

		-- Chunk 3 arrives early. Only chunk 1 can be delivered until the gap closes.
		DeliverChunk(1, "first")
		DeliverChunk(3, "last")
		assert.same({ first }, delivered)
		assert.same({ first }, received)

		-- Chunk 2 releases both pending chunks, but must not supply the ID for both.
		DeliverChunk(2, "middle")
		assert.same({ first, last, middle }, raw)
		assert.same({ first, middle, last }, delivered)
		assert.same({ first, middle, last }, received)
	end)

	it("reports the final chunk ID in whole-message mode", function()
		RegisterPrefix(true)

		-- Even with the final chunk buffered, neither processed callback can run yet.
		DeliverChunk(1, "first")
		DeliverChunk(3, "last")
		assert.same({}, delivered)
		assert.same({}, received)

		-- Chunk 2 completes assembly, but the whole message must report 3/3, not 2/3.
		DeliverChunk(2, "middle")
		assert.same({
			{ "first", sessionID, 1, 3 },
			{ "last", sessionID, 3, 3 },
			{ "middle", sessionID, 2, 3 },
		}, raw)

		local expected = { { "firstmiddlelast", sessionID, 3, 3 } }
		assert.same(expected, delivered)
		assert.same(expected, received)
	end)
end)

describe("Chomp.RegionalUniqueNamesEnabled", function()
	it("returns false when the API is disabled", function()
		stub(_G, "RegionalUniqueNamesEnabled", false)
		assert(not Chomp.RegionalUniqueNamesEnabled())
	end)

	it("returns true when the API is enabled", function()
		stub(_G, "RegionalUniqueNamesEnabled", true)
		assert(Chomp.RegionalUniqueNamesEnabled())
	end)
end)

describe("Chomp.NameSplitRealm", function()
	describe("with realm-local names", function()
		before_each(function()
			stub(_G, "RegionalUniqueNamesEnabled", false)
		end)

		it("splits a name and realm", function()
			local name, realm = Chomp.NameSplitRealm("Zugzug-Realm")
			assert(name == "Zugzug")
			assert(realm == "Realm")
		end)
	end)

	describe("with regional unique names", function()
		before_each(function()
			stub(_G, "RegionalUniqueNamesEnabled", true)
		end)

		it("does not split a full name", function()
			local name, realm = Chomp.NameSplitRealm("John Stormwind")
			assert(name == "John Stormwind")
			assert(realm == nil)
		end)
	end)
end)

describe("Chomp.NormalizeRealmName", function()
	it("removes spaces", function()
		assert(Chomp.NormalizeRealmName("Test Realm") == "TestRealm")
	end)

	it("removes periods", function()
		assert(Chomp.NormalizeRealmName("Test.Realm") == "TestRealm")
	end)

	it("removes realm separators", function()
		assert(Chomp.NormalizeRealmName("Test-Realm") == "TestRealm")
	end)

	it("preserves other characters", function()
		assert(Chomp.NormalizeRealmName("Test_Realm") == "Test_Realm")
	end)
end)

describe("Chomp.NameMergedRealm", function()
	describe("with realm-local names", function()
		before_each(function()
			stub(_G, "RegionalUniqueNamesEnabled", false)
		end)

		it("adds the current realm to a character name", function()
			assert(Chomp.NameMergedRealm("Zugzug") == "Zugzug-TestRealm")
		end)

		it("normalizes a supplied realm name", function()
			assert(Chomp.NameMergedRealm("Zugzug", "Test Realm") == "Zugzug-TestRealm")
		end)

		it("rejects a name that already includes the supplied realm", function()
			local success = pcall(Chomp.NameMergedRealm, "Zugzug-TestRealm", "TestRealm")
			assert(not success)
		end)
	end)

	describe("with regional unique names", function()
		before_each(function()
			stub(_G, "RegionalUniqueNamesEnabled", true)
		end)

		it("rejects a name without a surname", function()
			local success = pcall(Chomp.NameMergedRealm, "John")
			assert(not success)
		end)

		it("preserves a full name supplied as one value", function()
			assert(Chomp.NameMergedRealm("John Stormwind") == "John Stormwind")
		end)

		it("ignores a bogus realm returned with a full player name", function()
			assert(Chomp.NameMergedRealm("John Stormwind", "RealmName") == "John Stormwind")
		end)

		it("joins a full name returned as separate values", function()
			assert(Chomp.NameMergedRealm("John", "Stormwind") == "John Stormwind")
		end)

		it("preserves a full name with a second return value", function()
			assert(Chomp.NameMergedRealm("John Stormwind", "Stormwind") == "John Stormwind")
		end)
	end)
end)

local function CreateGameAccount(overrides)
	local account = {
		characterName = "John Stormwind",
		factionName = "Alliance",
		isInCurrentRegion = true,
		isOnline = true,
		clientProgram = BNET_CLIENT_WOW,
	}

	for key, value in pairs(overrides or {}) do
		account[key] = value
	end

	return account
end

describe("Chomp.Internal.GetBattleNetAccountKey", function()
	describe("with realm-local names", function()
		before_each(function()
			stub(_G, "RegionalUniqueNamesEnabled", false)
		end)

		it("merges the character and normalized realm names", function()
			local account = CreateGameAccount({
				characterName = "Zugzug",
				realmName = "Test Realm",
			})

			assert(Internal:GetBattleNetAccountKey(account) == "Zugzug-TestRealm")
		end)
	end)

	describe("with regional unique names", function()
		before_each(function()
			stub(_G, "RegionalUniqueNamesEnabled", true)
		end)

		it("preserves the character full name", function()
			-- Regional Battle.net data supplies the complete full name in
			-- characterName and internal realm name. Expectation is that the
			-- realm name is ignored.
			local account = CreateGameAccount({
				characterName = "John Stormwind",
				realmName = "Realm",
			})
			assert(Internal:GetBattleNetAccountKey(account) == "John Stormwind")
		end)
	end)
end)

describe("Chomp.Internal.CanExchangeWithGameAccount", function()
	describe("with realm-local names", function()
		before_each(function()
			stub(_G, "RegionalUniqueNamesEnabled", false)
			Internal.SameRealm = { TestRealm = true }
		end)

		it("rejects same-faction accounts on the same realm", function()
			local account = CreateGameAccount({
				characterName = "Zugzug",
				realmName = "Test Realm",
			})
			assert(not Internal:CanExchangeWithGameAccount(account))
		end)

		it("accepts cross-faction accounts on the same realm", function()
			local account = CreateGameAccount({
				characterName = "Zugzug",
				realmName = "Test Realm",
				factionName = "Horde",
			})
			assert(Internal:CanExchangeWithGameAccount(account))
		end)

		it("rejects accounts without a realm", function()
			local account = CreateGameAccount({
				characterName = "Zugzug",
				realmName = nil,
				factionName = "Horde",
			})
			assert(not Internal:CanExchangeWithGameAccount(account))
		end)
	end)

	describe("with regional unique names", function()
		before_each(function()
			stub(_G, "RegionalUniqueNamesEnabled", true)
			Internal.SameRealm = {}
		end)

		it("rejects same-faction accounts", function()
			local account = CreateGameAccount({
				characterName = "John Stormwind",
				realmName = nil,
			})
			assert(not Internal:CanExchangeWithGameAccount(account))
		end)

		it("accepts cross-faction accounts without a realm", function()
			local account = CreateGameAccount({
				characterName = "John Stormwind",
				realmName = nil,
				factionName = "Horde",
			})
			assert(Internal:CanExchangeWithGameAccount(account))
		end)
	end)
end)

describe("Chomp.Internal.GenerateMessageFilterKey", function()
	describe("with realm-local names", function()
		before_each(function()
			stub(_G, "RegionalUniqueNamesEnabled", false)
		end)

		it("discards the realm suffix", function()
			assert(Internal:GenerateMessageFilterKey("Zugzug-TestRealm") == "zugzug")
		end)
	end)

	describe("with regional unique names", function()
		before_each(function()
			stub(_G, "RegionalUniqueNamesEnabled", true)
		end)

		it("preserves the full name", function()
			assert(Internal:GenerateMessageFilterKey("Test-Realm") == "test-realm")
		end)
	end)
end)
