-- fsm.lua
-- Máy trạng thái hữu hạn (FSM) cho hệ thống auto-farm Blox Fruits (Sea 1)
-- Đảm bảo chuyển trạng thái mượt mà: IDLE -> GET_QUEST -> FARM_MOB -> ...

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- ==================== CẤU HÌNH ====================
local CONFIG = {
    FlySpeed = 150,                -- studs/giây
    QuestCheckDelay = 0.5,         -- thời gian chờ GUI cập nhật sau khi StartQuest
    FarmRetryDelay = 2,            -- thời gian chờ trước khi thử lại nếu kẹt
    MaxQuestRetries = 3,           -- số lần thử nhận quest tối đa
    MobOffsetY = 5,                -- khoảng cách phía trên quái để đứng farm
}

-- ==================== BIẾN TOÀN CỤC ====================
local State = "IDLE"
local ActiveTween = nil
local isRunning = true
local currentQuest = nil
local questRetryCount = 0

-- ==================== HÀM TIỆN ÍCH ====================

-- Lấy nhân vật và HumanoidRootPart một cách an toàn
local function getCharacter()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    return char, hrp
end

-- Kiểm tra quest đang hoạt động (an toàn, có pcall)
local function HasActiveQuest()
    local success, result = pcall(function()
        local gui = LocalPlayer:FindFirstChild("PlayerGui")
        if not gui then return false end
        local main = gui:FindFirstChild("Main")
        if not main then return false end
        local quest = main:FindFirstChild("Quest")
        if not quest then return false end
        return quest.Visible == true
    end)
    return success and result
end

-- Dừng tween hiện tại (nếu có) để tránh xung đột
local function stopActiveTween()
    if ActiveTween then
        ActiveTween:Cancel()
        ActiveTween = nil
    end
end

-- Bay tới một CFrame với tốc độ cố định, có thể dừng ngay khi isRunning = false
local function flyTo(targetCFrame, speed)
    stopActiveTween()
    if not isRunning then return end

    local char, hrp = getCharacter()
    if not hrp then return end

    -- Đảm bảo nhân vật không bị rơi hoặc trượt
    hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

    local distance = (targetCFrame.Position - hrp.Position).Magnitude
    if distance < 1 then return end -- đã ở vị trí

    local tweenInfo = TweenInfo.new(
        distance / speed,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.Out
    )

    ActiveTween = TweenService:Create(hrp, tweenInfo, { CFrame = targetCFrame })
    ActiveTween:Play()
    ActiveTween.Completed:Wait()

    ActiveTween = nil
end

-- Chuyển trạng thái (có log để dễ debug)
local function setState(newState)
    if State ~= newState then
        print(string.format("[FSM] %s -> %s", State, newState))
        State = newState
    end
end

-- ==================== CÁC TRẠNG THÁI ====================

-- IDLE: chờ đến khi isRunning = true và có nhiệm vụ cần làm
local function stateIdle()
    stopActiveTween()
    task.wait(0.5)
    if not isRunning then return end

    if HasActiveQuest() then
        setState("FARM_MOB")
    else
        setState("GET_QUEST")
    end
end

-- GET_QUEST: bay tới NPC, nhận nhiệm vụ, rồi chuyển sang FARM_MOB
local function stateGetQuest()
    if not isRunning then setState("IDLE") return end

    -- Lấy dữ liệu nhiệm vụ phù hợp (giả sử có module quests)
    local quests = require(ReplicatedStorage:WaitForChild("quests")) -- hoặc load từ JSON
    local playerLevel = LocalPlayer.Data.Level.Value
    local selectedQuest = nil
    for _, q in ipairs(quests) do
        if playerLevel >= q.MinLv and playerLevel <= q.QuestLv then
            selectedQuest = q
            break
        end
    end

    if not selectedQuest then
        warn("[FSM] Không tìm thấy quest phù hợp với level", playerLevel)
        setState("IDLE")
        return
    end

    currentQuest = selectedQuest

    -- Bay tới NPC
    local npcCFrame = CFrame.new(table.unpack(selectedQuest.NPC))
    flyTo(npcCFrame, CONFIG.FlySpeed)

    if not isRunning then setState("IDLE") return end

    -- Gọi nhận quest
    local success, err = pcall(function()
        ReplicatedStorage.Remotes.CommF_:InvokeServer(
            "StartQuest",
            selectedQuest.QuestName,
            selectedQuest.QuestLv
        )
    end)

    if not success then
        warn("[FSM] Lỗi khi gọi StartQuest:", err)
        setState("IDLE")
        return
    end

    -- QUAN TRỌNG: chờ GUI cập nhật
    task.wait(CONFIG.QuestCheckDelay)

    -- Kiểm tra lại xem quest đã thực sự hoạt động chưa
    if HasActiveQuest() then
        print("[FSM] Nhận quest thành công:", selectedQuest.QuestName)
        questRetryCount = 0
        setState("FARM_MOB")
    else
        questRetryCount = questRetryCount + 1
        warn(string.format("[FSM] Quest chưa kích hoạt (lần thử %d/%d)", questRetryCount, CONFIG.MaxQuestRetries))
        if questRetryCount >= CONFIG.MaxQuestRetries then
            questRetryCount = 0
            setState("IDLE")
        else
            -- Thử lại ngay mà không cần chuyển trạng thái
            task.wait(0.5)
            setState("GET_QUEST")
        end
    end
