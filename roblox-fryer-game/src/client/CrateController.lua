--!strict
-- CrateController.lua  (StarterPlayerScripts / a LocalScript require)
-- Client side of the crate flow. It NEVER decides rewards -- it only asks the server
-- and renders what comes back. Two responsibilities that matter for policy:
--   1. For Robux-linked crates, fetch and SHOW odds BEFORE the player commits to buy.
--   2. Open the reveal animation only from the server's authoritative OpenResponse.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("CrateTypes"))
local CrateCatalog = require(Shared:WaitForChild("CrateCatalog"))

type OpenResponse = Types.OpenResponse
type OddsDisclosure = Types.OddsDisclosure
type CrateInfo = Types.CrateInfo

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local OpenCrate = Remotes:WaitForChild("OpenCrate") :: RemoteEvent
local GetCrateOdds = Remotes:WaitForChild("GetCrateOdds") :: RemoteFunction

local CrateController = {}

-- Fetch honest odds for a crate. Returns a disclosure the UI can render.
-- For hidden-rate (earned-currency) crates, `hidden == true` and rows are nil.
function CrateController.fetchOdds(crateId: string): OddsDisclosure?
	local ok, result = pcall(function()
		return GetCrateOdds:InvokeServer(crateId)
	end)
	if not ok then
		warn("[CrateController] odds fetch failed:", result)
		return nil
	end
	return result
end

-- Show the store panel for a crate. For Robux-linked crates we MUST display odds
-- before the buy button becomes active -- that's the compliance requirement.
-- (UI rendering is stubbed; wire these to your actual GUI.)
function CrateController.showCrate(crateId: string)
	local crate = CrateCatalog.get(crateId)
	if not crate then
		return
	end

	local disclosure = CrateController.fetchOdds(crateId)

	if crate.robuxLinked then
		-- REQUIRED: render the odds table now. Do not enable purchase without it.
		if not disclosure or disclosure.hidden or not disclosure.rows then
			warn("[CrateController] Robux crate has no odds; blocking purchase UI")
			-- renderPurchaseBlocked(crate, "Odds unavailable")
			return
		end
		-- renderOddsTable(crate, disclosure.rows)  -- e.g. "Golden Fryer .... 3.5%"
		-- enableBuyButton(crate)
		print(("[CrateController] Showing disclosed odds for %s:"):format(crate.displayName))
		for _, row in disclosure.rows do
			print(("  %s (%s): %.2f%%"):format(row.displayName, row.rarity, row.percent))
		end
	else
		-- Earned-currency crate: odds hidden by design. Show the pool ("what's inside")
		-- but not the percentages.
		-- renderMysteryPool(crate)
		print(("[CrateController] %s is a mystery crate (rates hidden, earned currency)."):format(crate.displayName))
	end
end

-- Buy/open. Routes Robux crates through the Marketplace prompt and soft-currency
-- crates through the RemoteEvent.
function CrateController.open(crateId: string)
	local crate = CrateCatalog.get(crateId)
	if not crate then
		return
	end

	if crate.robuxLinked and crate.productId then
		-- The receipt processor on the server grants the crate and fires OpenCrate back.
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, crate.productId)
	else
		OpenCrate:FireServer(crateId)
	end
end

-- Server tells us the authoritative result (from either flow). Play the reveal here.
OpenCrate.OnClientEvent:Connect(function(response: OpenResponse)
	if response.ok then
		-- playReveal(response.reward, response.pityTriggered)
		local pity = response.pityTriggered and " (PITY!)" or ""
		print(("[CrateController] You got: %s [%s]%s -- %d opens until pity")
			:format(response.reward.displayName, response.reward.rarity, pity, response.opensUntilPity))
	else
		-- showError(response.reason)
		warn("[CrateController] open failed:", response.reason)
	end
end)

return CrateController
