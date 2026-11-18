-- ============================================================
-- fsm.lua  |  Kaitun – Finite State Machine  v2.1
-- ============================================================
-- FIXED:
--  [1] NPC stuck  → verify-arrival loop + 1 s settle trước
--      khi chuyển GET_QUEST → FARM_MOB
--  [2] Quest detection → multi-source HasActiveQuest()
--      (PlayerGui + LP.Data + CommF_ fallback)
--  [3] FARM_MOB  → workspace.Enemies scan, hover above mob,
--      AutoEquip tool từ Backpack, Activate() để attack
--  [+] AutoLoot Devil Fruit → collect + StoreFruit
-- ============================================================

local Players        = game:GetService("Players")
local TweenService   = game:GetService("TweenService")
local RunService     = game:GetService("RunService")

local LP = Players.LocalPlayer

-- ── Hằng số trạng thái ──────────────────────────────────────
local S = {
    IDLE         = "IDLE",
    GET_QUEST    = "GET_QUEST",
    FARM_MOB     = "FARM_MOB",
    RANDOM_FRUIT = "RANDOM_FRUIT",
    SEA2_QUEST   = "SEA2_QUEST",
}

-- ── Fruit model names (Blox Fruits) ─────────────────────────
-- Các fruit spawned trong workspace thường là Model có Name
-- chứa "Fruit" hoặc khớp tên cụ thể; ta check cả hai cách.
local FRUIT_KEYWORDS = {
    "Fruit", "Devil", "Logia", "Paramecia", "Zoan",
}

-- ── Utility helpers ──────────────────────────────────────────
local function safeCall(fn, ...)
    local ok, r = pcall(fn, ...)
    return ok and r or nil
end

local function safeInvoke(CommF_, ...)
    if not CommF_ then return nil end
    return safeCall(function(...) return CommF_:InvokeServer(...) end, ...)
end

local function getCommF()
    return workspace:FindFirstChild("CommF_")
end

-- ── FSM Constructor ──────────────────────────────────────────
local FSM = {}
FSM.__index = FSM

---@param config  table  decoded config.json
---@param quests  table  decoded quests.json
---@param ui      table  ui.lua module
function FSM.new(config, quests, ui)
    local self         = setmetatable({}, FSM)
    self.config        = config
    self.quests        = quests
    self.ui            = ui
    self.state         = S.IDLE
    self.quest         = nil
    self.activeTween   = nil
    self._physConn     = nil
    return self
end

-- ════════════════════════════════════════════════════════════
-- CHARACTER HELPERS
-- ════════════════════════════════════════════════════════════

function FSM:_char()   return LP.Character end

function FSM:_root()
    local c = self:_char()
    return c and c:FindFirstChild("HumanoidRootPart")
end

function FSM:_hum()
    local c = self:_char()
    return c and c:FindFirstChildOfClass("Humanoid")
end

function FSM:_alive()
    local h = self:_hum()
    return h ~= nil and h.Health > 0
end

function FSM:_lvl()
    for _, key in ipairs({"Level","Lv","level"}) do
        for _, src in ipairs({"leaderstats","Data","PlayerData"}) do
            local d = LP:FindFirstChild(src)
            local v = d and d:FindFirstChild(key)
            if v then return v.Value end
        end
    end
    return 1
end

function FSM:_beli()
    for _, key in ipairs({"Beli","Berries","beli"}) do
        for _, src in ipairs({"leaderstats","Data","PlayerData"}) do
            local d = LP:FindFirstChild(src)
            local v = d and d:FindFirstChild(key)
            if v then return v.Value end
        end
    end
    return 0
end

-- ════════════════════════════════════════════════════════════
-- MOVEMENT  (TweenService + rubber-band guard)
-- ════════════════════════════════════════════════════════════

