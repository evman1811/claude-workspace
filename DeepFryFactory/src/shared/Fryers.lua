--!strict
-- Fryers.lua  (ReplicatedStorage/Shared)
-- Thin accessor over Config.Fryers. Player uses the best fryer they've unlocked.

local Config = require(script.Parent.Config)

export type Fryer = {
	id: number,
	name: string,
	mult: number,
	safe: number,
	fryTime: number,
	unlockCrunch: number,
}

local Fryers = {}

Fryers.List = Config.Fryers :: { Fryer }

Fryers.ById = {} :: { [number]: Fryer }
for _, f in Config.Fryers do
	Fryers.ById[f.id] = f
end

function Fryers.get(id: number): Fryer?
	return Fryers.ById[id]
end

-- Highest fryer id whose unlockCrunch <= lifetimeCrunch.
function Fryers.highestUnlocked(lifetimeCrunch: number): number
	local best = 1
	for _, f in Fryers.List do
		if lifetimeCrunch >= f.unlockCrunch and f.id > best then
			best = f.id
		end
	end
	return best
end

return Fryers
