--!strict
-- InMemoryDataAdapter.lua
-- A minimal DataAdapter for local testing / Studio play. NOT for production -- it does
-- not persist. In production, implement the same interface backed by ProfileService or
-- DataStore, and make spendCurrency ATOMIC (check-and-deduct in one guarded step) so two
-- rapid opens can't double-spend.

local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("CrateTypes"))

type RewardInfo = Types.RewardInfo

local InMemoryDataAdapter = {}

type State = {
	currency: { [string]: number },
	inventory: { RewardInfo },
	pity: { [string]: number },
}

local states: { [Player]: State } = {}

local function stateFor(player: Player): State
	local s = states[player]
	if not s then
		s = {
			currency = { Frys = 100000, CrunchTokens = 0 }, -- starter funds for testing
			inventory = {},
			pity = {},
		}
		states[player] = s
	end
	return s
end

function InMemoryDataAdapter.getCurrency(player: Player, currency: string): number
	return stateFor(player).currency[currency] or 0
end

function InMemoryDataAdapter.spendCurrency(player: Player, currency: string, amount: number): boolean
	local s = stateFor(player)
	local have = s.currency[currency] or 0
	if have < amount then
		return false
	end
	s.currency[currency] = have - amount
	return true
end

function InMemoryDataAdapter.grantReward(player: Player, reward: RewardInfo)
	local s = stateFor(player)
	if reward.kind == "Currency" and reward.amount then
		s.currency.Frys = (s.currency.Frys or 0) + reward.amount
	end
	table.insert(s.inventory, reward)
end

function InMemoryDataAdapter.getPity(player: Player, crateId: string): number
	return stateFor(player).pity[crateId] or 0
end

function InMemoryDataAdapter.setPity(player: Player, crateId: string, value: number)
	stateFor(player).pity[crateId] = value
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

return InMemoryDataAdapter
