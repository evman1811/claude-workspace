--!strict
-- Bootstrap.client.lua  (LocalScript in StarterPlayerScripts)
-- Interactive, juicy 3D client. Builds a walk-up factory LOCALLY (each player sees their own
-- fryers reflecting their own state) and drives it from server snapshots. INTENT ONLY leaves
-- the client (ProximityPrompts fire StartFry/Bank/BuyUpgrade/Rebirth); the server is
-- authoritative. Everything is procedural — built-in textures only, no asset uploads needed.
--
-- Juice: meme objects drop from a conveyor into the fryer, arc to the bank counter with a
-- coin burst, or shrivel in smoke on burn. Dynamic post-processing punches on fry passes and
-- rare pulls. Flickering fryer lights, rarity auras (Epic+), camera shake, FOV punch,
-- count-up Crunch, and world-space sizzle meters.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
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

-- ---- palette / constants ---------------------------------------------------

local STEEL = Color3.fromRGB(70, 74, 82)
local STEEL_DARK = Color3.fromRGB(42, 45, 52)
local TRIM = Color3.fromRGB(255, 150, 45)
local OIL_COLOR = Color3.fromRGB(240, 170, 55)
local FLOOR_COLOR = Color3.fromRGB(34, 32, 36)
local GOLD = Color3.fromRGB(255, 205, 70)

local STATION_X = { -11, 0, 11 }
local STATION_Z = -18
local SHOP_POS = Vector3.new(20, 0, -9)
local REBIRTH_POS = Vector3.new(-20, 0, -9)
local BANK_POS = Vector3.new(0, 0, -4)
local FLOOR_TOP = 0.2

local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Cursed = 7 }
local function isEpicPlus(rarity: string?): boolean
	return (rarity and (RARITY_RANK[rarity] or 0) >= 4) or false
end

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

local function part(props: { [string]: any }, parent: Instance?): BasePart
	props.Anchored = if props.Anchored == nil then true else props.Anchored
	return make("Part", props, parent)
end

