--!strict
-- Types.lua  (ReplicatedStorage/Shared)
-- Shared shapes for the state snapshot the server pushes to clients. Keeping them here
-- means the UI and the server agree on field names at compile time.

export type LaneSnapshot = {
	index: number,
	state: string, -- "empty" | "ready" | "frying"
	templateId: string?, -- nil when empty
	rarity: string?,
	pass: number, -- fry passes completed (0 = fresh)
	value: number, -- current value (already includes fryer mult, NOT permMult)
	-- Present only while state == "frying" so the client can animate the timer:
	fryRemaining: number?, -- seconds left on the in-progress pass (server-authoritative)
	fryDuration: number?, -- total seconds this pass takes
	-- Odds of the NEXT pass burning (for the Sizzle Meter), 0..1:
	nextBurnChance: number,
}

export type StateSnapshot = {
	crunch: number,
	permMult: number,
	rebirths: number,
	ownedFryer: number,
	fryerName: string,
	fryerMult: number, -- so the client can preview "value if this pass survives"
	safeLine: number, -- effective safe passes (fryer + oil)
	burnPerPass: number, -- effective burn coefficient after oil
	upgradeLevels: { [string]: number },
	codex: { [string]: boolean },
	lanes: { LaneSnapshot },
	-- Convenience for the shop UI: id -> { level, cost, maxed }
	upgradeView: { [string]: { level: number, cost: number, maxed: boolean } },
	canRebirth: boolean,
}

return nil
