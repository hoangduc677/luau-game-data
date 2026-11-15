-- Tệp: fsm.lua (Bản gộp hoàn chỉnh cho Sea 1)
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

-- 1. Nạp JSON và UI
local function LoadJSON(fileName)
    local ok, raw = pcall(function() return game:HttpGet(BASE_URL .. fileName .. CACHE_BUST) end)
    if not ok then return nil end
    local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
    return ok2 and data or nil
end

local Config = LoadJSON("config.json") or { FlySpeed = 300, WeaponType = "Melee", AutoFarm = true }
local QuestsData = LoadJSON("quests.json")

local okUI, UIModule = pcall(function()
    return loadstring(game:HttpGet(BASE_URL .. "ui.lua" .. CACHE_BUST))()
end)

local Dashboard = nil
if okUI and UIModule then
    Dashboard = UIModule.CreateDashboard("⚡ KAITUN SEA 1", function(isRunning)
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

-- 2. Chống rơi (Anti-Gravity) & Xuyên tường (Noclip)
RunService.Stepped:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")

    if not FSM.Running then
        if hrp and hrp:FindFirstChild("MeowBV") then
            hrp.MeowBV:Destroy()
        end
        return
    end

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            part.CanCollide = false
        end
    end

    if hrp and not hrp:FindFirstChild("MeowBV") then
        local bv = Instance.new("BodyVelocity")
        bv.Name = "MeowBV"
        bv.Velocity = Vector3.new(0, 0, 0)
        bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        bv.Parent = hrp
    end
end)

-- 3. Hàm Fly ổn định
local function StableFlyTo(targetCF)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local dist = (hrp.Position - targetCF.Position).Magnitude
    if dist <= 15 then
        hrp.CFrame = targetCF
        return true
    end

    if FSM.ActiveTween then FSM.ActiveTween:Cancel() end
    local speed = Config.FlySpeed or 300
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
        if (hrp.Position - targetCF.Position).Magnitude <= 15 then
            tween:Cancel()
            hrp.CFrame = targetCF
            return true
        end
        task.wait(0.1)
    end
    return true
end

-- 4. Tự cầm vũ khí
local function AutoEquipWeapon()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local targetType = Config.WeaponType or "Melee"
    for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.ToolTip == targetType then
            hum:EquipTool(tool)
            break
        end
    end
end

-- 5. Xác định Sea và lấy Quest theo Level
local function GetCurrentSeaKey()
    local placeId = game.PlaceId
    if placeId == 2753915549 then return "Sea1"
    elseif placeId == 4442272183 then return "Sea2"
    else return "Sea3" end
end

local function GetCurrentQuest()
    if not QuestsData then return nil end
    local seaKey = GetCurrentSeaKey()
    local questList = QuestsData[seaKey]
    if not questList or #questList == 0 then return nil end

    local level = 1
    pcall(function() level = LocalPlayer.Data.Level.Value end)

    local bestQuest = questList[1]
    for _, q in ipairs(questList) do
        if level >= q.MinLv then bestQuest = q end
    end

    return {
        QuestName = bestQuest.QuestName,
        QuestLv = bestQuest.QuestLv,
        Mob = bestQuest.Mob,
        NPCCFrame = CFrame.new(bestQuest.NPC[1], bestQuest.NPC[2] + 3, bestQuest.NPC[3]),
        MobCFrame = bestQuest.MobPos and CFrame.new(bestQuest.MobPos[1], bestQuest.MobPos[2] + 15, bestQuest.MobPos[3])
                    or CFrame.new(bestQuest.NPC[1], bestQuest.NPC[2] + 25, bestQuest.NPC[3])
    }
end

local function HasActiveQuest()
    local ok, visible = pcall(function()
        return LocalPlayer.PlayerGui.Main.Quest.Visible
    end)
    return ok and visible or false
end

-- 6. Tự động nâng chỉ số, mua kỹ năng & kiểm tra Lv 700 ở Sea 1
local function HandleSea1Progression()
    if GetCurrentSeaKey() ~= "Sea1" then return false end

    local CommF = ReplicatedStorage.Remotes.CommF_
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
        if beli >= 10000 and not Sea1Bought.Geppo then
            CommF:InvokeServer("BuyHaki", "Geppo")
            Sea1Bought.Geppo = true
        end
        if beli >= 25000 and not Sea1Bought.Buso then
            CommF:InvokeServer("BuyHaki", "Buso")
            Sea1Bought.Buso = true
        end
        if beli >= 150000 and not Sea1Bought.BlackLeg then
            CommF:InvokeServer("BuyBlackLeg")
            Sea1Bought.BlackLeg = true
        end
        if beli >= 100000 and not Sea1Bought.Soru then
            CommF:InvokeServer("BuyHaki", "Soru")
            Sea1Bought.Soru = true
        end
    end)

    if level >= 700 then
        ChangeState("SEA2_QUEST", "UNLOCKING SEA 2")
        return true
    end
    return false
end