local function tween(inst: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local ti = TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local t = TweenService:Create(inst, ti, goal)
	t:Play()
	return t
end

-- ---- camera juice ----------------------------------------------------------

local camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: any
local BASE_FOV = 70
local shakeMag = 0

RunService:BindToRenderStep("DFCameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	camera = Workspace.CurrentCamera
	if camera and shakeMag > 0.02 then
		local off = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * (shakeMag * 2)
		camera.CFrame = camera.CFrame * CFrame.new(off)
		shakeMag *= math.max(0, 1 - dt * 7)
	end
end)

local function cameraShake(mag: number)
	shakeMag = math.max(shakeMag, mag)
end

local function fovPunch(amount: number)
	if not camera then
		return
	end
	tween(camera, 0.07, { FieldOfView = BASE_FOV - amount }, Enum.EasingStyle.Quad)
	task.delay(0.09, function()
		if camera then
			tween(camera, 0.28, { FieldOfView = BASE_FOV }, Enum.EasingStyle.Back)
		end
	end)
end

-- ---- post-processing -------------------------------------------------------

local function ensure(class: string, parent: Instance): any
	return parent:FindFirstChildOfClass(class) or make(class, {}, parent)
end

local bloom: BloomEffect
local colorFx: ColorCorrectionEffect

local function setupAtmosphere()
	Lighting.Technology = Enum.Technology.ShadowMap
	Lighting.Brightness = 1.4
	Lighting.Ambient = Color3.fromRGB(48, 42, 40)
	Lighting.OutdoorAmbient = Color3.fromRGB(58, 52, 52)
	Lighting.ClockTime = 20 -- night
	Lighting.EnvironmentDiffuseScale = 0.3
	Lighting.EnvironmentSpecularScale = 0.4

	local atmos = ensure("Atmosphere", Lighting)
	atmos.Density = 0.36
	atmos.Haze = 2.2 -- greasy haze
	atmos.Color = Color3.fromRGB(190, 165, 140)
	atmos.Decay = Color3.fromRGB(70, 50, 40)

	bloom = ensure("BloomEffect", Lighting)
	bloom.Intensity = 0.6
	bloom.Size = 24
	bloom.Threshold = 1.0

	colorFx = ensure("ColorCorrectionEffect", Lighting)
	colorFx.Saturation = 0.22 -- high saturation for the deep-fried look
	colorFx.Contrast = 0.12
	colorFx.Brightness = 0.02
	colorFx.TintColor = Color3.fromRGB(255, 238, 220)

	local dof = ensure("DepthOfFieldEffect", Lighting)
	dof.FarIntensity = 0.12
	dof.FocusDistance = 24
	dof.InFocusRadius = 26
	dof.NearIntensity = 0.05
end

-- Briefly intensify the fried look. `strong` for rare pulls.
local function fxPunch(strong: boolean)
	if not colorFx or not bloom then
		return
	end
	local satPeak = strong and 0.55 or 0.36
	local bloomPeak = strong and 1.6 or 1.0
	tween(colorFx, 0.08, { Saturation = satPeak, Contrast = strong and 0.24 or 0.18 })
	tween(bloom, 0.08, { Intensity = bloomPeak })
	task.delay(0.16, function()
		tween(colorFx, 0.5, { Saturation = 0.22, Contrast = 0.12 })
		tween(bloom, 0.5, { Intensity = 0.6 })
	end)
end

-- ---- world -----------------------------------------------------------------

local WORLD = make("Folder", { Name = "DeepFryWorld_Local" }, Workspace)

local function neon(props: { [string]: any }): BasePart
	props.Material = Enum.Material.Neon
	props.CanCollide = if props.CanCollide == nil then false else props.CanCollide
	return part(props, WORLD)
end

local coinAnchor: BasePart -- set in buildBankCounter
local coinBurst: ParticleEmitter

local function floatText(worldPos: Vector3, text: string, color: Color3)
	local p = part({
		CanCollide = false, Transparency = 1, Size = Vector3.new(1, 1, 1), Position = worldPos,
	}, WORLD)
	local bb = make("BillboardGui", { Adornee = p, Size = UDim2.new(0, 160, 0, 44), AlwaysOnTop = true }, p)
	local lbl = make("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne,
		TextScaled = true, TextColor3 = color, Text = text,
	}, bb)
	make("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }, lbl)
	tween(p, 0.9, { Position = worldPos + Vector3.new(0, 4, 0) })
	tween(lbl, 0.9, { TextTransparency = 1 })
	task.delay(0.95, function()
		p:Destroy()
	end)
end

local function buildBankCounter()
	local baseTop = FLOOR_TOP
	-- Counter desk.
	part({
		Name = "BankCounter",
		Size = Vector3.new(8, 3, 3),
		Position = Vector3.new(BANK_POS.X, baseTop + 1.5, BANK_POS.Z),
		Color = Color3.fromRGB(64, 46, 34),
		Material = Enum.Material.WoodPlanks,
	}, WORLD)
	-- Register.
	neon({
		Name = "Register",
		Size = Vector3.new(2, 1.4, 1.4),
		Position = Vector3.new(BANK_POS.X, baseTop + 3.7, BANK_POS.Z),
		Color = GOLD,
	})
	-- Sign.
	local anchor = part({
		CanCollide = false, Transparency = 1, Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(BANK_POS.X, baseTop + 6, BANK_POS.Z),
	}, WORLD)
	local bb = make("BillboardGui", { Adornee = anchor, Size = UDim2.new(0, 150, 0, 38), MaxDistance = 70 }, anchor)
	local lbl = make("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne,
		TextSize = 20, TextColor3 = GOLD, Text = "💰 BANK",
	}, bb)
	make("UIStroke", { Color = Color3.fromRGB(60, 40, 0), Thickness = 2 }, lbl)

	-- Coin burst emitter (off; :Emit on bank).
	coinAnchor = part({
		CanCollide = false, Transparency = 1, Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(BANK_POS.X, baseTop + 3.6, BANK_POS.Z),
	}, WORLD)
	coinBurst = make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(GOLD),
		Size = NumberSequence.new(0.6),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -18, 0),
		Rate = 0,
		Enabled = false,
	}, coinAnchor)
end

