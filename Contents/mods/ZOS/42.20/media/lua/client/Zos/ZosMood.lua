--[[
    Mood relief for Zork turns: earned on non-empty command submit, limited by
    a rolling real-time per-minute budget (anti-spam). Shell commands do not
    apply. SP/client-side stats.
]]

ZosMood = ZosMood or {}

local WINDOW_MS = 60 * 1000
local MAX_BOREDOM_PER_WINDOW = 10.0
local MAX_UNHAPPY_PER_WINDOW = 8.0
local PER_CMD_BOREDOM = 1.5
local PER_CMD_UNHAPPY = 1.2

-- Sliding window of { t = ms, boredom = n, unhappy = n }
local history = {}

local function prune(now)
    local keep = {}
    for i = 1, #history do
        local e = history[i]
        if now - e.t < WINDOW_MS then
            keep[#keep + 1] = e
        end
    end
    history = keep
end

local function usedInWindow()
    local boredom = 0
    local unhappy = 0
    for i = 1, #history do
        boredom = boredom + history[i].boredom
        unhappy = unhappy + history[i].unhappy
    end
    return boredom, unhappy
end

--- Apply mood for one Zork command line. No-op for empty/whitespace.
function ZosMood.onZorkCommand(player, rawLine)
    if player == nil or player.getStats == nil then
        return
    end
    local trimmed = string.trim(rawLine or "")
    if trimmed == "" then
        return
    end

    local now = getTimestampMs()
    prune(now)
    local usedB, usedU = usedInWindow()
    local boredom = math.min(PER_CMD_BOREDOM, math.max(0, MAX_BOREDOM_PER_WINDOW - usedB))
    local unhappy = math.min(PER_CMD_UNHAPPY, math.max(0, MAX_UNHAPPY_PER_WINDOW - usedU))
    if boredom <= 0 and unhappy <= 0 then
        return
    end

    local stats = player:getStats()
    if boredom > 0 then
        stats:remove(CharacterStat.BOREDOM, boredom)
    end
    if unhappy > 0 then
        stats:remove(CharacterStat.UNHAPPINESS, unhappy)
    end
    history[#history + 1] = { t = now, boredom = boredom, unhappy = unhappy }
end
