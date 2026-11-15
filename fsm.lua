-- fsm.lua — Finite State Machine cho Kaitun Blox Fruits
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local BASE_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/"

-- ================= CONFIG =================
local CONFIG = {
    FlySpeed = 150, QuestCheckDelay = 0.5, QuestRetryMax = 3,
    FarmRetryDelay = 1.5, FarmTimeoutSec = 60, MobOffsetY = 5,
    MobRadius = 60, QuestCacheTTL = 10, WeaponType = "Melee",
    AutoStoreFruit = true, AutoRandomFruit = true, MinBeliToRandom = 500000,
}
do
    local ok, raw = pcall(function() return game:HttpGet(BASE_URL .. "config.json") end)
    if ok and type(raw) == "string" and #raw > 0 then
        local ok2, d = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok2 and type(d) == "table" then
            for k, v in pairs(d) do CONFIG[k] = v end
        end
    end
end

-- ================= STATE =================
local State = "IDLE"
local isRunning = true
local ActiveTween = nil
local currentQuest = nil
local questRetryCount = 0

-- ================= HELPERS =================
local function getCharacter()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    return char, hrp
end

local function stopActiveTween()
    if ActiveTween then
        pcall(function() ActiveTween:Cancel() end)
        ActiveTween = nil
    end
end

local function setCanCollide(v)
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            part.CanCollide = v
        end
    end
end

local function flyTo(targetCFrame)
    stopActiveTween()
    if not isRunning then return end
    local char, hrp = getCharacter()
    if not hrp then return end
    hrp.AssemblyLinearVelocity = Vector3.zero
    local dist = (targetCFrame.Position - hrp.Position).Magnitude
    if dist < 1 then return end
    setCanCollide(false)
    ActiveTween = TweenService:Create(hrp,
        TweenInfo.new(dist / CONFIG.FlySpeed, Enum.EasingStyle.Linear),
        { CFrame = targetCFrame })
    ActiveTween:Play()
    ActiveTween.Completed:Wait()
    ActiveTween = nil
    setCanCollide(true)
end

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

local function GetPlayerLevel()
    local ok, lv = pcall(function() return LocalPlayer.Data.Level.Value end)
    return ok and tonumber(lv) or 1
end

local function GetPlayerBeli()
    local ok, b = pcall(function() return LocalPlayer.Data.Beli.Value end)
    return ok and tonumber(b) or 0
end

-- ================= LOAD QUESTS =================
local _questsCache, _questsCacheTime = nil, 0
local function LoadQuests(forceRefresh)
    if not forceRefresh and _questsCache and (tick() - _questsCacheTime < CONFIG.QuestCacheTTL) then
        return _questsCache
    end
    local ok, raw = pcall(function() return game:HttpGet(BASE_URL .. "quests.json") end)
    if not ok or type(raw) ~= "string" or #raw == 0 then return _questsCache or {} end
    local ok2, d = pcall(HttpService.JSONDecode, HttpService, raw)
    if ok2 and type(d) == "table" then
        -- ✅ FIX: quests.json có wrapper "Sea1"
        local list = d.Sea1 or d
        if type(list) == "table" and #list > 0 then
            _questsCache = list
            _questsCacheTime = tick()
        end
    end
    return _questsCache or {}
end

local function PickQuest(playerLevel)
    local quests = LoadQuests()
    if type(quests) ~= "table" or #quests == 0 then return nil end
    local best = nil
    for _, q in ipairs(quests) do
        local minLv = tonumber(q.MinLv) or 0
        if playerLevel >= minLv then
            if not best or minLv > (tonumber(best.MinLv) or 0) then
                best = q
            end
        end
    end
    return best
end

-- ================= COMBAT =================
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

local function getToolType(tool)
    local attr = tool:GetAttribute("WeaponType")
    if attr then return attr end
    local tip = tool.ToolTip
    if tip and tip ~= "" then return tip end
    return "Unknown"
end

local function AutoEquipWeapon(weaponType)
    weaponType = weaponType or CONFIG.WeaponType or "Melee"
    local char = LocalPlayer.Character
    if not char then return false end
    local cur = char:FindFirstChildOfClass("Tool")
    if cur and getToolType(cur) == weaponType then return true end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return false end
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and getToolType(tool) == weaponType then
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

local function AttackMob(targetRoot)
    local char = LocalPlayer.Character
    if not char then return end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return end
    pcall(function() tool:Activate() end)
    if targetRoot then
        pcall(function()
            local cam = workspace.CurrentCamera
            local pos, onScreen = cam:WorldToViewportPoint(targetRoot.Position)
            if onScreen then
                VirtualUser:ClickButton1(Vector2.new(pos.X, pos.Y))
            end
        end)
    end
end

-- ================= ANTI-AFK =================
LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end)
end)

-- ================= BACKGROUND =================
task.spawn(function()
    task.wait(2)
    pcall(function()
        ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", "Pirates")
    end)
end)

