-- Tệp: fsm.lua (Tích hợp Fast Attack [27] & Khóa vận tốc [19] trích xuất từ file Kaitun)
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
    LastRandomTick = 0
}

local Sea1Bought = { Geppo = false, Buso = false, Soru = false, BlackLeg = false }

-- ==========================================
-- 1. MODULE FAST ATTACK (Trích xuất từ khóa [27])
-- ==========================================
local Net = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net")
local HitParts = {
    "RightLowerArm", "RightUpperArm", "LeftLowerArm", "LeftUpperArm",
    "RightHand", "LeftHand", "HumanoidRootPart", "Head"
}

local DynamicHitRemote, DynamicHitId = nil, nil
pcall(function()
    local folders = {
        ReplicatedStorage:FindFirstChild("Util"),
        ReplicatedStorage:FindFirstChild("Common"),
        ReplicatedStorage:FindFirstChild("Remotes"),
        ReplicatedStorage:FindFirstChild("Assets"),
        ReplicatedStorage:FindFirstChild("FX")
    }
    for _, folder in ipairs(folders) do
        if folder then
            local function checkObj(obj)
                if obj:IsA("RemoteEvent") and obj:GetAttribute("Id") then
                    DynamicHitRemote = obj
                    DynamicHitId = obj:GetAttribute("Id")
                end
            end
            for _, child in ipairs(folder:GetChildren()) do checkObj(child) end
            folder.ChildAdded:Connect(checkObj)
        end
    end
end)

local function GetNearbyBladeHits(radius)
    local hits = {}
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return hits end

    local containers = {
        workspace:FindFirstChild("Enemies"),
        workspace:FindFirstChild("Characters")
    }

    for _, folder in ipairs(containers) do
        if folder then
            for _, mob in ipairs(folder:GetChildren()) do
                if mob ~= char then
                    local hum = mob:FindFirstChild("Humanoid")
                    local mobHrp = mob:FindFirstChild("HumanoidRootPart")
                    if hum and mobHrp and hum.Health > 0 and (mobHrp.Position - hrp.Position).Magnitude <= (radius or 60) then
                        local chosenPart = mob:FindFirstChild(HitParts[math.random(1, #HitParts)]) or mob.PrimaryPart or mobHrp
                        if chosenPart then
                            -- Gom quái lại gần để đánh lan
                            pcall(function()
                                mobHrp.CanCollide = false
                                mobHrp.Size = Vector3.new(50, 50, 50)
                            end)
                            table.insert(hits, { mob, chosenPart })
                        end
                    end
                end
            end
        end
    end
    return hits
end

local function ExecuteFastAttack()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChildOfClass("Tool") then return end

    local bladeHits = GetNearbyBladeHits(60)
    if #bladeHits == 0 then return end

    local mainPart = bladeHits[1][2]

    -- Phương thức 1: Gửi cặp lệnh chuẩn RE/RegisterAttack + RE/RegisterHit
    pcall(function()
        Net["RE/RegisterAttack"]:FireServer(0.05)
        Net["RE/RegisterHit"]:FireServer(mainPart, bladeHits)
    end)

    -- Phương thức 2: Gửi kèm gói tin giải mã XOR nếu server bật Anti-Cheat Remote Id
    pcall(function()
        if DynamicHitRemote and DynamicHitId and Net:FindFirstChild("seed") then
            local seedVal = Net.seed:InvokeServer()
            local timeKey = math.floor(workspace:GetServerTimeNow() / 10 % 10) + 1
            local encodedName = string.gsub("RE/RegisterHit", ".", function(c)
                return string.char(bit32.bxor(string.byte(c), timeKey))
            end)
            local ref = (cloneref and cloneref(DynamicHitRemote)) or DynamicHitRemote
            ref:FireServer(encodedName, bit32.bxor(DynamicHitId + 909090, seedVal * 2), mainPart, bladeHits)
        end
    end)
end

-- Chạy luồng Fast Attack liên tục độc lập (chu kỳ 0.05s chuẩn từ khóa [27])
task.spawn(function()
    while task.wait(0.05) do
        if FSM.Running and FSM.State == "FARM_MOB" then
            pcall(ExecuteFastAttack)
        end
    end
end)

-- ==========================================
-- 2. NẠP CẤU HÌNH & GIAO DIỆN
-- ==========================================
local function LoadJSON(fileName)
    local ok, raw = pcall(function() return game:HttpGet(BASE_URL .. fileName .. CACHE_BUST) end)
    if not ok then return nil end
    local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
    return ok2 and data or nil
end

local Config = LoadJSON("config.json") or { FlySpeed = 200, WeaponType = "Melee", AutoStoreFruit = true }
local QuestsData = LoadJSON("quests.json")

local okUI, UIModule = pcall(function()
    return loadstring(game:HttpGet(BASE_URL .. "ui.lua" .. CACHE_BUST))()
end)

local Dashboard = nil
if okUI and UIModule then
    Dashboard = UIModule.CreateDashboard("⚡ KAITUN SEA 1 PRO", function(isRunning)
        FSM.Running = isRunning
        if not isRunning and FSM.ActiveTween then
            FSM.ActiveTween:Cancel()
        end
    end)
end

local function SetUI(text)
    if Dashboard then Dashboard.SetStatus(text) end
end

local function ChangeState(newState, detailText)
    FSM.State = newState
    SetUI(detailText or newState)
end

-- ==========================================
-- 3. KHÓA VẬN TỐC KHÔNG DÙNG BODYVELOCITY (Từ khóa [19])
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

-- Chống AFK
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- ==========================================
-- 4. HÀM BAY & TRANG BỊ VŨ KHÍ
-- ==========================================
local function StableFlyTo(targetCF)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local dist = (hrp.Position - targetCF.Position).Magnitude
    if dist <= 12 then
        hrp.CFrame = targetCF
        return true
    end

    if FSM.ActiveTween then FSM.ActiveTween:Cancel() end
    local speed = Config.FlySpeed or 200
    local duration = dist / speed

    local tween = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = targetCF})
    FSM.ActiveTween = tween
    tween:Play()

    local startTick = tick()
    while tick() - startTick < duration do
        if not FSM.Running or not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            tween:Cancel()
            return false
        end
        if (hrp.Position - targetCF.Position).Magnitude <= 12 then
            tween:Cancel()
            hrp.CFrame = targetCF
            return true
        end
        task.wait(0.05)
    end
    return true
end

local function AutoEquipWeapon()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local targetType = Config.WeaponType or "Melee"
    local equipped = char:FindFirstChildOfClass("Tool")
    if equipped and (equipped.ToolTip == targetType or equipped:GetAttribute("WeaponType") == targetType) then
        return
    end

    for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if tool:IsA("Tool") and (tool.ToolTip == targetType or tool:GetAttribute("WeaponType") == targetType) then
            hum:EquipTool(tool)
            return
        end
    end

    local firstTool = LocalPlayer.Backpack:FindFirstChildOfClass("Tool")
    if firstTool then hum:EquipTool(firstTool) end
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
        MobCFrame = bestQuest.MobPos and CFrame.new(bestQuest.MobPos[1], bestQuest.MobPos[2] + 12, bestQuest.MobPos[3])
                    or CFrame.new(bestQuest.NPC[1], bestQuest.NPC[2] + 15, bestQuest.NPC[3])
    }
