--!strict
-- CrateCatalog.lua  (ReplicatedStorage/Shared)
-- CLIENT-SAFE crate metadata. This is replicated to every client, so it must NEVER
-- contain drop weights. Weights live in ServerStorage/CrateWeights.lua only.
--
-- The client uses this to render the store, the "what's inside" list, and cost.
-- Odds are requested separately via a RemoteFunction and are only returned for
-- robuxLinked crates (or hidden for pure earned-currency crates).

local Types = require(script.Parent.CrateTypes)

type CrateInfo = Types.CrateInfo
type RewardInfo = Types.RewardInfo

-- Reusable reward definitions (public info only).
local R: { [string]: RewardInfo } = {
	fryer_cast_iron = { id = "fryer_cast_iron", displayName = "Cast-Iron Fryer", rarity = "Common", kind = "Fryer" },
	fryer_stainless = { id = "fryer_stainless", displayName = "Stainless Fryer", rarity = "Uncommon", kind = "Fryer" },
	fryer_titanium = { id = "fryer_titanium", displayName = "Titanium Fryer", rarity = "Rare", kind = "Fryer" },
	fryer_plasma = { id = "fryer_plasma", displayName = "Plasma Fryer", rarity = "Epic", kind = "Fryer" },
	fryer_golden = { id = "fryer_golden", displayName = "Golden Fryer", rarity = "Legendary", kind = "Fryer" },
	fryer_singularity = { id = "fryer_singularity", displayName = "Singularity Fryer", rarity = "Mythic", kind = "Fryer" },

	boost_2x_frys_10m = { id = "boost_2x_frys_10m", displayName = "2x Frys (10 min)", rarity = "Uncommon", kind = "Boost", amount = 600 },
	currency_frys_500 = { id = "currency_frys_500", displayName = "500 Frys", rarity = "Common", kind = "Currency", amount = 500 },
	cosmetic_neon_basket = { id = "cosmetic_neon_basket", displayName = "Neon Basket Skin", rarity = "Rare", kind = "Cosmetic" },
}

local Catalog: { [string]: CrateInfo } = {
	-- EARNED-CURRENCY CRATE. Bought only with Frys earned by playing. Frys are NOT
	-- purchasable with Robux, so this crate is NOT a paid random item -> rates may stay hidden.
	crate_greasy = {
		id = "crate_greasy",
		displayName = "Greasy Crate",
		description = "Fished out of the fryer vat. Who knows what's inside?",
		currency = "Frys",
		price = 2500,
		robuxLinked = false, -- <-- rates legally allowed to be hidden
		pool = {
			R.fryer_cast_iron, R.fryer_stainless, R.fryer_titanium,
			R.currency_frys_500, R.boost_2x_frys_10m,
		},
		pityAfter = 40,
		pityFloorRarity = "Rare",
	},

	-- ROBUX-LINKED CRATE. Purchased with a Robux developer product. This IS a paid
	-- random item -> odds MUST be disclosed. The server will refuse to open it unless
	-- disclosure is available (it always is, because odds are derived from real weights).
	crate_golden = {
		id = "crate_golden",
		displayName = "Golden Crate",
		description = "Premium crate. Odds shown before you buy.",
		currency = "Robux",
		price = 199, -- display price; real charge is the dev product
		productId = 000000000, -- TODO: replace with your developer product id
		robuxLinked = true, -- <-- odds disclosure REQUIRED
		pool = {
			R.fryer_titanium, R.fryer_plasma, R.fryer_golden, R.fryer_singularity,
			R.cosmetic_neon_basket, R.boost_2x_frys_10m,
		},
		pityAfter = 20,
		pityFloorRarity = "Epic",
	},
}

local CrateCatalog = {}

function CrateCatalog.get(crateId: string): CrateInfo?
	return Catalog[crateId]
end

function CrateCatalog.all(): { [string]: CrateInfo }
	return Catalog
end

return CrateCatalog
