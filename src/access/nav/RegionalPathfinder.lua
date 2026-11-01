-- Reused from the old Pocket Accessibility project (src/accessibility/RegionalPathfinder.lua at
-- commit 71cdd419e) under decision 20; adapted for v0.3.98.

-- Read-only journey search across map transitions.
--
-- Cell-level collision remains the caller's responsibility. This module
-- searches a small graph of proven local routes joined by explicit warps or
-- connections and returns only the first transition the player should take.

local RegionalPathfinder = {}

local function stateKey(mapId, x, y)
  return table.concat({ tostring(mapId), tostring(x), tostring(y) }, ":")
end

local function before(a, b)
  if a.cost ~= b.cost then return a.cost < b.cost end
  return a.sequence < b.sequence
end

local function popBest(open)
  local best = 1
  for i = 2, #open do
    if before(open[i], open[best]) then best = i end
  end
  return table.remove(open, best)
end

local function callRoute(options, mapId, start, goals, initial, budget)
  local ok, result = pcall(
    options.route, mapId, start, goals, initial, budget)
  if not ok then return nil end
  return result
end

local function callTransitions(options, mapId)
  local ok, result = pcall(options.transitions, mapId)
  if not ok or type(result) ~= "table" then return {} end
  return result
end

function RegionalPathfinder.find(options)
  if type(options) ~= "table" or type(options.start) ~= "table"
     or type(options.target) ~= "table"
     or type(options.route) ~= "function"
     or type(options.transitions) ~= "function" then
    return nil, "invalid regional route request"
  end
  local start, target = options.start, options.target
  if type(start.mapId) ~= "string" or type(target.mapId) ~= "string"
     or type(start.x) ~= "number" or type(start.y) ~= "number"
     or type(target.goals) ~= "table" or #target.goals == 0 then
    return nil, "invalid regional route endpoints"
  end

  local maxStates = math.max(1, tonumber(options.maxStates) or 96)
  local maxTransitions = math.max(1, tonumber(options.maxTransitions) or 16)
  local clock = type(options.clock) == "function" and options.clock or os.clock
  local maxSeconds = math.max(0.01, tonumber(options.maxSeconds) or 0.5)
  local maxRouteSeconds = math.max(
    0.005, tonumber(options.maxRouteSeconds) or 0.05)
  local startedAt = clock()
  local function routeBudget()
    local remaining = maxSeconds - (clock() - startedAt)
    if remaining <= 0 then return nil end
    return math.min(maxRouteSeconds, remaining)
  end
  local sequence = 1
  local firstKey = stateKey(start.mapId, start.x, start.y)
  local open = { {
    mapId = start.mapId, x = start.x, y = start.y,
    cost = 0, hops = 0, sequence = sequence,
  } }
  local best = { [firstKey] = 0 }
  local expanded = 0

  while #open > 0 and expanded < maxStates do
    if not routeBudget() then return nil, "regional search timed out" end
    local state = popBest(open)
    local key = stateKey(state.mapId, state.x, state.y)
    if state.cost == best[key] then
      expanded = expanded + 1
      if state.mapId == target.mapId then
        local budget = routeBudget()
        if not budget then return nil, "regional search timed out" end
        local result = callRoute(options, state.mapId,
          { x = state.x, y = state.y }, target.goals,
          state.hops == 0, budget)
        if result then
          return {
            cost = state.cost + (result.cost or 0),
            firstTransition = state.firstTransition,
            final = state.hops == 0,
            expanded = expanded,
          }
        end
      end

      if state.hops < maxTransitions then
        for _, transition in ipairs(callTransitions(options, state.mapId)) do
          local budget = routeBudget()
          if not budget then return nil, "regional search timed out" end
          local result = callRoute(options, state.mapId,
            { x = state.x, y = state.y },
            { { x = transition.x, y = transition.y } },
            state.hops == 0, budget)
          if result then
            local cost = state.cost + (result.cost or 0) + 1
            local nextKey = stateKey(
              transition.destMap, transition.destX, transition.destY)
            if best[nextKey] == nil or cost < best[nextKey] then
              best[nextKey] = cost
              sequence = sequence + 1
              open[#open + 1] = {
                mapId = transition.destMap,
                x = transition.destX, y = transition.destY,
                cost = cost, hops = state.hops + 1, sequence = sequence,
                firstTransition = state.firstTransition or transition,
              }
            end
          end
        end
      end
    end
  end
  return nil, "no regional path"
end

return RegionalPathfinder