local function buildEnvironment()
	part({
		Name = "Floor", Size = Vector3.new(66, 1, 52), Position = Vector3.new(0, FLOOR_TOP - 0.5, -16),
		Color = FLOOR_COLOR, Material = Enum.Material.Slate, TopSurface = Enum.SurfaceType.Smooth,
	}, WORLD)
	part({
		Name = "Platform", Size = Vector3.new(50, 0.6, 12), Position = Vector3.new(0, FLOOR_TOP + 0.3, STATION_Z),
		Color = Color3.fromRGB(52, 55, 62), Material = Enum.Material.DiamondPlate,
	}, WORLD)
	for _, sx in { -25, 25 } do
		neon({ Size = Vector3.new(0.4, 0.7, 12), Position = Vector3.new(sx, FLOOR_TOP + 0.35, STATION_Z), Color = TRIM })
	end

	local walls = {
		{ size = Vector3.new(66, 20, 1), pos = Vector3.new(0, 10, -42) },
		{ size = Vector3.new(1, 20, 52), pos = Vector3.new(-33, 10, -16) },
		{ size = Vector3.new(1, 20, 52), pos = Vector3.new(33, 10, -16) },
	}
	for _, w in walls do
		part({
			Name = "Wall", Size = w.size, Position = w.pos,
			Color = Color3.fromRGB(26, 26, 30), Material = Enum.Material.Concrete, CanCollide = true,
		}, WORLD)
		local horizontal = w.size.X > w.size.Z
		neon({
			Size = if horizontal then Vector3.new(w.size.X, 0.3, 0.4) else Vector3.new(0.4, 0.3, w.size.Z),
			Position = w.pos + Vector3.new(0, 8, 0), Color = Color3.fromRGB(80, 200, 255),
		})
	end

	-- Neon title sign with its own colored light.
	local signPart = part({
		Name = "Sign", Size = Vector3.new(30, 6, 0.6), Position = Vector3.new(0, 15, -41.4),
		Color = Color3.fromRGB(16, 16, 20), Material = Enum.Material.SmoothPlastic, CanCollide = false,
	}, WORLD)
	make("PointLight", { Brightness = 3, Range = 22, Color = TRIM }, signPart)
	local sg = make("SurfaceGui", { Face = Enum.NormalId.Front, CanvasSize = Vector2.new(1200, 240) }, signPart)
	local signText = make("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.fromRGB(255, 190, 70), TextScaled = true, Text = "🍟 DEEP FRY FACTORY",
	}, sg)
	make("UIStroke", { Color = Color3.fromRGB(120, 60, 0), Thickness = 3 }, signText)

	-- Oil drums.
	for i, spot in { Vector3.new(-29, 0, -36), Vector3.new(29, 0, -36), Vector3.new(-29, 0, 4), Vector3.new(29, 0, 4) } do
		part({
			Name = "OilDrum", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 3, 3),
			Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(spot.X, FLOOR_TOP + 2, spot.Z),
			Color = if i % 2 == 0 then Color3.fromRGB(180, 60, 50) else Color3.fromRGB(60, 110, 170),
			Material = Enum.Material.Metal,
		}, WORLD)
	end

	-- Fry crates.
	local function crateStack(base: Vector3)
		for _, off in { Vector3.new(0, 0, 0), Vector3.new(2.1, 0, 0), Vector3.new(1.05, 2.1, 0) } do
			part({
				Name = "FryCrate", Size = Vector3.new(2, 2, 2),
				Position = base + Vector3.new(off.X, FLOOR_TOP + 1 + off.Y, off.Z),
				Color = Color3.fromRGB(210, 160, 60), Material = Enum.Material.WoodPlanks,
			}, WORLD)
		end
	end
	crateStack(Vector3.new(-27, 0, -24))
	crateStack(Vector3.new(27, 0, -24))
end

-- ---- prompts ---------------------------------------------------------------

local function addPrompt(parent: BasePart, actionText: string, key: Enum.KeyCode, order: number): ProximityPrompt
	return make("ProximityPrompt", {
		ActionText = actionText, ObjectText = "", KeyboardKeyCode = key, HoldDuration = 0,
		MaxActivationDistance = 12, RequiresLineOfSight = false, UIOffset = Vector2.new(0, order * 46),
	}, parent)
end

-- ---- fryer stations --------------------------------------------------------

type Station = {
	model: Model,
	cabinet: BasePart,
	oil: BasePart,
	indicator: BasePart,
	glow: PointLight,
	steam: ParticleEmitter,
	bubbles: ParticleEmitter,
	smoke: ParticleEmitter,
	memePart: BasePart,
	memeDecalF: Decal,
	memeDecalB: Decal,
	aura: ParticleEmitter,
	cardAnchor: BasePart,
	imageLabel: ImageLabel,
	nameLabel: TextLabel,
	valueLabel: TextLabel,
	statusLabel: TextLabel,
	meterFill: Frame,
	meterText: TextLabel,
	cardStroke: UIStroke,
	fryPrompt: ProximityPrompt,
	bankPrompt: ProximityPrompt,
	-- animation bookkeeping
	homePos: Vector3,
	chutePos: Vector3,
	frying: boolean,
	memeBusy: boolean,
	prevState: string?,
	prevValue: number,
	rank: number,
}

local stations: { [number]: Station } = {}
local fryTimers: { [number]: { endClock: number, duration: number } } = {}

