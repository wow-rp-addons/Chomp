-- luacheck: globals describe it before_each after_each mock stub

local Chomp = require("SpecHelper")

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
			local name, realm = Chomp.NameSplitRealm("Test-Realm")
			assert(name == "Test")
			assert(realm == "Realm")
		end)
	end)

	describe("with regional unique names", function()
		before_each(function()
			stub(_G, "RegionalUniqueNamesEnabled", true)
		end)

		it("does not split a full name", function()
			local name, realm = Chomp.NameSplitRealm("Test-Realm")
			assert(name == nil)
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
			assert(Chomp.NameMergedRealm("Test") == "Test-TestRealm")
		end)

		it("normalizes a supplied realm name", function()
			assert(Chomp.NameMergedRealm("Test", "Test Realm") == "Test-TestRealm")
		end)

		it("rejects a name that already includes the supplied realm", function()
			local success = pcall(Chomp.NameMergedRealm, "Test-TestRealm", "TestRealm")
			assert(not success)
		end)
	end)

	describe("with regional unique names", function()
		before_each(function()
			stub(_G, "RegionalUniqueNamesEnabled", true)
		end)

		it("rejects a name without a surname", function()
			local success = pcall(Chomp.NameMergedRealm, "Test")
			assert(not success)
		end)

		it("preserves a full name supplied as one value", function()
			assert(Chomp.NameMergedRealm("Test Realm") == "Test Realm")
		end)

		it("joins a full name returned as separate values", function()
			local firstName, surname = UnitFullName("target")
			assert(Chomp.NameMergedRealm(firstName, surname) == "Test Realm")
		end)

		it("rejects a full name that already includes the supplied surname", function()
			local success = pcall(Chomp.NameMergedRealm, "Test Realm", "Realm")
			assert(not success)
		end)
	end)
end)
