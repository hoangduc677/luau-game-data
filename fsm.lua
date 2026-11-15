--[[
    fsm.lua — Finite State Machine cho hệ thống Kaitun Blox Fruits (Sea 1)
    ---------------------------------------------------------------
    Kiến trúc : module split, không obfuscate, chạy trong executor
    States    : IDLE, GET_QUEST, FARM_MOB, RANDOM_FRUIT, SEA2_QUEST
    Nguồn     : BASE_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/"
    ---------------------------------------------------------------
    Kỹ thuật áp dụng từ reference:
      • GetTargets() quét mob trong bán kính 60 studs (thay vì duyệt toàn bộ workspace)
      • BodyVelocity hold tên riêng "_KaitunHold" — chống rớt khi đứng chờ NPC
      • HasActiveQuest() bọc pcall + check từng cấp GUI (tránh lỗi nil)
      • Chờ 0.5s sau StartQuest để server kịp cập nhật GUI
      • Cache quests trong 10s — tránh HttpGet lặp lại mỗi vòng
]]

-- =========================================================
-- SERVICES
-- =========================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local VirtualUser       = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

local BASE_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/"

-- =========================================================
-- CONFIG — load 1 lần, cache vĩnh viễn
-- =========================================================
local CONFIG = {
    FlySpeed        = 150,
    QuestCheckDelay = 0.5,   -- chờ server cập nhật GUI sau StartQuest
    QuestRetryMax   = 3,
    FarmRetryDelay  = 1.5,
    MobOffsetY      = 5,     -- đứng cao hơn mob 5 studs
    MobRadius       = 60,    -- bán kính quét mob (theo reference)
    QuestCacheTTL   = 10,    -- cache quests.json trong 10 giây
}

do
    local ok, raw = pcall(function()
        return game:HttpGet(BASE_URL .. "config.json")
    end)
    if ok and type(raw) == "string" and #raw > 0 then
        local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok2 and type(decoded) == "table" then
            for k, v in pairs(decoded) do CONFIG[k] = v end
        end
    end
end

-- =========================================================
-- STATE
-- =========================================================
local State             = "IDLE"
local isRunning         = true
local ActiveTween       = nil
local currentQuest      = nil
local questRetryCount   = 0

-- =========================================================
-- HELPERS
-- =========================================================

local _questsCache = nil
local _questsCacheTime = 0

local function LoadQuests(forceRefresh)
    if not forceRefresh and _questsCache and (tick() - _questsCacheTime < CONFIG.QuestCacheTTL) then
        return _questsCache
    end
    local ok, raw = pcall(function()
        return game:HttpGet(BASE_URL .. "quests.json")
    end)
    if not ok or type(raw) ~= "string" or #raw == 0 then
        return _questsCache or {}
    end
    local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
    if ok2 and type(decoded) == "table" then
        -- ✅ FIX: quests.json có wrapper "Sea1" → lấy mảng bên trong
        local list = decoded.Sea1 or decoded
        if type(list) == "table" and #list > 0 then
            _questsCache = list
            _questsCacheTime = tick()
        end
    end
    return _questsCache or {}
end

local function stopActiveTween()
    if ActiveTween then
        pcall(function() ActiveTween:Cancel() end)
        ActiveTween = nil
    end
end

-- BodyVelocity hold — dùng khi chờ NPC/portal (pattern từ reference)
local function createHold(hrp)
    local old = hrp:FindFirstChild("_KaitunHold")
    if old then old:Destroy() end
    local bv = Instance.new("BodyVelocity")
    bv.Name      = "_KaitunHold"
    bv.Velocity  = Vector3.zero
    bv.MaxForce  = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent    = hrp
    return bv
end

local function destroyHold(hrp)
    if hrp then
        local bv = hrp:FindFirstChild("_KaitunHold")
        if bv then bv:Destroy() end
    end
end