---Khởi tween bay đến targetPos.
---QUAN TRỌNG: không dùng await trực tiếp; dùng _awaitFly().
function FSM:_flyTo(targetPos, onDone)
    local root = self:_root()
    if not root then return nil end

    -- Hủy tween cũ trước
    if self.activeTween then
        self.activeTween:Cancel()
        self.activeTween = nil
    end

    -- Đặt character state sang Physics để giảm rubber-band
    local hum = self:_hum()
    if hum then
        safeCall(function()
            hum:ChangeState(Enum.HumanoidStateType.Physics)
        end)
    end

    local dist     = (root.Position - targetPos).Magnitude
    local duration = math.max(0.3, dist / self.config.FlySpeed)
    local info     = TweenInfo.new(duration, Enum.EasingStyle.Linear)

    local tw = TweenService:Create(root, info, {
        CFrame = CFrame.new(targetPos + Vector3.new(0, 4, 0))
    })

    self.activeTween = tw
    self.ui.SetActiveTween(tw)

    tw.Completed:Connect(function(ps)
        self.activeTween = nil
        self.ui.SetActiveTween(nil)
        -- Khôi phục state Humanoid
        if hum then
            safeCall(function()
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end)
        end
        if ps == Enum.PlaybackState.Completed and onDone then
            onDone()
        end
    end)

    tw:Play()
    return tw
end

