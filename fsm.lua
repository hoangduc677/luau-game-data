-- Tệp: fsm.lua (Hệ thống Kaitun Hoàn chỉnh: Quest động + Random Trái + Nhặt/Cất Kho Trái)
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local CONFIG_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/config.json?t=" .. tostring(os.time())
local QUESTS_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/quests.json?t=" .. tostring(os.time())
local UI_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/ui.lua?t=" .. tostring(os.time())

getgenv().DynamicSpeed = 150
local FSM = {
    State = "IDLE",
    Running = true
}

-- 1. Nạp Giao Diện UI
local okUI, UIModule = pcall(function() return loadstring(game:HttpGet(UI_URL))() end)
local Dashboard = nil
if okUI and UIModule then
    Dashboard = UIModule.CreateDashboard("⚡ KAITUN BLOX FRUITS", 
        function(isRunning) FSM.Running = isRunning end,
        function(newSpeed) getgenv().DynamicSpeed = newSpeed end
    )
end

-- 2. Tải Dữ liệu từ GitHub
local function LoadJSONData(url)
    local ok1, raw = pcall(function() return game:HttpGet(url) end)
    if not ok1 then return nil end
    local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok2 then return nil end
    return data
end

local Config = LoadJSONData(CONFIG_URL)
local QuestsData = LoadJSONData(QUESTS_URL)

if not Config or not QuestsData then
    warn("❌ Không thể tải file dữ liệu cấu hình từ GitHub!")
    return
end

local function UpdateState(newState)
    FSM.State = newState
    if Dashboard then Dashboard.SetStatus(newState) end
end

-- 3. Hàm lấy Quest chuẩn theo Level nhân vật
local function GetCurrentQuest()
    local level = 1
    pcall(function() level = LocalPlayer.Data.Level.Value end)

    local allQuests = {}
    if QuestsData.Sea1 then for _, q in ipairs(QuestsData.Sea1) do table.insert(allQuests, q) end end
    if QuestsData.Sea2 then for _, q in ipairs(QuestsData.Sea2) do table.insert(allQuests, q) end end
    if QuestsData.Sea3 then for _, q in ipairs(QuestsData.Sea3) do table.insert(allQuests, q) end end

    local bestQuest = allQuests[1]
    for _, q in ipairs(allQuests) do
        if level >= q.MinLv then bestQuest = q end
    end

    if bestQuest and bestQuest.NPC then
        bestQuest.NPCCFrame = CFrame.new(bestQuest.NPC[1], bestQuest.NPC[2], bestQuest.NPC[3])
    end
    return bestQuest
end

-- 4. Hàm tự động Nhặt Trái Ác Quỷ rơi dưới đất
local function CheckAndCollectFruit()
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Tool") and obj:FindFirstChild("Handle") then
            if string.find(obj.Name, "Fruit") then
                local fruitPart = obj.Handle
                local dist = (hrp.Position - fruitPart.Position).Magnitude
                print("🍎 Phát hiện trái cây rơi:", obj.Name, "| Khoảng cách:", math.floor(dist))
                hrp.CFrame = fruitPart.CFrame
                task.wait(0.4)
                return true
            end
        end
    end
    return false
end

-- 5. Hàm tự động Cất Kho Trái Ác Quỷ (Store Fruit)
local function AutoStoreFruits()
    pcall(function()
        local backpack = LocalPlayer.Backpack
        local character = LocalPlayer.Character
        local CommF = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_")

        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") and string.find(item.Name, "Fruit") then
                print("📦 Đang cất trái vào kho:", item.Name)
                CommF:InvokeServer("StoreFruit", item.Name)
            end
        end
        if character then
            for _, item in ipairs(character:GetChildren()) do
                if item:IsA("Tool") and string.find(item.Name, "Fruit") then
                    print("📦 Đang cất trái trên tay vào kho:", item.Name)
                    CommF:InvokeServer("StoreFruit", item.Name)
                end
            end
        end
    end)
end

-- 6. Định nghĩa các trạng thái FSM
local Actions = {
    IDLE = function()
        -- Kiểm tra tiền Beli để định kỳ random trái (ví dụ đủ 50k Beli)
        local beli = 0
        pcall(function() beli = LocalPlayer.Data.Beli.Value end)
        if beli >= 50000 then
            UpdateState("RANDOM_FRUIT")
            return
        end

        local activeQuest = GetCurrentQuest()
        if not activeQuest then
            UpdateState("COMPLETED")
            return
        end
        UpdateState("GET_QUEST: " .. activeQuest.Mob)
    end,

    GET_QUEST = function()
        local activeQuest = GetCurrentQuest()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local dist = (hrp.Position - activeQuest.NPCCFrame.Position).Magnitude
        if dist > 15 then
            local speed = getgenv().DynamicSpeed
            local tween = TweenService:Create(hrp, TweenInfo.new(dist / speed, Enum.EasingStyle.Linear), {CFrame = activeQuest.NPCCFrame})
            tween:Play()
            task.wait(dist / speed)
        else
            pcall(function()
                local CommF = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_")
                CommF:InvokeServer("StartQuest", activeQuest.QuestName, activeQuest.QuestLv)
            end)
            task.wait(1)
            UpdateState("FIND_MOB")
        end
    end,

    FIND_MOB = function()
        local activeQuest = GetCurrentQuest()
        local targetMob = nil
        local shortestDist = 99999
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        if workspace:FindFirstChild("Enemies") then
            for _, mob in ipairs(workspace.Enemies:GetChildren()) do
                if mob:FindFirstChild("Humanoid") and mob:FindFirstChild("HumanoidRootPart") and mob.Humanoid.Health > 0 then
                    if string.find(mob.Name, activeQuest.Mob) then
                        local d = (mob.HumanoidRootPart.Position - hrp.Position).Magnitude
                        if d < shortestDist then
                            shortestDist = d
                            targetMob = mob
                        end
                    end
                end
            end
        end

        if targetMob then
            local mobCF = targetMob.HumanoidRootPart.CFrame * CFrame.new(0, 10, 0)
            hrp.CFrame = mobCF
            pcall(function()
                game:GetService("VirtualUser"):CaptureController()
                game:GetService("VirtualUser"):Button1Down(Vector2.new(1280, 672))
            end)
        else
            UpdateState("GET_QUEST")
        end
    end,

    RANDOM_FRUIT = function()
        UpdateState("BUYING_FRUIT")
        pcall(function()
            local CommF = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_")
            local res = CommF:InvokeServer("Cousin", "Buy")
            print("🎲 Kết quả Random Trái:", tostring(res))
        end)
        task.wait(2)
        UpdateState("IDLE")
    end
}

-- 7. Vòng lặp điều phối chính (Ưu tiên nhặt trái & cất kho tuyệt đối)
task.spawn(function()
    while FSM.Running do
        pcall(AutoStoreFruits)
        local hasFruit = CheckAndCollectFruit()

        if hasFruit then
            UpdateState("COLLECTING_FRUIT")
        else
            local baseState = string.split(FSM.State, ":")[1]
            local action = Actions[baseState] or Actions[FSM.State]
            if action then pcall(action) end
        end
        task.wait(0.25)
    end
end)
