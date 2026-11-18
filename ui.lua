-- ============================================================
-- ui.lua  |  Kaitun Dashboard
-- Module trả về bảng UI với SetStatus(), SetActiveTween(),
-- IsRunning() để FSM giao tiếp không phụ thuộc lẫn nhau.
-- ============================================================

local Players        = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer    = Players.LocalPlayer
local PlayerGui      = LocalPlayer:WaitForChild("PlayerGui")

-- ── Xóa instance cũ khi re-inject ──────────────────────────
if PlayerGui:FindFirstChild("KaitunDashboard") then
    PlayerGui.KaitunDashboard:Destroy()
end

-- ── Root ScreenGui ──────────────────────────────────────────
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name               = "KaitunDashboard"
ScreenGui.ResetOnSpawn       = false
ScreenGui.IgnoreGuiInset     = true
ScreenGui.DisplayOrder       = 999
ScreenGui.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent             = PlayerGui

-- ── Helpers ─────────────────────────────────────────────────
local function mkCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = parent
end

local function mkLabel(parent, props)
    local lbl = Instance.new("TextLabel")
    for k, v in pairs(props) do lbl[k] = v end
    lbl.Parent = parent
    return lbl
end

-- ── Main Frame ──────────────────────────────────────────────
local Frame = Instance.new("Frame")
Frame.Name              = "MainFrame"
Frame.Size              = UDim2.new(0, 230, 0, 120)
Frame.Position          = UDim2.new(0, 12, 0.5, -60)
Frame.BackgroundColor3  = Color3.fromRGB(14, 14, 24)
Frame.BorderSizePixel   = 0
Frame.Active            = true
Frame.Parent            = ScreenGui
mkCorner(Frame, 10)

-- stroke
local stroke = Instance.new("UIStroke")
stroke.Color      = Color3.fromRGB(80, 80, 160)
stroke.Thickness  = 1
stroke.Parent     = Frame

-- ── Title bar ───────────────────────────────────────────────
local TitleBar = Instance.new("Frame")
TitleBar.Name             = "TitleBar"
TitleBar.Size             = UDim2.new(1, 0, 0, 32)
TitleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 55)
TitleBar.BorderSizePixel  = 0
TitleBar.Parent           = Frame
mkCorner(TitleBar, 10)

-- patch bottom corners of title bar
local patch = Instance.new("Frame")
patch.Size             = UDim2.new(1, 0, 0, 10)
patch.Position         = UDim2.new(0, 0, 1, -10)
patch.BackgroundColor3 = Color3.fromRGB(28, 28, 55)
patch.BorderSizePixel  = 0
patch.Parent           = TitleBar

mkLabel(TitleBar, {
    Size               = UDim2.new(1, -8, 1, 0),
    Position           = UDim2.new(0, 8, 0, 0),
    BackgroundTransparency = 1,
    Text               = "⚡  KAITUN",
    TextColor3         = Color3.fromRGB(255, 215, 0),
    TextSize           = 14,
    Font               = Enum.Font.GothamBold,
    TextXAlignment     = Enum.TextXAlignment.Left,
})

-- ── Status label ─────────────────────────────────────────────
local StatusLabel = mkLabel(Frame, {
    Name               = "StatusLabel",
    Size               = UDim2.new(1, -12, 0, 24),
    Position           = UDim2.new(0, 6, 0, 36),
    BackgroundTransparency = 1,
    Text               = "State: IDLE",
    TextColor3         = Color3.fromRGB(160, 230, 160),
    TextSize           = 12,
    Font               = Enum.Font.Gotham,
    TextXAlignment     = Enum.TextXAlignment.Left,
    TextTruncate       = Enum.TextTruncate.AtEnd,
})

-- ── Level / Beli info ────────────────────────────────────────
local InfoLabel = mkLabel(Frame, {
    Name               = "InfoLabel",
    Size               = UDim2.new(1, -12, 0, 20),
    Position           = UDim2.new(0, 6, 0, 60),
    BackgroundTransparency = 1,
    Text               = "Lv: --  |  Beli: --",
    TextColor3         = Color3.fromRGB(160, 160, 220),
    TextSize           = 11,
    Font               = Enum.Font.Gotham,
    TextXAlignment     = Enum.TextXAlignment.Left,
})

-- ── Toggle Button ────────────────────────────────────────────
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Name              = "ToggleBtn"
ToggleBtn.Size              = UDim2.new(1, -12, 0, 28)
ToggleBtn.Position          = UDim2.new(0, 6, 0, 84)
ToggleBtn.BackgroundColor3  = Color3.fromRGB(0, 180, 80)
ToggleBtn.BorderSizePixel   = 0
ToggleBtn.Text              = "▶  START"
ToggleBtn.TextColor3        = Color3.fromRGB(255, 255, 255)
ToggleBtn.TextSize          = 13
ToggleBtn.Font              = Enum.Font.GothamBold
ToggleBtn.AutoButtonColor   = false
ToggleBtn.Parent            = Frame
mkCorner(ToggleBtn, 6)

-- ── State variables ──────────────────────────────────────────
local isRunning   = false
local ActiveTween = nil

-- hover tint
ToggleBtn.MouseEnter:Connect(function()
    ToggleBtn.BackgroundColor3 = isRunning
        and Color3.fromRGB(255, 70, 70)
        or  Color3.fromRGB(0, 220, 100)
end)
ToggleBtn.MouseLeave:Connect(function()
    ToggleBtn.BackgroundColor3 = isRunning
        and Color3.fromRGB(220, 50, 50)
        or  Color3.fromRGB(0, 180, 80)
end)

ToggleBtn.MouseButton1Click:Connect(function()
    isRunning = not isRunning
    if isRunning then
        ToggleBtn.Text             = "⏹  STOP"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
        StatusLabel.Text           = "State: IDLE"
        StatusLabel.TextColor3     = Color3.fromRGB(160, 230, 160)
    else
        ToggleBtn.Text             = "▶  START"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 80)
        StatusLabel.Text           = "State: Stopped"
        StatusLabel.TextColor3     = Color3.fromRGB(220, 180, 100)
        if ActiveTween then
            ActiveTween:Cancel()
            ActiveTween = nil
        end
    end
end)

-- ── Drag ─────────────────────────────────────────────────────
do
    local dragging, dragInput, dragStart, startPos

    TitleBar.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging  = true
            dragStart = inp.Position
            startPos  = Frame.Position
            inp.Changed:Connect(function()
                if inp.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    TitleBar.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = inp
        end
    end)

    UserInputService.InputChanged:Connect(function(inp)
        if inp == dragInput and dragging then
            local d = inp.Position - dragStart
            Frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
end

-- ── Public API ───────────────────────────────────────────────
local UI = {}

function UI.SetStatus(text)
    StatusLabel.Text = "State: " .. tostring(text)
end

function UI.SetInfo(lv, beli)
    InfoLabel.Text = string.format("Lv: %d  |  Beli: %s",
        lv or 0,
        beli and string.format("%d", beli) or "--"
    )
end

function UI.SetActiveTween(tween)
    ActiveTween = tween
end

function UI.IsRunning()
    return isRunning
end

return UI
