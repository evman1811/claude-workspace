--!strict
-- ShopService.lua  (ServerScriptService/DeepFry)
-- Upgrade purchases and rebirth. All currency checks happen here, server-side.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local Config = require(Shared:WaitForChild("Config"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))

local DataService = require(script.Parent.DataService)
local PlayerRuntime = require(script.Parent.PlayerRuntime)

local ShopService = {}

local function deepCopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = deepCopy(v)
	end
	return out
end

function ShopService.buyUpgrade(player: Player, upgradeId: unknown)
	if type(upgradeId) ~= "string" then
		return
	end
	if not PlayerRuntime.allowIntent(player, "buyUpgrade", Config.RateLimit.buyUpgrade) then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local def = Upgrades.getDef(upgradeId)
	if not def then
		return -- unknown upgrade id from a tampered client
	end

	local level = data.upgradeLevels[upgradeId] or 0
	if Upgrades.isMaxed(upgradeId, level) then
		PlayerRuntime.toast(player, "error", def.name .. " is maxed.")
		return
	end

	local cost = Upgrades.costFor(upgradeId, level)
	if data.crunch < cost then
		PlayerRuntime.toast(player, "error", ("Need %d Crunch for %s."):format(cost, def.name))
		return
	end

	data.crunch -= cost
	data.upgradeLevels[upgradeId] = level + 1

	-- The lane upgrade adds a physical lane to the runtime.
	if upgradeId == "lane" then
		PlayerRuntime.ensureLanes(player, data)
	end

	PlayerRuntime.toast(player, "buy", ("Bought %s (Lv %d)."):format(def.name, level + 1))
	PlayerRuntime.push(player)
end

function ShopService.rebirth(player: Player)
	if not PlayerRuntime.allowIntent(player, "rebirth", Config.RateLimit.rebirth) then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	if data.crunch < Config.Rebirth.minCrunch then
		PlayerRuntime.toast(player, "error", ("Need %d Crunch to rebirth."):format(Config.Rebirth.minCrunch))
		return
	end

	-- Grant the permanent multiplier and bump the counter BEFORE wiping run progress.
	data.permMult *= Config.Rebirth.permMultStep
	data.rebirths += 1

	-- Reset the configured run-progression fields to their defaults.
	for _, field in Config.Rebirth.resetFields do
		data[field] = deepCopy(Config.DefaultData[field])
	end

	-- Rebuild lanes to the (now reset) lane count.
	PlayerRuntime.resetLanes(player, data)

	PlayerRuntime.toast(player, "rebirth", ("Rebirth! Permanent x%.2f income now active."):format(data.permMult))
	PlayerRuntime.push(player)
end

return ShopService
