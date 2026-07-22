# Deep Fry Factory — MVP

A server-authoritative Roblox idle game. Raw memes ride a conveyor into a fryer; each fry
pass multiplies value but adds burn risk past a safe line. Bank for Crunch, spend on
upgrades, prestige for a permanent multiplier.

Built with **Rojo + Luau**. Client sends **intent only** — every value, roll, and currency
change is decided and validated on the server.

## Project layout

```
default.project.json
src/
  shared/   -> ReplicatedStorage/Shared        (modules + types both sides use)
    Config.lua        ALL tunable numbers live here
    Templates.lua     10 original placeholder memes + rarity roll
    Fryers.lua        3 fryers
    Upgrades.lua      cost curve + effect resolution
    FryMath.lua       pure fry/burn formulas (client & server share these)
    Remotes.lua       RemoteEvent definitions + creation
    Types.lua         snapshot type shapes
  server/   -> ServerScriptService/DeepFry      (authoritative game logic)
    Bootstrap.server.lua   entry point: wires services + routes intents
    DataService.lua        ProfileService-style DataStore (session lock, autosave, on-leave)
    PlayerRuntime.lua      volatile per-player lanes + snapshot builder + sync
    FryService.lua         conveyor, StartFry, Bank, burn rolls, fryer unlocks
    ShopService.lua        BuyUpgrade, Rebirth
  client/   -> StarterPlayer/StarterPlayerScripts
    Bootstrap.client.lua   builds the whole UI in code, renders server snapshots
```

## Core loop & math (all resolved server-side)

- **Value at pass n:** `V = baseValue * fryerMult ^ n`
- **Safe line S:** `fryer.safe + oilBonus`. Passes `n <= S` never burn.
- **Burn chance (attempting pass n>S):** `q(n) = burnPerPass * (n - S)`, clamped to 95%.
- **On burn:** meme lost; player keeps a Burnt Crumb worth **10% of last safe value**.
- **Sizzle Meter:** the client shows the current bankable value and the next pass's burn %
  (sent from the server — the client never invents odds).

Tune anything in `src/shared/Config.lua`: rarities/weights, fryer stats, upgrade costs and
effects, rebirth requirement, spawn rate, save cadence.

## Save data (DataStore)

Fields: `crunch`, `ownedFryer`, `upgradeLevels {spawnRate, lane, oil}`, `codex`, `rebirths`,
`permMult`. Phase-2 stubs already persisted: `grease`, `era`. `DataService` session-locks
each profile (one live server owns it), auto-saves every 60s, saves on leave, and flushes on
shutdown via `BindToClose`. If DataStores are unavailable it falls back to an in-memory
profile so you can still test (no persistence).

---

## Sync into Studio & test

### 1. Install tooling (one-time)

