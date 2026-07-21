--!strict
-- CrateService.lua  (ServerScriptService)
-- The one authority for opening crates. Responsibilities:
--   * Enforce the Paid Random Items policy (Robux-linked crates cannot open without
--     disclosable odds).
--   * Validate every request (client is never trusted for crate id, cost, or result).
--   * Charge currency / verify the Robux receipt, roll server-side, grant the reward.
--   * Maintain pity counters and expose HONEST odds via a RemoteFunction.
--
-- Wire-up (do this in a small bootstrap Script, or call CrateService.start()):
--   local CrateService = require(ServerScriptService.CrateService)
--   CrateService.start({ data = MyDataAdapter })
--
-- `data` must implement the DataAdapter interface below. Bridge it to your real save
-- system (ProfileService / DataStore). A trivial in-memory adapter is provided for tests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("CrateTypes"))
local CrateCatalog = require(Shared:WaitForChild("CrateCatalog"))

local WeightedRandom = require(script.Parent.WeightedRandom)
local CrateWeights = require(script.Parent.CrateWeights)

type CrateInfo = Types.CrateInfo
type RewardInfo = Types.RewardInfo
type OpenResponse = Types.OpenResponse
type OddsDisclosure = Types.OddsDisclosure
type OddsRow = Types.OddsRow

-- Your save system implements this. Every method takes a Player.
export type DataAdapter = {
	getCurrency: (player: Player, currency: string) -> number,
	spendCurrency: (player: Player, currency: string, amount: number) -> boolean, -- false if insufficient
	grantReward: (player: Player, reward: RewardInfo) -> (),
	getPity: (player: Player, crateId: string) -> number,
	setPity: (player: Player, crateId: string, value: number) -> (),
}

local CrateService = {}
CrateService.__index = CrateService

local _data: DataAdapter? = nil
local _rng = Random.new() -- server RNG; tests can inject their own via openInternal
local _lastOpen: { [Player]: number } = {} -- anti-spam cooldown timestamps
local OPEN_COOLDOWN = 0.35 -- seconds; also guards against duplicate client fires

-- Build a fast lookup: rewardId -> RewardInfo, from the public catalog pools.
local _rewardIndex: { [string]: RewardInfo } = {}
local function indexRewards()
	for _, crate in CrateCatalog.all() do
		for _, reward in crate.pool do
			_rewardIndex[reward.id] = reward
		end
	end
end

local function rarityOf(rewardId: string): string?
	local r = _rewardIndex[rewardId]
	return r and r.rarity or nil
end

-- ---------------------------------------------------------------------------
-- Odds disclosure (the compliance core).
-- Derived from the SAME weights used to roll, so disclosed odds are always accurate.
-- ---------------------------------------------------------------------------
function CrateService.getDisclosure(crateId: string): OddsDisclosure?
	local crate = CrateCatalog.get(crateId)
	if not crate then
		return nil
	end

	-- Pure earned-currency crate: legally allowed to hide odds.
	if not crate.robuxLinked then
		return { crateId = crateId, hidden = true, rows = nil }
	end

	-- Robux-linked: MUST disclose. Convert weights to percentages.
	local rows = CrateWeights.get(crateId)
	local total = CrateWeights.total(crateId)
	if not rows or total <= 0 then
		-- A Robux-linked crate with no weights is a configuration error. Fail closed.
		return nil
	end

	local out: { OddsRow } = {}
	for _, row in rows do
		local info = _rewardIndex[row.rewardId]
		table.insert(out, {
			rewardId = row.rewardId,
			displayName = info and info.displayName or row.rewardId,
			rarity = (info and info.rarity or "Common") :: any,
			-- Round to 2 decimals for display. Kept exact enough to be honest.
			percent = math.floor((row.weight / total) * 10000 + 0.5) / 100,
		})
	end
	return { crateId = crateId, hidden = false, rows = out }
end

-- Hard invariant: a Robux-linked crate is openable ONLY if disclosure exists.
local function canLegallyOpen(crate: CrateInfo): (boolean, string?)
	if not crate.robuxLinked then
		return true, nil
	end
	local disc = CrateService.getDisclosure(crate.id)
	if not disc or disc.hidden or not disc.rows or #disc.rows == 0 then
		return false, "ODDS_NOT_DISCLOSED"
	end
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Core open logic. `rng` is injectable for tests. This function assumes payment
-- has already been validated by the caller (currency spent, or Robux receipt verified).
-- ---------------------------------------------------------------------------
local function openInternal(player: Player, crate: CrateInfo, rng: Random): OpenResponse
	local data = assert(_data, "CrateService.start() must be called with a DataAdapter")

	local pity = data.getPity(player, crate.id)
	local pityTriggered = false
	local rewardId: string?

	if crate.pityAfter > 0 and crate.pityFloorRarity and (pity + 1) >= crate.pityAfter then
		rewardId = WeightedRandom.rollWithFloor(crate.id, crate.pityFloorRarity, rarityOf, rng)
		pityTriggered = true
	else
		rewardId = WeightedRandom.roll(crate.id, rng)
	end

	if not rewardId then
		return { ok = false, reason = "ROLL_FAILED" }
	end

	local reward = _rewardIndex[rewardId]
	if not reward then
		return { ok = false, reason = "UNKNOWN_REWARD" }
	end

	-- Update pity: reset if a pity-floor-or-better dropped, else increment.
	if crate.pityAfter > 0 and crate.pityFloorRarity then
		local floorRank = WeightedRandom.rarityRank(crate.pityFloorRarity)
		if WeightedRandom.rarityRank(reward.rarity) >= floorRank then
			data.setPity(player, crate.id, 0)
			pity = 0
		else
			data.setPity(player, crate.id, pity + 1)
			pity += 1
		end
	end

	data.grantReward(player, reward)

	local opensUntilPity = 0
	if crate.pityAfter > 0 then
		opensUntilPity = math.max(0, crate.pityAfter - pity)
	end

	return {
		ok = true,
		crateId = crate.id,
		reward = reward,
		pityTriggered = pityTriggered,
		opensUntilPity = opensUntilPity,
	}
