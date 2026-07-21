--!strict
-- Bootstrap.client.lua  (LocalScript in StarterPlayerScripts)
-- Interactive 3D client. Builds a walk-up factory LOCALLY (so each player sees their own
-- fryers reflecting their own state) and drives it from server snapshots. The world sends
-- INTENT ONLY: ProximityPrompts fire StartFry / Bank / BuyUpgrade / Rebirth. The server
-- stays fully authoritative — it never trusts anything built here.
--
-- Meme art: each meme shows Config.TemplateImages[id] if you've added one, else a clean
-- rarity-colored placeholder card. No assets required to play.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Templates = require(Shared:WaitForChild("Templates"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local StartFry = Remotes.get(Remotes.Names.StartFry)
local Bank = Remotes.get(Remotes.Names.Bank)
local BuyUpgrade = Remotes.get(Remotes.Names.BuyUpgrade)
local Rebirth = Remotes.get(Remotes.Names.Rebirth)
local SyncState = Remotes.get(Remotes.Names.SyncState)
local Toast = Remotes.get(Remotes.Names.Toast)

-- ---- helpers ---------------------------------------------------------------

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx" }
local function abbrev(n: number): string
	n = math.floor(n)
	if n < 1000 then
		return tostring(n)
	end
	local tier = math.clamp(math.floor(math.log(n, 1000)), 1, #SUFFIXES - 1)
	return string.format("%.2f%s", n / (1000 ^ tier), SUFFIXES[tier + 1])
end

local function rarityColor(rarity: string?): Color3
	return (rarity and Config.RarityColors[rarity]) or Color3.fromRGB(150, 150, 150)
end

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- ---- world layout ----------------------------------------------------------
-- Everything is placed in front of the default spawn. All local (client-only) instances
-- are tagged so we never touch server-replicated objects.

local WORLD_FOLDER = make("Folder", { Name = "DeepFryWorld_Local" }, Workspace)

local STATION_X = { -10, 0, 10 } -- lane 1/2/3 x positions
local STATION_Z = -16
local SHOP_POS = Vector3.new(18, 0, -8)
local REBIRTH_POS = Vector3.new(-18, 0, -8)

-- A subtle factory floor pad so the area reads as "a place".
make("Part", {
	Name = "FactoryFloor",
	Anchored = true,
	Size = Vector3.new(52, 0.4, 34),
	Position = Vector3.new(0, 0.1, -14), -- nearly flush with the baseplate so it's walkable
	Color = Color3.fromRGB(48, 44, 40),
	Material = Enum.Material.Concrete,
	TopSurface = Enum.SurfaceType.Smooth,
}, WORLD_FOLDER)

-- Neon title sign.
do
	local signPart = make("Part", {
		Name = "Sign",
		Anchored = true,
		CanCollide = false,
		Size = Vector3.new(24, 6, 1),
		Position = Vector3.new(0, 12, -25),
		Color = Color3.fromRGB(20, 20, 24),
		Material = Enum.Material.SmoothPlastic,
	}, WORLD_FOLDER)
	local sg = make("SurfaceGui", { Face = Enum.NormalId.Front, CanvasSize = Vector2.new(960, 240) }, signPart)
	make("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.fromRGB(255, 180, 60),
		TextScaled = true,
		Text = "🍟 DEEP FRY FACTORY",
	}, sg)
end

-- ProximityPrompt factory.
local function addPrompt(parent: BasePart, actionText: string, key: Enum.KeyCode, order: number): ProximityPrompt
	local p = make("ProximityPrompt", {
		ActionText = actionText,
		ObjectText = "",
		KeyboardKeyCode = key,
		HoldDuration = 0,
		MaxActivationDistance = 12,
		RequiresLineOfSight = false,
		UIOffset = Vector2.new(0, order * 44), -- stack multiple prompts on one part
	}, parent)
	return p
end

-- ---- fryer stations --------------------------------------------------------

type Station = {
	model: Model,
	fryerPart: BasePart,
	imageLabel: ImageLabel,
	nameLabel: TextLabel,
	valueLabel: TextLabel,
	statusLabel: TextLabel,
	meterFill: Frame,
	meterText: TextLabel,
	fryPrompt: ProximityPrompt,
	bankPrompt: ProximityPrompt,
}

local stations: { [number]: Station } = {}
local fryTimers: { [number]: { endClock: number, duration: number } } = {}

local function buildStation(index: number): Station
	local x = STATION_X[index] or (STATION_X[#STATION_X] + (index - #STATION_X) * 10)
	local model = make("Model", { Name = "FryerStation" .. index }, WORLD_FOLDER)

	-- The fryer body (bottom rests on the floor: center y = height/2).
	local fryer = make("Part", {
		Name = "Fryer",
		Anchored = true,
		Size = Vector3.new(6, 4, 5),
		Position = Vector3.new(x, 2, STATION_Z),
		Color = Color3.fromRGB(60, 60, 68),
		Material = Enum.Material.DiamondPlate,
	}, model)

	-- Oil basket (neon rim on top) as visual flair.
	make("Part", {
		Name = "Oil",
		Anchored = true,
		CanCollide = false,
		Size = Vector3.new(5, 0.6, 4),
		Position = Vector3.new(x, 4.3, STATION_Z),
		Color = Color3.fromRGB(230, 150, 40),
		Material = Enum.Material.Neon,
	}, model)

	-- Floating meme card (billboard) above the fryer.
	local anchor = make("Part", {
		Name = "CardAnchor",
		Anchored = true,
		CanCollide = false,
		Transparency = 1,
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(x, 9, STATION_Z),
	}, model)

	local bb = make("BillboardGui", {
		Adornee = anchor,
		Size = UDim2.new(0, 230, 0, 200),
		StudsOffset = Vector3.new(0, 0, 0),
		AlwaysOnTop = false,
		MaxDistance = 60,
	}, anchor)

	local card = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(24, 24, 28),
		BackgroundTransparency = 0.1,
	}, bb)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
	make("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2, Transparency = 0.4 }, card)

	-- Meme image (or placeholder swatch).
	local image = make("ImageLabel", {
		Size = UDim2.new(1, -16, 0, 110),
		Position = UDim2.new(0, 8, 0, 8),
		BackgroundColor3 = Color3.fromRGB(80, 80, 80),
		BackgroundTransparency = 0,
		ScaleType = Enum.ScaleType.Crop,
		Image = "",
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, image)

	local nameLabel = make("TextLabel", {
		Size = UDim2.new(1, -12, 0, 22),
		Position = UDim2.new(0, 6, 0, 122),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Text = "Lane " .. index,
	}, card)

	local valueLabel = make("TextLabel", {
		Size = UDim2.new(1, -12, 0, 18),
		Position = UDim2.new(0, 6, 0, 144),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(255, 210, 120),
		Text = "",
	}, card)

	-- Sizzle meter.
	local meterBg = make("Frame", {
		Size = UDim2.new(1, -12, 0, 16),
		Position = UDim2.new(0, 6, 1, -22),
		BackgroundColor3 = Color3.fromRGB(50, 50, 55),
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, meterBg)
	local meterFill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(230, 90, 40),
	}, meterBg)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, meterFill)
	local meterText = make("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Text = "",
	}, meterBg)

	local statusLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, -22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Color3.fromRGB(120, 220, 255),
		Text = "",
	}, card)

	local fryPrompt = addPrompt(fryer, "Fry", Enum.KeyCode.E, 0)
	local bankPrompt = addPrompt(fryer, "Bank", Enum.KeyCode.Q, 1)
	fryPrompt.Triggered:Connect(function()
		StartFry:FireServer(index)
	end)
	bankPrompt.Triggered:Connect(function()
		Bank:FireServer(index)
	end)

	local st: Station = {
		model = model,
		fryerPart = fryer,
		imageLabel = image,
		nameLabel = nameLabel,
		valueLabel = valueLabel,
		statusLabel = statusLabel,
		meterFill = meterFill,
		meterText = meterText,
		fryPrompt = fryPrompt,
		bankPrompt = bankPrompt,
	}
	stations[index] = st
	return st
