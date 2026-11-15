-- ui.lua — Dashboard UI (Raw Instance, không dùng library ngoài)
local Players = game:GetService("Players")
local UserInput = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local Theme = {
    Bg      = Color3.fromRGB(20, 20, 25),
    BgPanel = Color3.fromRGB(30, 30, 38),
    Accent  = Color3.fromRGB(80, 180, 255),
    Text    = Color3.fromRGB(240, 240, 240),
    TextDim = Color3.fromRGB(160, 160, 170),
    Green   = Color3.fromRGB(80, 220, 120),
    Red     = Color3.fromRGB(230, 80, 80),
    Font    = Enum.Font.GothamMedium,
    FontBold= Enum.Font.GothamBold,
}

local UI = {}
UI.FSM = nil
UI.isRunning = true
UI._gui = nil
UI._statusLabel = nil
UI._subLabel = nil
UI._toggleBtn = nil
UI._mainFrame = nil

-- ✅ Fallback 3 lớp parent
local function parentSafe(gui)
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then
            gui.Parent = hui
            return "gethui"
        end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then
        local ok2 = pcall(function() gui.Parent = cg end)
        if ok2 and gui.Parent == cg then return "CoreGui" end
    end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        gui.Parent = pg
        return "PlayerGui"
    end
    return nil
end

local function createGUI()
    if UI._gui and UI._gui.Parent then
        UI._gui:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name           = "KaitunUI"
    gui.ResetOnSpawn   = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder   = 999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    if not parentSafe(gui) then
        warn("[UI] Không thể parent ScreenGui — executor chặn GUI")
        return nil
    end
    UI._gui = gui

    local main = Instance.new("Frame")
    main.Name             = "Main"
    main.Size             = UDim2.new(0, 240, 0, 120)
    main.Position         = UDim2.new(0, 20, 0, 20)
    main.BackgroundColor3 = Theme.Bg
    main.BorderSizePixel  = 0
    main.Active           = true
    main.Parent           = gui
    UI._mainFrame = main

    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Theme.Accent
    stroke.Thickness = 1
    stroke.Transparency = 0.5

    -- Title
    local title = Instance.new("Frame")
    title.Name             = "Title"
    title.Size             = UDim2.new(1, 0, 0, 28)
    title.BackgroundColor3 = Theme.BgPanel
    title.BorderSizePixel  = 0
    title.Parent           = main
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

    local titleText = Instance.new("TextLabel")
    titleText.Text              = "⚡ KAITUN"
    titleText.Font              = Theme.FontBold
    titleText.TextSize          = 13
    titleText.TextColor3        = Theme.Accent
    titleText.BackgroundTransparency = 1
    titleText.Position          = UDim2.new(0, 10, 0, 0)
    titleText.Size              = UDim2.new(1, -20, 1, 0)
    titleText.TextXAlignment    = Enum.TextXAlignment.Left
    titleText.Parent            = title

    -- Status
    local status = Instance.new("TextLabel")
    status.Name             = "Status"
    status.Text             = "State: IDLE"
    status.Font             = Theme.Font
    status.TextSize         = 13
    status.TextColor3       = Theme.Text
    status.BackgroundTransparency = 1
    status.Position         = UDim2.new(0, 10, 0, 36)
    status.Size             = UDim2.new(1, -20, 0, 22)
    status.TextXAlignment   = Enum.TextXAlignment.Left
    status.Parent           = main
    UI._statusLabel = status

    -- Sub status
    local sub = Instance.new("TextLabel")
    sub.Name             = "Sub"
    sub.Text             = "Level: — | Quest: —"
    sub.Font             = Theme.Font
    sub.TextSize         = 11
    sub.TextColor3       = Theme.TextDim
    sub.BackgroundTransparency = 1
    sub.Position         = UDim2.new(0, 10, 0, 58)
    sub.Size             = UDim2.new(1, -20, 0, 16)
    sub.TextXAlignment   = Enum.TextXAlignment.Left
    sub.Parent           = main
    UI._subLabel = sub

    -- Toggle button
    local btn = Instance.new("TextButton")
    btn.Name             = "Toggle"
    btn.Text             = "STOP"
    btn.Font             = Theme.FontBold
    btn.TextSize         = 13
    btn.TextColor3       = Theme.Text
    btn.BackgroundColor3 = Theme.Green
    btn.BorderSizePixel  = 0
    btn.Position         = UDim2.new(0, 10, 1, -38)
    btn.Size             = UDim2.new(1, -20, 0, 28)
    btn.AutoButtonColor  = false
    btn.Parent           = main
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    UI._toggleBtn = btn

    -- Drag
    local dragging, dragStart, startPos
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    title.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInput.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    -- Toggle handler
    btn.MouseButton1Click:Connect(function()
        UI.isRunning = not UI.isRunning
        if UI.FSM and UI.FSM.SetRunning then
            pcall(function() UI.FSM.SetRunning(UI.isRunning) end)
        end
        if UI.isRunning then
            btn.Text = "STOP"
            TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundColor3 = Theme.Green }):Play()
        else
            btn.Text = "START"
            TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundColor3 = Theme.Red }):Play()
        end
    end)

    return gui
end

function UI.SetStatus(text)
    if UI._statusLabel and UI._statusLabel.Parent then
        UI._statusLabel.Text = text or "State: —"
    end
end

function UI.SetSubStatus(level, questName)
    if UI._subLabel and UI._subLabel.Parent then
        UI._subLabel.Text = string.format("Level: %s | Quest: %s",
            tostring(level or "—"), tostring(questName or "—"))
    end
end

function UI.Init(fsm)
    UI.FSM = fsm
    UI.isRunning = true
    createGUI()

    task.spawn(function()
        while UI._gui and UI._gui.Parent do
            if UI.FSM then
                local ok, st = pcall(function() return UI.FSM.GetState() end)
                if ok and st then UI.SetStatus("State: " .. tostring(st)) end

                local okQ, q = pcall(function() return UI.FSM.GetQuest() end)
                if okQ and q then
                    local lv = "—"
                    pcall(function() lv = LocalPlayer.Data.Level.Value end)
                    UI.SetSubStatus(lv, q.QuestName)
                end
            end
            task.wait(0.5)
        end
    end)

    task.spawn(function()
        while UI._gui and UI._gui.Parent do
            if UI.FSM and UI.FSM.IsRunning then
                local running = UI.FSM.IsRunning()
                if running ~= UI.isRunning then
                    UI.isRunning = running
                    if UI._toggleBtn then
                        UI._toggleBtn.Text = running and "STOP" or "START"
                        UI._toggleBtn.BackgroundColor3 = running and Theme.Green or Theme.Red
                    end
                end
            end
            task.wait(0.3)
        end
    end)

    return UI
end

function UI.Destroy()
    if UI._gui then
        pcall(function() UI._gui:Destroy() end)
        UI._gui = nil
    end
end

return UI