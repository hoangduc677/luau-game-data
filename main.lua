-- main.lua — Load toàn bộ hệ thống
local BASE_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/"

-- Hàm load module an toàn
local function loadModule(name)
    local ok, raw = pcall(function() return game:HttpGet(BASE_URL .. name) end)
    if not ok or type(raw) ~= "string" or #raw == 0 then
        warn("[MAIN] Không tải được " .. name)
        return nil
    end
    local fn, err = loadstring(raw)
    if not fn then
        warn("[MAIN] loadstring fail " .. name .. ": " .. tostring(err))
        return nil
    end
    local ok2, result = pcall(fn)
    if not ok2 then
        warn("[MAIN] Chạy " .. name .. " fail: " .. tostring(result))
        return nil
    end
    return result
end

-- Load FSM
local FSM = loadModule("fsm.lua")
if not FSM then
    warn("[MAIN] ❌ Không load được fsm.lua — dừng")
    return
end

-- Load UI
local UI = loadModule("ui.lua")
if not UI then
    warn("[MAIN] ❌ Không load được ui.lua — dừng")
    return
end

-- Khởi tạo
UI.Init(FSM)
print("[MAIN] ✅ Kaitun đã khởi động")