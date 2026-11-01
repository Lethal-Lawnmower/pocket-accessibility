-- Scripted run for controller navigation (decision 23): hold the left
-- trigger and use the D-pad to change category and item, then auto-walk to
-- the stairs with a left stick click, and start guided navigation with a
-- right stick click downstairs.  Events go through love.gamepad* exactly as
-- a controller's would.  Read the "[access] say" lines.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end

  local function axis(value) love.gamepadaxis(nil, "triggerleft", value) U.wait(5) end
  local function button(b, frames)
    U.log("pad", b)
    love.gamepadpressed(nil, b)
    U.wait(2)
    love.gamepadreleased(nil, b)
    U.wait(frames or 15)
  end

  axis(1.0)                      -- hold the left trigger
  button("dpdown")               -- next category
  button("dpup")                 -- back to all
  button("dpright")              -- first object
  button("dpright")
  button("dpleft")               -- PC
  button("dpleft")               -- back to the stairs
  axis(0.0)                      -- release
  local mapBefore = game.overworld.map
  button("leftstick", 10)        -- auto-walk to the selected object
  for _ = 1, 600 do
    if game.overworld.map ~= mapBefore then break end
    U.wait(1)
  end
  U.wait(60)
  U.log(game.overworld.map ~= mapBefore and "PASS" or "FAIL", "auto-walk took the stairs")

  axis(1.0)
  button("dpright")
  button("dpright")
  axis(0.0)
  button("rightstick", 60)       -- guided navigation to it
  button("rightstick", 20)       -- and stop it again
  U.log("DONE")
end
