-- fsm.lua — Bản hoàn thiện (Fix crash, bay trên đầu quái, đánh bằng Net)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local BASE_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/"

local function notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Kaitun", Text = tostring(msg), Duration = 3,
        })
    end)
end

local CONFIG = {
    FlySpeed = 150, 
    MobOffsetY = 15, -- Bay cao hơn đầu quái 15 studs
    MobRadius = 300, 
    QuestCacheTTL = 10, 
    WeaponType = "Melee",
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

local State = "IDLE"
local isRunning = true
local ActiveTween = nil
local currentQuest = nil

-- 🔥 LẤY NET MODULE 1 LẦN DUY NHẤT (Tránh crash game)
local Net
pcall(function()
    Net = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))
end)

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

-- Tắt va chạm (CanCollide) để xuyên qua vật thể và quái
local function setCanCollide(v)
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = v
        end
    end
end

local function flyTo(targetCFrame)
    stopActiveTween()
    if not isRunning then return end
    local char, hrp = getCharacter()
    if not hrp then return end
    
    local dist = (targetCFrame.Position - hrp.Position).Magnitude
    if dist < 5 then return end
    
    setCanCollide(false)
    hrp.AssemblyLinearVelocity = Vector3.zero
    
    -- Điểm đến an toàn (cộng thêm Y)
    local safeTarget = targetCFrame + Vector3.new(0, 10, 0)
    
    if dist > 500 then
        hrp.CFrame = safeTarget
        task.wait(0.5) 
    else
        ActiveTween = TweenService:Create(hrp,
            TweenInfo.new(dist / CONFIG.FlySpeed, Enum.EasingStyle.Linear),
            { CFrame = safeTarget })
        ActiveTween:Play()
        ActiveTween.Completed:Wait()
        ActiveTween = nil
    end
    -- LƯU Ý: Không bật lại CanCollide ở đây để không bị rớt xuống đất
end

local function GetPlayerLevel()
    local ok, lv = pcall(function() return LocalPlayer.Data.Level.Value end)
    return ok and tonumber(lv) or 1
end

local _questsCache, _questsCacheTime = nil, 0
local function LoadQuests()
    if _questsCache and (tick() - _questsCacheTime < CONFIG.QuestCacheTTL) then return _questsCache end
    local ok, raw = pcall(function() return game:HttpGet(BASE_URL .. "quests.json") end)
    if not ok or type(raw) ~= "string" or #raw == 0 then return _questsCache or {} end
    local ok2, d = pcall(HttpService.JSONDecode, HttpService, raw)
    if ok2 and type(d) == "table" then
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
            if not best or minLv > (tonumber(best.MinLv) or 0) then best = q end
        end
    end
    return best
end

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
    table.sort(result, function(a, b)
        return (a.root.Position - origin).Magnitude < (b.root.Position - origin).Magnitude
    end)
    return result
end

local function AutoEquipWeapon()
    local weaponType = CONFIG.WeaponType or "Melee"
    local char = LocalPlayer.Character
    if not char then return false end
    local cur = char:FindFirstChildOfClass("Tool")
    if cur and (cur:GetAttribute("WeaponType") == weaponType or cur.ToolTip == weaponType) then return true end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return false end
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and (tool:GetAttribute("WeaponType") == weaponType or tool.ToolTip == weaponType) then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum:EquipTool(tool); task.wait(0.1); return true end
        end
    end
    return false
end

-- 🔥 HÀM ĐÁNH QUÁI (Không còn spam require, gây sát thương thật)
local function AttackMob(targetModel, targetRoot)
    local char = LocalPlayer.Character
    if not char then return end
    if not targetRoot or not targetRoot.Parent then return end
    
    -- Đánh bằng Net module (Chuẩn Blox Fruits)
    if Net then
        pcall(function()
            local hitList = {{targetModel, targetRoot}}
            Net["RE/RegisterAttack"]:FireServer(0.1)
            Net["RE/RegisterHit"]:FireServer(targetRoot, hitList)
        end)
    end
    
    -- Kích hoạt Tool dự phòng (để vung vũ khí)
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function() tool:Activate() end)
    end
