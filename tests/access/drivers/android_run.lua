-- Runs another driver on Android, used through isolated.lua.  The tests are not in
-- the app, so they are pushed to a folder on the device.  Drivers open files relative
-- to the working directory, so this moves there, and it keeps a copy of everything
-- printed in that folder's driver.log, where the script reads it.
--   POKEPORT_DRIVER=<root>/tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=<root>/tests/access/drivers/android_run.lua
--   ANDROID_TEST_ROOT=<root>   ANDROID_DRIVER=tests/access/drivers/<driver>.lua
return function(game)
  local ffi = require("ffi")
  ffi.cdef("int chdir(const char *path);")
  local root = os.getenv("ANDROID_TEST_ROOT")
  if ffi.C.chdir(root) ~= 0 then error("could not enter " .. tostring(root)) end
  local log = assert(io.open(root .. "/driver.log", "a"))
  local plainPrint = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    log:write(table.concat(parts, "\t"), "\n")
    log:flush()
    plainPrint(...)
  end
  -- run straight from POKEPORT_DRIVER, without isolated.lua, for drivers that press
  -- through the real love callbacks: driver runs skip where the layer normally sees the game
  local CurrentGame = package.loaded["src.access.CurrentGame"]
  if CurrentGame then CurrentGame.set(game) end
  local ok, failure = xpcall(function()
    return dofile(os.getenv("ANDROID_DRIVER"))(game)
  end, debug.traceback)
  if not ok then print("[driver] FAIL " .. tostring(failure)) end
  print("[driver] android_run finished")
  log:close()
  print = plainPrint
end