local function buildStation(index: number): Station
	local x = STATION_X[index] or (STATION_X[#STATION_X] + (index - #STATION_X) * 11)
	local baseTop = FLOOR_TOP + 0.6
	local model = make("Model", { Name = "FryerStation" .. index }, WORLD)

	local cabinet = part({
		Name = "Cabinet", Size = Vector3.new(5, 3.4, 4), Position = Vector3.new(x, baseTop + 1.7, STATION_Z),
		Color = STEEL, Material = Enum.Material.Metal,
	}, model)
	part({
		Name = "Plinth", Size = Vector3.new(5.4, 0.5, 4.4), Position = Vector3.new(x, baseTop + 0.25, STATION_Z),
		Color = STEEL_DARK, Material = Enum.Material.Metal,
	}, model)
	local indicator = neon({
		Name = "Indicator", Size = Vector3.new(0.6, 0.6, 0.3),
		Position = Vector3.new(x - 1.6, baseTop + 2.4, STATION_Z + 2.05), Color = Color3.fromRGB(120, 120, 120),
	})
	indicator.Parent = model

	local vatTop = baseTop + 3.4
	part({
		Name = "Vat", Size = Vector3.new(4.2, 1.6, 3.2), Position = Vector3.new(x, vatTop + 0.8, STATION_Z),
		Color = STEEL_DARK, Material = Enum.Material.Metal,
	}, model)
	local oil = part({
		Name = "Oil", Size = Vector3.new(3.7, 0.3, 2.7), Position = Vector3.new(x, vatTop + 1.5, STATION_Z),
		Color = OIL_COLOR, Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false,
	}, model)
	local glow = make("PointLight", { Brightness = 0.6, Range = 12, Color = OIL_COLOR }, oil)

	local steam = make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(235, 230, 220)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3.4) }),
		Lifetime = NumberRange.new(1.1, 1.8), Rate = 8, Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(18, 18), Acceleration = Vector3.new(0, 4, 0), Enabled = false,
	}, oil)
	local bubbles = make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(OIL_COLOR),
		Transparency = NumberSequence.new(0.2), Size = NumberSequence.new(0.4),
		Lifetime = NumberRange.new(0.3, 0.6), Rate = 14, Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(30, 30), Enabled = false,
	}, oil)

	part({
		Name = "Hood", Size = Vector3.new(6, 1.2, 5), Position = Vector3.new(x, vatTop + 4.2, STATION_Z),
		Color = Color3.fromRGB(28, 28, 32), Material = Enum.Material.Metal, CanCollide = false,
	}, model)

	-- Simple conveyor chute feeding the fryer from above/behind.
	part({
		Name = "Chute", Size = Vector3.new(2.4, 0.4, 5), Position = Vector3.new(x, vatTop + 5.6, STATION_Z - 2),
		Color = Color3.fromRGB(40, 40, 46), Material = Enum.Material.Metal, CanCollide = false,
		Orientation = Vector3.new(24, 0, 0),
	}, model)

	-- The physical meme object (drops in, arcs out, or shrivels).
	local homePos = Vector3.new(x, vatTop + 1.9, STATION_Z)
	local chutePos = Vector3.new(x, vatTop + 7.5, STATION_Z - 2)
	local memePart = part({
		Name = "Meme", Size = Vector3.new(1.9, 1.9, 0.5), Position = homePos,
		Color = Color3.fromRGB(150, 150, 150), Material = Enum.Material.SmoothPlastic,
		CanCollide = false, Transparency = 1,
	}, model)
	local memeDecalF = make("Decal", { Face = Enum.NormalId.Front, Transparency = 1 }, memePart)
	local memeDecalB = make("Decal", { Face = Enum.NormalId.Back, Transparency = 1 }, memePart)
	local aura = make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(GOLD),
		Size = NumberSequence.new(0.5), Transparency = NumberSequence.new(0.2),
		Lifetime = NumberRange.new(0.5, 0.9), Rate = 12, Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180), Enabled = false,
	}, memePart)
	local smoke = make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(60, 55, 50)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) }),
		Lifetime = NumberRange.new(0.6, 1.1), Rate = 0, Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(60, 60), Acceleration = Vector3.new(0, 5, 0), Enabled = false,
	}, memePart)

	-- Floating world-space card: sizzle meter + value + name.
	local cardAnchor = part({
		Name = "CardAnchor", CanCollide = false, Transparency = 1, Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(x, vatTop + 8.6, STATION_Z),
	}, model)
	local bb = make("BillboardGui", { Adornee = cardAnchor, Size = UDim2.new(0, 240, 0, 132), MaxDistance = 70 }, cardAnchor)
	local card = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(26, 26, 30) }, bb)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(40, 40, 46), Color3.fromRGB(18, 18, 22)) }, card)
	local cardStroke = make("UIStroke", { Color = Color3.fromRGB(90, 90, 90), Thickness = 3, Transparency = 0.1 }, card)
	-- (image kept for optional close-up; main art is on the physical meme)
	local image = make("ImageLabel", { Visible = false, Image = "" }, card)
	local nameLabel = make("TextLabel", {
		Size = UDim2.new(1, -14, 0, 26), Position = UDim2.new(0, 7, 0, 8), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = Color3.fromRGB(255, 255, 255), Text = "Lane " .. index,
	}, card)
	local valueLabel = make("TextLabel", {
		Size = UDim2.new(1, -14, 0, 20), Position = UDim2.new(0, 7, 0, 36), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = Color3.fromRGB(255, 210, 120), Text = "",
	}, card)
	local statusLabel = make("TextLabel", {
		Size = UDim2.new(1, -14, 0, 18), Position = UDim2.new(0, 7, 0, 58), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.fromRGB(120, 220, 255), Text = "",
	}, card)
	local meterBg = make("Frame", {
		Size = UDim2.new(1, -14, 0, 18), Position = UDim2.new(0, 7, 1, -26), BackgroundColor3 = Color3.fromRGB(48, 48, 54),
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, meterBg)
	local meterFill = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(235, 90, 40) }, meterBg)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, meterFill)
	local meterText = make("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextSize = 12, TextColor3 = Color3.fromRGB(255, 255, 255), Text = "",
	}, meterBg)

	local fryPrompt = addPrompt(cabinet, "Fry", Enum.KeyCode.E, 0)
	local bankPrompt = addPrompt(cabinet, "Bank", Enum.KeyCode.Q, 1)
	fryPrompt.Triggered:Connect(function()
		StartFry:FireServer(index)
	end)
	bankPrompt.Triggered:Connect(function()
		Bank:FireServer(index)
	end)

	local st: Station = {
		model = model, cabinet = cabinet, oil = oil, indicator = indicator, glow = glow,
		steam = steam, bubbles = bubbles, smoke = smoke, memePart = memePart,
		memeDecalF = memeDecalF, memeDecalB = memeDecalB, aura = aura, cardAnchor = cardAnchor,
		imageLabel = image, nameLabel = nameLabel, valueLabel = valueLabel, statusLabel = statusLabel,
		meterFill = meterFill, meterText = meterText, cardStroke = cardStroke,
		fryPrompt = fryPrompt, bankPrompt = bankPrompt,
		homePos = homePos, chutePos = chutePos, frying = false, memeBusy = false,
		prevState = nil, prevValue = 0, rank = 0,
	}
	stations[index] = st
	return st
