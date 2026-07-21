--!strict
-- Bootstrap.server.lua  (Script in ServerScriptService/DeepFry)
-- Single entry point. Wires services, creates remotes, and routes client intents.
-- Order matters: remotes exist before any client can WaitForChild them; DataService and
-- runtime are ready before the first PlayerAdded fires.

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local Remotes = require(Shared:WaitForChild("Remotes"))
local Fryers = require(Shared:WaitForChild("Fryers"))

local DataService = require(script.Parent.DataService)
local PlayerRuntime = require(script.Parent.PlayerRuntime)
local FryService = require(script.Parent.FryService)
local ShopService = require(script.Parent.ShopService)

-- 1) Remotes first.
Remotes.init()

-- 2) Services.
PlayerRuntime.init()
DataService.start()
FryService.start()

-- 3) Player lifecycle.
local function onPlayerAdded(player: Player)
	local data = DataService.load(player)
	PlayerRuntime.create(player)

	-- Bring ownedFryer up to whatever the current Crunch unlocks (handles config changes).
	local best = Fryers.highestUnlocked(data.crunch)
	if best > data.ownedFryer then
		data.ownedFryer = best
	end

	PlayerRuntime.ensureLanes(player, data)
	PlayerRuntime.push(player)

	-- Redundant push shortly after join to cover the case where the client's SyncState
	-- listener wasn't connected yet when the first snapshot fired.
	task.delay(1.5, function()
		if player.Parent == Players then
			PlayerRuntime.push(player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	PlayerRuntime.destroy(player)
	-- DataService handles the save on PlayerRemoving itself.
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
-- Cover players who loaded before this script ran (Studio "Play" edge case).
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- 4) Route client intents. Each handler validates everything server-side.
local startFry = Remotes.get(Remotes.Names.StartFry)
local bank = Remotes.get(Remotes.Names.Bank)
local buyUpgrade = Remotes.get(Remotes.Names.BuyUpgrade)
local rebirth = Remotes.get(Remotes.Names.Rebirth)

startFry.OnServerEvent:Connect(function(player, laneIndex)
	FryService.startFry(player, laneIndex)
end)

bank.OnServerEvent:Connect(function(player, laneIndex)
	FryService.bank(player, laneIndex)
end)

buyUpgrade.OnServerEvent:Connect(function(player, upgradeId)
	ShopService.buyUpgrade(player, upgradeId)
end)

rebirth.OnServerEvent:Connect(function(player)
	ShopService.rebirth(player)
end)

print("[DeepFryFactory] Server ready.")
