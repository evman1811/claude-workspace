--!strict
-- WeightedRandom.lua  (ServerStorage/ServerScriptService)
-- Server-authoritative weighted selection + pity. Pure functions where possible so it's
-- unit-testable. Uses a per-call Random object (never math.random) for reproducibility
-- in tests and to avoid global RNG state contention.

local CrateWeights = require(script.Parent.CrateWeights)

export type WeightRow = CrateWeights.WeightRow

local WeightedRandom = {}

-- Pick a rewardId from a crate's weights. `rng` is a Random; pass your own in tests.
-- Returns nil only if the crate has no weights configured (a bug).
function WeightedRandom.roll(crateId: string, rng: Random): string?
	local rows = CrateWeights.get(crateId)
	if not rows or #rows == 0 then
		return nil
	end

	local total = CrateWeights.total(crateId)
	if total <= 0 then
		return nil
	end

	-- rng:NextNumber(0, total) is in [0, total). Walk the cumulative distribution.
	local target = rng:NextNumber(0, total)
	local cumulative = 0
	for _, row in rows do
		cumulative += row.weight
		if target < cumulative then
			return row.rewardId
		end
	end

	-- Floating-point safety net: fall through to the last row.
	return rows[#rows].rewardId
end

-- Ordinal ranking of rarities so pity can enforce "at least Epic".
local RARITY_RANK: { [string]: number } = {
	Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6,
}

function WeightedRandom.rarityRank(rarity: string): number
	return RARITY_RANK[rarity] or 0
end

-- Among a crate's pool, roll but FORCE a result whose rarity >= floorRarity.
-- Used when the pity counter fires. Re-weights only the qualifying rows so the pity
-- reward still respects relative rarity among the qualifying set (a golden pity is
-- rarer than an epic pity).
-- `rarityOf` maps rewardId -> rarity string (server passes a resolver from the catalog).
function WeightedRandom.rollWithFloor(
	crateId: string,
	floorRarity: string,
	rarityOf: (string) -> string?,
	rng: Random
): string?
	local rows = CrateWeights.get(crateId)
	if not rows then
		return nil
	end

	local floor = WeightedRandom.rarityRank(floorRarity)
	local qualifying: { WeightRow } = {}
	local total = 0
	for _, row in rows do
		local rarity = rarityOf(row.rewardId)
		if rarity and WeightedRandom.rarityRank(rarity) >= floor then
			table.insert(qualifying, row)
			total += row.weight
		end
	end

	-- If nothing qualifies (misconfigured pity floor), fall back to a normal roll
	-- rather than handing out nothing.
	if #qualifying == 0 or total <= 0 then
		return WeightedRandom.roll(crateId, rng)
	end

	local target = rng:NextNumber(0, total)
	local cumulative = 0
	for _, row in qualifying do
		cumulative += row.weight
		if target < cumulative then
			return row.rewardId
		end
	end
	return qualifying[#qualifying].rewardId
end

return WeightedRandom
