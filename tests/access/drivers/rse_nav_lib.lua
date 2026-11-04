-- Helpers for the Ruby, Sapphire and Emerald navigation drivers: the FireRed
-- library (gen3_nav_lib.lua) with what differs on these cartridges, read from
-- the running game's constants.  Harness setup only; silent and isolated.
local L = {}

function L.new(game)
  local self = dofile("tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U = self.U
  local GameData = require("src.access.nav.gen3.GameData")
  self.GameData = GameData
  self.prefix = GameData.mapPrefix()

  function self.id(name) return self.prefix .. name end

  -- every map of this cartridge, sorted
  function self.mapIds()
    local ids = {}
    for id in pairs(game.data.maps or {}) do
      if type(id) == "string" and id:sub(1, #self.prefix) == self.prefix then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
  end

  -- A party that knows every field move, and every badge, through the game's
  -- own party and flag store.
  function self.giveParty(species, level)
    local s = self.session()
    local Party = require("src.core.game3.party")
    local FieldMoves = require("src.core.game3.field_moves")
    local Flags = require("src.core.game3.scripting.flags")
    local flag = GameData.flag("FLAG_SYS_POKEMON_GET")
    if flag then self.setFlag(flag, true) end
    s.party = {}
    Party.giveMon(s, species or 9, level or 90)
    Party.giveMon(s, species or 9, level or 90)
    local M = FieldMoves.MOVES
    local function moves(mon, list)
      local pp = {}
      for i = 1, #list do pp[i] = 30 end
      mon.moves, mon.pp, mon.maxPp = list, pp, { unpack(pp) }
    end
    -- Hydro Pump first: upstream's auto-fight uses move 1
    moves(s.party[1], { 56, M.SURF, M.STRENGTH, M.CUT })
    moves(s.party[2], { 56, M.ROCK_SMASH, M.WATERFALL, M.DIVE })
    Party.giveMon(s, species or 9, level or 90)
    moves(s.party[3], { 56, M.FLASH, M.SECRET_POWER, M.FLY })
    for _, badge in ipairs(Flags.forVersion(GameData.id()).BADGES or {}) do
      if badge.flag then self.setFlag(badge.flag, true) end
    end
    return s.party[1]
  end

  -- A long Repel: the walks, not wild battles, are under test.
  function self.repel()
    local var = GameData.var("VAR_REPEL_STEP_COUNT")
    if var then self.setVar(var, 60000) end
  end

  -- The game's own options block for this cartridge.
  function self.fastWalk(speed)
    local block = GameData.profile().optionsBlock or GameData.id()
    game.options[block] = game.options[block] or {}
    game.options[block].accessAutoWalkSpeed = speed or 8
  end

  -- The live floor as rows of characters, for reading a failed walk from the log.
  function self.showFloor(tag)
    local world = self.nav():worldState()
    local map = world.map
    local Terrain = require("src.access.nav.gen3.TerrainSemantics")
    local objects = {}
    for _, actor in ipairs(world.npcs or {}) do objects[actor.cellY * 1024 + actor.cellX] = actor.invisible and "i" or "O" end
    local switches = {}
    for _, cell in ipairs(self.nav():floorSwitchCells(world)) do switches[cell.y * 1024 + cell.x] = true end
    for y = 0, map.heightCells - 1 do
      local row = {}
      for x = 0, map.widthCells - 1 do
        local key = y * 1024 + x
        local beh = map:behavior(x, y)
        local dir, kind = Terrain.forced(beh)
        local ch = "#"
        if x == world.player.cellX and y == world.player.cellY then ch = "@"
        elseif objects[key] then ch = objects[key]
        elseif map:warpAt(x, y) then ch = "W"
        elseif switches[key] then ch = "S"
        elseif dir then ch = ({ up = "^", down = "v", left = "<", right = ">" })[dir]
        elseif kind == "ice" then ch = "/"
        elseif beh == Terrain.HOENN_MB.CRACKED_FLOOR then ch = "c"
        elseif beh == Terrain.HOENN_MB.CRACKED_FLOOR_HOLE then ch = "h"
        elseif beh == Terrain.MB.THIN_ICE then ch = "t"
        elseif beh == Terrain.MB.CRACKED_ICE then ch = "x"
        elseif map:isWater(x, y) then ch = "~"
        elseif map:isWalkableCell(x, y) then ch = "." end
        row[#row + 1] = ch
      end
      U.log("FLOOR", tag or "", string.format("%3d", y), table.concat(row))
    end
  end

  local firstBoot = self.boot
  function self.boot()
    if not firstBoot() then return false end
    U.log("BOOTED", GameData.id(), self.where())
    return true
  end

  return self
end

return L
