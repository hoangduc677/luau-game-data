-- Tệp: fsm.lua (Đã liên kết toàn diện với ui.lua)
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local CONFIG_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/config.json?t=" .. tostring(os.time())
local UI_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/ui.lua?t=" .. tostring(os.time())

-- Biến toàn cục điều khiển từ UI
getgenv().DynamicSpeed = 150
local FSM = {
    State = "IDLE",
    Index = 1,
    Tween = nil,
    Running = true
}

-- 1. Nạp UI và truyền hàm callback
local okUI, UIModule = pcall(function() return loadstring(game:HttpGet(UI_URL))() end)
local Dashboard = nil

if okUI and UIModule then
    Dashboard = UIModule.CreateDashboard(
        "⚡ HỆ THỐNG KAITUN FSM", 
        function(isRunning) -- Hàm nhận sự kiện Bật/Dừng
            FSM.Running = isRunning
            if not isRunning and FSM.Tween then
                FSM.Tween:Cancel()
                FSM.Tween = nil
            end
        end,
        function(newSpeed) -- Hàm nhận sự kiện đổi Tốc độ
            getgenv().DynamicSpeed = newSpeed
            print("[UI Event] Đã đổi tốc độ bay thành:", newSpeed)
            -- Nếu đang bay, hủy tween cũ để nó áp dụng tốc độ mới ngay lập tức
            if FSM.Tween then
                FSM.Tween:Cancel()
                FSM.Tween = nil
            end
        end
    )
end

-- 2. Tải Tọa Độ
local function LoadConfig()
    local ok1, raw = pcall(function() return game:HttpGet(CONFIG_URL) end)
    if not ok1 then return nil end
    local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok2 then return nil end

    for _, loc in ipairs(data.Locations) do
        local c = loc.Coords
        loc.CFrame = CFrame.new(c[1], c[2], c[3])
    end
    return data
end

local Config = LoadConfig()
if not Config then return end

local function UpdateState(newState)
    FSM.State = newState
    if Dashboard then Dashboard.SetStatus(newState) end
end

-- 3. Hành vi FSM
local Actions = {
    IDLE = function()
        local target = Config.Locations[FSM.Index]
        if not target then
            UpdateState("COMPLETED")
            FSM.Running = false
            return
        end
        UpdateState("MOVING: " .. target.Name)
    end,

    MOVING = function()
        local target = Config.Locations[FSM.Index]
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local dist = (hrp.Position - target.CFrame.Position).Magnitude
        if dist <= 10 then
            if FSM.Tween then FSM.Tween:Cancel(); FSM.Tween = nil end
            UpdateState("WORK")
            return
        end

        if not FSM.Tween then
            local speed = getgenv().DynamicSpeed -- Lấy tốc độ linh hoạt từ UI
            FSM.Tween = TweenService:Create(hrp, TweenInfo.new(dist / speed, Enum.EasingStyle.Linear), {CFrame = target.CFrame})
            FSM.Tween:Play()
        end
    end,

    WORK = function()
        task.wait(2)
        FSM.Index += 1
        UpdateState("IDLE")
    end
}

-- 4. Vòng lặp điều phối
task.spawn(function()
    while true do
        if FSM.Running then
            local baseState = string.split(FSM.State, ":")[1]
            local action = Actions[baseState] or Actions[FSM.State]
            if action then pcall(action) end
        end
        task.wait(0.2)
    end
end)
