--!strict
-- Config.lua  (ReplicatedStorage/Shared)
-- THE single source of tunable numbers. If a value affects balance, it lives here.
-- Everything else (services, math) reads from this table so you can tune the whole
-- economy in one place.

local Config = {}

-- ---------------------------------------------------------------------------
-- Core fry math
-- ---------------------------------------------------------------------------
-- Value at pass n:  V = baseValue * fryerMult ^ n
-- Burn chance past the fryer's safe line S:  q(n) = burnPerPass * (n - S), clamped.
Config.Fry = {
	burnPerPass = 0.12, -- +12% burn chance for each pass beyond the safe line
	burnChanceCap = 0.95, -- never a guaranteed burn; keeps a sliver of hope
	crumbFraction = 0.10, -- Burnt Crumb = 10% of last safe value
	minFryTime = 0.5, -- floor on fry pass duration after upgrades (seconds)
}

-- ---------------------------------------------------------------------------
-- Conveyor / lanes
-- ---------------------------------------------------------------------------
Config.Conveyor = {
	baseSpawnInterval = 4.0, -- seconds to spawn a fresh meme into an empty lane
	startingLanes = 1, -- lanes a new player has
	maxLanes = 3,
}

-- ---------------------------------------------------------------------------
-- Rarity table. Weights are percentages that sum to 100. Rolled server-side:
-- pick a rarity by weight, then pick uniformly among that rarity's templates.
-- baseValue here is the canonical value for the rarity; individual templates
-- inherit it (see Templates.lua).
-- ---------------------------------------------------------------------------
Config.Rarities = {
	{ name = "Common", weight = 60.0, baseValue = 1 },
	{ name = "Uncommon", weight = 25.0, baseValue = 3 },
	{ name = "Rare", weight = 10.0, baseValue = 10 },
	{ name = "Epic", weight = 4.0, baseValue = 40 },
	{ name = "Legendary", weight = 0.9, baseValue = 200 },
	{ name = "Mythic", weight = 0.09, baseValue = 1000 },
	{ name = "Cursed", weight = 0.01, baseValue = 10000 },
}

-- Display colors for the codex / meme cards (client-side only).
Config.RarityColors = {
	Common = Color3.fromRGB(180, 180, 180),
	Uncommon = Color3.fromRGB(90, 200, 90),
	Rare = Color3.fromRGB(70, 140, 255),
	Epic = Color3.fromRGB(170, 90, 240),
	Legendary = Color3.fromRGB(255, 175, 40),
	Mythic = Color3.fromRGB(255, 80, 140),
	Cursed = Color3.fromRGB(200, 40, 40),
}

-- ---------------------------------------------------------------------------
-- Fryers. Player auto-uses the best fryer they've unlocked (ownedFryer index).
-- A fryer unlocks the moment lifetime Crunch reaches unlockCrunch.
-- ---------------------------------------------------------------------------
Config.Fryers = {
	{ id = 1, name = "Rusty Basket", mult = 1.6, safe = 3, fryTime = 2.0, unlockCrunch = 0 },
	{ id = 2, name = "Diner Deep-Fryer", mult = 1.7, safe = 3, fryTime = 1.9, unlockCrunch = 2500 },
	{ id = 3, name = "Industrial Vat", mult = 1.8, safe = 4, fryTime = 1.7, unlockCrunch = 40000 },
}

-- ---------------------------------------------------------------------------
-- Upgrades. Cost of the NEXT level = baseCost * costGrowth ^ currentLevel.
-- Effects are resolved in Upgrades.lua so the numbers stay declarative here.
-- ---------------------------------------------------------------------------
Config.Upgrades = {
	costGrowth = 1.7,

	spawnRate = {
		id = "spawnRate",
		name = "Faster Conveyor",
		desc = "Memes spawn quicker.",
		baseCost = 50,
		maxLevel = 20,
		-- Each level multiplies the spawn interval by this (compounding).
		intervalFactorPerLevel = 0.92,
	},

	lane = {
		id = "lane",
		name = "Extra Lane",
		desc = "Fry more memes at once (max 3 lanes).",
		baseCost = 1000,
		-- maxLevel derived from Conveyor.maxLanes - startingLanes; kept explicit for clarity.
		maxLevel = 2,
	},

	oil = {
		id = "oil",
		name = "Premium Oil",
		desc = "+1 safe pass and gentler burns per level.",
		baseCost = 250,
		maxLevel = 6,
		safeBonusPerLevel = 1, -- +1 safe pass per level
		burnReductionPerLevel = 0.01, -- burnPerPass reduced by this per level (additive)
	},
}

-- ---------------------------------------------------------------------------
-- Rebirth
-- ---------------------------------------------------------------------------
Config.Rebirth = {
	minCrunch = 100000, -- must have at least this much banked Crunch to rebirth
	permMultStep = 1.5, -- permanent income multiplier gained per rebirth (multiplicative)
	-- Fields wiped on rebirth. Codex, rebirths, permMult, grease persist.
	resetFields = { "crunch", "ownedFryer", "upgradeLevels" },
}

-- ---------------------------------------------------------------------------
-- Saving
-- ---------------------------------------------------------------------------
Config.Save = {
	dataStoreName = "DeepFryFactory_v1",
	keyPrefix = "Player_",
	autoSaveInterval = 60, -- seconds
	sessionLockStaleAfter = 1800, -- seconds; a lock older than this is considered abandoned
	loadRetries = 5,
	retryDelay = 2,
}

-- Default save profile for a brand-new player. Stub fields (grease, era) are here so
-- Phase 2 systems have somewhere to live without a data migration.
Config.DefaultData = {
	crunch = 0,
	ownedFryer = 1,
	upgradeLevels = { spawnRate = 0, lane = 0, oil = 0 },
	codex = {}, -- [templateId] = true once discovered
	rebirths = 0,
	permMult = 1.0,

	-- Phase 2 stubs (persisted now so later features don't need a migration).
	grease = 0,
	era = "RageComics",
}

-- Anti-spam: minimum seconds between accepted intents of the same kind per player.
Config.RateLimit = {
	startFry = 0.1,
	bank = 0.1,
	buyUpgrade = 0.15,
	rebirth = 1.0,
}

return Config