end

local function getStation(index: number): Station
	return stations[index] or buildStation(index)
end

local latest: any = nil

local function updateStation(laneSnap: any)
	local st = getStation(laneSnap.index)

	if laneSnap.state == "empty" then
		st.imageLabel.Image = ""
		st.imageLabel.BackgroundColor3 = Color3.fromRGB(60, 60, 66)
		st.nameLabel.Text = "Empty — spawning…"
		st.valueLabel.Text = ""
		st.statusLabel.Text = ""
		st.meterFill.Size = UDim2.new(0, 0, 1, 0)
		st.meterText.Text = ""
		st.fryPrompt.Enabled = false
		st.bankPrompt.Enabled = false
		st.fryerPart.Color = Color3.fromRGB(60, 60, 68)
		fryTimers[laneSnap.index] = nil
		return
	end

	local template = laneSnap.templateId and Templates.get(laneSnap.templateId)
	local name = template and template.name or "???"

	-- Meme art or placeholder.
	if template and template.image then
		st.imageLabel.Image = template.image
		st.imageLabel.BackgroundTransparency = 1
	else
		st.imageLabel.Image = ""
		st.imageLabel.BackgroundTransparency = 0
		st.imageLabel.BackgroundColor3 = rarityColor(laneSnap.rarity)
	end

	st.nameLabel.Text = ("%s  •  %s"):format(name, laneSnap.rarity or "?")
	st.nameLabel.TextColor3 = rarityColor(laneSnap.rarity)

	local nextValue = laneSnap.value * (latest and latest.fryerMult or 1)
	st.valueLabel.Text = ("Pass %d — %s   →   %s"):format(laneSnap.pass, abbrev(laneSnap.value), abbrev(nextValue))

	local burn = laneSnap.nextBurnChance or 0
	st.meterFill.Size = UDim2.new(math.clamp(burn, 0, 1), 0, 1, 0)
	st.meterText.Text = ("🔥 %d%%"):format(math.floor(burn * 100 + 0.5))

	if laneSnap.state == "frying" then
		st.statusLabel.Text = "🍳 Frying…"
		st.fryPrompt.Enabled = false
		st.bankPrompt.Enabled = false
		st.fryerPart.Color = Color3.fromRGB(200, 120, 50)
		if laneSnap.fryRemaining and laneSnap.fryDuration then
			fryTimers[laneSnap.index] = { endClock = os.clock() + laneSnap.fryRemaining, duration = laneSnap.fryDuration }
		end
	else -- ready
		st.statusLabel.Text = "Ready — [E] Fry  [Q] Bank"
		st.fryPrompt.Enabled = true
		st.bankPrompt.Enabled = true
		st.fryerPart.Color = Color3.fromRGB(60, 60, 68)
		fryTimers[laneSnap.index] = nil
	end
