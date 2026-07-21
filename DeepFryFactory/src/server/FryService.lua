--!strict
-- FryService.lua  (ServerScriptService/DeepFry)
-- The core loop, fully server-authoritative:
--   * conveyor spawns memes into empty lanes on a timer,
--   * StartFry runs one fry pass (timed), then rolls burn,
--   * Bank cashes a meme out for Crunch and unlocks better fryers.
-- The client only sends lane indices; every value, roll, and currency change happens here.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local Config = require(Shared:WaitForChild("Config"))
local Templates = require(Shared:WaitForChild("Templates"))
local Fryers = require(Shared:WaitForChild("Fryers"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))
local FryMath = require(Shared:WaitForChild("FryMath"))

local DataService = require(script.Parent.DataService)
local PlayerRuntime = require(script.Parent.PlayerRuntime)

local FryService = {}

local rng = Random.new()

local function currentFryer(data: any): Fryers.Fryer
	return (Fryers.get(data.ownedFryer) or Fryers.get(1)) :: Fryers.Fryer
end

local function clearLane(lane: PlayerRuntime.Lane)
	lane.state = "empty"
	lane.template = nil
	lane.pass = 0
	lane.fryStartClock = nil
	lane.fryDuration = nil
	lane.fryToken += 1 -- invalidate any pending resolution
	lane.nextSpawnAt = os.clock() + Config.Conveyor.baseSpawnInterval -- refined below on spawn
end

-- Recompute an empty lane's spawn timer using the player's current upgrade levels.
local function scheduleSpawn(data: any, lane: PlayerRuntime.Lane)
	lane.nextSpawnAt = os.clock() + Upgrades.spawnInterval(data.upgradeLevels)
end

-- ---- conveyor --------------------------------------------------------------

-- Mark a template discovered in the codex; returns true if it's newly discovered.
local function discover(data: any, template: Templates.Template): boolean
	if not data.codex[template.id] then
		data.codex[template.id] = true
		return true
	end
	return false
end

local function stepConveyor()
	local nowc = os.clock()
	PlayerRuntime.forEach(function(player, rt)
		local data = DataService.get(player)
		if not data then
			return
		end
		local changed = false
		for _, lane in rt.lanes do
			if lane.state == "empty" then
				if not lane.nextSpawnAt then
					scheduleSpawn(data, lane)
				elseif nowc >= lane.nextSpawnAt then
					local template = Templates.roll(rng)
					lane.template = template
					lane.pass = 0
					lane.state = "ready"
					lane.fryStartClock = nil
					lane.fryDuration = nil
					lane.nextSpawnAt = nil
					changed = true
					if discover(data, template) then
						PlayerRuntime.toast(player, "discover", "New meme discovered: " .. template.name .. "!")
					end
				end
			end
		end
		if changed then
			PlayerRuntime.push(player)
		end
	end)
end

-- ---- intents ---------------------------------------------------------------

function FryService.startFry(player: Player, laneIndex: unknown)
	if type(laneIndex) ~= "number" then
		return
	end
	if not PlayerRuntime.allowIntent(player, "startFry", Config.RateLimit.startFry) then
		return
	end
	local rt = PlayerRuntime.get(player)
	local data = DataService.get(player)
	if not rt or not data then
		return
	end
	local lane = rt.lanes[laneIndex]
	if not lane or lane.state ~= "ready" or not lane.template then
		return
	end

	local fryer = currentFryer(data)
	local duration = math.max(Config.Fry.minFryTime, fryer.fryTime)

	lane.state = "frying"
	lane.fryStartClock = os.clock()
	lane.fryDuration = duration
	lane.fryToken += 1
	local token = lane.fryToken
	PlayerRuntime.push(player)

	task.delay(duration, function()
		FryService._resolvePass(player, laneIndex, token)
	end)
end

-- Resolve a fry pass after its timer. `token` guards against stale/duplicate resolutions
-- (e.g. the lane was banked or the meme burned via another path in the meantime).
function FryService._resolvePass(player: Player, laneIndex: number, token: number)
	if player.Parent ~= Players then
		return
	end
	local rt = PlayerRuntime.get(player)
	local data = DataService.get(player)
	if not rt or not data then
		return
	end
	local lane = rt.lanes[laneIndex]
	if not lane or lane.state ~= "frying" or lane.fryToken ~= token or not lane.template then
		return
	end

	local fryer = currentFryer(data)
	local safeLine = FryMath.safeLine(fryer.safe, Upgrades.oilSafeBonus(data.upgradeLevels))
	local burnPerPass = Upgrades.burnPerPass(data.upgradeLevels)

	local attemptPass = lane.pass + 1
	local q = FryMath.burnChance(attemptPass, safeLine, burnPerPass)

	if rng:NextNumber(0, 1) < q then
		-- BURN: meme lost, award a Burnt Crumb (10% of last safe value).
		local crumb = FryMath.crumbValue(lane.template.baseValue, fryer.mult, lane.pass, safeLine)
		local gain = math.floor(crumb * data.permMult)
		data.crunch += gain
		PlayerRuntime.toast(player, "burn", ("Burned! Salvaged %d Crunch."):format(gain))
		clearLane(lane)
		scheduleSpawn(data, lane)
		FryService._checkFryerUnlock(player, data)
	else
		-- SURVIVE: value grows, meme is ready to bank or risk again.
		lane.pass = attemptPass
		lane.state = "ready"
		lane.fryStartClock = nil
		lane.fryDuration = nil
	end

	PlayerRuntime.push(player)
end

function FryService.bank(player: Player, laneIndex: unknown)
	if type(laneIndex) ~= "number" then
		return
	end
	if not PlayerRuntime.allowIntent(player, "bank", Config.RateLimit.bank) then
		return
	end
	local rt = PlayerRuntime.get(player)
	local data = DataService.get(player)
	if not rt or not data then
		return
	end
	local lane = rt.lanes[laneIndex]
	if not lane or lane.state ~= "ready" or not lane.template then
		return
	end

	local fryer = currentFryer(data)
	local value = FryMath.value(lane.template.baseValue, fryer.mult, lane.pass)
	local gain = math.floor(value * data.permMult)
	data.crunch += gain
	PlayerRuntime.toast(player, "bank", ("Banked %d Crunch!"):format(gain))

	clearLane(lane)
	scheduleSpawn(data, lane)
	FryService._checkFryerUnlock(player, data)
	PlayerRuntime.push(player)
end

-- Auto-unlock the best fryer the player's Crunch now affords.
function FryService._checkFryerUnlock(player: Player, data: any)
	local best = Fryers.highestUnlocked(data.crunch)
	if best > data.ownedFryer then
		data.ownedFryer = best
		local f = Fryers.get(best)
		if f then
			PlayerRuntime.toast(player, "fryer", "Unlocked fryer: " .. f.name .. "!")
		end
	end
end

-- ---- lifecycle -------------------------------------------------------------

function FryService.start()
	-- Conveyor heartbeat. A single loop steps every player's lanes; cheap for an MVP.
	task.spawn(function()
		while true do
			stepConveyor()
			task.wait(0.2)
		end
	end)
end

return FryService
