-- Tệp: fsm.lua (Thêm logic kiểm tra Level và chọn Quest tự động)
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

-- 1. Nạp UI điều khiển
local okUI, UIModule = pcall(function() return loadstring(game:HttpGet(UI_URL))() end)
local Dashboard = nil
if okUI and UIModule then
    Dashboard = UIModule.CreateDashboard("⚡ KAITUN AUTO QUEST", 
        function(isRunning) FSM.Running = isRunning end,
        function(newSpeed) getgenv().DynamicSpeed = newSpeed end
    )
end

-- 2. Tải dữ liệu Tọa độ chung và Nhiệm vụ từ GitHub
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
    warn("❌ Không thể tải file dữ liệu từ GitHub!")
    return
end

-- 3. Hàm tự động quét Level hiện tại để chọn Quest chuẩn xác
local function GetCurrentQuest()
    -- Lấy level của người chơi (Mặc định trả về 1 nếu chưa load dữ liệu game)
    local level = 1
    pcall(function()
        level = LocalPlayer.Data.Level.Value
    end)

    -- Xác định Sea dựa trên Level hoặc gộp toàn bộ danh sách để quét
    local allQuests = {}
    if QuestsData.Sea1 then for _, q in ipairs(QuestsData.Sea1) do table.insert(allQuests, q) end end
    if QuestsData.Sea2 then for _, q in ipairs(QuestsData.Sea2) do table.insert(allQuests, q) end end
    if QuestsData.Sea3 then for _, q in ipairs(QuestsData.Sea3) do table.insert(allQuests, q) end end

    -- Tìm nhiệm vụ phù hợp với level cao nhất mà nhân vật đạt được
    local bestQuest = allQuests[1]
    for _, q in ipairs(allQuests) do
        if level >= q.MinLv then
            bestQuest = q
        end
    end

    -- Chuyển đổi tọa độ NPC từ mảng [X, Y, Z] sang CFrame
    if bestQuest and bestQuest.NPC then
        bestQuest.NPCCFrame = CFrame.new(bestQuest.NPC[1], bestQuest.NPC[2], bestQuest.NPC[3])
    end

    return bestQuest
end

local function UpdateState(newState)
    FSM.State = newState
    if Dashboard then Dashboard.SetStatus(newState) end
end

-- 4. FSM Logic cập nhật theo nhiệm vụ động
local Actions = {
    IDLE = function()
        local activeQuest = GetCurrentQuest()
        if not activeQuest then
            UpdateState("COMPLETED")
            return
        end
        print("📜 Đang làm nhiệm vụ đánh quái:", activeQuest.Mob, "| Level yêu cầu:", activeQuest.MinLv)
        UpdateState("GET_QUEST: " .. activeQuest.Mob)
    end,

    GET_QUEST = function()
        local activeQuest = GetCurrentQuest()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        -- Bay tới NPC nhận nhiệm vụ
        local dist = (hrp.Position - activeQuest.NPCCFrame.Position).Magnitude
        if dist > 15 then
            local speed = getgenv().DynamicSpeed
            -- Tween tới NPC
            local tween = TweenService:Create(hrp, TweenInfo.new(dist / speed, Enum.EasingStyle.Linear), {CFrame = activeQuest.NPCCFrame})
            tween:Play()
            task.wait(dist / speed)
        else
            -- Đã tới gần NPC -> Gọi Remote nhận nhiệm vụ
            pcall(function()
                local CommF = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("CommF_")
                CommF:InvokeServer("StartQuest", activeQuest.QuestName, activeQuest.QuestLv)
            end)
            task.wait(1)
            UpdateState("FARMING")
        end
    end,

    FARMING = function()
        -- Trạng thái này sẽ tìm quái dựa theo activeQuest.Mob ở bước sau
        UpdateState("FIND_MOB")
    end,

    FIND_MOB = function()
        local activeQuest = GetCurrentQuest()
        local targetMob = nil
        local shortestDist = 99999
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

        if not hrp then return end

        -- Quét thư mục Enemies trong workspace để tìm đúng loại quái nhiệm vụ
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
            -- Bay tới đầu quái và đánh
            local mobCF = targetMob.HumanoidRootPart.CFrame * CFrame.new(0, 10, 0)
            hrp.CFrame = mobCF
            
            -- Gửi lệnh tấn công giả lập
            pcall(function()
                game:GetService("VirtualUser"):CaptureController()
                game:GetService("VirtualUser"):Button1Down(Vector2.new(1280, 672))
            end)
        else
            -- Nếu chưa thấy quái, bay về bãi quái mặc định trong config.json hoặc chờ
            UpdateState("GET_QUEST")
        end
    end
}

-- 5. Vòng lặp điều phối trung tâm
task.spawn(function()
    while FSM.Running do
        local baseState = string.split(FSM.State, ":")[1]
        local action = Actions[baseState] or Actions[FSM.State]
        if action then 
            pcall(action) 
        end
        task.wait(0.2)
    end
end)
