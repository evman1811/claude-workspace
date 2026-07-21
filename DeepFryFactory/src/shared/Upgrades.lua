--!strict
-- Upgrades.lua  (ReplicatedStorage/Shared)
-- Upgrade cost curve + effect resolution. Pure functions: given a player's upgradeLevels
-- table, return the derived gameplay values. Server trusts these; client uses the same
-- functions to preview costs/effects so the two never disagree.

local Config = require(script.Parent.Config)

local Upgrades = {}

Upgrades.Defs = {
	spawnRate = Config.Upgrades.spawnRate,
	lane = Config.Upgrades.lane,
	oil = Config.Upgrades.oil,
}

-- Ordered list for stable UI rendering.
Upgrades.Order = { "spawnRate", "lane", "oil" }

function Upgrades.getDef(id: string)
	return Upgrades.Defs[id]
end

-- Cost of the NEXT level (going from `level` to `level+1`).
-- cost = baseCost * costGrowth ^ level
function Upgrades.costFor(id: string, level: number): number
	local def = Upgrades.Defs[id]
	if not def then
		return math.huge
	end
	return math.floor(def.baseCost * (Config.Upgrades.costGrowth ^ level))
end

function Upgrades.maxLevel(id: string): number
	local def = Upgrades.Defs[id]
	return def and def.maxLevel or 0
end

function Upgrades.isMaxed(id: string, level: number): boolean
	return level >= Upgrades.maxLevel(id)
end

-- ---- Derived gameplay values -------------------------------------------------

-- Effective conveyor spawn interval given the spawnRate level.
function Upgrades.spawnInterval(levels: { [string]: number }): number
	local lvl = levels.spawnRate or 0
	local def = Config.Upgrades.spawnRate
	local interval = Config.Conveyor.baseSpawnInterval * (def.intervalFactorPerLevel ^ lvl)
	return math.max(0.25, interval)
end

-- Number of active lanes.
function Upgrades.laneCount(levels: { [string]: number }): number
	local lvl = levels.lane or 0
	return math.min(Config.Conveyor.maxLanes, Config.Conveyor.startingLanes + lvl)
end

-- Extra safe passes from oil.
function Upgrades.oilSafeBonus(levels: { [string]: number }): number
	local lvl = levels.oil or 0
	return lvl * Config.Upgrades.oil.safeBonusPerLevel
end

-- Effective per-pass burn coefficient after oil reduction (never below a small floor).
function Upgrades.burnPerPass(levels: { [string]: number }): number
	local lvl = levels.oil or 0
	local reduced = Config.Fry.burnPerPass - lvl * Config.Upgrades.oil.burnReductionPerLevel
	return math.max(0.02, reduced)
end

return Upgrades
