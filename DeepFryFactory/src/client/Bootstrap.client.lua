--!strict
-- Bootstrap.client.lua  (LocalScript in StarterPlayerScripts)
-- Builds the whole UI in code (no imported assets) and renders server snapshots. The
-- client sends INTENT ONLY (StartFry/Bank/BuyUpgrade/Rebirth); it never computes currency.
-- The Sizzle Meter just displays the value + burn odds the server already sent.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Templates = require(Shared:WaitForChild("Templates"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Remotes
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
	local tier = math.floor(math.log(n, 1000))
	tier = math.clamp(tier, 1, #SUFFIXES - 1)
	local scaled = n / (1000 ^ tier)
	return string.format("%.2f%s", scaled, SUFFIXES[tier + 1])
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

-- ---- build static UI -------------------------------------------------------

local gui = make("ScreenGui", {
	Name = "DeepFryUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
}, playerGui)

-- Top bar
local topBar = make("Frame", {
	Size = UDim2.new(1, 0, 0, 56),
	BackgroundColor3 = Color3.fromRGB(28, 22, 18),
	BorderSizePixel = 0,
}, gui)

local crunchLabel = make("TextLabel", {
	Size = UDim2.new(0, 340, 1, 0),
	Position = UDim2.new(0, 16, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 24,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 210, 120),
	Text = "🍟 0 Crunch",
}, topBar)

local rebirthInfo = make("TextLabel", {
	Size = UDim2.new(0, 300, 1, 0),
	Position = UDim2.new(0, 360, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(200, 200, 200),
	Text = "Rebirths: 0  |  Income x1.00",
}, topBar)

local rebirthBtn = make("TextButton", {
	Size = UDim2.new(0, 170, 0, 40),
	Position = UDim2.new(1, -186, 0.5, -20),
	BackgroundColor3 = Color3.fromRGB(120, 40, 160),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "Rebirth",
	AutoButtonColor = true,
}, topBar)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, rebirthBtn)
rebirthBtn.MouseButton1Click:Connect(function()
	Rebirth:FireServer()
end)

-- Lanes container (center-left)
local lanesFrame = make("Frame", {
	Size = UDim2.new(0.62, -24, 1, -140),
	Position = UDim2.new(0, 16, 0, 72),
	BackgroundTransparency = 1,
}, gui)
make("UIListLayout", {
	Padding = UDim.new(0, 12),
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, lanesFrame)

-- Shop (right)
local shopFrame = make("Frame", {
	Size = UDim2.new(0.38, -24, 0.55, -80),
	Position = UDim2.new(0.62, 8, 0, 72),
	BackgroundColor3 = Color3.fromRGB(24, 24, 30),
	BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, shopFrame)
make("TextLabel", {
	Size = UDim2.new(1, -20, 0, 30),
	Position = UDim2.new(0, 10, 0, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "Upgrades",
}, shopFrame)
local shopList = make("Frame", {
	Size = UDim2.new(1, -20, 1, -44),
	Position = UDim2.new(0, 10, 0, 38),
	BackgroundTransparency = 1,
}, shopFrame)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, shopList)

-- Codex (bottom-right)
local codexFrame = make("Frame", {
	Size = UDim2.new(0.38, -24, 0.45, -8),
	Position = UDim2.new(0.62, 8, 0.55, 0),
	BackgroundColor3 = Color3.fromRGB(24, 24, 30),
	BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, codexFrame)
make("TextLabel", {
	Size = UDim2.new(1, -20, 0, 28),
	Position = UDim2.new(0, 10, 0, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "Codex",
}, codexFrame)
local codexScroll = make("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -40),
	Position = UDim2.new(0, 10, 0, 34),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, codexFrame)
local codexGrid = make("UIGridLayout", {
	CellSize = UDim2.new(0, 150, 0, 26),
	CellPadding = UDim2.new(0, 6, 0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, codexScroll)

-- Toast
local toastLabel = make("TextLabel", {
	Size = UDim2.new(0, 520, 0, 36),
	Position = UDim2.new(0.31, 0, 1, -52),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.fromRGB(20, 20, 20),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamMedium,
	TextSize = 16,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "",
	TextTransparency = 1,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, toastLabel)

-- ---- dynamic state ---------------------------------------------------------

local latest: any = nil
local laneCards: { [number]: any } = {} -- index -> { card, ... labels/buttons }
-- Per-lane local fry timer, captured when a "frying" snapshot arrives.
local fryTimers: { [number]: { endClock: number, duration: number } } = {}

-- Build (once) or fetch a lane card for the given index.
local function getLaneCard(index: number)
	local existing = laneCards[index]
	if existing then
		return existing
	end

	local card = make("Frame", {
		Size = UDim2.new(1, 0, 0, 150),
		BackgroundColor3 = Color3.fromRGB(30, 30, 36),
		BorderSizePixel = 0,
		LayoutOrder = index,
	}, lanesFrame)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, card)

	local accent = make("Frame", {
		Size = UDim2.new(0, 8, 1, 0),
		BackgroundColor3 = Color3.fromRGB(120, 120, 120),
		BorderSizePixel = 0,
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, accent)

	local title = make("TextLabel", {
		Size = UDim2.new(1, -28, 0, 26),
		Position = UDim2.new(0, 20, 0, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Text = "Lane " .. index,
	}, card)

	local valueLabel = make("TextLabel", {
		Size = UDim2.new(1, -28, 0, 22),
		Position = UDim2.new(0, 20, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 210, 120),
		Text = "",
	}, card)

	-- Sizzle Meter (burn bar)
	local meterBg = make("Frame", {
		Size = UDim2.new(1, -28, 0, 16),
		Position = UDim2.new(0, 20, 0, 62),
		BackgroundColor3 = Color3.fromRGB(50, 50, 55),
		BorderSizePixel = 0,
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, meterBg)
	local meterFill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(230, 90, 40),
		BorderSizePixel = 0,
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

	-- Fry-timer progress bar (shown while frying)
	local timerBg = make("Frame", {
		Size = UDim2.new(1, -28, 0, 6),
		Position = UDim2.new(0, 20, 0, 84),
		BackgroundColor3 = Color3.fromRGB(40, 40, 45),
		BorderSizePixel = 0,
		Visible = false,
	}, card)
	local timerFill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(90, 200, 255),
		BorderSizePixel = 0,
	}, timerBg)

	-- Buttons
	local fryBtn = make("TextButton", {
		Size = UDim2.new(0.5, -24, 0, 38),
		Position = UDim2.new(0, 20, 1, -46),
		BackgroundColor3 = Color3.fromRGB(210, 120, 40),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = Color3.fromRGB(20, 20, 20),
		Text = "Fry",
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, fryBtn)
	fryBtn.MouseButton1Click:Connect(function()
		StartFry:FireServer(index)
	end)

	local bankBtn = make("TextButton", {
		Size = UDim2.new(0.5, -24, 0, 38),
		Position = UDim2.new(0.5, 4, 1, -46),
		BackgroundColor3 = Color3.fromRGB(60, 170, 90),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = Color3.fromRGB(20, 20, 20),
		Text = "Bank",
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, bankBtn)
	bankBtn.MouseButton1Click:Connect(function()
		Bank:FireServer(index)
	end)

	local entry = {
		card = card,
		accent = accent,
		title = title,
		valueLabel = valueLabel,
		meterFill = meterFill,
		meterText = meterText,
		timerBg = timerBg,
		timerFill = timerFill,
		fryBtn = fryBtn,
		bankBtn = bankBtn,
	}
	laneCards[index] = entry
	return entry
end

local function renderLane(laneSnap: any)
	local c = getLaneCard(laneSnap.index)
	c.accent.BackgroundColor3 = rarityColor(laneSnap.rarity)

	if laneSnap.state == "empty" then
		c.title.Text = ("Lane %d — spawning…"):format(laneSnap.index)
		c.valueLabel.Text = ""
		c.meterFill.Size = UDim2.new(0, 0, 1, 0)
		c.meterText.Text = ""
		c.timerBg.Visible = false
		c.fryBtn.Visible = false
		c.bankBtn.Visible = false
		fryTimers[laneSnap.index] = nil
		return
	end

	local template = laneSnap.templateId and Templates.get(laneSnap.templateId)
	local name = template and template.name or "???"
	c.title.Text = ("%s  •  %s  •  pass %d"):format(name, laneSnap.rarity or "?", laneSnap.pass)

	-- Value line: current bankable value, and (if you fry) the potential next value.
	local nextValue = laneSnap.value * (latest and latest.fryerMult or 1)
	c.valueLabel.Text = ("Value %s   →   fry for %s (if it survives)"):format(
		abbrev(laneSnap.value),
		abbrev(nextValue)
	)

	-- Sizzle meter = burn chance of the next pass.
	local burn = laneSnap.nextBurnChance or 0
	c.meterFill.Size = UDim2.new(math.clamp(burn, 0, 1), 0, 1, 0)
	c.meterText.Text = ("🔥 Burn risk: %d%%"):format(math.floor(burn * 100 + 0.5))

	c.fryBtn.Visible = true
	c.bankBtn.Visible = true

	if laneSnap.state == "frying" then
		c.fryBtn.Active = false
		c.fryBtn.AutoButtonColor = false
		c.fryBtn.BackgroundColor3 = Color3.fromRGB(120, 90, 60)
		c.fryBtn.Text = "Frying…"
		c.timerBg.Visible = true
		if laneSnap.fryRemaining and laneSnap.fryDuration then
			fryTimers[laneSnap.index] = {
				endClock = os.clock() + laneSnap.fryRemaining,
				duration = laneSnap.fryDuration,
			}
		end
	else -- ready
		c.fryBtn.Active = true
		c.fryBtn.AutoButtonColor = true
		c.fryBtn.BackgroundColor3 = Color3.fromRGB(210, 120, 40)
		c.fryBtn.Text = "Fry"
		c.timerBg.Visible = false
		fryTimers[laneSnap.index] = nil
	end
end

-- Remove cards for lanes that no longer exist (shouldn't happen mid-session, but safe).
local function pruneLanes(activeCount: number)
	for index, entry in laneCards do
		if index > activeCount then
			entry.card:Destroy()
			laneCards[index] = nil
			fryTimers[index] = nil
		end
	end
end

-- Shop
local shopRows: { [string]: any } = {}
local function getShopRow(id: string, order: number)
	local existing = shopRows[id]
	if existing then
		return existing
	end
	local def = Upgrades.getDef(id)
	local btn = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = Color3.fromRGB(38, 38, 46),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = order,
	}, shopList)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, btn)
	local title = make("TextLabel", {
		Size = UDim2.new(1, -12, 0, 22),
		Position = UDim2.new(0, 10, 0, 6),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Text = def and def.name or id,
	}, btn)
	local sub = make("TextLabel", {
		Size = UDim2.new(1, -12, 0, 20),
		Position = UDim2.new(0, 10, 0, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(190, 190, 190),
		Text = "",
	}, btn)
	btn.MouseButton1Click:Connect(function()
		BuyUpgrade:FireServer(id)
	end)
	local entry = { btn = btn, title = title, sub = sub }
	shopRows[id] = entry
	return entry
end

local function renderShop(snap: any)
	for order, id in Upgrades.Order do
		local row = getShopRow(id, order)
		local view = snap.upgradeView[id]
		local def = Upgrades.getDef(id)
		if view.maxed then
			row.sub.Text = ("Lv %d — MAX"):format(view.level)
			row.btn.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
		else
			local affordable = snap.crunch >= view.cost
			row.sub.Text = ("Lv %d — cost %s Crunch"):format(view.level, abbrev(view.cost))
			row.btn.BackgroundColor3 = affordable and Color3.fromRGB(46, 60, 46) or Color3.fromRGB(38, 38, 46)
		end
		row.title.Text = (def and def.name or id)
	end
end

-- Codex
local codexCells: { [string]: any } = {}
local function renderCodex(snap: any)
	for order, template in Templates.List do
		local cell = codexCells[template.id]
		if not cell then
			cell = make("TextLabel", {
				BackgroundColor3 = Color3.fromRGB(38, 38, 46),
				BorderSizePixel = 0,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = Color3.fromRGB(230, 230, 230),
				Text = "",
				LayoutOrder = order,
			}, codexScroll)
			make("UICorner", { CornerRadius = UDim.new(0, 6) }, cell)
			codexCells[template.id] = cell
		end
		local found = snap.codex[template.id]
		if found then
			cell.Text = template.name
			cell.TextColor3 = rarityColor(template.rarity)
			cell.BackgroundColor3 = Color3.fromRGB(44, 44, 52)
		else
			cell.Text = "??? (" .. template.rarity .. ")"
			cell.TextColor3 = Color3.fromRGB(120, 120, 120)
			cell.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
		end
	end
end

local function render(snap: any)
	crunchLabel.Text = ("🍟 %s Crunch"):format(abbrev(snap.crunch))
	rebirthInfo.Text = ("%s  |  Rebirths: %d  |  Income x%.2f"):format(snap.fryerName, snap.rebirths, snap.permMult)
	rebirthBtn.BackgroundColor3 = snap.canRebirth and Color3.fromRGB(150, 60, 200) or Color3.fromRGB(70, 50, 80)
	rebirthBtn.Text = snap.canRebirth and "Rebirth ✓" or "Rebirth 🔒"

	pruneLanes(#snap.lanes)
	for _, laneSnap in snap.lanes do
		renderLane(laneSnap)
	end
	renderShop(snap)
	renderCodex(snap)
end

-- ---- events ----------------------------------------------------------------

SyncState.OnClientEvent:Connect(function(snap)
	latest = snap
	render(snap)
end)

local toastTween
Toast.OnClientEvent:Connect(function(kind: string, text: string)
	toastLabel.Text = text
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = 0.15
	local myTag = tick()
	toastLabel:SetAttribute("tag", myTag)
	task.delay(2.2, function()
		if toastLabel:GetAttribute("tag") == myTag then
			toastLabel.TextTransparency = 1
			toastLabel.BackgroundTransparency = 1
		end
	end)
end)

-- Smoothly animate the fry-timer bars using the locally captured end time.
RunService.RenderStepped:Connect(function()
	for index, timer in fryTimers do
		local entry = laneCards[index]
		if entry and entry.timerBg.Visible then
			local remaining = math.max(0, timer.endClock - os.clock())
			local frac = 1 - (remaining / timer.duration)
			entry.timerFill.Size = UDim2.new(math.clamp(frac, 0, 1), 0, 1, 0)
		end
	end
end)

print("[DeepFryFactory] Client UI ready.")