task.spawn(function()
    while true do
        if isRunning then
            pcall(function()
                local pts = LocalPlayer.Data.Points.Value
                if pts and pts > 0 then
                    local melee = math.floor(pts * 0.7)
                    local def = pts - melee
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

task.spawn(function()
    while true do
        if isRunning then
            pcall(function()
                local C = ReplicatedStorage.Remotes.CommF_
                C:InvokeServer("BuyHaki", "Buso")
                local beli = GetPlayerBeli()
                if beli >= 100000 then C:InvokeServer("BuyHaki", "Geppo") end
                if beli >= 150000 then C:InvokeServer("BuyHaki", "Soru") end
            end)
        end
        task.wait(30)
    end
end)

task.spawn(function()
    while true do
        if isRunning and CONFIG.AutoStoreFruit then
            pcall(function()
                local char = LocalPlayer.Character
                if not char then return end
                for _, tool in ipairs(char:GetChildren()) do
                    if tool:IsA("Tool") and getToolType(tool) == "Blox Fruit" then
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", tool.Name)
                    end
                end
            end)
        end
        task.wait(5)
    end
end)

-- ================= FSM =================
local function setState(s)
    if State ~= s then
        print(string.format("[FSM] %s → %s", State, s))
        State = s
    end
end

local function stateIdle()
    stopActiveTween()
    task.wait(0.5)
    if not isRunning then return end
    if HasActiveQuest() then setState("FARM_MOB") else setState("GET_QUEST") end
end

local function stateGetQuest()
    if not isRunning then setState("IDLE"); return end
    local lv = GetPlayerLevel()
    local q = PickQuest(lv)
    if not q then
        warn("[FSM] Không tìm được quest cho level", lv)
        task.wait(2)
        setState("IDLE")
        return
    end
    currentQuest = q

    local npc = Vector3.new(q.NPC[1], q.NPC[2], q.NPC[3])
    flyTo(CFrame.new(npc))
    if not isRunning then setState("IDLE"); return end

    local ok, err = pcall(function()
        ReplicatedStorage.Remotes.CommF_:InvokeServer("StartQuest", q.QuestName, q.QuestLv)
    end)
    if not ok then
        warn("[FSM] StartQuest fail:", err)
        task.wait(1); setState("IDLE"); return
    end

    task.wait(CONFIG.QuestCheckDelay)

    if HasActiveQuest() then
        print("[FSM] ✔ Quest OK:", q.QuestName)
        questRetryCount = 0
        setState("FARM_MOB")
    else
        questRetryCount = questRetryCount + 1
        warn(string.format("[FSM] Quest chưa active (%d/%d)", questRetryCount, CONFIG.QuestRetryMax))
        if questRetryCount >= CONFIG.QuestRetryMax then
            questRetryCount = 0
            task.wait(2)
            setState("IDLE")
        else
            task.wait(0.5)
            setState("GET_QUEST")
        end
    end
end

local function stateFarmMob()
    if not isRunning then setState("IDLE"); return end
    if not currentQuest then setState("GET_QUEST"); return end
    if not HasActiveQuest() then setState("GET_QUEST"); return end

    local mobPos = Vector3.new(currentQuest.MobPos[1], currentQuest.MobPos[2], currentQuest.MobPos[3])
    local target = CFrame.new(mobPos + Vector3.new(0, CONFIG.MobOffsetY, 0))
    flyTo(target)
    if not isRunning then setState("IDLE"); return end

    local char, hrp = getCharacter()
    if hrp then
        hrp.CFrame = target
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
    AutoEquipWeapon(CONFIG.WeaponType)

    local farmEnd = tick() + (CONFIG.FarmTimeoutSec or 60)
    while isRunning and tick() < farmEnd do
        if not HasActiveQuest() then
            print("[FSM] Quest complete → GET_QUEST")
            setState("GET_QUEST")
            return
        end
        if not hrp or not hrp.Parent then break end

        hrp.CFrame = target
        hrp.AssemblyLinearVelocity = Vector3.zero

        local enemies = GetEnemiesInRadius(hrp.Position, CONFIG.MobRadius)
        if #enemies == 0 then
            task.wait(0.3)
        else
            for _, e in ipairs(enemies) do
                if not isRunning then break end
                if e.humanoid.Health <= 0 then break end
                AttackMob(e.root)
                task.wait(0.05)
            end
        end
        task.wait(0.05)
    end

    if isRunning and HasActiveQuest() then
        warn("[FSM] Farm timeout, retry quest")
        setState("GET_QUEST")
    end
end

local function stateRandomFruit()
    if not isRunning then setState("IDLE"); return end
    if not CONFIG.AutoRandomFruit then setState("IDLE"); return end
    pcall(function()
        if GetPlayerBeli() >= (CONFIG.MinBeliToRandom or 500000) then
            ReplicatedStorage.Remotes.CommF_:InvokeServer("Cousin", "Buy")
        end
    end)
    task.wait(2)
    setState("IDLE")
end

local function stateSea2Quest()
    if not isRunning then setState("IDLE"); return end
    task.wait(1)
    setState("IDLE")
end

-- ================= LOOP =================
local handlers = {
    IDLE = stateIdle, GET_QUEST = stateGetQuest, FARM_MOB = stateFarmMob,
    RANDOM_FRUIT = stateRandomFruit, SEA2_QUEST = stateSea2Quest,
}

task.spawn(function()
    while true do
        if not isRunning then
            stopActiveTween()
            setCanCollide(true)
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

-- ================= API =================
return {
    SetRunning = function(v)
        isRunning = v == true
        if not isRunning then
            stopActiveTween()
            setCanCollide(true)
        end
    end,
    GetState = function() return State end,
    GetQuest = function() return currentQuest end,
    IsRunning = function() return isRunning end,
}