-- 7. Nhặt & Cất Trái Ác Quỷ
local function AutoStoreFruits()
    if not Config.AutoStoreFruit then return end
    pcall(function()
        local CommF = ReplicatedStorage.Remotes.CommF_
        local containers = { LocalPlayer.Backpack, LocalPlayer.Character }
        for _, container in ipairs(containers) do
            if container then
                for _, item in ipairs(container:GetChildren()) do
                    if item:IsA("Tool") and string.find(item.Name, "Fruit") then
                        local fruitCode = item:GetAttribute("OriginalName") or item.Name
                        CommF:InvokeServer("StoreFruit", fruitCode, item)
                    end
                end
            end
        end
    end)
end

local function CheckAndCollectFruit()
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Tool") and string.find(obj.Name, "Fruit") and obj:FindFirstChild("Handle") then
            SetUI("COLLECTING: " .. obj.Name)
            StableFlyTo(obj.Handle.CFrame)
            return true
        end
    end
    return false
end

-- 8. Bảng hành động FSM
local Actions = {
    IDLE = function()
        if GetCurrentSeaKey() ~= "Sea1" then
            SetUI("NOT IN SEA 1 (Teleporting...)")
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("TravelMain")
            end)
            task.wait(3)
            return
        end

        if HandleSea1Progression() then return end

        if Config.AutoRandomFruit and (tick() - FSM.LastRandomTick > 120) then
            local beli = 0
            pcall(function() beli = LocalPlayer.Data.Beli.Value end)
            if beli >= (Config.MinBeliToRandom or 500000) then
                ChangeState("RANDOM_FRUIT", "RANDOM_FRUIT")
                return
            end
        end

        if HasActiveQuest() then
            ChangeState("FARM_MOB", "FARMING")
        else
            ChangeState("GET_QUEST", "GET_QUEST")
        end
    end,

    RANDOM_FRUIT = function()
        FSM.LastRandomTick = tick()
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("Cousin", "Buy")
        end)
        task.wait(1)
        ChangeState("IDLE", "IDLE")
    end,

    GET_QUEST = function()
        if HandleSea1Progression() then return end
        if HasActiveQuest() then
            ChangeState("FARM_MOB", "FARMING")
            return
        end

        local q = GetCurrentQuest()
        if not q then
            SetUI("NO QUEST DATA")
            task.wait(2)
            return
        end

        SetUI("FLY TO NPC: " .. q.Mob)
        if StableFlyTo(q.NPCCFrame) then
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("StartQuest", q.QuestName, q.QuestLv)
            end)
            task.wait(0.8)
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

        if targetMob then
            SetUI("KILLING: " .. q.Mob)
            AutoEquipWeapon()
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = targetMob.HumanoidRootPart.CFrame * CFrame.new(0, 12, 0)
                VirtualUser:CaptureController()
                VirtualUser:Button1Down(Vector2.new(1280, 672))
            end
        else
            SetUI("WAITING MOB: " .. q.Mob)
            StableFlyTo(q.MobCFrame)
        end
    end,

    SEA2_QUEST = function()
        local CommF = ReplicatedStorage.Remotes.CommF_
        local prog = CommF:InvokeServer("DressrosaQuestProgress")

        if prog and prog.UsedKey and prog.KilledIceBoss then
            SetUI("TRAVELING TO SEA 2...")
            CommF:InvokeServer("TravelDressrosa")
            task.wait(5)
            return
        end

        if not prog or not prog.TalkedDetective then
            CommF:InvokeServer("DressrosaQuestProgress", "Detective")
            task.wait(1)
        end

        if not prog or not prog.UsedKey then
            local key = LocalPlayer.Backpack:FindFirstChild("Key") or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Key"))
            if key and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
                LocalPlayer.Character.Humanoid:EquipTool(key)
                StableFlyTo(CFrame.new(1347, 37, -1325))
                CommF:InvokeServer("DressrosaQuestProgress", "UseKey")
                task.wait(1)
            end
        end

        local boss = workspace:FindFirstChild("Enemies") and workspace.Enemies:FindFirstChild("Ice Admiral")
        if boss and boss:FindFirstChild("Humanoid") and boss.Humanoid.Health > 0 then
            SetUI("KILLING: Ice Admiral")
            AutoEquipWeapon()
            LocalPlayer.Character.HumanoidRootPart.CFrame = boss.HumanoidRootPart.CFrame * CFrame.new(0, 12, 0)
            VirtualUser:CaptureController()
            VirtualUser:Button1Down(Vector2.new(1280, 672))
        else
            StableFlyTo(CFrame.new(1347, 37, -1325))
        end
    end
}

-- 9. Vòng lặp trung tâm
task.spawn(function()
    while true do
        if FSM.Running then
            pcall(AutoStoreFruits)
            local foundFruit = CheckAndCollectFruit()
            if not foundFruit then
                local action = Actions[FSM.State]
                if action then
                    local ok, err = pcall(action)
                    if not ok then
                        warn("[FSM ERROR]:", err)
                        SetUI("ERR: Check F9")
                    end
                else
                    FSM.State = "IDLE"
                end
            end
        end
        task.wait(0.2)
    end
end)
