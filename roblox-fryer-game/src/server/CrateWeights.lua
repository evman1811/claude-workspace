--!strict
-- CrateWeights.lua  (ServerStorage) -- SECRET. Never replicated to clients.
--
-- The single source of truth for drop rates. Two consumers read from here and NOWHERE
-- else so disclosed odds can never drift from actual rolls:
--   1. WeightedRandom  -> uses weights to pick a reward.
--   2. CrateService.getDisclosure -> converts the SAME weights into percentages.
--
-- Weights are relative (not percentages). A reward's probability = weight / sum(weights).
-- Keep this file in ServerStorage (or ServerScriptService). If it ever ends up in
-- ReplicatedStorage, hidden rates are no longer hidden -- treat that as a P0 bug.

export type WeightRow = { rewardId: string, weight: number }

local Weights: { [string]: { WeightRow } } = {
	-- Greasy Crate (hidden-rate, earned currency). Odds never shown to players.
	crate_greasy = {
		{ rewardId = "fryer_cast_iron", weight = 550 }, -- 55.00%
		{ rewardId = "currency_frys_500", weight = 250 }, -- 25.00%
		{ rewardId = "fryer_stainless", weight = 120 }, -- 12.00%
		{ rewardId = "boost_2x_frys_10m", weight = 60 }, -- 6.00%
		{ rewardId = "fryer_titanium", weight = 20 }, -- 2.00%
	},

	-- Golden Crate (Robux-linked). These EXACT weights become the disclosed odds.
	crate_golden = {
		{ rewardId = "fryer_titanium", weight = 500 }, -- 50.00%
		{ rewardId = "boost_2x_frys_10m", weight = 250 }, -- 25.00%
		{ rewardId = "fryer_plasma", weight = 150 }, -- 15.00%
		{ rewardId = "cosmetic_neon_basket", weight = 60 }, -- 6.00%
		{ rewardId = "fryer_golden", weight = 35 }, -- 3.50%
		{ rewardId = "fryer_singularity", weight = 5 }, -- 0.50%
	},
}

local CrateWeights = {}

function CrateWeights.get(crateId: string): { WeightRow }?
	return Weights[crateId]
end

-- Total weight for a crate; used to turn weights into percentages.
function CrateWeights.total(crateId: string): number
	local rows = Weights[crateId]
	if not rows then
		return 0
	end
	local sum = 0
	for _, row in rows do
		sum += row.weight
	end
	return sum
end

return CrateWeights
