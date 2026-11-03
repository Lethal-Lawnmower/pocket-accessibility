-- Gen 1 navigation helpers with no game: the whole-floor boulder search on small fake
-- floors, and sign names from a sign's own words.  The real floors are run by
-- tests/access/drivers/gen1_puzzles.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")
local check, eq = T.check, T.eq

local BoulderPlan = require("src.access.nav.BoulderPlan")

-- "#" wall, "." floor, "B" boulder, "P" player, "T" target, "h" hole to avoid, "w" warp
local function floor(rows)
  local map = { widthCells = #rows[1], heightCells = #rows, def = { tileset = "CAVERN", warps = {} }, tiles = {} }
  local world = { map = map, entities = {}, targets = {}, avoid = {} }
  for y, row in ipairs(rows) do
    for x = 1, #row do
      local c = row:sub(x, x)
      map.tiles[(y - 1) .. ":" .. (x - 1)] = c
      if c == "B" then
        world.entities[#world.entities + 1] = { cellX = x - 1, cellY = y - 1, def = { sprite = "SPRITE_BOULDER" } }
      elseif c == "P" then
        world.player = { cellX = x - 1, cellY = y - 1 }
      elseif c == "T" then
        world.targets[#world.targets + 1] = { x = x - 1, y = y - 1 }
      elseif c == "h" or c == "w" then
        world.avoid[(x - 1) .. "," .. (y - 1)] = true
      end
    end
  end
  world.entities[#world.entities + 1] = world.player
  function map:inBounds(x, y) return x >= 0 and y >= 0 and x < self.widthCells and y < self.heightCells end
  function map:cellTile(x, y) return self.tiles[y .. ":" .. x] end
  function map:isWalkableCell(x, y) return self:inBounds(x, y) and self.tiles[y .. ":" .. x] ~= "#" end
  function map:isWarpTileCell() return false end
  function map:cellCollision() return 0 end
  function map:isWaterCell() return false end
  function map:warpAtCell() return nil end
  return world
end

local function fill(world, budget)
  return BoulderPlan.fill(world, world.targets, world.avoid, world.avoid, nil, budget)
end

-- one boulder, straight in
do
  local world = floor({
    "#######",
    "#P.B.T#",
    "#######",
  })
  local steps = fill(world)
  check(steps ~= nil, "straight push found")
  eq(#steps, 2, "two pushes")
  eq(steps[1].direction, "right", "pushes right")
  eq(steps[1].standX, 2, "stands behind the boulder")
end

-- the player has to walk round to the far side first
do
  local world = floor({
    "########",
    "#......#",
    "#.B.P..#",
    "#.T....#",
    "########",
  })
  local steps = fill(world)
  check(steps ~= nil, "plan with a walk round")
  eq(steps[1].direction, "down", "the only push down")
  eq(steps[1].standY, 1, "from above")
end

-- a boulder in a corner can never come out, so nothing is promised
do
  local world = floor({
    "#####",
    "#B.P#",
    "#...#",
    "#.T.#",
    "#####",
  })
  eq(fill(world), nil, "no plan for a dead boulder")
end

-- a boulder out of the way first: another one blocks the only corridor
do
  local world = floor({
    "#########",
    "#P.B..T.#",
    "###.#####",
    "###.#####",
    "#########",
  })
  local steps = fill(world)
  eq(#(steps or {}), 3, "pushes along the corridor to the target")
end

-- never onto a hole or warp that is not the target
do
  local world = floor({
    "#######",
    "#P.BhT#",
    "#######",
  })
  eq(fill(world), nil, "a hole in the way stops the search")
end

-- opening: a boulder in a doorway, pushed through to reach the far side
do
  local world = floor({
    "#####",
    "#P..#",
    "##B##",
    "#...#",
    "#...#",
    "#####",
  })
  local steps, reason = BoulderPlan.opening(world, { { x = 1, y = 4 } }, {}, {}, nil)
  eq(reason, nil, "a push is needed")
  check(steps ~= nil and #steps == 2, "opening found")
  eq(steps[1].direction, "down", "pushes through the doorway")

  local open = floor({
    "#######",
    "#P.B..#",
    "#.....#",
    "#######",
  })
  local none, why = BoulderPlan.opening(open, { { x = 5, y = 1 } }, {}, {}, nil)
  eq(why, "open", "no push needed")
  eq(#none, 0, "empty plan")
end

-- the budget is honest
do
  local world = floor({
    "#########",
    "#P.B..T.#",
    "#########",
  })
  local steps = fill(world, { maxExpanded = 0 })
  eq(steps, nil, "over budget gives no plan")
end

-- sign names (the module needs the game's data only at run time)
package.loaded["src.access.Speech"] = package.loaded["src.access.Speech"] or { say = function() end }
local Gen1 = require("src.access.nav.gen1.Navigation")
eq(Gen1.signNameFrom("ROUTE 1\nPALLET TOWN -\nVIRIDIAN CITY"), "Sign: ROUTE 1 PALLET TOWN - VIRIDIAN CITY", "lines joined")
eq(Gen1.signNameFrom("TRAINER TIPS!\fCatch POK\195\169MON\nand expand your\fcollection!"),
  "Sign: TRAINER TIPS! Catch POK\195\169MON and expand your", "a short first page takes the next, cut at a word")
eq(Gen1.signNameFrom("{PLAYER}'s house", { player = "RED" }), "Sign: RED's house", "names filled in")
eq(Gen1.signNameFrom(""), nil, "no words, no name")
eq(Gen1.signNameFrom(nil), nil, "nothing to read")

T.finish("gen1 navigation")