end

local function getStation(index: number): Station
	return stations[index] or buildStation(index)
end

-- ---- meme object appearance + animations -----------------------------------

local function dressMeme(st: Station, template: any, rarity: string?)
	st.memePart.Color = rarityColor(rarity)
	if template and template.image then
		st.memeDecalF.Texture = template.image
		st.memeDecalB.Texture = template.image
		st.memeDecalF.Transparency = 0
		st.memeDecalB.Transparency = 0
	else
		st.memeDecalF.Transparency = 1
		st.memeDecalB.Transparency = 1
	end
	st.aura.Color = ColorSequence.new(rarityColor(rarity))
	st.aura.Enabled = isEpicPlus(rarity)
end

local function hideMeme(st: Station)
	st.memePart.Transparency = 1
	st.memeDecalF.Transparency = 1
	st.memeDecalB.Transparency = 1
	st.aura.Enabled = false
	st.memePart.Size = Vector3.new(1.9, 1.9, 0.5)
	st.memePart.Position = st.homePos
end

local function dropMeme(st: Station)
	st.memeBusy = true
	st.memePart.Transparency = 0
	st.memePart.Size = Vector3.new(1.9, 1.9, 0.5)
	st.memePart.Position = st.chutePos
	local t = tween(st.memePart, 0.45, { Position = st.homePos }, Enum.EasingStyle.Bounce)
	t.Completed:Connect(function()
		st.memeBusy = false
	end)
end

local function survivePop(st: Station)
	st.memeBusy = true
	tween(st.memePart, 0.1, { Size = Vector3.new(2.5, 2.5, 0.6) }, Enum.EasingStyle.Back)
	task.delay(0.11, function()
		local t = tween(st.memePart, 0.12, { Size = Vector3.new(1.9, 1.9, 0.5) })
		t.Completed:Connect(function()
			st.memeBusy = false
		end)
	end)
	fxPunch(false)
end

local function burnMeme(st: Station)
	st.memeBusy = true
	st.smoke:Emit(20)
	st.memePart.Color = Color3.fromRGB(40, 30, 24)
	tween(st.memePart, 0.4, { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 }, Enum.EasingStyle.Quad)
	task.delay(0.45, function()
		hideMeme(st)
		st.memeBusy = false
	end)
	cameraShake(0.9)
end

