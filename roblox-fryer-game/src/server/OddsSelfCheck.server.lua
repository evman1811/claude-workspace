--!strict
-- OddsSelfCheck.server.lua  (optional Script in ServerScriptService)
-- Runs once at startup and fails LOUDLY if any Robux-linked crate cannot disclose odds,
-- or if disclosed percentages don't sum to ~100%. This is your compliance guardrail:
-- if someone adds a paid crate but forgets weights, the server warns at boot instead of
-- silently shipping an illegal loot box.
--
-- Run this AFTER Bootstrap has started CrateService (script ordering: rename to
-- "zzOddsSelfCheck" or add a short wait, since Script execution order isn't guaranteed).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CrateCatalog = require(Shared:WaitForChild("CrateCatalog"))
local CrateService = require(script.Parent.CrateService)

task.defer(function()
	local problems = 0

	for crateId, crate in CrateCatalog.all() do
		local disc = CrateService.getDisclosure(crateId)

		if crate.robuxLinked then
			if not disc or disc.hidden or not disc.rows then
				warn(("[OddsSelfCheck] FAIL: Robux-linked crate '%s' has NO disclosable odds. This violates the Paid Random Items policy."):format(crateId))
				problems += 1
			else
				local sum = 0
				for _, row in disc.rows do
					sum += row.percent
				end
				-- Allow small rounding slack from 2-decimal display rounding.
				if math.abs(sum - 100) > 0.5 then
					warn(("[OddsSelfCheck] WARN: crate '%s' odds sum to %.2f%% (expected ~100%%). Check weights."):format(crateId, sum))
					problems += 1
				else
					print(("[OddsSelfCheck] OK: '%s' discloses %d outcomes summing to %.2f%%."):format(crateId, #disc.rows, sum))
				end
			end
		else
			-- Earned-currency crate: hidden is expected and legal.
			if disc and not disc.hidden then
				warn(("[OddsSelfCheck] NOTE: earned-currency crate '%s' is exposing odds; that's allowed but unusual."):format(crateId))
			else
				print(("[OddsSelfCheck] OK: '%s' hides odds (earned currency, policy-compliant)."):format(crateId))
			end
		end
	end

	if problems == 0 then
		print("[OddsSelfCheck] All crates pass compliance checks.")
	else
		warn(("[OddsSelfCheck] %d compliance problem(s) found. Fix before shipping."):format(problems))
	end
end)
