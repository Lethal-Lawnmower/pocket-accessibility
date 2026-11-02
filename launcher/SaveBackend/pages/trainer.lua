-- The Trainer page: name, IDs, wallet and what only some games have.  Same rows
-- and limits as upstream's panels/Trainer.lua.  The smallest page, and the
-- pattern the others follow (docs/access/save-editor.md).
local Ops = require("Ops")
local Gen = require("Gen")

local Page = {}

local function fieldsFor(S)
  local save, version = S.save, S.version
  local fields = {
    { id = "name", label = "Trainer name", kind = "text",
      value = (save.player and save.player.name) or save.name or save.playerName or "" },
    { id = "id", label = "Trainer ID", kind = "number", lo = 0, hi = 65535,
      value = (save.player and save.player.id) or save.trainerId or 0,
      help = "Part of your trainer identity. Changing it can affect who owns a Pokémon." },
  }
  local function number(id, label, value, hi, help)
    fields[#fields + 1] = { id = id, label = label, kind = "number", lo = 0, hi = hi, value = value, help = help }
  end
  if Gen.ofState(S) == 3 then
    number("secretId", "Secret ID", save.secretId or 0, 65535,
      "Part of your trainer identity. Changing it can affect who owns a Pokémon.")
  end
  number("money", "Money", Gen.money(save), 999999, "Your wallet.")
  number("coins", "Coins", Gen.coins(save), 9999, "Game Corner coins.")
  if Gen.hasBuenaPoints(save, version) then
    number("buenaPoints", "Buena points", Gen.buenaPoints(save, version), 30, "Blue Card points for Buena's prizes.")
  end
  if Gen.hasBerryPowder(save, version) then
    number("berryPowder", "Berry Powder", Gen.berryPowder(save, version), Gen.BERRY_POWDER_MAX,
      "Powder from Berry Crush, spent at the Berry Powder shop.")
  end
  if Gen.hasVolcanicAsh(save, version) then
    number("volcanicAsh", "Volcanic Ash", Gen.volcanicAsh(save, version), Gen.VOLCANIC_ASH_MAX,
      "Ash collected in the Soot Sack, spent at the Glass Workshop.")
  end
  if Gen.hasBattlePoints(save, version) then
    number("battlePoints", "Battle Points", Gen.battlePoints(save, version), Gen.BATTLE_POINTS_MAX,
      "Battle Frontier points, spent at the Exchange Service Corner.")
  end
  if Gen.hasMirageIsland(save, version) then
    number("mirageIsland", "Mirage Island value", Gen.mirageIslandValue(save, version), 65535,
      "Mirage Island shows when this matches the low half of a party Pokémon's PID.")
    fields[#fields + 1] = { id = "mirageState", label = "Mirage Island", kind = "info",
      value = Gen.mirageIslandVisible(save, version) and "Visible" or "Hidden" }
  end
  if Gen.hasPlayerGender(save, version) then
    fields[#fields + 1] = { id = "gender", label = "Gender", kind = "choice", value = Gen.playerGender(save),
      options = { { value = "male", label = "Male" }, { value = "female", label = "Female" } } }
  end
  return fields
end

function Page.model(S)
  local save, version = S.save, S.version
  local actions = {}
  if Gen.hasMirageIsland(save, version) then
    actions[1] = { id = "mirage", label = "Make Mirage Island appear",
      enabled = not Gen.mirageIslandVisible(save, version) and Gen.mirageIslandMon(save) ~= nil }
  end
  return { fields = fieldsFor(S), actions = actions }
end

function Page.set(S, _, request)
  if request.field == "gender" then
    Ops.setPlayerGender(S, request.value)
  else
    Ops.setTrainerProperty(S, request.field, request.value)
  end
end

function Page.action(S, _, request)
  if request.action == "mirage" then Ops.setMirageIslandFromParty(S) end
end

return Page
