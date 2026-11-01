-- The launcher's game list (launcher/PocketLauncher/GameCatalog.cs) mirrors
-- upstream's src/core/GameVersion.lua: the same ids, the cache folder each
-- game is extracted to, and every accepted cartridge SHA-1.  The launcher
-- reads a game as imported from that folder's marker, and identifies a
-- chosen ROM by its SHA-1, so a drift would show a game as missing or
-- refuse a good dump.  This test reads the C# source as text.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")

local file = assert(io.open("launcher/PocketLauncher/GameCatalog.cs", "rb"))
local source = file:read("*a")
file:close()

-- new("crystal", "Pokémon Crystal", "crystal", ["sha", "sha"]) entries
local catalog, order = {}, {}
for id, name, folder, hashes in source:gmatch('new%("(%w+)",%s*"([^"]+)",%s*"([%w_]+)",%s*%[(.-)%][^)]*%)') do
  local sha1s = {}
  for sha1 in hashes:gmatch('"(%x+)"') do sha1s[#sha1s + 1] = sha1:lower() end
  catalog[id] = { name = name, folder = folder, sha1s = sha1s }
  order[#order + 1] = id
end

local expected = { "red", "blue", "yellow", "gold", "silver", "crystal",
  "firered", "leafgreen", "ruby", "sapphire", "emerald" }
eq(table.concat(order, ","), table.concat(expected, ","), "the launcher lists every upstream game in order")

for _, id in ipairs(expected) do
  local entry = catalog[id]
  check(entry ~= nil, id .. " is in the launcher's catalog")
  if entry then
    eq(entry.folder .. "/", GameVersion.cachePrefix(id), id .. " cache folder matches GameVersion")
    local want = {}
    for _, revision in ipairs(GameVersion.revisions(id)) do want[#want + 1] = revision.sha1:lower() end
    table.sort(want)
    table.sort(entry.sha1s)
    eq(table.concat(entry.sha1s, ","), table.concat(want, ","), id .. " accepted ROM hashes match GameVersion")
    check(entry.name:find("Pok", 1, true) == 1, id .. " has a spoken name")
  end
end

T.finish("launcher catalog")
