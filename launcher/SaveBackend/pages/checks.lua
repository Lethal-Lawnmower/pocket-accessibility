-- The Checks page: read-only results for every Pokémon, same report as upstream's
-- panels/Checks.lua (Legality.save).  Upstream's rule stands: a clean result stays
-- unchecked and is never called legal, because origin is not proved.
local Legality = require("Legality")
local Ops = require("Ops")

local Page = {}

-- upstream's words, from tools/save-editor/README.md
local NOT_CERTIFIED = "A record without property errors remains unchecked, never certified legal."

-- The same cache upstream's panel keeps: one report per edit.
local function reportFor(S)
  if S._checksRevision ~= S.revision or S._checksSave ~= S.save or not S.checkReport then
    S.checkReport = Legality.save(S)
    S._checksRevision, S._checksSave = S.revision, S.save
  end
  return S.checkReport
end

local function counted(count, word)
  return ("%d %s%s"):format(count, word, count == 1 and "" or "s")
end

local function issueText(report)
  local parts = {}
  for _, check in ipairs(report.checks or {}) do
    local kind = check.kind == "error" and "Error" or check.kind == "warning" and "Warning" or "Note"
    parts[#parts + 1] = kind .. ": " .. tostring(check.message)
  end
  if #parts == 0 then return "No property errors. Values pass. Origin still needs checking." end
  return table.concat(parts, "; ")
end

function Page.model(S, state)
  local report = reportFor(S)
  local rows, selected = {}, nil
  for i, entry in ipairs(report.entries) do
    local result = counted(entry.report.errors, "error")
    if entry.report.warnings > 0 then result = result .. ", " .. counted(entry.report.warnings, "warning") end
    rows[i] = { id = entry.label, text = ("%s, %s, %s"):format(entry.label, Ops.monName(S, entry.mon), result) }
    if entry.label == state.selected then selected = entry end
  end
  selected = selected or report.entries[1]
  return {
    summary = ("%d Pokémon, %s. Origin checks still need review.\n%s"):format(
      #report.entries, counted(report.errors, "error"), NOT_CERTIFIED),
    list = { label = "Pokémon", rows = rows, selected = selected and selected.label or nil, filter = true },
    fields = { {
      id = "issues", label = "Issues", kind = "info",
      value = selected and issueText(selected.report) or "No Pokémon in the party or boxes.",
    } },
    actions = { {
      id = "fix", label = "Fix all errors",
      confirm = "Fix invalid values, stats and PP across your party and boxes? Anything needing a manual choice stays for review.",
    } },
  }
end

function Page.action(S, _, request)
  if request.action == "fix" then Ops.fixAllErrors(S) end
end

return Page