-- Bay tới CFrame với tốc độ cố định, dừng ngay khi isRunning = false
local function flyTo(targetCFrame, holdDuringFlight)
    stopActiveTween()
    if not isRunning then return end

    local char, hrp = getCharacter()
    if not hrp then return end

    -- Khoá vận tốc (không dùng BodyVelocity theo yêu cầu)
    hrp.AssemblyLinearVelocity = Vector3.zero

    local distance = (targetCFrame.Position - hrp.Position).Magnitude
    if distance < 1 then return end

    local hold = holdDuringFlight and createHold(hrp) or nil

    local tweenInfo = TweenInfo.new(
        distance / CONFIG.FlySpeed,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.Out
    )

    ActiveTween = TweenService:Create(hrp, tweenInfo, { CFrame = targetCFrame })
    ActiveTween:Play()
    ActiveTween.Completed:Wait()
    ActiveTween = nil

    if hold then hold:Destroy() end
end

-- HasActiveQuest — bọc pcall + check từng cấp (fix lỗi nil)
local function HasActiveQuest()
    local ok, result = pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then return false end
        local main = pg:FindFirstChild("Main")
        if not main then return false end
        local quest = main:FindFirstChild("Quest")
        if not quest then return false end
        return quest.Visible == true
    end)
    return ok and result == true
end

-- GetPlayerLevel — an toàn
local function GetPlayerLevel()
    local ok, lv = pcall(function()
        return LocalPlayer.Data.Level.Value
    end)
    return ok and tonumber(lv) or 1
end

-- GetPlayerBeli
local function GetPlayerBeli()
    local ok, beli = pcall(function()
        return LocalPlayer.Data.Beli.Value
    end)
    return ok and tonumber(beli) or 0
end

-- =========================================================
-- LOAD QUESTS.JSON (cache TTL)
-- =========================================================
local _questsCache = nil
local _questsCacheTime = 0

local function LoadQuests(forceRefresh)
    if not forceRefresh and _questsCache and (tick() - _questsCacheTime < CONFIG.QuestCacheTTL) then
        return _questsCache
    end
    local ok, raw = pcall(function()
        return game:HttpGet(BASE_URL .. "quests.json")
    end)
    if not ok or type(raw) ~= "string" or #raw == 0 then
        return _questsCache or {}
    end
    local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
    if ok2 and type(decoded) == "table" then
        _questsCache = decoded
        _questsCacheTime = tick()
    end
    return _questsCache or {}
end

-- Chọn quest phù hợp với level
local function PickQuest(playerLevel)
    local quests = LoadQuests()
    if type(quests) ~= "table" or #quests == 0 then return nil end

    -- Ưu tiên quest trong range [MinLv, QuestLv]
    for _, q in ipairs(quests) do
        if playerLevel >= (q.MinLv or 0) and playerLevel <= (q.QuestLv or 0) then
            return q
        end
    end
    -- Fallback: quest cao nhất có MinLv <= level
    local best = nil
    for _, q in ipairs(quests) do
        if playerLevel >= (q.MinLv or 0) then
            if not best or (q.QuestLv or 0) > (best.QuestLv or 0) then
                best = q
            end
        end
    end
    return best
end

-- =========================================================
-- GET TARGETS — quét mob trong bán kính (pattern từ reference)
-- =========================================================
local function GetEnemiesInRadius(origin, radius)
    radius = radius or CONFIG.MobRadius
    local result = {}
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return result end
    for _, model in ipairs(enemies:GetChildren()) do
        local hum = model:FindFirstChildOfClass("Humanoid")
        local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        if hum and hrp and hum.Health > 0 then
            if (hrp.Position - origin).Magnitude <= radius then
                table.insert(result, { model = model, humanoid = hum, root = hrp })
            end
        end
    end
    return result
end

-- =========================================================
-- AUTO EQUIP WEAPON
-- =========================================================
local function AutoEquipWeapon(weaponType)
    weaponType = weaponType or CONFIG.WeaponType or "Melee"
    local char = LocalPlayer.Character
    if not char then return end

    -- Nếu đã cầm tool đúng loại thì thôi
    local currentTool = char:FindFirstChildOfClass("Tool")
    if currentTool and currentTool:GetAttribute("WeaponType") == weaponType then
        return true
    end

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return false end

    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and tool:GetAttribute("WeaponType") == weaponType then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum:EquipTool(tool)
                task.wait(0.1)
                return true
            end
        end
    end
    return false
end