end

-- ---- shop kiosk ------------------------------------------------------------

local shopPanel: Frame -- built below in the ScreenGui section
local shopOpen = false

local function buildKiosk(name: string, pos: Vector3, color: Color3, actionText: string): (BasePart, ProximityPrompt)
	local part = make("Part", {
		Name = name,
		Anchored = true,
		Size = Vector3.new(4, 6, 4),
		Position = Vector3.new(pos.X, 3, pos.Z),
		Color = color,
		Material = Enum.Material.Neon,
	}, WORLD_FOLDER)
	local anchor = make("Part", {
		Anchored = true, CanCollide = false, Transparency = 1,
		Size = Vector3.new(1, 1, 1), Position = Vector3.new(pos.X, 8, pos.Z),
	}, WORLD_FOLDER)
	local bb = make("BillboardGui", { Adornee = anchor, Size = UDim2.new(0, 160, 0, 40), MaxDistance = 60 }, anchor)
	make("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.fromRGB(255, 255, 255),
		Text = name,
	}, bb)
	local prompt = addPrompt(part, actionText, Enum.KeyCode.E, 0)
	return part, prompt
end

local _, shopPrompt = buildKiosk("SHOP", SHOP_POS, Color3.fromRGB(60, 140, 90), "Open Shop")
local _, rebirthPrompt = buildKiosk("REBIRTH", REBIRTH_POS, Color3.fromRGB(150, 60, 200), "Rebirth")

