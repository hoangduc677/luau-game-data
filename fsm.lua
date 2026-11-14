-- Tệp: fsm.lua (Bản ép buộc chạy trực tiếp)
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local CONFIG_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/config.json?t=" .. tostring(os.time())
local QUESTS_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/quests.json?t=" .. tostring(os.time())
local UI_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/ui.lua?t=" .. tostring(os.time())

local FSM = {
    local Actions = {
    GET_QUEST = function()
        local activeQuest = GetSafeQuest()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        UpdateState("MOVING_TO_NPC")
        print("🚀 Đang bay tới NPC giao nhiệm vụ...")

        StableFlyTo(activeQuest.NPCCFrame, function()
            print("✅ Đã đến NPC! Đang gọi lệnh nhận nhiệm vụ...")
            pcall(function()
                local CommF = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_")
                CommF:InvokeServer("StartQuest", activeQuest.QuestName, activeQuest.QuestLv)
            end)
            task.wait(1)
            UpdateState("FIND_MOB")
        end)
    end,

    FIND_MOB = function()
        local activeQuest = GetSafeQuest()
        UpdateState("FARMING: " .. activeQuest.Mob)
        
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local targetMob = nil
        if workspace:FindFirstChild("Enemies") then
            for _, mob in ipairs(workspace.Enemies:GetChildren()) do
                if mob:FindFirstChild("Humanoid") and mob:FindFirstChild("HumanoidRootPart") and mob.Humanoid.Health > 0 then
                    if string.find(mob.Name, activeQuest.Mob) then
                        targetMob = mob
                        break
                    end
                end
            end
        end

        if targetMob then
            hrp.CFrame = targetMob.HumanoidRootPart.CFrame * CFrame.new(0, 12, 0)
            pcall(function()
                game:GetService("VirtualUser"):CaptureController()
                game:GetService("VirtualUser"):Button1Down(Vector2.new(1280, 672))
            end)
        else
            UpdateState("GET_QUEST")
        end
    end
}

-- 1. Nạp Giao Diện UI
local okUI, UIModule = pcall(function() return loadstring(game:HttpGet(UI_URL))() end)
local Dashboard = nil
if okUI and UIModule then
    Dashboard = UIModule.CreateDashboard("⚡ KAITUN DEBUG", function(isRunning)
        FSM.Running = isRunning
    end)
end

local function UpdateState(newState)
    FSM.State = newState
    if Dashboard then Dashboard.SetStatus(newState) end
    print("[FSM DEBUG] Đang ở trạng thái:", newState)
end

-- 2. Tải Dữ liệu Quests phòng hờ
local function LoadJSONData(url)
    local ok1, raw = pcall(function() return game:HttpGet(url) end)
    if not ok1 then return nil end
    local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok2 then return nil end
    return data
end

local QuestsData = LoadJSONData(QUESTS_URL)

-- 3. Hàm lấy Quest an toàn tuyệt đối (Không sợ lỗi dữ liệu)
local function GetSafeQuest()
    if not QuestsData or not QuestsData.Sea1 then
        -- Trả về dữ liệu cứng phòng khi mạng lỗi
        return {
            QuestName = "BanditQuest1",
            QuestLv = 1,
            Mob = "Bandit",
            NPCCFrame = CFrame.new(1059, 21, 1549)
        }
    end
    
    local q = QuestsData.Sea1[1]
    return {
        QuestName = q.QuestName,
        QuestLv = q.QuestLv,
        Mob = q.Mob,
        NPCCFrame = CFrame.new(q.NPC[1], q.NPC[2] + 5, q.NPC[3])
    }
end

-- 4. Hàm Fly ổn định
local function StableFlyTo(targetCFrame, onComplete)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if FSM.ActiveTween then
        FSM.ActiveTween:Cancel()
        FSM.ActiveTween = nil
    end

    hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    local dist = (hrp.Position - targetCFrame.Position).Magnitude
    local duration = dist / 350 -- Tốc độ bay 350

    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
    FSM.ActiveTween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
    
    FSM.ActiveTween.Completed:Connect(function(state)
        if state == Enum.PlaybackState.Completed and onComplete then
            onComplete()
        end
        FSM.ActiveTween = nil
    end)
    FSM.ActiveTween:Play()
end

-- 5. Hành vi FSM
local Actions = {
    GET_QUEST = function()
        local activeQuest = GetSafeQuest()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        UpdateState("MOVING_TO_NPC")
        print("🚀 Đang bay tới NPC giao nhiệm vụ tại tọa độ:", tostring(activeQuest.NPCCFrame.Position))

        StableFlyTo(activeQuest.NPCCFrame, function()
            print("✅ Đã đến NPC! Đang gọi lệnh nhận nhiệm vụ...")
            pcall(function()
                local CommF = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_")
                CommF:InvokeServer("StartQuest", activeQuest.QuestName, activeQuest.QuestLv)
            end)
            task.wait(1)
            UpdateState("FIND_MOB")
        end)
    end,

    FIND_MOB = function()
        local activeQuest = GetSafeQuest()
        UpdateState("FARMING: " .. activeQuest.Mob)
        
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local targetMob = nil
        if workspace:FindFirstChild("Enemies") then
            for _, mob in ipairs(workspace.Enemies:GetChildren()) do
                if mob:FindFirstChild("Humanoid") and mob:FindFirstChild("HumanoidRootPart") and mob.Humanoid.Health > 0 then
                    if string.find(mob.Name, activeQuest.Mob) then
                        targetMob = mob
                        break
                    end
                end
            end
        end

        if targetMob then
            hrp.CFrame = targetMob.HumanoidRootPart.CFrame * CFrame.new(0, 12, 0)
            pcall(function()
                game:GetService("VirtualUser"):CaptureController()
                game:GetService("VirtualUser"):Button1Down(Vector2.new(1280, 672))
            end)
        else
            print("⚠️ Chưa tìm thấy quái loại:", activeQuest.Mob, "- Đang bay lại NPC...")
            UpdateState("GET_QUEST")
        end
    end
}

-- 6. Vòng lặp chính
task.spawn(function()
    while FSM.Running do
        local action = Actions[FSM.State]
        if action then
            local success, err = pcall(action)
            if not success then
                warn("❌ Lỗi thực thi trạng thái:", err)
            end
        end
        task.wait(1)
    end
end)