-- ── [FIX #1] Await flight với verify loop ───────────────────
-- Sau khi tween "hoàn tất" (Completed), server có thể rubber-band
-- nhân vật về. Ta poll vị trí thực cho đến khi thực sự gần đích.
---@return boolean  true = đến nơi, false = bị dừng
function FSM:_awaitFly(targetPos, toleranceStuds)
    toleranceStuds = toleranceStuds or 25
    local tweenDone = false

    self:_flyTo(targetPos, function() tweenDone = true end)

    -- Chờ tween báo xong
    local t0 = tick()
    while not tweenDone and self.ui.IsRunning() do
        task.wait(0.05)
        if tick() - t0 > 60 then break end   -- timeout 60 s
    end

    if not self.ui.IsRunning() then return false end

    -- [FIX #1] Verify: chờ thêm đến khi khoảng cách thực < tolerance
    -- (xử lý rubber-band: tween xong nhưng server vẫn chưa confirm)
    local t1 = tick()
    while self.ui.IsRunning() do
        local root = self:_root()
        if not root then break end
        if (root.Position - targetPos).Magnitude <= toleranceStuds then
            break
        end
        -- Nếu rubber-band đẩy ra xa, re-tween
        if tick() - t1 > 2 then
            t1 = tick()
            self:_flyTo(targetPos)
        end
        task.wait(0.1)
    end

    return self.ui.IsRunning()
end

-- ════════════════════════════════════════════════════════════
-- [FIX #2] QUEST STATE DETECTION  (multi-source)
-- ════════════════════════════════════════════════════════════

---Trả về true nếu player đang có nhiệm vụ active.
function FSM:_hasActiveQuest()
    -- Nguồn 1: PlayerGui → Main → Quest (Blox Fruits hiển thị frame này)
    local ok1 = safeCall(function()
        local gui   = LP.PlayerGui
        local main  = gui:FindFirstChild("Main")
        if not main then return false end
        local qFrame = main:FindFirstChild("Quest")
        return qFrame and qFrame.Visible
    end)
    if ok1 then return true end

    -- Nguồn 2: LP.Data.Quest.Name (một số phiên bản BF)
    local ok2 = safeCall(function()
        local data = LP:FindFirstChild("Data")
        if not data then return false end
        local qData = data:FindFirstChild("Quest")
        if not qData then return false end
        local nameVal = qData:FindFirstChild("Name")
        return nameVal and nameVal.Value ~= ""
    end)
    if ok2 then return true end

    -- Nguồn 3: CommF_ fallback
    local CommF_ = getCommF()
    if CommF_ then
        local r = safeInvoke(CommF_, "HasQuest")
        if r then return true end
    end

    return false
end

---Chọn quest phù hợp với level hiện tại.
function FSM:_pickQuest()
    local lv   = self:_lvl()
    local best = nil
    for _, q in ipairs(self.quests) do
        if lv >= q.MinLv then best = q end
    end
    return best
end

-- ════════════════════════════════════════════════════════════
-- [FIX #3] MOB SYSTEM
-- ════════════════════════════════════════════════════════════

---Tìm mob gần nhất khớp tên trong workspace.Enemies.
---Fallback: quét workspace nếu Enemies không tồn tại.
---@return BasePart|nil  HumanoidRootPart của mob, hoặc nil
function FSM:_findNearestMob(mobName, centerPos)
    local root = self:_root()
    if not root then return nil end
    local refPos = root.Position

    -- Ưu tiên workspace.Enemies (Blox Fruits folder)
    local containers = {}
    local enemiesFolder = workspace:FindFirstChild("Enemies")
    if enemiesFolder then
        table.insert(containers, enemiesFolder)
    else
        table.insert(containers, workspace)
    end

    local best, bestDist = nil, math.huge

    for _, container in ipairs(containers) do
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("Model") and obj.Name:find(mobName) then
                local mobRoot = obj:FindFirstChild("HumanoidRootPart")
                local hum     = obj:FindFirstChildOfClass("Humanoid")
                if mobRoot and hum and hum.Health > 0 then
                    local d = (refPos - mobRoot.Position).Magnitude
                    if d < bestDist then
                        best, bestDist = mobRoot, d
                    end
                end
            end
        end
    end

    -- Giới hạn 500 studs để không grab mob ở đảo khác
    return (bestDist < 500) and best or nil
end

-- ── Auto-equip vũ khí từ Backpack ───────────────────────────
function FSM:_autoEquipWeapon()
    local char = self:_char()
    local hum  = self:_hum()
    if not char or not hum then return end

    -- Nếu đã có Tool trong tay → thôi
    for _, obj in ipairs(char:GetChildren()) do
        if obj:IsA("Tool") then return end
    end

    -- Lấy tool đầu tiên trong Backpack
    local bp = LP:FindFirstChild("Backpack")
    if not bp then return end

    for _, item in ipairs(bp:GetChildren()) do
        if item:IsA("Tool") then
            safeCall(function() hum:EquipTool(item) end)
            task.wait(0.3)
            return
        end
    end

    -- Fallback: CommF_ equip (nếu game dùng server-side equip)
    local CommF_ = getCommF()
    if CommF_ then
        safeInvoke(CommF_, "Equip", self.config.WeaponType or "Melee")
    end
end

-- ── Attack một mob đã tìm thấy ───────────────────────────────
-- Chiến lược:
--   1. Bay sát (nếu còn xa).
--   2. Activate tool đang cầm → đòn đánh cận chiến.
--   3. Fallback: CommF_ Melee / Z-Skill.
function FSM:_attackMob(mobHRP, fallbackPos)
    local root = self:_root()
    if not root then return end

    local dist = (root.Position - mobHRP.Position).Magnitude

    -- Bước 1: Rút gần
    if dist > 12 then
        -- Dùng short tween (không await) để không block attack loop
        self:_flyTo(mobHRP.Position + Vector3.new(0, 5, 0))
        task.wait(math.min(dist / self.config.FlySpeed, 1.5))
    end

    -- Bước 2: Activate tool
    local char = self:_char()
    if char then
        for _, obj in ipairs(char:GetChildren()) do
            if obj:IsA("Tool") then
                safeCall(function() obj:Activate() end)
                break
            end
        end
    end

    -- Bước 3: CommF_ fallback Melee attack
    local CommF_ = getCommF()
    if CommF_ then
        safeInvoke(CommF_, "Melee", mobHRP)
        -- Nếu dùng VirtualUser / KeyCode Z (skill) thì thêm vào đây
    end
end

-- ════════════════════════════════════════════════════════════
-- [+] AUTO LOOT DEVIL FRUIT
-- ════════════════════════════════════════════════════════════

---Quét workspace tìm Devil Fruit đang spawn, nhặt và cất vào kho.
function FSM:_lootFruits()
    local root = self:_root()
    if not root then return end

    local function isFruitModel(obj)
        if not obj:IsA("Model") and not obj:IsA("Part") then return false end
        for _, kw in ipairs(FRUIT_KEYWORDS) do
            if obj.Name:find(kw) then return true end
        end
        return false
    end

    -- Blox Fruits để fruit trong workspace trực tiếp hoặc folder Fruits
    local fruitFolder = workspace:FindFirstChild("Fruits") or workspace
    local targets = {}

    for _, obj in ipairs(fruitFolder:GetChildren()) do
        if isFruitModel(obj) then
            local pos
            if obj:IsA("Model") then
                local p = obj:FindFirstChildOfClass("BasePart")
                pos = p and p.Position
            else
                pos = obj.Position
            end
            if pos then
                table.insert(targets, { obj = obj, pos = pos })
            end
        end
    end

    if #targets == 0 then return end

    -- Nhặt fruit gần nhất
    local nearest, nearDist = nil, math.huge
    for _, t in ipairs(targets) do
        local d = (root.Position - t.pos).Magnitude
        if d < nearDist then nearest, nearDist = t, d end
    end

    if not nearest then return end

    self.ui.SetStatus("🍎 Nhặt fruit: " .. nearest.obj.Name)

    -- Bay tới fruit
    local arrived = self:_awaitFly(nearest.pos, 10)
    if not arrived then return end

    -- Collect + Store qua CommF_
    local CommF_ = getCommF()
    if CommF_ then
        -- Tên hàm tuỳ server; thử cả hai biến thể phổ biến
        safeInvoke(CommF_, "CollectFruit", nearest.obj)
        safeInvoke(CommF_, "PickFruit",    nearest.obj)
        task.wait(0.5)
        if self.config.AutoStoreFruit then
            self.ui.SetStatus("🍎 Cất fruit vào kho…")
            safeInvoke(CommF_, "StoreFruit")
            safeInvoke(CommF_, "StoreFruits")  -- alias thứ 2
        end
    end

    task.wait(0.5)
end

-- ════════════════════════════════════════════════════════════
-- STATE: TRANSITION HELPER
-- ════════════════════════════════════════════════════════════

function FSM:_to(state)
    self.state = state
    self.ui.SetStatus(state)
end

-- ════════════════════════════════════════════════════════════
-- STATE HANDLERS
-- ════════════════════════════════════════════════════════════

-- ── IDLE ─────────────────────────────────────────────────────
function FSM:_doIDLE()
    if not self:_alive() then
        self.ui.SetStatus("💀 Respawning…")
        task.wait(5)
        return
    end

    -- Chọn phe Hải Tặc
    local CommF_ = getCommF()
    if CommF_ then
        safeInvoke(CommF_, "SetTeam", "Pirates")
    end

    self:_to(S.GET_QUEST)
end

-- ── GET_QUEST ────────────────────────────────────────────────
-- [FIX #1 + #2]
function FSM:_doGET_QUEST()
    local q = self:_pickQuest()
    if not q then
        self.ui.SetStatus("⚠ No quest – waiting…")
        task.wait(3)
        return
    end
    self.quest = q

    -- ── 1. Bay tới NPC ───────────────────────────────────────
    self.ui.SetStatus("🗺 → NPC: " .. q.QuestName)
    local npcPos = Vector3.new(q.NPC[1], q.NPC[2], q.NPC[3])

    local arrivedNPC = self:_awaitFly(npcPos, 20)
    if not arrivedNPC then return end

    -- ── 2. Nhận quest ────────────────────────────────────────
    local CommF_ = getCommF()
    if CommF_ then
        -- API Blox Fruits: StartQuest(questName, questLevel)
        safeInvoke(CommF_, "StartQuest", q.QuestName, q.QuestLv)
    end

    -- ── 3. [FIX #1] Settle delay: chờ server xác nhận ────────
    self.ui.SetStatus("📋 Accepting quest…")
    task.wait(1.0)   -- đủ để server ghi nhận và trả HasQuest = true

    -- ── 4. [FIX #2] Verify quest đã được nhận ───────────────
    local retries = 0
    while not self:_hasActiveQuest() and retries < 3 do
        retries = retries + 1
        self.ui.SetStatus("📋 Retry accept (" .. retries .. "/3)…")
        if CommF_ then
            safeInvoke(CommF_, "StartQuest", q.QuestName, q.QuestLv)
        end
        task.wait(1.0)
    end

    if not self:_hasActiveQuest() then
        -- Quest vẫn không nhận được (có thể đang cooldown); thử lại sau
        self.ui.SetStatus("⚠ Quest accept failed – retry in 3s")
        task.wait(3)
        return   -- quay về GET_QUEST ở vòng lặp FSM
    end

    -- ── 5. [FIX #1] QUAN TRỌNG: chỉ chuyển FARM_MOB sau khi
    --      quest đã active → tránh kẹt NPC
    self:_to(S.FARM_MOB)
end

-- ── FARM_MOB ─────────────────────────────────────────────────
-- [FIX #3]
function FSM:_doFARM_MOB()
    local q = self.quest
    if not q then
        self:_to(S.GET_QUEST)
        return
    end

    -- ── 1. Bay tới vùng mob ──────────────────────────────────
    self.ui.SetStatus("✈ → Mob area: " .. q.Mob)
    local mobPos = Vector3.new(q.MobPos[1], q.MobPos[2], q.MobPos[3])

    local arrivedMob = self:_awaitFly(mobPos, 30)
    if not arrivedMob then return end

    -- ── 2. Equip vũ khí một lần ──────────────────────────────
    self:_autoEquipWeapon()

    -- ── 3. Vòng lặp farm ────────────────────────────────────
    self.ui.SetStatus("⚔ Farming: " .. q.Mob)

    while self.ui.IsRunning() do
        -- Cập nhật HUD
        self.ui.SetInfo(self:_lvl(), self:_beli())

        -- Chết → IDLE
        if not self:_alive() then
            self:_to(S.IDLE)
            return
        end

        -- Quest xong (frame Quest ẩn) → IDLE để nhận quest mới
        if not self:_hasActiveQuest() then
            self.ui.SetStatus("✅ Quest done!")
            task.wait(0.5)
            self:_to(S.IDLE)
            return
        end

        -- Đủ Beli → đổi fruit
        if self.config.AutoRandomFruit
            and self:_beli() >= self.config.MinBeliToRandom then
            self:_to(S.RANDOM_FRUIT)
            return
        end

        -- Auto loot fruit trong màn
        if self.config.AutoStoreFruit then
            self:_lootFruits()
        end

        -- [FIX #3] Tìm mob trong workspace.Enemies
        local mobHRP = self:_findNearestMob(q.Mob, mobPos)

        if mobHRP then
            self:_attackMob(mobHRP, mobPos)
        else
            -- Không có mob (chưa spawn hoặc đã chết hết) → hover tại farm
            local root = self:_root()
            if root and (root.Position - mobPos).Magnitude > 60 then
                -- Fly ngắn, không await để không block loop
                self:_flyTo(mobPos)
                task.wait(1)
            else
                task.wait(0.5) -- đứng chờ mob spawn
            end
        end

        task.wait(0.2)
    end
end

-- ── RANDOM_FRUIT ─────────────────────────────────────────────
function FSM:_doRANDOM_FRUIT()
    self.ui.SetStatus("🎲 Random Fruit…")

    -- Vị trí Blox Fruits Dealer gần nhất Sea 1
    local dealerPos = Vector3.new(-1872, 137, -1888)
    local ok = self:_awaitFly(dealerPos, 15)
    if not ok then return end

    local CommF_ = getCommF()
    if CommF_ then
        safeInvoke(CommF_, "BuyRandomFruit")
        task.wait(0.8)
        if self.config.AutoStoreFruit then
            self.ui.SetStatus("🍎 Storing fruit…")
            safeInvoke(CommF_, "StoreFruit")
            task.wait(0.5)
        end
    end

    task.wait(0.5)
    self:_to(S.GET_QUEST)
end

-- ── SEA2_QUEST (WIP) ─────────────────────────────────────────
function FSM:_doSEA2_QUEST()
    self.ui.SetStatus("🌊 Sea 2 – coming soon")
    task.wait(3)
    self:_to(S.IDLE)
end

-- ════════════════════════════════════════════════════════════
-- BACKGROUND: Stats + Skills (mỗi 10 s)
-- ════════════════════════════════════════════════════════════

function FSM:_autoStats()
    local CommF_ = getCommF()
    if not CommF_ then return end

    local stats = safeInvoke(CommF_, "GetStats")
    if not stats then return end

    local pts   = (stats.StatPoints or 0)
    if pts <= 0 then return end

    local melee = math.floor(pts * 0.7)
    local def   = pts - melee

    for _ = 1, melee do safeInvoke(CommF_, "AddStat", "Melee")   end
    for _ = 1, def   do safeInvoke(CommF_, "AddStat", "Defense") end
end

function FSM:_autoSkills()
    local CommF_ = getCommF()
    if not CommF_ then return end

    local lv   = self:_lvl()
    local beli = self:_beli()

    -- Luôn bật Buso Haki
    safeInvoke(CommF_, "Haki", "Buso")

    local skillList = {
        { name = "Buso",     minLv = 1,   cost = 25000  },
        { name = "Geppo",    minLv = 15,  cost = 20000  },
        { name = "BlackLeg", minLv = 1,   cost = 500000 },
        { name = "Soru",     minLv = 300, cost = 750000 },
    }
    for _, sk in ipairs(skillList) do
        if lv >= sk.minLv and beli >= sk.cost then
            safeInvoke(CommF_, "BuySkill", sk.name)
        end
    end
end

-- ════════════════════════════════════════════════════════════
-- HEARTBEAT: Anti-knockback + CanCollide + Anti-AFK
-- ════════════════════════════════════════════════════════════

function FSM:_startPhysics()
    local afkTimer = 0

    self._physConn = RunService.Heartbeat:Connect(function(dt)
        local char = self:_char()
        if not char then return end

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false

                -- Chống knockback: chỉ lock velocity khi đang có tween
                if part.Name == "HumanoidRootPart" and self.activeTween then
                    part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                end
            end
        end

        -- Anti-AFK: nhúc camera mỗi ~60 s
        afkTimer += dt
        if afkTimer >= 60 then
            afkTimer = 0
            local cam = workspace.CurrentCamera
            if cam then
                cam.CFrame = cam.CFrame
                    * CFrame.Angles(0, math.random(-1, 1) * 1e-4, 0)
            end
        end
    end)
end

-- ════════════════════════════════════════════════════════════
-- START / STOP
-- ════════════════════════════════════════════════════════════

function FSM:Start()
    self.state = S.IDLE
    self:_startPhysics()

    -- Luồng nền: stats + skills
    task.spawn(function()
        while self.ui.IsRunning() do
            self:_autoStats()
            self:_autoSkills()
            task.wait(10)
        end
    end)

    -- Luồng chính: FSM loop
    task.spawn(function()
        while self.ui.IsRunning() do
            local s = self.state
            if     s == S.IDLE         then self:_doIDLE()
            elseif s == S.GET_QUEST    then self:_doGET_QUEST()
            elseif s == S.FARM_MOB     then self:_doFARM_MOB()
            elseif s == S.RANDOM_FRUIT then self:_doRANDOM_FRUIT()
            elseif s == S.SEA2_QUEST   then self:_doSEA2_QUEST()
            end
            task.wait(0.05)
        end
        self:Stop()
    end)
end

function FSM:Stop()
    if self.activeTween then
        self.activeTween:Cancel()
        self.activeTween = nil
    end
    if self._physConn then
        self._physConn:Disconnect()
        self._physConn = nil
    end
    self.ui.SetActiveTween(nil)
end

return FSM
