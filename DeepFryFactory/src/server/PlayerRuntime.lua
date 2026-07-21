--!strict
-- PlayerRuntime.lua  (ServerScriptService/DeepFry)
-- Per-player VOLATILE state (not saved): the live lanes and their fry passes, plus the
-- one place that builds the state snapshot and pushes it to the client. Persistent data
-- lives in DataService; this is the runtime layer on top of it.

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Templates = require(Shared:WaitForChild("Templates"))
local Fryers = require(Shared:WaitForChild("Fryers"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))
local FryMath = require(Shared:WaitForChild("FryMath"))
local DataService = require(script.Parent.DataService)

export type Lane = {
	state: string, -- "empty" | "ready" | "frying"
	template: Templates.Template?,
	pass: number,
	fryStartClock: number?, -- os.clock() when the current pass began
	fryDuration: number?,
	fryToken: number, -- bumped to invalidate stale scheduled resolutions
	nextSpawnAt: number?, -- os.clock() when an empty lane should spawn its next meme
}

export type Runtime = {
	lanes: { Lane },
	lastIntent: { [string]: number }, -- intent name -> last accepted os.clock()
}

local PlayerRuntime = {}

local runtimes: { [Player]: Runtime } = {}

local SyncEvent: RemoteEvent
local ToastEvent: RemoteEvent

function PlayerRuntime.init()
	SyncEvent = Remotes.get(Remotes.Names.SyncState)
	ToastEvent = Remotes.get(Remotes.Names.Toast)
end

local function newLane(): Lane
	return {
		state = "empty",
		template = nil,
		pass = 0,
		fryStartClock = nil,
		fryDuration = nil,
		fryToken = 0,
		nextSpawnAt = nil,
	}
end

function PlayerRuntime.create(player: Player)
	runtimes[player] = { lanes = {}, lastIntent = {} }
end

function PlayerRuntime.destroy(player: Player)
	runtimes[player] = nil
end

function PlayerRuntime.get(player: Player): Runtime?
	return runtimes[player]
end

-- Grow the lane list to match the player's purchased lane count. Lanes only ever
-- increase (max 3), so we never destroy an in-progress fry.
function PlayerRuntime.ensureLanes(player: Player, data: any)
	local rt = runtimes[player]
	if not rt then
		return
	end
	local want = Upgrades.laneCount(data.upgradeLevels)
	while #rt.lanes < want do
		local lane = newLane()
		lane.nextSpawnAt = os.clock() -- spawn its first meme promptly
		table.insert(rt.lanes, lane)
	end
end

-- Wipe all lanes and rebuild to the player's current lane count. Used on rebirth, when
-- the lane upgrade is reset. Any pending fry resolutions are invalidated by token mismatch.
function PlayerRuntime.resetLanes(player: Player, data: any)
	local rt = runtimes[player]
	if not rt then
		return
	end
	rt.lanes = {}
	PlayerRuntime.ensureLanes(player, data)
end

-- Simple per-intent rate limit. Returns true if the intent is allowed right now.
function PlayerRuntime.allowIntent(player: Player, intent: string, minGap: number): boolean
	local rt = runtimes[player]
	if not rt then
		return false
	end
	local last = rt.lastIntent[intent]
	local nowc = os.clock()
	if last and (nowc - last) < minGap then
		return false
	end
	rt.lastIntent[intent] = nowc
	return true
end

-- ---- snapshot --------------------------------------------------------------

-- The fryer the player currently uses (best unlocked).
local function currentFryer(data: any): Fryers.Fryer
	local f = Fryers.get(data.ownedFryer) or Fryers.get(1)
	return f :: Fryers.Fryer
end

function PlayerRuntime.buildSnapshot(player: Player): any?
	local data = DataService.get(player)
	local rt = runtimes[player]
	if not data or not rt then
		return nil
	end

	local fryer = currentFryer(data)
	local safeLine = FryMath.safeLine(fryer.safe, Upgrades.oilSafeBonus(data.upgradeLevels))
	local burnPerPass = Upgrades.burnPerPass(data.upgradeLevels)

	local lanes = {}
	for i, lane in rt.lanes do
		local value = 0
		local nextBurn = 0
		local templateId, rarity
		if lane.template then
			templateId = lane.template.id
			rarity = lane.template.rarity
			value = FryMath.value(lane.template.baseValue, fryer.mult, lane.pass)
			nextBurn = FryMath.burnChance(lane.pass + 1, safeLine, burnPerPass)
		end
		-- Server os.clock() is meaningless to the client, so send seconds REMAINING on
		-- the in-progress pass. The client animates its own local timer from there.
		local fryRemaining: number? = nil
		if lane.state == "frying" and lane.fryStartClock and lane.fryDuration then
			fryRemaining = math.max(0, lane.fryDuration - (os.clock() - lane.fryStartClock))
		end
		table.insert(lanes, {
			index = i,
			state = lane.state,
			templateId = templateId,
			rarity = rarity,
			pass = lane.pass,
			value = value,
			fryRemaining = fryRemaining,
			fryDuration = lane.fryDuration,
			nextBurnChance = nextBurn,
		})
	end

	local upgradeView = {}
	for _, id in Upgrades.Order do
		local level = data.upgradeLevels[id] or 0
		upgradeView[id] = {
			level = level,
			cost = Upgrades.costFor(id, level),
			maxed = Upgrades.isMaxed(id, level),
		}
	end

	return {
		crunch = data.crunch,
		permMult = data.permMult,
		rebirths = data.rebirths,
		ownedFryer = data.ownedFryer,
		fryerName = fryer.name,
		fryerMult = fryer.mult,
		safeLine = safeLine,
		burnPerPass = burnPerPass,
		upgradeLevels = data.upgradeLevels,
		codex = data.codex,
		lanes = lanes,
		upgradeView = upgradeView,
		canRebirth = data.crunch >= Config.Rebirth.minCrunch,
	}
end

function PlayerRuntime.push(player: Player)
	local snapshot = PlayerRuntime.buildSnapshot(player)
	if snapshot then
		SyncEvent:FireClient(player, snapshot)
	end
end

function PlayerRuntime.toast(player: Player, kind: string, text: string)
	ToastEvent:FireClient(player, kind, text)
end

-- Iterate all live runtimes (used by the conveyor loop).
function PlayerRuntime.forEach(fn: (player: Player, rt: Runtime) -> ())
	for player, rt in runtimes do
		if player.Parent == Players then
			fn(player, rt)
		end
	end
end

return PlayerRuntime