local function bankMeme(st: Station, gain: number)
	st.memeBusy = true
	st.aura.Enabled = false
	local up = st.homePos + Vector3.new(0, 3, 0)
	local counterTop = coinAnchor and coinAnchor.Position or (BANK_POS + Vector3.new(0, 4, 0))
	tween(st.memePart, 0.16, { Position = up }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(0.16, function()
		local t = tween(st.memePart, 0.34, { Position = counterTop, Size = Vector3.new(0.8, 0.8, 0.3) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		t.Completed:Connect(function()
			if coinBurst then
				coinBurst:Emit(18)
			end
			floatText(counterTop + Vector3.new(0, 1, 0), "+" .. abbrev(gain), GOLD)
			hideMeme(st)
			st.memeBusy = false
		end)
	end)
	fovPunch(7)
end

-- ---- station state update --------------------------------------------------

local latest: any = nil

local function setFrying(st: Station, on: boolean)
	st.frying = on
	st.steam.Enabled = on
	st.bubbles.Enabled = on
	st.oil.Transparency = on and 0 or 0.15
end

local function updateStation(laneSnap: any)
	local st = getStation(laneSnap.index)
	local prev = st.prevState
	local template = laneSnap.templateId and Templates.get(laneSnap.templateId)
	local rc = rarityColor(laneSnap.rarity)
	st.rank = (laneSnap.rarity and RARITY_RANK[laneSnap.rarity]) or 0

	-- Card text.
	if laneSnap.state == "empty" then
		st.nameLabel.Text = "Empty — spawning…"
		st.nameLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
		st.valueLabel.Text = ""
		st.statusLabel.Text = ""
		st.meterFill.Size = UDim2.new(0, 0, 1, 0)
		st.meterText.Text = ""
		st.cardStroke.Color = Color3.fromRGB(90, 90, 90)
	else
		local name = template and template.name or "???"
		st.nameLabel.Text = ("%s • %s"):format(name, laneSnap.rarity or "?")
		st.nameLabel.TextColor3 = rc
		st.cardStroke.Color = rc
		local nextValue = laneSnap.value * (latest and latest.fryerMult or 1)
		st.valueLabel.Text = ("Pass %d — %s → %s"):format(laneSnap.pass, abbrev(laneSnap.value), abbrev(nextValue))
		local burn = laneSnap.nextBurnChance or 0
		st.meterFill.Size = UDim2.new(math.clamp(burn, 0, 1), 0, 1, 0)
		st.meterText.Text = ("🔥 %d%%"):format(math.floor(burn * 100 + 0.5))
		st.statusLabel.Text = laneSnap.state == "frying" and "🍳 Frying…" or "[E] Fry   [Q] Bank"
	end

	-- Indicator + prompts + fry FX.
	if laneSnap.state == "frying" then
		st.indicator.Color = Color3.fromRGB(255, 140, 40)
		st.fryPrompt.Enabled = false
		st.bankPrompt.Enabled = false
		setFrying(st, true)
		if laneSnap.fryRemaining and laneSnap.fryDuration then
			fryTimers[laneSnap.index] = { endClock = os.clock() + laneSnap.fryRemaining, duration = laneSnap.fryDuration }
		end
	elseif laneSnap.state == "ready" then
		st.indicator.Color = Color3.fromRGB(80, 220, 100)
		st.fryPrompt.Enabled = true
		st.bankPrompt.Enabled = true
		setFrying(st, false)
		fryTimers[laneSnap.index] = nil
	else -- empty
		st.indicator.Color = Color3.fromRGB(90, 90, 90)
		st.fryPrompt.Enabled = false
		st.bankPrompt.Enabled = false
		setFrying(st, false)
		fryTimers[laneSnap.index] = nil
	end

	-- Transition-driven object juice.
	if laneSnap.state == "ready" and (prev == nil or prev == "empty") then
		dressMeme(st, template, laneSnap.rarity)
		if prev == "empty" then
			dropMeme(st)
			fxPunch(isEpicPlus(laneSnap.rarity))
			if isEpicPlus(laneSnap.rarity) then
				cameraShake(0.5)
			end
		else
			-- initial sync: just show it in place
			st.memePart.Transparency = 0
			st.memePart.Position = st.homePos
			st.memePart.Size = Vector3.new(1.9, 1.9, 0.5)
		end
	elseif laneSnap.state == "ready" and prev == "frying" then
		survivePop(st)
	elseif laneSnap.state == "frying" and prev == "ready" then
		fxPunch(false)
	elseif laneSnap.state == "frying" and prev == nil then
		-- Connected mid-fry: just show the meme resting in the vat.
		dressMeme(st, template, laneSnap.rarity)
		st.memePart.Transparency = 0
		st.memePart.Position = st.homePos
		st.memePart.Size = Vector3.new(1.9, 1.9, 0.5)
	elseif laneSnap.state == "empty" and prev == "ready" then
		bankMeme(st, math.floor(st.prevValue * (latest and latest.permMult or 1)))
	elseif laneSnap.state == "empty" and prev == "frying" then
		burnMeme(st)
	elseif laneSnap.state == "empty" and prev == nil then
		hideMeme(st)
	end

	st.prevValue = laneSnap.value
	st.prevState = laneSnap.state
end

-- ---- kiosks ----------------------------------------------------------------

local function buildKiosk(name: string, pos: Vector3, color: Color3, actionText: string): ProximityPrompt
	local baseTop = FLOOR_TOP
	local body = part({
		Name = name .. "Kiosk", Size = Vector3.new(4, 6, 4), Position = Vector3.new(pos.X, baseTop + 3, pos.Z),
		Color = Color3.fromRGB(30, 30, 36), Material = Enum.Material.Metal,
	}, WORLD)
	neon({ Name = "Screen", Size = Vector3.new(3, 3.4, 0.2), Position = Vector3.new(pos.X, baseTop + 3.6, pos.Z + 2.05), Color = color })
	neon({ Name = "Beam", Size = Vector3.new(1.4, 5, 1.4), Position = Vector3.new(pos.X, baseTop + 8.5, pos.Z), Color = color, Transparency = 0.55 })
	make("PointLight", { Brightness = 2.5, Range = 16, Color = color }, body)
	local anchor = part({ CanCollide = false, Transparency = 1, Size = Vector3.new(1, 1, 1), Position = Vector3.new(pos.X, baseTop + 9, pos.Z) }, WORLD)
	local bb = make("BillboardGui", { Adornee = anchor, Size = UDim2.new(0, 170, 0, 42), MaxDistance = 70 }, anchor)
	local lbl = make("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne,
		TextSize = 22, TextColor3 = Color3.fromRGB(255, 255, 255), Text = name,
	}, bb)
	make("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }, lbl)
	return addPrompt(body, actionText, Enum.KeyCode.E, 0)
end

-- ---- HUD (minimal: Crunch + Shop button) -----------------------------------

local gui = make("ScreenGui", { Name = "DeepFryHUD", ResetOnSpawn = false, IgnoreGuiInset = true }, playerGui)

local topBar = make("Frame", {
	Size = UDim2.new(0, 320, 0, 46), Position = UDim2.new(0, 14, 0, 14), BackgroundColor3 = Color3.fromRGB(22, 18, 15),
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, topBar)
make("UIStroke", { Color = TRIM, Thickness = 1.5, Transparency = 0.4 }, topBar)
local crunchLabel = make("TextLabel", {
	Size = UDim2.new(1, -16, 0, 24), Position = UDim2.new(0, 14, 0, 3), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 210, 120), Text = "🍟 0 Crunch",
}, topBar)
local infoLabel = make("TextLabel", {
	Size = UDim2.new(1, -16, 0, 14), Position = UDim2.new(0, 14, 0, 27), BackgroundTransparency = 1,
	Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(190, 190, 190), Text = "Rebirths 0 • x1.00",
}, topBar)

local shopButton = make("TextButton", {
	Size = UDim2.new(0, 120, 0, 44), Position = UDim2.new(0, 348, 0, 15),
	BackgroundColor3 = Color3.fromRGB(60, 150, 95), Font = Enum.Font.GothamBold, TextSize = 16,
	TextColor3 = Color3.fromRGB(255, 255, 255), Text = "🛒 Shop", AutoButtonColor = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, shopButton)

-- Button juice: scale on hover/press.
local function juiceButton(btn: GuiButton, base: UDim2)
	btn.Size = base
	btn.MouseEnter:Connect(function()
		tween(btn, 0.12, { Size = base + UDim2.fromOffset(6, 4) }, Enum.EasingStyle.Back)
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, 0.12, { Size = base })
	end)
	btn.MouseButton1Down:Connect(function()
		tween(btn, 0.08, { Size = base - UDim2.fromOffset(4, 3) })
	end)
	btn.MouseButton1Up:Connect(function()
		tween(btn, 0.1, { Size = base + UDim2.fromOffset(6, 4) }, Enum.EasingStyle.Back)
	end)
end
juiceButton(shopButton, shopButton.Size)

-- Shop panel.
local shopPanel = make("Frame", {
	Size = UDim2.new(0, 340, 0, 262), Position = UDim2.new(0.5, -170, 0.5, -131),
	BackgroundColor3 = Color3.fromRGB(24, 24, 30), Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 14) }, shopPanel)
make("UIStroke", { Color = Color3.fromRGB(60, 190, 110), Thickness = 1.5, Transparency = 0.3 }, shopPanel)
make("TextLabel", {
	Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 12, 0, 8), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 255, 255), Text = "Upgrades",
}, shopPanel)
local closeShop = make("TextButton", {
	Size = UDim2.new(0, 28, 0, 28), Position = UDim2.new(1, -34, 0, 8), BackgroundColor3 = Color3.fromRGB(120, 50, 50),
	Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.fromRGB(255, 255, 255), Text = "X",
}, shopPanel)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, closeShop)
local shopList = make("Frame", { Size = UDim2.new(1, -20, 1, -48), Position = UDim2.new(0, 10, 0, 42), BackgroundTransparency = 1 }, shopPanel)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, shopList)