end

LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end)
end)

local function setState(s)
    if State ~= s then State = s end
end

local function stateIdle()
    stopActiveTween()
    setCanCollide(true) -- Bật lại va chạm khi đứng chờ
    task.wait(0.5)
    if isRunning then setState("GET_QUEST") end
end

local function stateGetQuest()
    if not isRunning then setState("IDLE"); return end
    local lv = GetPlayerLevel()
    local q = PickQuest(lv)
    if not q then task.wait(2); setState("IDLE"); return end
    currentQuest = q

    notify("Đang tới NPC: " .. q.QuestName)
    local npc = Vector3.new(q.NPC[1], q.NPC[2], q.NPC[3])
    flyTo(CFrame.new(npc))
    
    -- Bật lại va chạm để không rớt qua map ở NPC
    setCanCollide(true)
    
    pcall(function()
        ReplicatedStorage.Remotes.CommF_:InvokeServer("StartQuest", q.QuestName, q.QuestLv)
    end)
    task.wait(1)
    
    notify("✅ Đã nhận Quest, ra bãi đánh quái!")
    setState("FARM_MOB")
end

local function stateFarmMob()
    if not isRunning then setState("IDLE"); return end
    if not currentQuest then setState("GET_QUEST"); return end

    local mobPos = Vector3.new(currentQuest.MobPos[1], currentQuest.MobPos[2], currentQuest.MobPos[3])
    local target = CFrame.new(mobPos + Vector3.new(0, CONFIG.MobOffsetY, 0))
    
    notify("Đang tới bãi quái: " .. currentQuest.Mob)
    flyTo(target)
    if not isRunning then setState("IDLE"); return end

    local char, hrp = getCharacter()
    AutoEquipWeapon()

    -- 🔥 TẮT VA CHẠM ĐỂ BAY LƠ LỬNG TRÊN ĐẦU QUÁI
    setCanCollide(false) 

    local noEnemyTime = 0
    local farmEnd = tick() + 120

    while isRunning and tick() < farmEnd do
        if not hrp or not hrp.Parent then break end

        local enemies = GetEnemiesInRadius(hrp.Position, 300)
        
        if #enemies == 0 then
            noEnemyTime = noEnemyTime + 0.1
            if noEnemyTime > 15 then 
                notify("Hết quái, tìm Quest mới!")
                setState("GET_QUEST")
                return
            end
            -- Giữ nhân vật lơ lửng ở bãi quái
            hrp.CFrame = target
            hrp.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.2)
        else
            noEnemyTime = 0
            local nearest = enemies[1]
            
            if nearest and nearest.root then
                -- 🔥 BÁM THEO QUÁI: Gim thẳng CFrame lên đầu quái (Không dùng Lerp gây giật)
                local targetMob = CFrame.new(nearest.root.Position + Vector3.new(0, CONFIG.MobOffsetY, 0))
                hrp.CFrame = targetMob
                hrp.AssemblyLinearVelocity = Vector3.zero
                
                -- Đánh quái liên tục
                AttackMob(nearest.model, nearest.root)
            end
            
            task.wait(0.15) -- Tốc độ đánh (Chỉnh số này nhỏ hơn để đánh nhanh hơn)
        end
        task.wait(0.05)
    end

    if isRunning then setState("GET_QUEST") end
end

local handlers = { IDLE = stateIdle, GET_QUEST = stateGetQuest, FARM_MOB = stateFarmMob }

task.spawn(function()
    while true do
        if not isRunning then
            stopActiveTween()
            setCanCollide(true)
            setState("IDLE")
            task.wait(0.5)
        else
            local fn = handlers[State]
            if fn then pcall(fn) else setState("IDLE") end
        end
        task.wait(0.05)
    end
end)

return {
    SetRunning = function(v)
        isRunning = v == true
        if not isRunning then stopActiveTween(); setCanCollide(true) end
    end,
    GetState = function() return State end,
    GetQuest = function() return currentQuest end,
    IsRunning = function() return isRunning end,
}