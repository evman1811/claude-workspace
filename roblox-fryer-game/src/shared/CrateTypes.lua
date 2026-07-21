--!strict
-- CrateTypes.lua
-- Shared type definitions for the crate / paid-random-item system.
-- Placed in ReplicatedStorage so both client and server compile against the same shapes.
--
-- POLICY NOTE (read once):
--   Roblox "Paid Random Items" policy requires that any randomly-awarded item which can be
--   obtained with Robux -- directly OR indirectly (e.g. via an in-game currency that itself
--   can be bought with Robux) -- must have its odds disclosed to the player BEFORE purchase,
--   and those odds must be accurate.
--
--   Therefore every crate declares `robuxLinked`:
--     * robuxLinked = true  -> odds MUST be disclosable. The server refuses to open it
--                              otherwise. Disclosed odds are derived from the real weights,
--                              so they can never be wrong.
--     * robuxLinked = false -> pure earned-currency crate. Rates MAY stay hidden.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

-- Public, client-safe description of a single possible reward.
-- NOTE: this intentionally carries NO weight/odds. Weights live server-side only
-- (see CrateWeights in ServerStorage) so hidden-rate crates stay hidden.
export type RewardInfo = {
	id: string, -- stable reward id, e.g. "fryer_titanium"
	displayName: string,
	rarity: Rarity,
	kind: "Fryer" | "Cosmetic" | "Currency" | "Pet" | "Boost",
	amount: number?, -- for stackable rewards (currency, boosts)
	iconId: string?, -- rbxassetid for UI
}

-- Public, client-safe description of a crate. Contains everything the storefront UI
-- needs EXCEPT the odds. Never put weights in here.
export type CrateInfo = {
	id: string, -- stable crate id, e.g. "crate_golden"
	displayName: string,
	description: string,

	-- Cost side.
	currency: "Frys" | "CrunchTokens" | "Robux",
	price: number, -- amount of `currency`, or the developer-product/gamepass price context
	productId: number?, -- Roblox developer product id when currency == "Robux"

	-- Compliance flag. If the crate can be obtained with Robux directly or indirectly,
	-- this MUST be true and odds MUST be disclosable.
	robuxLinked: boolean,

	-- The full pool of things that CAN drop, for display ("what's inside").
	pool: { RewardInfo },

	-- Pity: guarantee a >= this rarity within `pityAfter` opens. 0 = no pity.
	pityAfter: number,
	pityFloorRarity: Rarity?,
}

-- What the server sends back after a successful open.
export type OpenResult = {
	ok: true,
	crateId: string,
	reward: RewardInfo,
	pityTriggered: boolean,
	opensUntilPity: number, -- remaining opens before pity fires (for honest UI)
}

export type OpenFailure = {
	ok: false,
	reason: string, -- machine-readable, e.g. "INSUFFICIENT_FUNDS", "ODDS_NOT_DISCLOSED"
}

export type OpenResponse = OpenResult | OpenFailure

-- One row of disclosed odds. Percent is 0..100, rounded for display but derived
-- from the exact server weights.
export type OddsRow = {
	rewardId: string,
	displayName: string,
	rarity: Rarity,
	percent: number, -- e.g. 3.5 means 3.5%
}

-- Disclosure payload. `hidden = true` is only ever legal when robuxLinked == false.
export type OddsDisclosure = {
	crateId: string,
	hidden: boolean, -- true only for pure earned-currency crates
	rows: { OddsRow }?, -- present iff hidden == false
}

return nil
