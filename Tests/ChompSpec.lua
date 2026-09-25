-- luacheck: globals describe it before_each after_each mock stub

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
