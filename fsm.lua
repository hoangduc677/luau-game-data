-- Tệp: fsm.lua (Fix nhảy trạng thái + Fix Fast Attack chuẩn [27] + FlySpeed 150)
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local BASE_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/"
local CACHE_BUST = "?t=" .. tostring(os.time())

local FSM = {
    State = "IDLE",
    Running = true,
    ActiveTween = nil,
    CurrentQuest = nil,
    LastProgTick = 0
}

local Sea1Bought = { Geppo = false, Buso = false, Soru = false, BlackLeg = false }

-- ==========================================
-- 1. NẠP CẤU HÌNH & GIAO DIỆN
-- ==========================================
local function LoadJSON(fileName)
    local ok, raw = pcall(function() return game:HttpGet(BASE_URL .. fileName .. CACHE_BUST) end)
    if not ok then return nil end
    local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
    return ok2 and data or nil
end

local Config = LoadJSON("config.json") or { FlySpeed = 150, WeaponType = "Melee", AutoStoreFruit = true }
Config.FlySpeed = 150
local QuestsData = LoadJSON("quests.json")

local okUI, UIModule = pcall(function()
    return loadstring(game:HttpGet(BASE_URL .. "ui.lua" .. CACHE_BUST))()
end)

local Dashboard = nil
if okUI and UIModule then
    Dashboard = UIModule.CreateDashboard("⚡ KAITUN SEA 1 (SPEED 150)", function(isRunning)
        FSM.Running = isRunning
        if not isRunning and FSM.ActiveTween then
            FSM.ActiveTween:Cancel()
            FSM.ActiveTween = nil
        end
    end)
end

local function SetUI(text)
    if Dashboard then Dashboard.SetStatus(text) end
end

local function ChangeState(newState, detailText)
    if FSM.State ~= newState then
        FSM.State = newState
    end
    SetUI(detailText or newState)
end

-- ==========================================
-- 2. MODULE FAST ATTACK CHUẨN (Khóa [27] - Không chỉnh sửa Hitbox quái)
-- ==========================================
local Net = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net")
local HitParts = {
    "RightLowerArm", "RightUpperArm", "LeftLowerArm", "LeftUpperArm",
    "RightHand", "LeftHand", "HumanoidRootPart", "Head"
}

local DynamicHitRemote, DynamicHitId = nil, nil
local CachedSeed = nil

task.spawn(function()
    pcall(function()
        for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
            if obj:IsA("RemoteEvent") and obj:GetAttribute("Id") then
                DynamicHitRemote = obj
                DynamicHitId = obj:GetAttribute("Id")
                break
            end
        end
        ReplicatedStorage.DescendantAdded:Connect(function(obj)
            if obj:IsA("RemoteEvent") and obj:GetAttribute("Id") then
                DynamicHitRemote = obj
                DynamicHitId = obj:GetAttribute("Id")
            end
        end)
    end)

    -- Cập nhật seed định kỳ ở luồng riêng để không làm nghẽn nhịp đánh
    while task.wait(1) do
        if FSM.Running and Net:FindFirstChild("seed") then
            pcall(function()
                CachedSeed = Net.seed:InvokeServer()
            end)
        end
    end
end)

