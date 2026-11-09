-- Touch gesture recogniser for blind players on Android (decision 66).
--
-- Pure: it is fed touch events with explicit timestamps (seconds) and the
-- screen size, and returns the gestures it recognised.  It never reads the
-- clock or touches the game, so tests can drive it with exact timings.
-- TouchInput.lua turns the gestures into game buttons and navigation.
--
-- A "stroke" runs from the first finger down to the last finger up.  At the
-- end of a stroke it is classified, in this order:
--   rotation  exactly two fingers, and the line between them turned at
--             least ROTATE_MIN_DEGREES (clockwise or counterclockwise as
--             seen on the screen)
--   tap       every finger stayed within TAP_MAX_MOVE and the stroke was
--             short; one, two or three fingers.  A second tap with the same
--             number of fingers starting within DOUBLE_TAP_SECONDS of the
--             first one ending makes a double tap.  A single tap is only
--             reported once that window has passed (update), because it
--             could still become a double tap.
--   swipe     the fingers' average position moved at least SWIPE_MIN_MOVE,
--             fast enough; its direction is the larger of the two axes
-- Anything else (a long press, a slow drag) is no gesture.  Holding a
-- direction is not decided by the owner and is deliberately not recognised.
--
-- Every gesture says which half of the screen it started in, from the
-- fingers' starting average.  "top" is the navigation half and "bottom" the
-- movement half (decision 66).  Upright (portrait) the screen is cut across:
-- top and bottom as named.  On its side (landscape, wider than tall) it is
-- cut down the middle (the owner, 2026-11-09): the left half moves, like a
-- controller's D-pad, and the right half navigates.
--
-- Gestures:
--   { kind = "swipe",  direction = "up"|"down"|"left"|"right", fingers, half, x, y }
--   { kind = "tap",    fingers, taps = 1|2, half, x, y }
--   { kind = "rotate", direction = "clockwise"|"counterclockwise", degrees, half, x, y }

local Gestures = {}

