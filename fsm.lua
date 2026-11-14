-- Tệp: fsm.lua (Tối ưu hóa cơ chế Fly ổn định & Giao diện gọn gàng)
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local CONFIG_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/config.json?t=" .. tostring(os.time())
local QUESTS_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/quests.json?t=" .. tostring(os.time())
local UI_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/ui.lua?t=" .. tostring(os.time())

local FSM = {
    State = "IDLE",
    Running = true,
    ActiveTween = nil
}

-- 1. Nạp Giao Diện UI Gọn Gàng
local okUI, UIModule = pcall(function() return loadstring(game:HttpGet(UI_URL))() end)
local Dashboard = nil
if okUI and UIModule then
    Dashboard = UIModule.CreateDashboard("⚡ KAITUN BLOX FRUITS", function(isRunning)
        FSM.Running = isRunning
        if not isRunning and FSM.ActiveTween then
            FSM.ActiveTween:Cancel()
            FSM.ActiveTween = nil
        end
    end)
end

-- 2. Tải Dữ liệu JSON từ GitHub
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

-- 3. Lấy Quest chuẩn theo Level
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
        bestQuest.NPCCFrame = CFrame.new(bestQuest.NPC[1], bestQuest.NPC[2] + 5, bestQuest.NPC[3])
    end
    return bestQuest
end

-- 4. Hàm Fly ổn định siêu mượt (Tự động khóa trọng lực & tạo Tween an toàn)
local function StableFlyTo(targetCFrame, onComplete)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if FSM.ActiveTween then
        FSM.ActiveTween:Cancel()
        FSM.ActiveTween = nil
    end

    -- Khóa chuyển động vật lý thông thường để tránh bị đẩy lệch hướng khi bay
    hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    
    local dist = (hrp.Position - targetCFrame.Position).Magnitude
    local flySpeed = 350 -- Tốc độ bay ổn định (studs/s)
    local duration = dist / flySpeed

    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
    FSM.ActiveTween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
    
    FSM.ActiveTween.Completed:Connect(function(playbackState)
        if playbackState == Enum.PlaybackState.Completed then
            if onComplete then onComplete() end
        end
        FSM.ActiveTween = nil
    end)

    FSM.ActiveTween:Play()
end

-- 5. Hàm Nhặt Trái & Cất Kho
local function CheckAndCollectFruit()
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Tool") and obj:FindFirstChild("Handle") then
            if string.find(obj.Name, "Fruit") then
                local fruitPart = obj.Handle
                StableFlyTo(fruitPart.CFrame + Vector3.new(0, 5, 0))
                return true
            end
        end
    end
    return false
end

local function AutoStoreFruits()
    pcall(function()
        local backpack = LocalPlayer.Backpack
        local character = LocalPlayer.Character
        local CommF = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_")

        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") and string.find(item.Name, "Fruit") then
                CommF:InvokeServer("StoreFruit", item.Name)
            end
        end
        if character then
            for _, item in ipairs(character:GetChildren()) do
                if item:IsA("Tool") and string.find(item.Name, "Fruit") then
                    CommF:InvokeServer("StoreFruit", item.Name)
                end
            end
        end
    end)
end

-- 6. Trạng thái FSM
local Actions = {
    IDLE = function()
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
        UpdateState("GET_QUEST: " + activeQuest.Mob)
    end,

    GET_QUEST = function()
        local activeQuest = GetCurrentQuest()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local dist = (hrp.Position - activeQuest.NPCCFrame.Position).Magnitude
        if dist > 15 then
            StableFlyTo(activeQuest.NPCCFrame, function()
                pcall(function()
                    local CommF = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_")
                    CommF:InvokeServer("StartQuest", activeQuest.QuestName, activeQuest.QuestLv)
                end)
            end)
            task.wait(1)
        else
            pcall(function()
                local CommF = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_")
                CommF:InvokeServer("StartQuest", activeQuest.QuestName, activeQuest.QuestLv)
            end)
            task.wait(0.5)
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
            local mobCF = targetMob.HumanoidRootPart.CFrame * CFrame.new(0, 12, 0)
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
            CommF:InvokeServer("Cousin", "Buy")
        end)
        task.wait(2)
        UpdateState("IDLE")
    end
}

-- 7. Vòng lặp điều phối chính
task.spawn(function()
    while FSM.Running do
        pcall(AutoStoreFruits)
        local hasFruit = CheckAndCollectFruit()

        if not hasFruit then
            local baseState = string.split(FSM.State, ":")[1]
            local action = Actions[baseState] or Actions[FSM.State]
            if action then pcall(action) end
        else
            UpdateState("COLLECTING_FRUIT")
        end
        task.wait(0.2)
    end
end)