rebirthPrompt.Triggered:Connect(function()
	Rebirth:FireServer()
end)

-- ---- HUD (thin: currency, shop panel, codex, toast) ------------------------

local gui = make("ScreenGui", { Name = "DeepFryHUD", ResetOnSpawn = false, IgnoreGuiInset = true }, playerGui)

-- Top bar
local topBar = make("Frame", {
	Size = UDim2.new(0, 460, 0, 44),
	Position = UDim2.new(0, 12, 0, 12),
	BackgroundColor3 = Color3.fromRGB(24, 20, 16),
	BackgroundTransparency = 0.1,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, topBar)
local crunchLabel = make("TextLabel", {
	Size = UDim2.new(0.55, 0, 1, 0), Position = UDim2.new(0, 12, 0, 0),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 210, 120),
	Text = "🍟 0 Crunch",
}, topBar)
local infoLabel = make("TextLabel", {
	Size = UDim2.new(0.45, -12, 1, 0), Position = UDim2.new(0.55, 0, 0, 0),
	BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(200, 200, 200),
	Text = "Rebirths 0 • x1.00",
}, topBar)

-- Shop panel (hidden until you walk to the SHOP kiosk)
shopPanel = make("Frame", {
	Size = UDim2.new(0, 340, 0, 260),
	Position = UDim2.new(0.5, -170, 0.5, -130),
	BackgroundColor3 = Color3.fromRGB(24, 24, 30),
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, shopPanel)
make("TextLabel", {
	Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 12, 0, 8), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 255, 255), Text = "Upgrades",
}, shopPanel)
local closeShop = make("TextButton", {
	Size = UDim2.new(0, 28, 0, 28), Position = UDim2.new(1, -34, 0, 8),
	BackgroundColor3 = Color3.fromRGB(120, 50, 50), Font = Enum.Font.GothamBold, TextSize = 16,
	TextColor3 = Color3.fromRGB(255, 255, 255), Text = "X",
}, shopPanel)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, closeShop)
local shopList = make("Frame", {
	Size = UDim2.new(1, -20, 1, -48), Position = UDim2.new(0, 10, 0, 42), BackgroundTransparency = 1,
}, shopPanel)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, shopList)

local function setShopOpen(open: boolean)
	shopOpen = open
	shopPanel.Visible = open
end
closeShop.MouseButton1Click:Connect(function()
	setShopOpen(false)
end)
shopPrompt.Triggered:Connect(function()
	setShopOpen(not shopOpen)
end)

local shopRows: { [string]: any } = {}
local function renderShop(snap: any)
	for order, id in Upgrades.Order do
		local row = shopRows[id]
		if not row then
			local def = Upgrades.getDef(id)
			local btn = make("TextButton", {
				Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = Color3.fromRGB(38, 38, 46),
				Text = "", AutoButtonColor = true, LayoutOrder = order,
			}, shopList)
			make("UICorner", { CornerRadius = UDim.new(0, 8) }, btn)
			local title = make("TextLabel", {
				Size = UDim2.new(1, -12, 0, 22), Position = UDim2.new(0, 10, 0, 6), BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(255, 255, 255), Text = def and def.name or id,
			}, btn)
			local sub = make("TextLabel", {
				Size = UDim2.new(1, -12, 0, 20), Position = UDim2.new(0, 10, 0, 28), BackgroundTransparency = 1,
				Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(190, 190, 190), Text = "",
			}, btn)
			btn.MouseButton1Click:Connect(function()
				BuyUpgrade:FireServer(id)
			end)
			row = { btn = btn, title = title, sub = sub }
			shopRows[id] = row
		end
		local view = snap.upgradeView[id]
		if view.maxed then
			row.sub.Text = ("Lv %d — MAX"):format(view.level)
			row.btn.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
		else
			local afford = snap.crunch >= view.cost
			row.sub.Text = ("Lv %d — %s Crunch"):format(view.level, abbrev(view.cost))
			row.btn.BackgroundColor3 = afford and Color3.fromRGB(46, 60, 46) or Color3.fromRGB(38, 38, 46)
		end
	end
