-- Tệp: fsm.lua (Quản lý lộ trình di chuyển tuần tự)
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local CONFIG_URL = "https://raw.githubusercontent.com/hoangduc677/luau-game-data/main/config.json?t=" .. tostring(os.time())

-- 1. Hàm tải dữ liệu từ file config.json của bạn
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

-- 2. Khởi tạo bộ não điều khiển trạng thái (FSM)
local FSM = {
    State = "IDLE",     -- Trạng thái hiện tại
    Index = 1,          -- Đang đi tới điểm thứ mấy (1 là Zone_1, 2 là Zone_2)
    Tween = nil,        -- Lưu lệnh bay để không gọi trùng
    Running = true
}

-- 3. Các hành động tương ứng với từng trạng thái
local Actions = {
    IDLE = function()
        local target = Config.Locations[FSM.Index]
        if not target then
            FSM.State = "DONE"
            return
        end
        print("🎯 Chuẩn bị đi tới:", target.Name)
        FSM.State = "MOVING"
    end,

    MOVING = function()
        local target = Config.Locations[FSM.Index]
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local dist = (hrp.Position - target.CFrame.Position).Magnitude
        if dist <= 10 then
            if FSM.Tween then FSM.Tween:Cancel(); FSM.Tween = nil end
            FSM.State = "WORK"
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
        print("⚡ Đã tới nơi:", target.Name, "- Đang xử lý (chờ 2 giây)...")
        task.wait(2)
        FSM.Index += 1      -- Chuyển sang điểm tiếp theo
        FSM.State = "IDLE"  -- Quay lại trạng thái IDLE để kiểm tra điểm mới
    end,

    DONE = function()
        print("🏁 Hoàn thành toàn bộ lộ trình!")
        FSM.Running = false
    end
}

-- 4. Vòng lặp trung tâm duy nhất
task.spawn(function()
    while FSM.Running do
        if Actions[FSM.State] then
            pcall(Actions[FSM.State])
        end
        task.wait(0.2)
    end
end)