You don't have Rojo installed yet. Easiest path is [Aftman](https://github.com/LPGhatguy/aftman)
or [Rokit](https://github.com/rojo-rbx/rokit), or grab the Rojo release directly.

```powershell
# with Aftman (recommended)
aftman add rojo-rbx/rojo
aftman install

# --- OR --- with cargo
cargo install rojo

# verify
rojo --version
```

Also install the **Rojo** plugin inside Studio (Studio → Toolbox → Plugins → search "Rojo",
or `rojo plugin install`).

### 2. Serve the project

From this folder (`DeepFryFactory/`):

```powershell
rojo serve
```

You'll see `Rojo server listening on port 34872`.

### 3. Connect from Studio

1. Open a new **Baseplate** place in Studio.
2. Open **Game Settings → Security → enable "Enable Studio Access to API Services"**
   (required for DataStore saves; without it the game runs but won't persist).
3. Click the **Rojo** plugin button → **Connect** (default `localhost:34872`).
   The tree syncs into ReplicatedStorage/ServerScriptService/StarterPlayer.

### 4. Play the fry loop (walk-up 3D factory)

Press **Play** (F5). You spawn inside the **Deep Fry Factory** — walk around with WASD.

- Walk up to a **fryer station**. A meme drops from the conveyor into the vat; a floating
  card shows its **value** and **🔥 burn risk** (the Sizzle Meter).
- Press **E** to **Fry** (bubbles + steam, value jumps by the fryer mult). Keep frying past
  the safe line and burn risk climbs. Fry too far → **smoke puff + shrivel**, small crumb.
- Press **Q** to **Bank** — the meme **arcs to the 💰 BANK counter** with a coin burst and a
  floating `+Crunch`.
- Walk to the green **SHOP** kiosk (or the on-screen **🛒 Shop** button) → press **E** →
  buy **Faster Conveyor / Extra Lane / Premium Oil**.
- Reach a fryer's unlock threshold (2,500 / 40,000 Crunch) and it auto-equips.
- Walk to the purple **REBIRTH** pad at 100k Crunch → press **E** for a permanent ×1.5.
- Press **C** anywhere to toggle the **Codex**.

### 5. Fast-testing tips

- To reach rebirth quickly, temporarily lower `Config.Rebirth.minCrunch`, or bump
  `Config.Rarities` Common `baseValue`. Everything balance-related is in `Config.lua`.
- To verify saving: bank some Crunch, **Stop**, **Play** again — your Crunch/upgrades persist
  (with API Services enabled). In a real server, leaving the game triggers the save.
- Two-player session-lock test: use **Test → Clients and Servers → 2 players** (Local Server).

## What you need to place / import in Studio (art)

**Nothing is required.** The entire factory — fryers, oil, steam/bubbles/smoke, coin bursts,
auras, neon signs, night lighting, and post-processing — is built procedurally in code using
Roblox's **built-in particle textures**, so it runs and looks complete with zero uploads.

These are the **only** things that involve importing/placing art, and all are **optional**:

| Piece | Required? | How |
|-------|-----------|-----|
| **Meme artwork** (the face on each fried token) | Optional | Studio → **Asset Manager → Images → Add** your own original PNGs. Copy each asset ID into `Config.TemplateImages` in `src/shared/Config.lua`, e.g. `blank_bob = "rbxassetid://123456789",`. Until added, each meme shows a clean **rarity-colored token**. **Original art only — no copyrighted memes.** |
| **Custom particle textures** | Optional | Currently `rbxasset://textures/particles/*` (built-in). To restyle steam/smoke/coins, upload images and swap the `Texture = "rbxasset://…"` strings in `Bootstrap.client.lua`. |
| **Spawn orientation** | Optional | Players use the default `SpawnLocation`. To have them face the fryers on spawn, rotate the SpawnLocation so `-Z` points at the factory (stations sit around `z = -18`). |
| **Meshes instead of block parts** | Optional (polish) | Everything is Parts for a low-poly look. To use modeled fryers/props, swap the parts built in `buildStation` / `buildEnvironment` for MeshParts — keep the `Station` table handles the animation code references. |

## Juice / feel (all automatic, no setup)

- Memes **drop from the chute**, **arc to the BANK counter** with a coin burst + floating
  `+Crunch`, or **shrivel in smoke** on burn.
- **Post-processing** (high saturation/contrast, bloom, DOF, greasy Atmosphere, night
  lighting) **punches** on each fry pass and harder on **Epic+ pulls**.
- **Camera shake** on burn, **FOV punch** on collect, **idle-bob** on cards/memes,
  **count-up** Crunch, **hover/press scale** on buttons.
- **Epic+ memes** get a rarity-colored **aura**; fryer lights **flicker** warm; neon signs glow.
- Sizzle Meter + value live in a **world-space billboard** over each fryer; the flat HUD is
  trimmed to the **Crunch total + Shop button**.
- Particle emitters are mostly burst-on-demand (`:Emit`) or enabled only while frying, to keep
  counts **mobile-friendly**.

## What's intentionally out of scope (Phase 2)

Eras beyond Rage Comics, pets, trading, events, leaderboards, loot crates, Codex reward
payouts. Save data already reserves `grease`/`era` so those won't need a migration.
(The separate `roblox-fryer-game/` folder in this repo is the Phase-2 loot-crate system,
kept apart from this MVP.)