local function GetNearbyBladeHits(radius)
    local hits = {}
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return hits end

    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return hits end

    for _, mob in ipairs(enemies:GetChildren()) do
        if mob ~= char then
            local hum = mob:FindFirstChild("Humanoid")
            local mobHrp = mob:FindFirstChild("HumanoidRootPart")
            if hum and mobHrp and hum.Health > 0 and (mobHrp.Position - hrp.Position).Magnitude <= (radius or 60) then
                local chosenPart = mob:FindFirstChild(HitParts[math.random(1, #HitParts)]) or mob.PrimaryPart or mobHrp
                if chosenPart then
                    table.insert(hits, { mob, chosenPart })
                end
            end
        end
    end
    return hits
end

local function ExecuteFastAttack()
    local char = LocalPlayer.Character
    if not char then return end

    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return end

    local bladeHits = GetNearbyBladeHits(60)
    if #bladeHits == 0 then return end

    local mainPart = bladeHits[1][2]

    -- Gửi cặp gói tin đánh chuẩn của Blox Fruits
    pcall(function()
        Net["RE/RegisterAttack"]:FireServer(0.05)
        Net["RE/RegisterHit"]:FireServer(mainPart, bladeHits)
    end)

    -- Gửi kèm gói tin xác thực XOR nếu server yêu cầu
    if DynamicHitRemote and DynamicHitId and CachedSeed then
        pcall(function()
            local timeKey = math.floor(workspace:GetServerTimeNow() / 10 % 10) + 1
            local encodedName = string.gsub("RE/RegisterHit", ".", function(c)
                return string.char(bit32.bxor(string.byte(c), timeKey))
            end)
            local ref = (cloneref and cloneref(DynamicHitRemote)) or DynamicHitRemote
            ref:FireServer(encodedName, bit32.bxor(DynamicHitId + 909090, CachedSeed * 2), mainPart, bladeHits)
        end)
    end
end

-- Vòng lặp Fast Attack độc lập
task.spawn(function()
    while task.wait(0.06) do
        if FSM.Running and FSM.State == "FARM_MOB" then
            pcall(ExecuteFastAttack)
        end
    end
end)

-- ==========================================
-- 3. KHÓA VẬN TỐC & CHỐNG AFK
-- ==========================================
RunService.Heartbeat:Connect(function()
    if not FSM.Running then return end
    local char = LocalPlayer.Character
    if not char then return end

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end
    end
end)

LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- ==========================================
-- 4. HÀM BAY (Tốc độ cố định 150) & TRANG BỊ VŨ KHÍ
-- ==========================================
local function StopFly()
    if FSM.ActiveTween then
        FSM.ActiveTween:Cancel()
        FSM.ActiveTween = nil
    end
end

local function StableFlyTo(targetCF)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local dist = (hrp.Position - targetCF.Position).Magnitude
    if dist <= 10 then
        StopFly()
        hrp.CFrame = targetCF
        return true
    end

    StopFly()
    local speed = 150
    local duration = dist / speed

    local tween = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = targetCF})
    FSM.ActiveTween = tween
    tween:Play()

    local startTick = tick()
    while tick() - startTick < duration do
        if not FSM.Running or not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            StopFly()
            return false
        end
        if (hrp.Position - targetCF.Position).Magnitude <= 10 then
            StopFly()
            hrp.CFrame = targetCF
            return true
        end
        task.wait(0.05)
    end
    StopFly()
    return true
end

local function AutoEquipWeapon()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local targetType = Config.WeaponType or "Melee"
    local equipped = char:FindFirstChildOfClass("Tool")
    if equipped and (equipped.ToolTip == targetType or equipped:GetAttribute("WeaponType") == targetType or equipped.ToolTip == "") then
        return
    end

    for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if tool:IsA("Tool") and (tool.ToolTip == targetType or tool:GetAttribute("WeaponType") == targetType) then
            hum:EquipTool(tool)
            return
        end
    end

    -- Fallback: Cầm vũ khí cận chiến mặc định (Combat ở Sea 1 thường có ToolTip rỗng)
    for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if tool:IsA("Tool") and not string.find(tool.Name, "Fruit") then
            hum:EquipTool(tool)
            return
        end
    end
end

-- ==========================================
-- 5. NHIỆM VỤ & TIẾN TRÌNH SEA 1
-- ==========================================
local function GetCurrentQuest()
    if not QuestsData or not QuestsData.Sea1 then return nil end
    local level = 1
    pcall(function() level = LocalPlayer.Data.Level.Value end)

    local questList = QuestsData.Sea1
    local bestQuest = questList[1]
    for _, q in ipairs(questList) do
        if level >= q.MinLv then bestQuest = q end
    end

    return {
        QuestName = bestQuest.QuestName,
        QuestLv = bestQuest.QuestLv,
        Mob = bestQuest.Mob,
        NPCCFrame = CFrame.new(bestQuest.NPC[1], bestQuest.NPC[2] + 3, bestQuest.NPC[3]),
        MobCFrame = bestQuest.MobPos and CFrame.new(bestQuest.MobPos[1], bestQuest.MobPos[2] + 14, bestQuest.MobPos[3])
                    or CFrame.new(bestQuest.NPC[1], bestQuest.NPC[2] + 15, bestQuest.NPC[3])
    }
end

local function HasActiveQuest()
    local ok, visible = pcall(function()
        return LocalPlayer.PlayerGui.Main.Quest.Visible
    end)
    return ok and visible or false
end

local function HandleSea1ProgressionAsync()
    if tick() - FSM.LastProgTick < 5 then return end
    FSM.LastProgTick = tick()

    task.spawn(function()
        local CommF = ReplicatedStorage.Remotes.CommF_
        if LocalPlayer.Team == nil then
            pcall(function() CommF:InvokeServer("SetTeam", "Pirates") end)
        end

        local beli, points = 0, 0
        pcall(function()
            beli = LocalPlayer.Data.Beli.Value
            points = LocalPlayer.Data.Points.Value
        end)

        if points > 0 then
            pcall(function()
                CommF:InvokeServer("AddPoint", "Melee", math.ceil(points * 0.7))
                CommF:InvokeServer("AddPoint", "Defense", math.floor(points * 0.3))
            end)
        end

        if LocalPlayer.Character and not LocalPlayer.Character:FindFirstChild("HasBuso") then
            pcall(function() CommF:InvokeServer("Buso") end)
        end

        pcall(function()
            if beli >= 10000 and not Sea1Bought.Geppo then CommF:InvokeServer("BuyHaki", "Geppo"); Sea1Bought.Geppo = true end
            if beli >= 25000 and not Sea1Bought.Buso then CommF:InvokeServer("BuyHaki", "Buso"); Sea1Bought.Buso = true end
            if beli >= 150000 and not Sea1Bought.BlackLeg then CommF:InvokeServer("BuyBlackLeg"); Sea1Bought.BlackLeg = true end
            if beli >= 100000 and not Sea1Bought.Soru then CommF:InvokeServer("BuyHaki", "Soru"); Sea1Bought.Soru = true end
        end)
    end)
end

-- ==========================================
-- 6. BẢNG TRẠNG THÁI FSM (ĐÃ KHÓA CHỐNG NHẢY VIỆC)
-- ==========================================
local Actions = {
    IDLE = function()
        HandleSea1ProgressionAsync()
        if HasActiveQuest() then
            FSM.CurrentQuest = GetCurrentQuest()
            ChangeState("FARM_MOB", "ĐANG FARM")
        else
            ChangeState("GET_QUEST", "ĐI NHẬN QUEST")
        end
    end,

    GET_QUEST = function()
        if HasActiveQuest() then
            FSM.CurrentQuest = GetCurrentQuest()
            ChangeState("FARM_MOB", "ĐANG FARM")
            return
        end

        local q = GetCurrentQuest()
        if not q then
            SetUI("THIẾU DỮ LIỆU QUEST")
            task.wait(2)
            return
        end

        FSM.CurrentQuest = q
        SetUI("BAY TỚI NPC: " .. q.Mob)

        if StableFlyTo(q.NPCCFrame) then
            SetUI("ĐANG NHẬN QUEST: " .. q.Mob)
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("StartQuest", q.QuestName, q.QuestLv)
            end)

            -- Chờ tối đa 2 giây để server xác nhận Quest hiện trên UI trước khi chuyển sang FARM_MOB
            for _ = 1, 20 do
                if HasActiveQuest() then
                    ChangeState("FARM_MOB", "ĐANG ĐÁNH: " .. q.Mob)
                    return
                end
                task.wait(0.1)
            end
        end
    end,

    FARM_MOB = function()
        -- Kiểm tra kép 2 lần tránh bị nhảy trạng thái do lag UI 1 khung hình
        if not HasActiveQuest() then
            task.wait(0.3)
            if not HasActiveQuest() then
                FSM.CurrentQuest = nil
                ChangeState("GET_QUEST", "NHẬN QUEST MỚI")
                return
            end
        end

        HandleSea1ProgressionAsync()
        local q = FSM.CurrentQuest or GetCurrentQuest()
        if not q then return end

        local targetMob = nil
        local shortestDist = math.huge
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

        if workspace:FindFirstChild("Enemies") and hrp then
            for _, mob in ipairs(workspace.Enemies:GetChildren()) do
                local hum = mob:FindFirstChild("Humanoid")
                local mobHrp = mob:FindFirstChild("HumanoidRootPart")
                if hum and mobHrp and hum.Health > 0 and string.find(mob.Name, q.Mob) then
                    local d = (mobHrp.Position - hrp.Position).Magnitude
                    if d < shortestDist then
                        shortestDist = d
                        targetMob = mob
                    end
                end
            end
        end

        if targetMob and targetMob:FindFirstChild("HumanoidRootPart") then
            StopFly()
            SetUI("ĐANG ĐÁNH: " .. q.Mob)
            AutoEquipWeapon()
            if hrp then
                -- Đứng trên đầu quái 14 studs (trong tầm 60 studs của Fast Attack, tránh quái đánh trúng)
                hrp.CFrame = targetMob.HumanoidRootPart.CFrame * CFrame.new(0, 14, 0)
            end
        else
            SetUI("BAY TỚI BÃI QUÁI: " .. q.Mob)
            StableFlyTo(q.MobCFrame)
        end
    end
}

-- ==========================================
-- 7. VÒNG LẶP ĐIỀU PHỐI CHÍNH
-- ==========================================
task.spawn(function()
    while task.wait(0.15) do
        if FSM.Running then
            local action = Actions[FSM.State]
            if action then
                local ok, err = pcall(action)
                if not ok then
                    warn("[FSM ERROR]:", err)
                end
            else
                FSM.State = "IDLE"
            end
        end
    end
end)
