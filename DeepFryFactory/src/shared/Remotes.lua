--!strict
-- Remotes.lua  (ReplicatedStorage/Shared)
-- Central definition + lazy creation of every RemoteEvent. Both sides require this so
-- names can never drift. The server calls Remotes.init() once at boot (creates the
-- instances); clients call Remotes.get(name) and WaitForChild under the hood.
--
-- Client -> Server (intent only, always validated server-side):
--   StartFry(laneIndex)      -- run one more fry pass on the meme in that lane
--   Bank(laneIndex)          -- cash out the meme in that lane for Crunch
--   BuyUpgrade(upgradeId)    -- purchase the next level of an upgrade
--   Rebirth()                -- prestige
--
-- Server -> Client:
--   SyncState(snapshot)      -- authoritative full/partial state for the UI
--   Toast(kind, text)        -- transient message ("Burned!", "New meme discovered!")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

Remotes.Names = {
	StartFry = "StartFry",
	Bank = "Bank",
	BuyUpgrade = "BuyUpgrade",
	Rebirth = "Rebirth",
	SyncState = "SyncState",
	Toast = "Toast",
}

local FOLDER_NAME = "Remotes"

-- Server-only: create the folder + RemoteEvents.
function Remotes.init(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in Remotes.Names do
		if not folder:FindFirstChild(name) then
			local re = Instance.new("RemoteEvent")
			re.Name = name
			re.Parent = folder
		end
	end
	return folder
end

-- Either side: fetch a RemoteEvent by name (waits for replication on the client).
function Remotes.get(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
