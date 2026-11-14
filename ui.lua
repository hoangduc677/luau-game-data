-- Tệp: ui.lua (Module Giao diện dùng chung)
local CoreGui = game:GetService("CoreGui")
local UI = {}

function UI.CreateDashboard(titleText, onToggleCallback)
    local parent = (gethui and gethui()) or CoreGui
    if parent:FindFirstChild("MeowModularUI") then
        parent.MeowModularUI:Destroy()
    end

    local gui = Instance.new("ScreenGui", parent)
    gui.Name = "MeowModularUI"
    gui.ResetOnSpawn = false

    local main = Instance.new("Frame", gui)
    main.Size = UDim2.new(0, 240, 0, 115)
    main.Position = UDim2.new(0.5, -120, 0.12, 0)
    main.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
    main.Active = true
    main.Draggable = true
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(65, 130, 255)
    stroke.Thickness = 1.2

    local title = Instance.new("TextLabel", main)
    title.Size = UDim2.new(1, 0, 0, 28)
    title.BackgroundTransparency = 1
    title.Text = titleText or "CONTROL PANEL"
    title.TextColor3 = Color3.fromRGB(100, 170, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12

    local status = Instance.new("TextLabel", main)
    status.Size = UDim2.new(0.9, 0, 0, 24)
    status.Position = UDim2.new(0.05, 0, 0, 32)
    status.BackgroundTransparency = 1
    status.Text = "State: IDLE"
    status.TextColor3 = Color3.fromRGB(220, 220, 230)
    status.Font = Enum.Font.GothamMedium
    status.TextSize = 11

    local btn = Instance.new("TextButton", main)
    btn.Size = UDim2.new(0.9, 0, 0, 34)
    btn.Position = UDim2.new(0.05, 0, 0, 66)
    btn.BackgroundColor3 = Color3.fromRGB(45, 165, 95)
    btn.Text = "ĐANG CHẠY (Bấm để dừng)"
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local isRunning = true
    btn.MouseButton1Click:Connect(function()
        isRunning = not isRunning
        btn.Text = isRunning and "ĐANG CHẠY (Bấm để dừng)" or "ĐÃ TẠM DỪNG (Bấm để chạy)"
        btn.BackgroundColor3 = isRunning and Color3.fromRGB(45, 165, 95) or Color3.fromRGB(185, 60, 60)
        if onToggleCallback then onToggleCallback(isRunning) end
    end)

    -- Trả về bảng chứa hàm cập nhật chữ trạng thái cho FSM gọi
    return {
        SetStatus = function(text)
            status.Text = "State: " .. tostring(text)
        end
    }
end

return UI
