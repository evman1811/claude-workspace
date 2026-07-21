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

### 4. Play the fry loop

Press **Play** (F5). You should see:

- A **🍟 Crunch** counter, a **Rebirth** button (locked until 100k Crunch), and the fryer name
  in the top bar.
- One **lane** card. Within a moment a meme spawns (watch the Codex fill in on first sight).
- Click **Fry** to run a pass — the blue timer bar fills, then value jumps by the fryer mult.
- Keep frying past the safe line and the **🔥 Burn risk** meter climbs. Fry too far and it
  burns (you get a small Crunch crumb and a new meme spawns).
- Click **Bank** to cash the meme in. Crunch goes up.
- Buy **Faster Conveyor / Extra Lane / Premium Oil** in the Upgrades panel.
- Reach a fryer's unlock threshold (2,500 / 40,000 Crunch) and it auto-equips.
- Hit 100k Crunch → **Rebirth** to reset the run for a permanent ×1.5 income multiplier.

### 5. Fast-testing tips

- To reach rebirth quickly, temporarily lower `Config.Rebirth.minCrunch`, or bump
  `Config.Rarities` Common `baseValue`. Everything balance-related is in `Config.lua`.
- To verify saving: bank some Crunch, **Stop**, **Play** again — your Crunch/upgrades persist
  (with API Services enabled). In a real server, leaving the game triggers the save.
- Two-player session-lock test: use **Test → Clients and Servers → 2 players** (Local Server).

## What's intentionally out of scope (Phase 2)

Eras beyond Rage Comics, pets, trading, events, leaderboards, loot crates, Codex reward
payouts. Save data already reserves `grease`/`era` so those won't need a migration.
(The separate `roblox-fryer-game/` folder in this repo is the Phase-2 loot-crate system,
kept apart from this MVP.)
