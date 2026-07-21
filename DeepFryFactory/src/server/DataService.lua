--!strict
-- DataService.lua  (ServerScriptService/DeepFry)
-- Lightweight ProfileService-style DataStore layer: session locking, field reconciliation,
-- periodic auto-save, on-leave save, and BindToClose flush. Not the full ProfileService
-- library, but the same guarantees for an MVP: one live session owns a profile at a time,
-- and data is never silently overwritten by a second server.
--
-- Studio note: DataStores require "Enable Studio Access to API Services" (Game Settings ->
-- Security). Without it, load/save fail and this service falls back to an in-memory profile
-- so you can still test the loop (data won't persist).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

type Profile = {
	data: any,
	released: boolean,
	inMemoryOnly: boolean, -- true when DataStore is unavailable (Studio without API access)
}

local DataService = {}

local store = DataStoreService:GetDataStore(Config.Save.dataStoreName)
local profiles: { [Player]: Profile } = {}
local jobId = game.JobId ~= "" and game.JobId or "studio-" .. tostring(os.time())

-- ---- helpers ---------------------------------------------------------------

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

-- Fill any missing fields in `data` from `defaults` (recursively). Returns true if it
-- changed anything (useful for logging, not required here).
local function reconcile(data: any, defaults: any)
	for k, v in defaults do
		if data[k] == nil then
			data[k] = deepCopy(v)
		elseif type(v) == "table" and type(data[k]) == "table" then
			reconcile(data[k], v)
		end
	end
end

local function keyFor(player: Player): string
	return Config.Save.keyPrefix .. tostring(player.UserId)
end

local function now(): number
	return os.time()
end

-- ---- load / save -----------------------------------------------------------

-- Attempts to claim the session lock and return the player's data. Retries on transient
-- DataStore errors. On persistent failure, returns an in-memory-only default profile.
function DataService.load(player: Player): any
	local key = keyFor(player)

	for attempt = 1, Config.Save.loadRetries do
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(stored)
				stored = stored or { data = nil, lock = nil }

				-- Session-lock check: refuse if another live session holds a fresh lock.
				local lock = stored.lock
				if lock and lock.jobId ~= jobId then
					local age = now() - (lock.timestamp or 0)
					if age < Config.Save.sessionLockStaleAfter then
						-- Locked elsewhere and not stale: abort this write (return nil).
						return nil
					end
					-- else: stale lock, we steal it below.
				end

				stored.lock = { jobId = jobId, timestamp = now() }
				stored.data = stored.data or deepCopy(Config.DefaultData)
				return stored
			end)
		end)

		if ok and result ~= nil then
			local data = result.data
			reconcile(data, Config.DefaultData)
			profiles[player] = { data = data, released = false, inMemoryOnly = false }
			return data
		elseif ok and result == nil then
			-- Locked by a live session; wait and retry (that session may be leaving).
			warn(("[DataService] %s profile locked elsewhere, retry %d/%d"):format(player.Name, attempt, Config.Save.loadRetries))
			task.wait(Config.Save.retryDelay)
		else
			warn(("[DataService] load error for %s (attempt %d): %s"):format(player.Name, attempt, tostring(result)))
			task.wait(Config.Save.retryDelay)
		end
	end

	-- Give up on persistence; hand back a volatile profile so play can continue.
	warn(("[DataService] Falling back to in-memory profile for %s (no persistence)."):format(player.Name))
	local data = deepCopy(Config.DefaultData)
	profiles[player] = { data = data, released = false, inMemoryOnly = true }
	return data
end

-- Writes the player's current data back and (if release) clears the session lock.
function DataService.save(player: Player, release: boolean?)
	local profile = profiles[player]
	if not profile or profile.released then
		return
	end
	if profile.inMemoryOnly then
		if release then
			profile.released = true
			profiles[player] = nil
		end
		return
	end

	local key = keyFor(player)
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(stored)
			stored = stored or {}
			-- Only write if we still own the lock (or it's ours / stale).
			local lock = stored.lock
			if lock and lock.jobId ~= jobId then
				local age = now() - (lock.timestamp or 0)
				if age < Config.Save.sessionLockStaleAfter then
					-- Someone else owns it now; don't clobber their data.
					return nil
				end
			end
			stored.data = profile.data
			if release then
				stored.lock = nil
			else
				stored.lock = { jobId = jobId, timestamp = now() }
			end
			return stored
		end)
	end)

	if not ok then
		warn(("[DataService] save failed for %s: %s"):format(player.Name, tostring(err)))
	end

	if release then
		profile.released = true
		profiles[player] = nil
	end
end

-- Accessor for other services.
function DataService.get(player: Player): any?
	local profile = profiles[player]
	return profile and profile.data or nil
end

-- ---- lifecycle -------------------------------------------------------------

function DataService.start()
	-- Auto-save loop.
	task.spawn(function()
		while true do
			task.wait(Config.Save.autoSaveInterval)
			for player in profiles do
				DataService.save(player, false)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player, true)
	end)

	-- Flush everything on shutdown. BindToClose blocks shutdown until saves finish.
	game:BindToClose(function()
		if RunService:IsStudio() then
			-- In Studio, give a short grace but don't hang forever.
		end
		local pending = {}
		for player in profiles do
			table.insert(pending, player)
		end
		for _, player in pending do
			task.spawn(function()
				DataService.save(player, true)
			end)
		end
		-- Small settle window so the spawned saves can issue their requests.
		task.wait(2)
	end)
end

return DataService