-- =========================================================
-- ATTACK MOB — dùng Tool:Activate + VirtualUser click
-- =========================================================
local function AttackMob(targetRoot)
    local char = LocalPlayer.Character
    if not char then return end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return end

    -- Cách 1: Activate tool
    pcall(function() tool:Activate() end)

    -- Cách 2: VirtualUser click vào vị trí mob trên màn hình
    if targetRoot then
        pcall(function()
            local camera = workspace.CurrentCamera
            local screenPos, onScreen = camera:WorldToViewportPoint(targetRoot.Position)
            if onScreen then
                VirtualUser:ClickButton1(Vector2.new(screenPos.X, screenPos.Y))
            end
        end)
    end
end

-- =========================================================
-- ANTI-AFK (pattern phổ biến)
-- =========================================================
LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end)
end)

-- =========================================================
-- BACKGROUND TASKS — chạy song song, không thuộc FSM
-- =========================================================

-- Chọn phe Pirates
task.spawn(function()
    task.wait(2)
    pcall(function()
        ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", "Pirates")
    end)
end)

-- Tự cộng điểm Stats 70% Melee / 30% Defense
task.spawn(function()
    while true do
        if isRunning then
            pcall(function()
                local points = LocalPlayer.Data.Points.Value
                if points > 0 then
                    local melee = math.floor(points * 0.7)
                    local def   = points - melee
                    if melee > 0 then
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("AddPoint", "Melee", melee)
                    end
                    if def > 0 then
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("AddPoint", "Defense", def)
                    end
                end
            end)
        end
        task.wait(10)
    end
end)

-- Bật Haki Buso + mua kỹ năng khi đủ tiền
task.spawn(function()
    while true do
        if isRunning then
            pcall(function()
                local CommF = ReplicatedStorage.Remotes.CommF_
                -- Buso
                CommF:InvokeServer("BuyHaki", "Buso")
                -- Geppo / Soru / BlackLeg (chỉ mua khi đủ beli)
                local beli = GetPlayerBeli()
                if beli >= 100000 then CommF:InvokeServer("BuyHaki", "Geppo") end
                if beli >= 150000 then CommF:InvokeServer("BuyHaki", "Soru") end
                if beli >= 500000 then CommF:InvokeServer("BlackLeg", "Learn") end
            end)
        end
        task.wait(30)
    end
end)

-- Tự nhặt và cất trái vào kho
task.spawn(function()
    while true do
        if isRunning and CONFIG.AutoStoreFruit then
            pcall(function()
                local char = LocalPlayer.Character
                if not char then return end
                for _, tool in ipairs(char:GetChildren()) do
                    if tool:IsA("Tool") and tool:GetAttribute("WeaponType") == "Blox Fruit" then
                        local fruitName = tool.Name
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", fruitName)
                    end
                end
            end)
        end
        task.wait(5)
    end
end)

-- =========================================================
-- FSM STATE HANDLERS
-- =========================================================

local function setState(newState)
    if State ~= newState then
        print(string.format("[FSM] %s → %s", State, newState))
        State = newState
    end
end

-- ---------- IDLE ----------
local function stateIdle()
    stopActiveTween()
    task.wait(0.5)
    if not isRunning then return end

    if HasActiveQuest() then
        setState("FARM_MOB")
    else
        setState("GET_QUEST")
    end
end

-- ---------- GET_QUEST ----------
local function stateGetQuest()
    if not isRunning then setState("IDLE"); return end

    local playerLevel = GetPlayerLevel()
    local q = PickQuest(playerLevel)
    if not q then
        warn("[FSM] Không tìm được quest phù hợp cho level", playerLevel)
        task.wait(2)
        setState("IDLE")
        return
    end
    currentQuest = q

    -- Bay tới NPC
    local npcPos = Vector3.new(q.NPC[1], q.NPC[2], q.NPC[3])
    flyTo(CFrame.new(npcPos), false)

    if not isRunning then setState("IDLE"); return end

    -- Gọi StartQuest
    local ok, err = pcall(function()
        ReplicatedStorage.Remotes.CommF_:InvokeServer("StartQuest", q.QuestName, q.QuestLv)
    end)
    if not ok then
        warn("[FSM] StartQuest lỗi:", err)
        task.wait(1)
        setState("IDLE")
        return
    end

    -- Chờ GUI cập nhật — FIX LỖI KẸT NPC
    task.wait(CONFIG.QuestCheckDelay)

    if HasActiveQuest() then
        print("[FSM] ✔ Nhận quest thành công:", q.QuestName)
        questRetryCount = 0
        setState("FARM_MOB")
    else
        questRetryCount += 1
        warn(string.format("[FSM] Quest chưa kích hoạt (%d/%d)", questRetryCount, CONFIG.QuestRetryMax))
        if questRetryCount >= CONFIG.QuestRetryMax then
            questRetryCount = 0
            setState("IDLE")
        else
            task.wait(0.5)
            setState("GET_QUEST")
        end
    end
