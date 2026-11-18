-- ============================================================
-- main.lua  |  Kaitun Loader
-- Fetch config + quests từ GitHub → khởi động UI + FSM.
-- Đây là file duy nhất cần paste vào executor.
-- ============================================================

local BASE_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/"

-- ── Fetch JSON helper ────────────────────────────────────────
local HttpService = game:GetService("HttpService")

local function fetchJSON(path)
    local ok, body = pcall(function()
        return game:HttpGet(BASE_URL .. path)
    end)
    if not ok then
        warn("[Kaitun] fetch failed: " .. path .. " – " .. tostring(body))
        return nil
    end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok2 then
        warn("[Kaitun] JSON decode failed: " .. path)
        return nil
    end
    return data
end

-- ── Fetch Lua module helper ───────────────────────────────────
local function fetchModule(path)
    local ok, body = pcall(function()
        return game:HttpGet(BASE_URL .. path)
    end)
    if not ok then
        warn("[Kaitun] module fetch failed: " .. path)
        return nil
    end
    local fn, err = loadstring(body)
    if not fn then
        warn("[Kaitun] loadstring failed: " .. tostring(err))
        return nil
    end
    return fn()
end

-- ── Load data ────────────────────────────────────────────────
print("[Kaitun] Loading config…")
local config = fetchJSON("config.json")
if not config then
    return warn("[Kaitun] Cannot load config. Abort.")
end

print("[Kaitun] Loading quests…")
local quests = fetchJSON("quests.json")
if not quests then
    return warn("[Kaitun] Cannot load quests. Abort.")
end

-- ── Load modules ─────────────────────────────────────────────
print("[Kaitun] Loading ui.lua…")
local UI = fetchModule("ui.lua")
if not UI then
    return warn("[Kaitun] Cannot load UI. Abort.")
end

print("[Kaitun] Loading fsm.lua…")
local FSM = fetchModule("fsm.lua")
if not FSM then
    return warn("[Kaitun] Cannot load FSM. Abort.")
end

-- ── Wire up ──────────────────────────────────────────────────
local machine = FSM.new(config, quests, UI)

-- Lắng nghe nút START từ UI để kích hoạt FSM
-- (UI đã tự toggle isRunning; ta poll bằng vòng đơn giản)
task.spawn(function()
    local wasRunning = false
    while true do
        local running = UI.IsRunning()
        if running and not wasRunning then
            machine:Start()
        elseif not running and wasRunning then
            machine:Stop()
        end
        wasRunning = running
        task.wait(0.2)
    end
end)

print("[Kaitun] Ready ✔  Press START on the dashboard.")
