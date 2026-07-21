# Fryer Game — Crate System (Paid Random Items, policy-compliant)

Server-authoritative loot crates for the fryer idle game. Hidden rates where the policy
allows it; automatic, accurate odds disclosure where it requires it.

## The one rule that shapes everything

Roblox's **Paid Random Items policy**: if a random reward can be obtained with Robux —
directly *or indirectly* (including via an in-game currency that can itself be bought with
Robux) — you **must disclose accurate odds before purchase**.

So rates may be hidden **only** for crates bought with currency that is *earned through
gameplay and never purchasable with Robux*.

This system encodes that as a hard invariant:

| Crate flag           | Currency example        | Odds shown? | Enforced by |
|----------------------|-------------------------|-------------|-------------|
| `robuxLinked = false`| Frys (earned only)      | Hidden ✅   | allowed by policy |
| `robuxLinked = true` | Robux dev product       | Disclosed ✅| server refuses to open without a valid odds table |

Disclosed odds are **derived from the same server weights used to roll**, so published
odds can never drift from actual drop rates.

> ⚠️ If you ever let players buy Frys with Robux, Frys crates become *indirectly* Robux
> purchasable — flip their `robuxLinked` to `true`. `OddsSelfCheck` will then force you to
> provide a disclosure or fail at boot.

## Layout (Rojo)

```
src/shared   -> ReplicatedStorage/Shared   (client-safe: types, catalog — NO weights)
src/server   -> ServerScriptService         (secret weights, roll logic, service)
src/client   -> StarterPlayerScripts        (UI/reveal — never decides rewards)
```

| File | Role |
|------|------|
| `shared/CrateTypes.lua` | Shared type defs. |
| `shared/CrateCatalog.lua` | Client-safe crate metadata. **Contains no weights.** |
| `server/CrateWeights.lua` | **SECRET** drop weights. Single source of truth. |
| `server/WeightedRandom.lua` | Weighted roll + pity (floor guarantee). Pure, testable. |
| `server/CrateService.lua` | Authority: validation, compliance gate, charge, roll, grant, odds disclosure. |
| `server/InMemoryDataAdapter.lua` | Test-only save stub. Replace with ProfileService/DataStore. |
| `server/Bootstrap.server.lua` | Starts the service. |
| `server/OddsSelfCheck.server.lua` | Boots-time compliance guardrail. |
| `client/CrateController.lua` | Fetches + shows odds, prompts purchase, plays reveal. |

## Wiring in your save system

Implement the `DataAdapter` interface (see top of `CrateService.lua`). The only subtlety:
**`spendCurrency` must be atomic** (check-and-deduct in one guarded step) so two rapid
opens can't double-spend. `openInternal` charges first, rolls second.

## Two open flows

- **Soft currency (Frys):** client `FireServer` → server validates, charges, rolls,
  fires result back.
- **Robux:** client `PromptProductPurchase` → `MarketplaceService.ProcessReceipt` verifies
  the receipt server-side, runs the compliance gate, rolls, grants, and returns
  `PurchaseGranted`. Rewards are never granted on the client's word.

## Anti-exploit posture

- Client never sends a reward, price, or crate contents — only a crate id.
- Weights live in `ServerScriptService` (not replicated). Keep them out of
  `ReplicatedStorage` — treat a leak there as a P0.
- Per-player open cooldown guards against spam / duplicate fires.
- Robux crates are rejected on the soft-currency path (`USE_ROBUX_PURCHASE`).

## Tuning odds

Edit only `server/CrateWeights.lua`. Weights are relative; probability = weight ÷ Σweights.
`OddsSelfCheck` prints each Robux crate's disclosed outcomes and verifies they sum to ~100%.