local shopOpen = false
local function setShopOpen(open: boolean)
	shopOpen = open
	shopPanel.Visible = open
end
closeShop.MouseButton1Click:Connect(function()
	setShopOpen(false)
end)
shopButton.MouseButton1Click:Connect(function()
	setShopOpen(not shopOpen)
end)

local shopRows: { [string]: any } = {}
local function renderShop(snap: any)
	for order, id in Upgrades.Order do
		local row = shopRows[id]
		if not row then
			local def = Upgrades.getDef(id)
			local btn = make("TextButton", {
				Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = Color3.fromRGB(38, 38, 46), Text = "",
				AutoButtonColor = true, LayoutOrder = order,
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

-- Codex (toggle C).
local codexPanel = make("Frame", {
	Size = UDim2.new(0, 320, 0, 300), Position = UDim2.new(1, -334, 0.5, -150),
	BackgroundColor3 = Color3.fromRGB(24, 24, 30), Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 14) }, codexPanel)
make("UIStroke", { Color = TRIM, Thickness = 1.5, Transparency = 0.4 }, codexPanel)
make("TextLabel", {
	Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 12, 0, 8), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 255, 255), Text = "Codex  (press C)",
}, codexPanel)
local codexScroll = make("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -44), Position = UDim2.new(0, 10, 0, 40), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
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

-- Toast.
local toastLabel = make("TextLabel", {
	Size = UDim2.new(0, 520, 0, 38), Position = UDim2.new(0.5, -260, 1, -62), BackgroundColor3 = Color3.fromRGB(18, 18, 20),
	BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "", TextTransparency = 1,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, toastLabel)

-- ---- render + events -------------------------------------------------------

local rebirthPrompt: ProximityPrompt
local targetCrunch = 0
local displayCrunch = 0

local function render(snap: any)
	targetCrunch = snap.crunch
	infoLabel.Text = ("%s • Rebirths %d • x%.2f"):format(snap.fryerName, snap.rebirths, snap.permMult)

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

	if rebirthPrompt then
		rebirthPrompt.ActionText = snap.canRebirth and "Rebirth ✓" or "Rebirth (need 100k)"
	end
	renderShop(snap)
	renderCodex(snap)
end

SyncState.OnClientEvent:Connect(function(snap)
	latest = snap
	render(snap)
end)

Toast.OnClientEvent:Connect(function(kind: string, text: string)
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

-- Per-frame juice: count-up, timers, idle bob, flicker.
RunService.RenderStepped:Connect(function()
	-- Crunch count-up.
	if math.abs(targetCrunch - displayCrunch) > 0.5 then
		displayCrunch += (targetCrunch - displayCrunch) * 0.15
		crunchLabel.Text = ("🍟 %s Crunch"):format(abbrev(displayCrunch))
	elseif displayCrunch ~= targetCrunch then
		displayCrunch = targetCrunch
		crunchLabel.Text = ("🍟 %s Crunch"):format(abbrev(displayCrunch))
	end

	local now = os.clock()
	for index, st in stations do
		-- Fry timer text.
		local timer = fryTimers[index]
		if timer then
			st.statusLabel.Text = ("🍳 Frying… %.1fs"):format(math.max(0, timer.endClock - now))
		end
		-- Idle bob of the floating card + resting meme.
		local bob = math.sin(now * 2 + index) * 0.12
		st.cardAnchor.Position = Vector3.new(st.cardAnchor.Position.X, st.homePos.Y + 6.7 + bob, st.cardAnchor.Position.Z)
		if not st.memeBusy and st.prevState == "ready" then
			st.memePart.Position = Vector3.new(st.homePos.X, st.homePos.Y + bob * 0.6, st.homePos.Z)
		end
		-- Warm flicker inside the fryer.
		local target = st.frying and 2.4 or 0.7
		st.glow.Brightness = target * (0.82 + 0.18 * math.random())
	end
end)

-- ---- go --------------------------------------------------------------------

setupAtmosphere()
buildEnvironment()
buildBankCounter()
local shopPrompt = buildKiosk("SHOP", SHOP_POS, Color3.fromRGB(60, 190, 110), "Open Shop")
rebirthPrompt = buildKiosk("REBIRTH", REBIRTH_POS, Color3.fromRGB(180, 90, 240), "Rebirth")
shopPrompt.Triggered:Connect(function()
	setShopOpen(not shopOpen)
end)
rebirthPrompt.Triggered:Connect(function()
	Rebirth:FireServer()
end)

print("[DeepFryFactory] Juicy world ready. Walk to a fryer and press E.")