-- Thresholds, all in one place.  Distances are fractions of the screen's
-- shorter side, so they mean the same on a phone and a tablet, in either
-- orientation.  None of these has been tuned on a real touchscreen yet.
Gestures.THRESHOLDS = {
  -- a swipe moves the fingers at least this far (6% of the shorter side:
  -- about 1.5 cm on a 10 inch tablet held either way)
  SWIPE_MIN_MOVE = 0.06,
  -- a slower movement is a drag, not a swipe
  SWIPE_MAX_SECONDS = 1.0,
  -- a tap moves no finger further than this (finger wobble)
  TAP_MAX_MOVE = 0.04,
  -- a tap is shorter than this; a longer touch is a press and hold
  TAP_MAX_SECONDS = 0.35,
  -- a second tap must start this soon after the first one ended
  DOUBLE_TAP_SECONDS = 0.30,
  -- three fingers land and lift less evenly, so their taps get more time to
  -- finish and a longer wait for the second tap (the owner on the Pixel
  -- Tablet, 2026-11-09: the three-finger double tap for START was "a little
  -- too short").  A three-finger single tap (SELECT) waits this long too.
  THREE_FINGER_TAP_MAX_SECONDS = 0.50,
  THREE_FINGER_DOUBLE_TAP_SECONDS = 0.55,
  -- a two-finger turn of at least this many degrees is a rotation
  ROTATE_MIN_DEGREES = 45,
  -- a stroke still open this long has lost its releases (the app lost
  -- focus, a system pop-up took the touch): the next press starts afresh
  STALE_SECONDS = 5,
}

local Recogniser = {}
Recogniser.__index = Recogniser

-- The tap length and second-tap wait for a number of fingers.
local function tapMax(th, fingers)
  return (fingers or 1) >= 3 and th.THREE_FINGER_TAP_MAX_SECONDS or th.TAP_MAX_SECONDS
end
local function doubleWindow(th, fingers)
  return (fingers or 1) >= 3 and th.THREE_FINGER_DOUBLE_TAP_SECONDS or th.DOUBLE_TAP_SECONDS
end

-- opts.size: function returning the screen's width and height, in the same
-- units as the touch coordinates.  opts.thresholds: overrides for tests.
function Gestures.new(opts)
  opts = opts or {}
  local thresholds = {}
  for key, value in pairs(Gestures.THRESHOLDS) do thresholds[key] = value end
  for key, value in pairs(opts.thresholds or {}) do thresholds[key] = value end
  return setmetatable({
    size = opts.size or function() return 1, 1 end,
    thresholds = thresholds,
    stroke = nil,   -- the stroke in progress
    pending = nil,  -- a finished tap that may still become a double tap
  }, Recogniser)
end

-- Which half of a w x h screen a point is in: "top" (navigation) or
-- "bottom" (movement).  Landscape is cut left and right, left moving.
function Gestures.half(x, y, w, h)
  if type(w) == "number" and type(h) == "number" and w > h then
    return x >= w / 2 and "top" or "bottom"
  end
  return (type(h) == "number" and h > 0 and y < h / 2) and "top" or "bottom"
end

local function shorterSide(self)
  local w, h = self.size()
  w, h = tonumber(w) or 1, tonumber(h) or 1
  local short = math.min(w, h)
  if short <= 0 then short = 1 end
  return short, h, w
end

-- The angle of the line from the stroke's first finger to its second.
local function pairAngle(stroke)
  local a = stroke.fingers[stroke.order[1]]
  local b = stroke.fingers[stroke.order[2]]
  if not (a and b) then return nil end
  return math.atan2(b.y - a.y, b.x - a.x)
end

-- Wraps an angle difference into -pi..pi, so turning past the axis does not
-- count as a whole turn the other way.
local function wrap(delta)
  while delta > math.pi do delta = delta - 2 * math.pi end
  while delta < -math.pi do delta = delta + 2 * math.pi end
  return delta
end

local function trackRotation(stroke)
  if stroke.maxFingers ~= 2 or stroke.down ~= 2 then return end
  local angle = pairAngle(stroke)
  if not angle then return end
  if stroke.lastAngle then
    stroke.rotation = stroke.rotation + wrap(angle - stroke.lastAngle)
  end
  stroke.lastAngle = angle
end

-- A finished tap waiting for its window to pass is reported as a single tap.
local function flushPending(self, out)
  if not self.pending then return end
  local p = self.pending
  self.pending = nil
  out[#out + 1] = { kind = "tap", fingers = p.fingers, taps = 1, half = p.half, x = p.x, y = p.y }
end

function Recogniser:pressed(id, x, y, t)
  local out = {}
  local stroke = self.stroke
  if stroke and t - stroke.startTime > self.thresholds.STALE_SECONDS then
    stroke, self.stroke = nil, nil
  end
  if not stroke then
    stroke = { fingers = {}, order = {}, down = 0, maxFingers = 0,
               startTime = t, rotation = 0 }
    self.stroke = stroke
    -- a stroke starting after the double-tap window cannot pair with the
    -- waiting tap
    if self.pending and t - self.pending.endTime > doubleWindow(self.thresholds, self.pending.fingers) then
      flushPending(self, out)
    end
  end
  if stroke.fingers[id] then return out end -- a repeated press for a finger already down
  stroke.fingers[id] = { sx = x, sy = y, x = x, y = y, down = true }
  stroke.order[#stroke.order + 1] = id
  stroke.down = stroke.down + 1
  if stroke.down > stroke.maxFingers then stroke.maxFingers = stroke.down end
  if stroke.down == 2 and stroke.maxFingers == 2 then
    stroke.lastAngle = pairAngle(stroke)
  end
  return out
end

function Recogniser:moved(id, x, y, _t)
  local stroke = self.stroke
  local finger = stroke and stroke.fingers[id]
  if not (finger and finger.down) then return {} end
  finger.x, finger.y = x, y
  trackRotation(stroke)
  return {}
end

-- Classifies a finished stroke.
local function classify(self, stroke, t, out)
  local th = self.thresholds
  local short, h, w = shorterSide(self)
  local n = stroke.maxFingers
  local duration = t - stroke.startTime
  local sx, sy, dx, dy, maxMove = 0, 0, 0, 0, 0
  for _, id in ipairs(stroke.order) do
    local f = stroke.fingers[id]
    sx, sy = sx + f.sx, sy + f.sy
    local fx, fy = f.x - f.sx, f.y - f.sy
    dx, dy = dx + fx, dy + fy
    local move = math.sqrt(fx * fx + fy * fy)
    if move > maxMove then maxMove = move end
  end
  local count = #stroke.order
  sx, sy, dx, dy = sx / count, sy / count, dx / count, dy / count
  local half = Gestures.half(sx, sy, w, h)

  -- screen y grows downwards, so a growing angle turns clockwise as seen
  local degrees = math.deg(stroke.rotation)
  if n == 2 and math.abs(degrees) >= th.ROTATE_MIN_DEGREES then
    flushPending(self, out)
    out[#out + 1] = { kind = "rotate", direction = degrees > 0 and "clockwise" or "counterclockwise",
                      degrees = degrees, half = half, x = sx, y = sy }
    return
  end

  if maxMove <= th.TAP_MAX_MOVE * short and duration <= tapMax(th, n) then
    local p = self.pending
    if p and p.fingers == n and stroke.startTime - p.endTime <= doubleWindow(th, n) then
      self.pending = nil
      out[#out + 1] = { kind = "tap", fingers = n, taps = 2, half = p.half, x = p.x, y = p.y }
      return
    end
    flushPending(self, out)
    self.pending = { fingers = n, endTime = t, half = half, x = sx, y = sy }
    return
  end

  flushPending(self, out)
  local distance = math.sqrt(dx * dx + dy * dy)
  if distance >= th.SWIPE_MIN_MOVE * short and duration <= th.SWIPE_MAX_SECONDS then
    local direction
    if math.abs(dx) > math.abs(dy) then
      direction = dx > 0 and "right" or "left"
    else
      direction = dy > 0 and "down" or "up"
    end
    out[#out + 1] = { kind = "swipe", direction = direction, fingers = n, half = half, x = sx, y = sy }
  end
end

function Recogniser:released(id, x, y, t)
  local out = {}
  local stroke = self.stroke
  local finger = stroke and stroke.fingers[id]
  if not (finger and finger.down) then return out end
  if x and y then
    finger.x, finger.y = x, y
    trackRotation(stroke)
  end
  finger.down = false
  stroke.down = stroke.down - 1
  if stroke.down > 0 then return out end
  self.stroke = nil
  classify(self, stroke, t, out)
  return out
end

-- Reports a waiting single tap once its double-tap window has passed.  Call
-- every frame.
function Recogniser:update(t)
  local out = {}
  local p = self.pending
  if not p or t - p.endTime <= doubleWindow(self.thresholds, p.fingers) then return out end
  -- a stroke under way that began inside the window may still be the second tap
  if self.stroke and self.stroke.startTime - p.endTime <= doubleWindow(self.thresholds, p.fingers) then
    return out
  end
  flushPending(self, out)
  return out
end

-- Forgets everything (focus lost: the system may never send the releases).
function Recogniser:reset()
  self.stroke, self.pending = nil, nil
end

-- True while fingers are down.
function Recogniser:active()
  return self.stroke ~= nil
end

return Gestures
