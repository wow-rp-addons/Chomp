-- luacheck: globals describe it

local Chomp = require("SpecHelper")

describe("Chomp", function()
	it("Loads the addon Lua files", function()
		assert(type(Chomp) == "table")
		assert(type(Chomp.Internal) == "table")
		assert(type(Chomp.Serialize) == "function")
		assert(type(Chomp.Deserialize) == "function")
	end)
end)