end

-- ---------------------------------------------------------------------------
-- Request handler for soft-currency (Frys / CrunchTokens) opens.
-- Robux opens go through MarketplaceService.ProcessReceipt instead (see start()).
-- ---------------------------------------------------------------------------
local function handleOpenRequest(player: Player, crateId: unknown): OpenResponse
	-- Validate types coming off the wire.
	if typeof(crateId) ~= "string" then
		return { ok = false, reason = "BAD_REQUEST" }
	end

	-- Cooldown / anti-spam.
	local now = os.clock()
	local last = _lastOpen[player]
	if last and (now - last) < OPEN_COOLDOWN then
		return { ok = false, reason = "RATE_LIMITED" }
	end
	_lastOpen[player] = now

	local crate = CrateCatalog.get(crateId :: string)
	if not crate then
		return { ok = false, reason = "UNKNOWN_CRATE" }
	end

	-- Robux-linked crates are NOT bought through this path; they must go through the
	-- receipt flow so Roblox actually charges the player. Reject here.
	if crate.currency == "Robux" or crate.robuxLinked then
		return { ok = false, reason = "USE_ROBUX_PURCHASE" }
	end

	-- Compliance gate (defense-in-depth; earned crates pass trivially).
	local legal, why = canLegallyOpen(crate)
	if not legal then
		return { ok = false, reason = why or "ODDS_NOT_DISCLOSED" }
	end

	local data = assert(_data, "CrateService not started")

	-- Charge first, roll second. spendCurrency must be atomic in your data layer.
	if not data.spendCurrency(player, crate.currency, crate.price) then
		return { ok = false, reason = "INSUFFICIENT_FUNDS" }
	end

	return openInternal(player, crate, _rng)
end

-- ---------------------------------------------------------------------------
-- Startup: creates remotes and wires the Robux receipt processor.
-- ---------------------------------------------------------------------------
function CrateService.start(opts: { data: DataAdapter })
	assert(opts and opts.data, "CrateService.start requires { data = <DataAdapter> }")
	_data = opts.data
	indexRewards()

	-- Remotes live under ReplicatedStorage/Remotes.
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	local openEvent = Instance.new("RemoteEvent")
	openEvent.Name = "OpenCrate"
	openEvent.Parent = remotesFolder

	local oddsFunc = Instance.new("RemoteFunction")
	oddsFunc.Name = "GetCrateOdds"
	oddsFunc.Parent = remotesFolder

	-- Odds disclosure: client asks, server answers with honest odds (or hidden flag).
	oddsFunc.OnServerInvoke = function(_player: Player, crateId: unknown): OddsDisclosure?
		if typeof(crateId) ~= "string" then
			return nil
		end
		return CrateService.getDisclosure(crateId :: string)
	end

	-- Soft-currency open flow.
	openEvent.OnServerEvent:Connect(function(player: Player, crateId: unknown)
		local response = handleOpenRequest(player, crateId)
		openEvent:FireClient(player, response)
	end)

	-- Robux open flow: map developer products -> crate ids, verify receipts.
	local productToCrate: { [number]: string } = {}
	for _, crate in CrateCatalog.all() do
		if crate.robuxLinked and crate.productId then
			productToCrate[crate.productId] = crate.id
		end
	end

	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player then
			-- Player left; let Roblox retry later so we don't lose the purchase.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local crateId = productToCrate[receipt.ProductId]
		if not crateId then
			-- Not one of our crates; another handler owns it. Do not grant.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local crate = CrateCatalog.get(crateId)
		if not crate then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- Compliance gate: never open a Robux crate whose odds aren't disclosable.
		local legal = canLegallyOpen(crate)
		if not legal then
			warn(("[CrateService] Refusing paid open of %s: odds not disclosed"):format(crateId))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local response = openInternal(player, crate, _rng)
		if response.ok then
			openEvent:FireClient(player, response)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	Players.PlayerRemoving:Connect(function(player)
		_lastOpen[player] = nil
	end)
end

-- Exposed for unit tests: open with an injected RNG and pre-validated payment.
function CrateService._openForTest(player: Player, crateId: string, rng: Random): OpenResponse
	local crate = CrateCatalog.get(crateId)
	if not crate then
		return { ok = false, reason = "UNKNOWN_CRATE" }
	end
	return openInternal(player, crate, rng)
end

return CrateService
