--!strict
-- FryMath.lua  (ReplicatedStorage/Shared)
-- Pure, deterministic fry math. No RNG, no state -- just the formulas. Shared so the
-- client's Sizzle Meter shows EXACTLY what the server will resolve. The server owns the
-- actual burn roll; the client only displays the odds these functions return.

local Config = require(script.Parent.Config)

local FryMath = {}

-- Value of a meme after `pass` fry passes.  V = baseValue * mult ^ pass
function FryMath.value(baseValue: number, mult: number, pass: number): number
	return baseValue * (mult ^ pass)
end

-- Effective safe line = fryer's safe passes + oil bonus.
function FryMath.safeLine(fryerSafe: number, oilSafeBonus: number): number
	return fryerSafe + oilSafeBonus
end

-- Burn chance for ATTEMPTING pass `n` (the pass you're about to run).
--   n <= safe  -> 0
--   n >  safe  -> burnPerPass * (n - safe), clamped to [0, cap]
function FryMath.burnChance(n: number, safe: number, burnPerPass: number): number
	if n <= safe then
		return 0
	end
	local q = burnPerPass * (n - safe)
	return math.clamp(q, 0, Config.Fry.burnChanceCap)
end

-- Value of the Burnt Crumb awarded when a meme burns at attempted pass `n`.
-- "10% of last safe value" -> value at the last pass that was within the safe line.
function FryMath.crumbValue(baseValue: number, mult: number, currentPass: number, safe: number): number
	local lastSafePass = math.min(currentPass, safe)
	local lastSafeValue = FryMath.value(baseValue, mult, lastSafePass)
	return lastSafeValue * Config.Fry.crumbFraction
end

return FryMath
