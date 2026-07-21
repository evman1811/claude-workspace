--!strict
-- Bootstrap.server.lua  (a Script in ServerScriptService)
-- Starts the crate system. Swap InMemoryDataAdapter for your real save adapter.

local CrateService = require(script.Parent.CrateService)
local DataAdapter = require(script.Parent.InMemoryDataAdapter)

CrateService.start({ data = DataAdapter })

print("[Bootstrap] CrateService started.")