end

-- Codex panel (toggle with C)
local codexPanel = make("Frame", {
	Size = UDim2.new(0, 320, 0, 300), Position = UDim2.new(1, -332, 0.5, -150),
	BackgroundColor3 = Color3.fromRGB(24, 24, 30), Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, codexPanel)
make("TextLabel", {
	Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 12, 0, 8), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 255, 255), Text = "Codex  (press C)",
}, codexPanel)
local codexScroll = make("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -44), Position = UDim2.new(0, 10, 0, 40), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, codexPanel)
make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, codexScroll)

local codexCells: { [string]: any } = {}
local function renderCodex(snap: any)
	for order, template in Templates.List do
		local cell = codexCells[template.id]
		if not cell then
			cell = make("TextLabel", {
				Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = Color3.fromRGB(38, 38, 46),
				Font = Enum.Font.GothamMedium, TextSize = 13, LayoutOrder = order, Text = "",
			}, codexScroll)
			make("UICorner", { CornerRadius = UDim.new(0, 6) }, cell)
			codexCells[template.id] = cell
		end
		if snap.codex[template.id] then
			cell.Text = template.name .. "  (" .. template.rarity .. ")"
			cell.TextColor3 = rarityColor(template.rarity)
		else
			cell.Text = "??? (" .. template.rarity .. ")"
			cell.TextColor3 = Color3.fromRGB(120, 120, 120)
		end
	end
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	if input.KeyCode == Enum.KeyCode.C then
		codexPanel.Visible = not codexPanel.Visible
	end
end)

-- Toast
local toastLabel = make("TextLabel", {
	Size = UDim2.new(0, 520, 0, 36), Position = UDim2.new(0.5, -260, 1, -60),
	BackgroundColor3 = Color3.fromRGB(20, 20, 20), BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "", TextTransparency = 1,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, toastLabel)

-- ---- render + events -------------------------------------------------------

local function render(snap: any)
	crunchLabel.Text = ("🍟 %s Crunch"):format(abbrev(snap.crunch))
	infoLabel.Text = ("%s • Rebirths %d • x%.2f"):format(snap.fryerName, snap.rebirths, snap.permMult)

	-- Remove stations for lanes that no longer exist.
	for index, st in stations do
		if index > #snap.lanes then
			st.model:Destroy()
			stations[index] = nil
			fryTimers[index] = nil
		end
	end
	for _, laneSnap in snap.lanes do
		updateStation(laneSnap)
	end

	-- Keep the rebirth prompt visible; its label reflects readiness and the server
	-- still validates the actual rebirth request.
	rebirthPrompt.ActionText = snap.canRebirth and "Rebirth ✓" or "Rebirth (need 100k)"

	renderShop(snap)
	renderCodex(snap)
end

SyncState.OnClientEvent:Connect(function(snap)
	latest = snap
	render(snap)
end)

Toast.OnClientEvent:Connect(function(_kind: string, text: string)
	toastLabel.Text = text
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = 0.15
	local tag = tick()
	toastLabel:SetAttribute("tag", tag)
	task.delay(2.4, function()
		if toastLabel:GetAttribute("tag") == tag then
			toastLabel.TextTransparency = 1
			toastLabel.BackgroundTransparency = 1
		end
	end)
end)

-- Animate the frying tint / status countdown locally.
RunService.RenderStepped:Connect(function()
	for index, timer in fryTimers do
		local st = stations[index]
		if st then
			local remaining = math.max(0, timer.endClock - os.clock())
			st.statusLabel.Text = ("🍳 Frying… %.1fs"):format(remaining)
		end
	end
end)

print("[DeepFryFactory] Interactive world ready. Walk to a fryer and press E.")
