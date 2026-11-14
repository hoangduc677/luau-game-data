-- Tệp: fsm.lua (Đã tích hợp giao diện ui.lua)
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local CONFIG_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/config.json?t=" .. tostring(os.time())
local UI_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/ui.lua?t=" .. tostring(os.time())

-- 1. Nạp Module Giao Diện từ GitHub của bạn
local okUI, UIModule = pcall(function()
    return loadstring(game:HttpGet(UI_URL))()
end)

local Dashboard = nil
if okUI and UIModule then
    -- Tạo bảng điều khiển với tiêu đề "HỆ THỐNG KAITUN FSM"
    Dashboard = UIModule.CreateDashboard("⚡ HỆ THỐNG KAITUN FSM", function(isRunning)
        -- Xử lý khi bấm nút Bật/Dừng trên UI
        -- (Có thể gán biến FSM.Running = isRunning ở đây nếu muốn)
    end)
else
    warn("⚠️ Không thể tải giao diện ui.lua, tiếp tục chạy chế độ ẩn.")
end

-- 2. Tải Dữ Liệu Tọa Độ
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

-- 3. Khởi tạo FSM
local FSM = {
    State = "IDLE",
    Index = 1,
    Tween = nil,
    Running = true
}

-- Hàm cập nhật trạng thái ra màn hình giao diện
local function UpdateState(newState)
    FSM.State = newState
    if Dashboard then
        Dashboard.SetStatus(newState)
    end
    print("[FSM Status]:", newState)
end

-- 4. Hành vi các trạng thái
local Actions = {
    IDLE = function()
        local target = Config.Locations[FSM.Index]
        if not target then
            UpdateState("DONE")
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
            local speed = Config.Settings.MoveSpeed or 150
            FSM.Tween = TweenService:Create(hrp, TweenInfo.new(dist / speed, Enum.EasingStyle.Linear), {CFrame = target.CFrame})
            FSM.Tween:Play()
        end
    end,

    WORK = function()
        local target = Config.Locations[FSM.Index]
        task.wait(2) -- Giả lập thời gian làm việc tại chỗ
        FSM.Index += 1
        UpdateState("IDLE")
    end,

    DONE = function()
        UpdateState("COMPLETED")
        FSM.Running = false
    end
}

-- 5. Vòng lặp điều phối
task.spawn(function()
    while FSM.Running do
        -- Xử lý chuỗi trạng thái bắt đầu bằng MOVING
        local baseState = string.split(FSM.State, ":")[1]
        local action = Actions[baseState] or Actions[FSM.State]
        
        if action then
            pcall(action)
        end
        task.wait(0.2)
    end
end)