end

-- FARM_MOB: bay tới bãi quái, giữ vị trí, và đánh quái
local function stateFarmMob()
    if not isRunning then setState("IDLE") return end

    if not currentQuest then
        setState("GET_QUEST")
        return
    end

    -- Nếu quest đã hoàn thành (GUI ẩn), quay lại nhận quest mới
    if not HasActiveQuest() then
        print("[FSM] Quest hoàn thành hoặc đã mất, quay lại GET_QUEST")
        setState("GET_QUEST")
        return
    end

    -- Bay tới vị trí quái (cao hơn MobCFrame một chút)
    local mobPos = Vector3.new(table.unpack(currentQuest.MobPos))
    local targetCFrame = CFrame.new(mobPos + Vector3.new(0, CONFIG.MobOffsetY, 0))
    flyTo(targetCFrame, CONFIG.FlySpeed)

    if not isRunning then setState("IDLE") return end

    -- Giữ vị trí ổn định phía trên quái
    local char, hrp = getCharacter()
    if hrp then
        hrp.CFrame = targetCFrame
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    end

    -- Tự động trang bị vũ khí và đánh quái
    -- (Giả sử có hàm autoEquipWeapon và attackMob từ module khác)
    -- Ở đây chỉ minh họa vòng lặp đánh quái
    local attackEndTime = tick() + 5 -- đánh trong 5 giây rồi kiểm tra lại quest
    while isRunning and tick() < attackEndTime do
        -- TODO: gọi hàm đánh quái thực tế
        -- attackMob()
        task.wait(0.1)
    end

    -- Sau khi đánh xong, kiểm tra lại quest
    if HasActiveQuest() then
        -- Vẫn còn quest, tiếp tục farm (lặp lại)
        task.wait(CONFIG.FarmRetryDelay)
    else
        setState("GET_QUEST")
    end
end

-- RANDOM_FRUIT: (giữ nguyên logic cũ, chỉ minh họa)
local function stateRandomFruit()
    if not isRunning then setState("IDLE") return end
    -- TODO: logic random fruit
    task.wait(1)
    setState("IDLE")
end

-- SEA2_QUEST: (giữ nguyên logic cũ, chỉ minh họa)
local function stateSea2Quest()
    if not isRunning then setState("IDLE") return end
    -- TODO: logic Sea 2
    task.wait(1)
    setState("IDLE")
end

-- ==================== VÒNG LẶP CHÍNH ====================
local stateHandlers = {
    IDLE = stateIdle,
    GET_QUEST = stateGetQuest,
    FARM_MOB = stateFarmMob,
    RANDOM_FRUIT = stateRandomFruit,
    SEA2_QUEST = stateSea2Quest,
}

local function mainLoop()
    while true do
        if not isRunning then
            stopActiveTween()
            setState("IDLE")
            task.wait(0.5)
        else
            local handler = stateHandlers[State]
            if handler then
                handler()
            else
                warn("[FSM] Trạng thái không hợp lệ:", State)
                setState("IDLE")
            end
        end
        task.wait(0.05)
    end
end

-- Khởi chạy vòng lặp
task.spawn(mainLoop)

-- ==================== API ĐIỀU KHIỂN TỪ BÊN NGOÀI ====================
return {
    SetRunning = function(value)
        isRunning = value
        if not value then
            stopActiveTween()
        end
    end,
    GetState = function()
        return State
    end,
    SetStatus = function(text)
        -- Gọi UI.SetStatus nếu có
    end,
}