--!strict
-- Templates.lua  (ReplicatedStorage/Shared)
-- The ~10 meme templates for the Rage Comics era. Names are ORIGINAL placeholders --
-- no copyrighted meme images or names. Swap `iconId` for your own uploaded art later.
--
-- Each template inherits its rarity's baseValue from Config. Rolling is done in two
-- steps (rarity by weight, then uniform within rarity) so drop rates exactly match the
-- Config.Rarities weights regardless of how many templates share a rarity.

local Config = require(script.Parent.Config)

export type Template = {
	id: string,
	name: string,
	rarity: string,
	baseValue: number,
	iconId: string?, -- rbxassetid; nil uses a generated placeholder swatch
}

-- rarity -> baseValue lookup from Config.
local rarityValue: { [string]: number } = {}
for _, r in Config.Rarities do
	rarityValue[r.name] = r.baseValue
end

local function make(id: string, name: string, rarity: string): Template
	local baseValue = rarityValue[rarity]
	assert(baseValue ~= nil, "Template " .. id .. " has unknown rarity " .. rarity)
	return { id = id, name = name, rarity = rarity, baseValue = baseValue }
end

-- 10 original placeholder templates spread across the 7 rarities.
local list: { Template } = {
	make("blank_bob", "Blank-Stare Bob", "Common"),
	make("meh_manny", "Meh Manny", "Common"),
	make("grumble_gary", "Grumble Gary", "Uncommon"),
	make("sly_sammy", "Sly Sammy", "Uncommon"),
	make("rage_randy", "Rage Randy", "Rare"),
	make("panic_pete", "Panic Pete", "Rare"),
	make("overcooked_olly", "Overcooked Olly", "Epic"),
	make("golden_gordon", "Golden Gordon", "Legendary"),
	make("mythic_marge", "Mythic Marge", "Mythic"),
	make("cursed_carl", "Cursed Carl", "Cursed"),
}

local Templates = {}

Templates.List = list

-- id -> Template
Templates.ById = {} :: { [string]: Template }
-- rarity -> { Template }
Templates.ByRarity = {} :: { [string]: { Template } }

for _, t in list do
	Templates.ById[t.id] = t
	local bucket = Templates.ByRarity[t.rarity]
	if not bucket then
		bucket = {}
		Templates.ByRarity[t.rarity] = bucket
	end
	table.insert(bucket, t)
end

function Templates.get(id: string): Template?
	return Templates.ById[id]
end

-- Server-authoritative roll. Pass in a Random (injected for tests / determinism).
function Templates.roll(rng: Random): Template
	-- Total weight (defensive; Config sums to 100 but don't assume).
	local total = 0
	for _, r in Config.Rarities do
		total += r.weight
	end

	local target = rng:NextNumber(0, total)
	local cumulative = 0
	local chosenRarity = Config.Rarities[#Config.Rarities].name
	for _, r in Config.Rarities do
		cumulative += r.weight
		if target < cumulative then
			chosenRarity = r.name
			break
		end
	end

	local bucket = Templates.ByRarity[chosenRarity]
	if not bucket or #bucket == 0 then
		-- Rarity with no templates configured: fall back to a Common.
		bucket = Templates.ByRarity["Common"]
	end
	return bucket[rng:NextInteger(1, #bucket)]
end

return Templates