end

-- ---------- FARM_MOB ----------
local function stateFarmMob()
    if not isRunning then setState("IDLE"); return end
    if not currentQuest then setState("GET_QUEST"); return end

    -- Nếu quest đã hoàn thành thì quay lại
    if not HasActiveQuest() then
        print("[FSM] Quest hoàn thành → GET_QUEST")
        setState("GET_QUEST")
        return
    end

    -- Bay tới bãi quái (cao hơn mob 5 studs)
    local mobPos  = Vector3.new(currentQuest.MobPos[1], currentQuest.MobPos[2], currentQuest.MobPos[3])
    local target  = CFrame.new(mobPos + Vector3.new(0, CONFIG.MobOffsetY, 0))
    flyTo(target, false)

    if not isRunning then setState("IDLE"); return end

    -- Giữ vị trí ổn định
    local char, hrp = getCharacter()
    if hrp then
        hrp.CFrame = target
        hrp.AssemblyLinearVelocity = Vector3.zero
    end

    -- Equip weapon
    AutoEquipWeapon(CONFIG.WeaponType or "Melee")

    -- Vòng lặp đánh quái trong 5s
    local attackEnd = tick() + 5
    while isRunning and tick() < attackEnd do
        if not HasActiveQuest() then break end
        if not hrp or not hrp.Parent then break end

        local enemies = GetEnemiesInRadius(hrp.Position, CONFIG.MobRadius)
        if #enemies == 0 then
            task.wait(0.3)
        else
            for _, e in ipairs(enemies) do
                if not isRunning then break end
                if e.humanoid.Health <= 0 then break end
                AttackMob(e.root)
                task.wait(0.1)
            end
        end
        task.wait(0.05)
    end

    task.wait(CONFIG.FarmRetryDelay)
end

-- ---------- RANDOM_FRUIT ----------
local function stateRandomFruit()
    if not isRunning then setState("IDLE"); return end
    if not CONFIG.AutoRandomFruit then setState("IDLE"); return end

    pcall(function()
        local beli = GetPlayerBeli()
        if beli >= (CONFIG.MinBeliToRandom or 500000) then
            ReplicatedStorage.Remotes.CommF_:InvokeServer("Cousin", "Buy")
        end
    end)
    task.wait(2)
    setState("IDLE")
end

-- ---------- SEA2_QUEST (stub) ----------
local function stateSea2Quest()
    if not isRunning then setState("IDLE"); return end
    -- TODO: logic Sea 2 — chưa implement
    task.wait(1)
    setState("IDLE")
end

-- =========================================================
-- MAIN LOOP
-- =========================================================
local handlers = {
    IDLE         = stateIdle,
    GET_QUEST    = stateGetQuest,
    FARM_MOB     = stateFarmMob,
    RANDOM_FRUIT = stateRandomFruit,
    SEA2_QUEST   = stateSea2Quest,
}

task.spawn(function()
    while true do
        if not isRunning then
            stopActiveTween()
            local _, hrp = getCharacter()
            destroyHold(hrp)
            setState("IDLE")
            task.wait(0.5)
        else
            local fn = handlers[State]
            if fn then
                local ok, err = pcall(fn)
                if not ok then
                    warn("[FSM] Handler error:", err)
                    setState("IDLE")
                end
            else
                warn("[FSM] Unknown state:", State)
                setState("IDLE")
            end
        end
        task.wait(0.05)
    end
end)

-- =========================================================
-- PUBLIC API (dùng từ ui.lua)
-- =========================================================
return {
    SetRunning = function(v)
        isRunning = v == true
        if not isRunning then
            stopActiveTween()
            local _, hrp = getCharacter()
            destroyHold(hrp)
        end
    end,
    GetState    = function() return State end,
    GetQuest    = function() return currentQuest end,
    GetTargets  = GetEnemiesInRadius,   -- expose để module khác dùng
    IsRunning   = function() return isRunning end,
}