end

local function HasActiveQuest()
    local ok, visible = pcall(function()
        return LocalPlayer.PlayerGui.Main.Quest.Visible
    end)
    return ok and visible or false
end

local function HandleSea1Progression()
    local CommF = ReplicatedStorage.Remotes.CommF_
    if LocalPlayer.Team == nil then
        pcall(function() CommF:InvokeServer("SetTeam", "Pirates") end)
    end

    local level = LocalPlayer.Data.Level.Value
    local beli = LocalPlayer.Data.Beli.Value
    local points = LocalPlayer.Data.Points.Value

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

    return false
end

-- ==========================================
-- 6. BẢNG TRẠNG THÁI FSM
-- ==========================================
local Actions = {
    IDLE = function()
        HandleSea1Progression()
        if HasActiveQuest() then
            ChangeState("FARM_MOB", "FARMING")
        else
            ChangeState("GET_QUEST", "GET_QUEST")
        end
    end,

    GET_QUEST = function()
        if HasActiveQuest() then
            ChangeState("FARM_MOB", "FARMING")
            return
        end

        local q = GetCurrentQuest()
        if not q then SetUI("NO QUEST DATA"); task.wait(2); return end

        SetUI("FLY TO NPC: " .. q.Mob)
        if StableFlyTo(q.NPCCFrame) then
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("StartQuest", q.QuestName, q.QuestLv)
            end)
            task.wait(0.5)
            ChangeState("FARM_MOB", "FARMING: " .. q.Mob)
        end
    end,

    FARM_MOB = function()
        if not HasActiveQuest() then
            ChangeState("GET_QUEST", "GET_QUEST")
            return
        end

        local q = GetCurrentQuest()
        if not q then return end

        local targetMob = nil
        if workspace:FindFirstChild("Enemies") then
            for _, mob in ipairs(workspace.Enemies:GetChildren()) do
                if mob:FindFirstChild("Humanoid") and mob:FindFirstChild("HumanoidRootPart") and mob.Humanoid.Health > 0 then
                    if string.find(mob.Name, q.Mob) then
                        targetMob = mob
                        break
                    end
                end
            end
        end

        if targetMob and targetMob:FindFirstChild("HumanoidRootPart") then
            SetUI("KILLING: " .. q.Mob)
            AutoEquipWeapon()
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                -- Đứng cách đầu quái 12 studs (trong tầm 60 studs của Fast Attack [27])
                hrp.CFrame = targetMob.HumanoidRootPart.CFrame * CFrame.new(0, 12, 0)
            end
        else
            SetUI("WAITING MOB: " .. q.Mob)
            StableFlyTo(q.MobCFrame)
        end
    end
}

-- ==========================================
-- 7. VÒNG LẶP ĐIỀU PHỐI
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
