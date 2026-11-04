-- Scripted run for navigation: in the player's bedroom and then Pallet Town,
-- turn on the F7 command layer and use its keys (object list, filters,
-- spoken directions).  Keys go
-- through love.keypressed, so they pass the accessibility router exactly as
-- a real key press would.  Read the "[access] say" lines.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end

  local function key(k, shift, frames)
    if shift then love.keyboard.isDown = function(name) return name == "lshift" end end
    U.log("key", (shift and "shift+" or "") .. k)
    love.keypressed(k, k, false)
    love.keyreleased(k, k)
    if shift then love.keyboard.isDown = function() return false end end
    U.wait(frames or 15)
  end
  local realIsDown = love.keyboard.isDown
  love.keyboard.isDown = function() return false end

  key("f8", false, 30)          -- help
  key("f7")                     -- command layer on
  key("l")                      -- next
  key("l")
  key("j")                      -- previous
  key("l", true)                -- next filter
  key("k", false, 400)          -- spoken directions to the selected object
  key("k")                      -- and stop

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(30)
  key("l")
  key("l")
  key("f7")                     -- command layer off
  love.keyboard.isDown = realIsDown
  U.log("DONE")
end
