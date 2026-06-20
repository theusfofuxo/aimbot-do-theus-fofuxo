-- ====================================================================
-- PREMONITION ENGINE v108.5.0 - DELTA PREMIUM EDITION (HOOK EDITION)
-- ====================================================================

if not game:IsLoaded() then
    game.Loaded:Wait()
end
task.wait(1)

-- Gerenciamento de conexões obsoletas para evitar vazamento de memória (Memory Leak)
local ENV = (getgenv and getgenv()) or _G
if ENV.PremonitionConnections then
    for _, conn in ipairs(ENV.PremonitionConnections) do
        pcall(function() conn:Disconnect() end)
    end
end
ENV.PremonitionConnections = {}
local function AddConnection(conn)
    table.insert(ENV.PremonitionConnections, conn)
    return conn
end

if ENV.PremonitionLoopActive then
    ENV.PremonitionLoopActive = false
    task.wait(0.1)
end
ENV.PremonitionLoopActive = true

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera")

local TARGET_TAG = "Premonition_ActiveTarget"

-- ==================== CONFIGURAÇÕES GERAIS DA ENGINE ====================
local Settings = {
    ShowFOV = false,
    FovDegrees = 15,
    FovColorR = 0, FovColorG = 180, FovColorB = 255,
    CrosshairEnabled = false,
    CrosshairType = "Ponto",
    CrosshairColorR = 255, CrosshairColorG = 50, CrosshairColorB = 50,
    CrosshairSize = 8,
    CrosshairGap = 2,
    SnapMarkers = false,
    AimbotEnabled = false,
    Hitbox = "Head",
    SmoothValue = 4,
    StickyStrength = 60,
    TargetPriority = "Distancia FOV",
    DynamicSmoothness = false,
    DynamicSmoothMultiplier = 5,
    StickyLock = false,
    BreakoutForce = 25,
    WeightRecoverySpeed = 3.0,
    MagneticVectorSnapping = false,
    GravitationalExponent = 2.5,
    HumanFriction = false,
    ProximityDampEnabled = false,
    ProximityMaxDistance = 25,
    ProximityMinStrength = 35,
    NeuromuscularTremor = false,
    TremorIntensity = 2,
    MovementPrediction = false,
    PredictStrength = 50,
    AntiLagFiltering = false,
    BallisticCorrection = false,
    
    -- Valores Base (Serão sobrescritos dinamicamente pelo Hook se calibrado)
    MuzzleVelocity = 1000,
    BulletGravity = 196.2,
    AutoCalibrateUniversal = true,
    
    FlickEnabled = false,
    FlickSmooth = 2,
    FlickFovDegrees = 8,
    
    WallCheck = false,
    MultiBoneScan = false,
    WallPenetration = false,
    MaxPenetrationThick = 2.5,
    TeamCheck = false,
    HitboxExpander = false,
    HitboxSize = 0,
    AdaptiveFovEnabled = false,
    AdaptiveFovMultiplier = 0.5,

    -- ==================== UPGRADE: CORE RAGE ENGINE CONFIGS ====================
    RageEnabled = false,
    RageHitbox = "Head",
    RageWallCheck = false,
    RageInstantSnapping = false, -- Falso por padrão para usar a nova cinemática fluida
    RageSmoothness = 3.5,        -- Controla a força do arrasto hidrodinâmico e Bézier
    RageStabilizer = true,       -- Ativa o Filtro Kalman contra Lag/Jitter
    RageMaxDistance = 2000
}

-- ==================== SISTEMA DE MEMÓRIA DA ENGINE ====================
local TargetMotionCache = {}
local CurrentTarget = nil
local TargetPart = nil

-- Memória dedicada do motor Core Rage (Vetores físicos e históricos do Kalman)
local CoreRageTarget = nil
local RageAngularVelocity = Vector3.zero
local RageKalmanHistory = {}

-- ==================== HOOK UNIVERSAL DE AUTO-CALIBRAÇÃO REAL ====================
local LastTriggerTime = 0
AddConnection(UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
        LastTriggerTime = os.clock()
    end
end))

local function TrackProjectileVelocity(part)
    local lastPos = part.Position
    local startTime = os.clock()
    task.wait(0.03)
    
    if part and part.Parent then
        local currentPos = part.Position
        local deltaPos = (currentPos - lastPos).Magnitude
        local deltaTime = os.clock() - startTime
        
        if deltaTime > 0 and deltaPos > 5 then
            local realVelocity = deltaPos / deltaTime
            if realVelocity > 50 and realVelocity < 8000 then
                Settings.MuzzleVelocity = realVelocity
                local velocityY = part.AssemblyLinearVelocity and part.AssemblyLinearVelocity.Y
                if velocityY and math.abs(velocityY) > 1 then
                    Settings.BulletGravity = math.abs(Workspace.Gravity)
                end
            end
        end
    end
end

local function HookWorkspaceContainer(container)
    AddConnection(container.ChildAdded:Connect(function(child)
        if not Settings.AutoCalibrateUniversal or (os.clock() - LastTriggerTime > 0.3) then return end
        if child:IsA("BasePart") or child:IsA("MeshPart") then
            local myCharacter = LocalPlayer.Character
            if myCharacter then
                local root = myCharacter:FindFirstChild("HumanoidRootPart")
                if root and (child.Position - root.Position).Magnitude < 12 then
                    task.spawn(TrackProjectileVelocity, child)
                end
            end
        end
    end))
end

HookWorkspaceContainer(Workspace)
if Workspace:FindFirstChild("Projectiles") then HookWorkspaceContainer(Workspace.Projectiles) end
if Workspace:FindFirstChild("Debris") then HookWorkspaceContainer(Workspace.Debris) end

-- ==================== MATEMÁTICA VETORIAL E TELA ====================
local function GetTrueScreenCenter()
    Camera = Workspace.CurrentCamera
    if not Camera then return Vector2.new(0, 0) end
    return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
end
local ScreenCenter = GetTrueScreenCenter()

local function CalculateAngularRadius(degrees)
    Camera = Workspace.CurrentCamera
    if not Camera then return 55 end
    return (math.tan(math.rad(degrees) / 2) / math.tan(math.rad(Camera.FieldOfView) / 2)) * (Camera.ViewportSize.Y / 2) 
end

local function CalculateAdaptiveFov(baseFov, targetPart, myRoot)
    if not Settings.AdaptiveFovEnabled or not targetPart or not myRoot then return baseFov end
    local distance = (targetPart.Position - myRoot.Position).Magnitude
    local speed = (targetPart.AssemblyLinearVelocity or Vector3.zero).Magnitude
    return baseFov * math.clamp(1 + (math.clamp(distance / 100, 0, 1) + math.clamp(speed / 50, 0, 1)) * Settings.AdaptiveFovMultiplier, 0.5, 2.5) 
end

local function validateCharacter(char)
    if not char or not char.Parent then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health > 0
end

local function CleanMotionCache()
    local currentTime = os.clock()
    for key, data in pairs(TargetMotionCache) do
        if currentTime - data.lastUpdate > 2.0 then TargetMotionCache[key] = nil end
    end
    -- Limpa histórico Kalman órfão
    for id, _ in pairs(RageKalmanHistory) do
        if not Workspace:FindFirstChild(id) then RageKalmanHistory[id] = nil end
    end
end

for _, child in ipairs(CoreGui:GetChildren()) do
    if child.Name == "DeltaPremium_FinalRelease" then pcall(function() child:Destroy() end) end
end

-- ==================== OVERLAYS GRÁFICOS (FOV & RETÍCULA) ====================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DeltaPremium_FinalRelease"; ScreenGui.ResetOnSpawn = false; ScreenGui.IgnoreGuiInset = true; ScreenGui.DisplayOrder = 999; ScreenGui.Parent = CoreGui

local FOVCircle = Instance.new("Frame")
FOVCircle.Name = "AutonomousFOV"; FOVCircle.AnchorPoint = Vector2.new(0.5, 0.5); FOVCircle.BackgroundTransparency = 1; FOVCircle.ZIndex = 10; FOVCircle.Parent = ScreenGui
local Stroke = Instance.new("UIStroke", FOVCircle); Stroke.Thickness = 1.5; Stroke.Transparency = 0.2
Instance.new("UICorner", FOVCircle).CornerRadius = UDim.new(1, 0)

local FlickFOVCircle = Instance.new("Frame")
FlickFOVCircle.Name = "FlickFOV"; FlickFOVCircle.AnchorPoint = Vector2.new(0.5, 0.5); FlickFOVCircle.BackgroundTransparency = 1; FlickFOVCircle.ZIndex = 9; FlickFOVCircle.Parent = ScreenGui
local FlickStroke = Instance.new("UIStroke", FlickFOVCircle); FlickStroke.Thickness = 1.5; FlickStroke.Transparency = 0.2
Instance.new("UICorner", FlickFOVCircle).CornerRadius = UDim.new(1, 0)

local CrosshairBase = Instance.new("Frame")
CrosshairBase.Name = "CrosshairContainer"; CrosshairBase.Size = UDim2.new(0, 100, 0, 100); CrosshairBase.AnchorPoint = Vector2.new(0.5, 0.5); CrosshairBase.BackgroundTransparency = 1; CrosshairBase.ZIndex = 12; CrosshairBase.Parent = ScreenGui
local CrosshairObjects = { Lines = {} }

local function BuildCrosshairInstances()
    CrosshairBase:ClearAllChildren()
    local dot = Instance.new("Frame")
    dot.AnchorPoint = Vector2.new(0.5, 0.5); dot.BorderSizePixel = 0; dot.ZIndex = 3; dot.Parent = CrosshairBase
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    CrosshairObjects.Dot = dot
    for i = 1, 4 do
        local arm = Instance.new("Frame"); arm.BorderSizePixel = 0; arm.AnchorPoint = Vector2.new(0.5, 0.5); arm.ZIndex = 3; arm.Parent = CrosshairBase
        CrosshairObjects.Lines[i] = arm
    end
end
BuildCrosshairInstances()

local SnapLeft = Instance.new("TextLabel"); SnapLeft.BackgroundTransparency = 1; SnapLeft.Text = "["; SnapLeft.Font = Enum.Font.GothamBold; SnapLeft.TextSize = 18; SnapLeft.TextColor3 = Color3.fromRGB(185, 28, 28); SnapLeft.Visible = false; SnapLeft.ZIndex = 2; SnapLeft.Parent = ScreenGui
local SnapRight = Instance.new("TextLabel"); SnapRight.BackgroundTransparency = 1; SnapRight.Text = "]"; SnapRight.Font = Enum.Font.GothamBold; SnapRight.TextSize = 18; SnapRight.TextColor3 = Color3.fromRGB(185, 28, 28); SnapRight.Visible = false; SnapRight.ZIndex = 2; SnapRight.Parent = ScreenGui

-- ==================== CÁLCULO DE BALÍSTICA E PREDIÇÃO ====================
local function CalculateAdvancedPrediction(targetPart, deltaTime)
    if not targetPart or not Settings.MovementPrediction then return targetPart.Position end
    local currentPos = targetPart.Position
    local velocity = targetPart.AssemblyLinearVelocity or Vector3.zero
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot or (Settings.AntiLagFiltering and velocity.Magnitude > 120) then return currentPos end

    local ping = 0.03
    pcall(function() ping = game:GetService("Stats").Network.ServerToClientPing:GetValue() / 1000 end)
    ping = math.clamp(ping, 0.005, 0.15)
    local predictedPos = currentPos + (velocity * (ping * (Settings.PredictStrength / 50)))

    if Settings.BallisticCorrection then
        local distance = (currentPos - myRoot.Position).Magnitude
        local travelTime = distance / Settings.MuzzleVelocity
        predictedPos = predictedPos + Vector3.new(0, 0.5 * Settings.BulletGravity * (travelTime ^ 2), 0)
    end
    return predictedPos
end

-- MATEMÁTICA AVANÇADA DO NOVO CORE RAGE: FILTRO KALMAN & BÉZIER CÚBICA
local function ProcessKalmanRage(part)
    if not part then return Vector3.zero end
    local id = part.Name .. "_" .. tostring(part.Parent)
    local currentPos = part.Position
    
    if not RageKalmanHistory[id] then
        RageKalmanHistory[id] = { pos = currentPos, vel = Vector3.zero }
        return currentPos
    end
    
    local lastData = RageKalmanHistory[id]
    -- Constante de ganho adaptativo contra Jitter/Desaceleração de Rede
    local kGain = Settings.RageStabilizer and 0.35 or 1.0
    local estimatedPos = lastData.pos + (lastData.vel * 0.016)
    local filteredPos = estimatedPos + kGain * (currentPos - estimatedPos)
    
    lastData.vel = (filteredPos - lastData.pos) / 0.016
    lastData.pos = filteredPos
    
    return filteredPos
end

local function GetBezierPoint(p0, p1, p2, t)
    -- Curva de Bézier Cúbica Simplificada para suavização de transição angular
    local l1 = p0:Lerp(p1, t)
    local l2 = p1:Lerp(p2, t)
    return l1:Lerp(l2, t)
end

-- ==================== POOL DE HITBOXES SEGURO (ANTI-FLING) ====================
local HitboxPool = { parts = {}, inUse = {}, maxSize = 40 }
local WALL_CHECK_PARAMS = RaycastParams.new()
WALL_CHECK_PARAMS.FilterType = Enum.RaycastFilterType.Exclude
WALL_CHECK_PARAMS.IgnoreWater = true
WALL_CHECK_PARAMS.RespectCanCollide = true

local function UpdateIgnoreList()
    local list = {Workspace.CurrentCamera, Workspace:FindFirstChild("Terrain")}
    if LocalPlayer.Character then
        for _, part in ipairs(LocalPlayer.Character:GetDescendants()) do
            if part:IsA("BasePart") then table.insert(list, part) end
        end
    end
    for part, isUsed in pairs(HitboxPool.inUse) do
        if isUsed and part.Parent then table.insert(list, part) end
    end
    WALL_CHECK_PARAMS.FilterDescendantsInstances = list
end

local function GetHitboxFromPool()
    for _, part in ipairs(HitboxPool.parts) do
        if not HitboxPool.inUse[part] then
            HitboxPool.inUse[part] = true
            return part
        end
    end
    if #HitboxPool.parts < HitboxPool.maxSize then
        local newPart = Instance.new("Part")
        newPart.Name = "Premonition_Hitbox"; newPart.Anchored = false
        newPart.CanCollide = false; newPart.Massless = true
        newPart.Transparency = 0.85; newPart.Material = Enum.Material.ForceField
        newPart.Color = Color3.fromRGB(185, 28, 28); newPart.CastShadow = false
        table.insert(HitboxPool.parts, newPart)
        HitboxPool.inUse[newPart] = true
        return newPart
    end
    return nil
end

local function ReleaseHitbox(part)
    if part then
        part.Parent = nil
        local weld = part:FindFirstChildOfClass("Weld")
        if weld then weld:Destroy() end
        HitboxPool.inUse[part] = nil
    end
end

local function UpdateExpandedHitboxes(character, size)
    if not character or not character.Parent then return end
    
    for _, partName in ipairs({"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart"}) do
        local part = character:FindFirstChild(partName)
        if part then
            local oldHitbox = part:FindFirstChild("ExpandedHitbox")
            if oldHitbox then ReleaseHitbox(oldHitbox) end
        end
    end

    if not Settings.HitboxExpander or size <= 0 then return end

    for _, partName in ipairs({"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart"}) do
        local part = character:FindFirstChild(partName)
        if part and part:IsA("BasePart") then
            local hitbox = GetHitboxFromPool()
            if hitbox then
                hitbox.Name = "ExpandedHitbox"
                hitbox.Size = part.Size * (1 + (size / 3.5))
                local weld = Instance.new("Weld")
                weld.Part0 = part; weld.Part1 = hitbox; weld.C0 = CFrame.new(0, 0, 0); weld.Parent = weld
                hitbox.Parent = part
            end
        end
    end
end

-- ==================== LÓGICA DO WALLCHECK ====================
local function ScanDynamicExposedMassa(character)
    if not character then return nil end
    local origin = Camera.CFrame.Position
    local boneCandidates = Settings.MultiBoneScan and {Settings.Hitbox, "Head", "UpperTorso", "HumanoidRootPart"} or {Settings.Hitbox}
    local bestPart, minDist = nil, math.huge
    local screenCenter = GetTrueScreenCenter()

    for _, boneName in ipairs(boneCandidates) do
        local part = character:FindFirstChild(boneName)
        if part and part:IsA("BasePart") then
            local targetPos = part.Position
            local hitboxPart = part:FindFirstChild("ExpandedHitbox")
            if Settings.HitboxExpander and Settings.HitboxSize > 0 and hitboxPart then targetPos = hitboxPart.Position end
            
            local direction = targetPos - origin
            local hitVisible = false

            if not Settings.WallCheck then
                hitVisible = true
            else
                UpdateIgnoreList()
                local result = Workspace:Raycast(origin, direction, WALL_CHECK_PARAMS)
                
                if result then
                    local hitInstance = result.Instance
                    if hitInstance:IsDescendantOf(character) then
                        hitVisible = true
                    elseif Settings.WallPenetration then
                        local revResult = Workspace:Raycast(targetPos, origin - targetPos, WALL_CHECK_PARAMS)
                        if revResult and revResult.Instance == hitInstance then
                            local thick = (result.Position - revResult.Position).Magnitude
                            if thick <= Settings.MaxPenetrationThick then
                                hitVisible = true
                            end
                        end
                    end
                else
                    hitVisible = true
                end
            end

            if hitVisible then
                local aimPart = (Settings.HitboxExpander and Settings.HitboxSize > 0 and hitboxPart) or part
                local screenPos, onScreen = Camera:WorldToViewportPoint(aimPart.Position)
                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                    if dist < minDist then minDist = dist; bestPart = aimPart end
                end
            end
        end
    end
    return bestPart
end

local function AdvancedTeamCheck(targetPlayer)
    if not Settings.TeamCheck or not targetPlayer then return true end
    if targetPlayer.Team and LocalPlayer.Team then return targetPlayer.Team ~= LocalPlayer.Team end
    return true
end

-- ==================== MONTAGEM DA UI INTERATIVA ====================
local MainPanel = Instance.new("Frame")
MainPanel.Name = "MainPanel"; MainPanel.Parent = ScreenGui; MainPanel.Size = UDim2.new(0, 560, 0, 360); MainPanel.Position = UDim2.new(0.5, -280, 0.5, -180); MainPanel.BackgroundColor3 = Color3.fromRGB(14, 14, 16); MainPanel.BorderSizePixel = 0; MainPanel.Active = true
Instance.new("UICorner", MainPanel).CornerRadius = UDim.new(0, 10)

local FloatingToggle = Instance.new("ImageButton")
FloatingToggle.Name = "Premonition_FloatingToggle"; FloatingToggle.Size = UDim2.new(0, 46, 0, 46); FloatingToggle.Position = UDim2.new(0, 15, 0.4, 0); FloatingToggle.BackgroundColor3 = Color3.fromRGB(20, 20, 22); FloatingToggle.Image = "rbxassetid://10747373159"; FloatingToggle.ImageColor3 = Color3.fromRGB(185, 28, 28); FloatingToggle.ZIndex = 100; FloatingToggle.Parent = ScreenGui
Instance.new("UICorner", FloatingToggle).CornerRadius = UDim.new(1, 0)
Instance.new("UIStroke", FloatingToggle).Color = Color3.fromRGB(38, 38, 42)

local isFloatDragging = false
local dragStart, startPos

AddConnection(FloatingToggle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then isFloatDragging = true; dragStart = input.Position; startPos = FloatingToggle.Position end end))
AddConnection(UserInputService.InputChanged:Connect(function(input)
    if isFloatDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        FloatingToggle.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end end))
AddConnection(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then isFloatDragging = false end end))

FloatingToggle.MouseButton1Click:Connect(function()
    MainPanel.Visible = not MainPanel.Visible
    if MainPanel.Visible then
        MainPanel.Size = UDim2.new(0, 560, 0, 0)
        TweenService:Create(MainPanel, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0, 560, 0, 360)}):Play()
    end end)

local dragToggle, pDragStart, pStartPos
AddConnection(MainPanel.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragToggle = true; pDragStart = input.Position; pStartPos = MainPanel.Position end end))
AddConnection(UserInputService.InputChanged:Connect(function(input)
    if dragToggle and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - pDragStart
        MainPanel.Position = UDim2.new(pStartPos.X.Scale, pStartPos.X.Offset + delta.X, pStartPos.Y.Scale, pStartPos.Y.Offset + delta.Y)
    end end))
AddConnection(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragToggle = false end end))

local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"; Sidebar.Parent = MainPanel; Sidebar.Size = UDim2.new(0, 60, 1, 0); Sidebar.BackgroundColor3 = Color3.fromRGB(255, 255, 255); Sidebar.BorderSizePixel = 0; Sidebar.ZIndex = 2
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 10)

local SidebarGradient = Instance.new("UIGradient")
SidebarGradient.Rotation = 90
SidebarGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0.0, Color3.fromRGB(185, 28, 28)),
    ColorSequenceKeypoint.new(0.35, Color3.fromRGB(110, 20, 22)),
    ColorSequenceKeypoint.new(0.60, Color3.fromRGB(24, 14, 16)),
    ColorSequenceKeypoint.new(1.0, Color3.fromRGB(14, 14, 16))
})
SidebarGradient.Parent = Sidebar

local RightSideCover = Instance.new("Frame")
RightSideCover.Name = "RightSideCover"; RightSideCover.Parent = Sidebar; RightSideCover.Size = UDim2.new(0, 15, 1, 0); RightSideCover.Position = UDim2.new(1, -15, 0, 0); RightSideCover.BackgroundColor3 = Color3.fromRGB(255, 255, 255); RightSideCover.BorderSizePixel = 0; RightSideCover.ZIndex = 3
SidebarGradient:Clone().Parent = RightSideCover

local Separator = Instance.new("Frame")
Separator.Name = "Separator"; Separator.Parent = MainPanel; Separator.Size = UDim2.new(0, 1, 1, 0); Separator.Position = UDim2.new(0, 60, 0, 0); Separator.BackgroundColor3 = Color3.fromRGB(35, 35, 40); Separator.BorderSizePixel = 0; Separator.ZIndex = 4

local ButtonContainer = Instance.new("Frame")
ButtonContainer.Name = "ButtonContainer"; ButtonContainer.Parent = MainPanel; ButtonContainer.Size = UDim2.new(0, 60, 1, 0); ButtonContainer.BackgroundTransparency = 1; ButtonContainer.ZIndex = 15
local Layout = Instance.new("UIListLayout", ButtonContainer); Layout.Padding = UDim.new(0, 14); Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center; Layout.VerticalAlignment = Enum.VerticalAlignment.Top
local Padding = Instance.new("UIPadding", ButtonContainer); Padding.PaddingTop = UDim.new(0, 20)

local PageContainer = Instance.new("Frame")
PageContainer.Name = "PageContainer"; PageContainer.Parent = MainPanel; PageContainer.Size = UDim2.new(1, -80, 1, -20); PageContainer.Position = UDim2.new(0, 72, 0, 10); PageContainer.BackgroundTransparency = 1; PageContainer.ZIndex = 5

local Paginas = {}
local BotaoAtivo = nil

local function CriarPagina(nome, subTitulo)
    local CanvasGroup = Instance.new("CanvasGroup")
    CanvasGroup.Name = nome .. "Page"; CanvasGroup.Size = UDim2.new(1, 0, 1, 0); CanvasGroup.BackgroundTransparency = 1; CanvasGroup.GroupTransparency = 1; CanvasGroup.Visible = false; CanvasGroup.ZIndex = 6; CanvasGroup.Parent = PageContainer

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Size = UDim2.new(1, 0, 0, 20); TitleLabel.BackgroundTransparency = 1; TitleLabel.Text = nome:upper(); TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255); TitleLabel.Font = Enum.Font.GothamBold; TitleLabel.TextSize = 18; TitleLabel.TextXAlignment = Enum.TextXAlignment.Left; TitleLabel.Parent = CanvasGroup

    local SubLabel = Instance.new("TextLabel")
    SubLabel.Size = UDim2.new(1, 0, 0, 14); SubLabel.Position = UDim2.new(0, 0, 0, 20); SubLabel.BackgroundTransparency = 1; SubLabel.Text = subTitulo; SubLabel.TextColor3 = Color3.fromRGB(130, 130, 135); SubLabel.Font = Enum.Font.GothamMedium; SubLabel.TextSize = 10; SubLabel.TextXAlignment = Enum.TextXAlignment.Left; SubLabel.Parent = CanvasGroup

    local PageScroll = Instance.new("ScrollingFrame")
    PageScroll.Size = UDim2.new(1, 0, 1, -40); PageScroll.Position = UDim2.new(0, 0, 0, 40); PageScroll.BackgroundTransparency = 1; PageScroll.ScrollBarThickness = 2; PageScroll.ScrollBarImageColor3 = Color3.fromRGB(185, 28, 28); PageScroll.Parent = CanvasGroup

    local ScrollLayout = Instance.new("UIListLayout", PageScroll)
    ScrollLayout.Padding = UDim.new(0, 6); ScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local Columns = Instance.new("Frame")
    Columns.Size = UDim2.new(1, 0, 0, 0); Columns.AutomaticSize = Enum.AutomaticSize.Y; Columns.BackgroundTransparency = 1; Columns.Parent = PageScroll
    local ColLayout = Instance.new("UIListLayout", Columns); ColLayout.FillDirection = Enum.FillDirection.Horizontal; ColLayout.Padding = UDim.new(0, 8)

    local ColLeft = Instance.new("Frame")
    ColLeft.Size = UDim2.new(0.49, 0, 0, 0); ColLeft.AutomaticSize = Enum.AutomaticSize.Y; ColLeft.BackgroundTransparency = 1; ColLeft.Parent = Columns
    Instance.new("UIListLayout", ColLeft).Padding = UDim.new(0, 5)

    local ColRight = Instance.new("Frame")
    ColRight.Size = UDim2.new(0.49, 0, 0, 0); ColRight.AutomaticSize = Enum.AutomaticSize.Y; ColRight.BackgroundTransparency = 1; ColRight.Parent = Columns
    Instance.new("UIListLayout", ColRight).Padding = UDim.new(0, 5)

    local PreviewRegion = Instance.new("Frame")
    PreviewRegion.Size = UDim2.new(1, -6, 0, 0); PreviewRegion.AutomaticSize = Enum.AutomaticSize.Y; PreviewRegion.BackgroundTransparency = 1; PreviewRegion.Parent = PageScroll
    Instance.new("UIListLayout", PreviewRegion).HorizontalAlignment = Enum.HorizontalAlignment.Center

    ScrollLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        PageScroll.CanvasSize = UDim2.new(0, 0, 0, ScrollLayout.AbsoluteContentSize.Y + 10)
    end)

    Paginas[nome] = { Group = CanvasGroup, Left = ColLeft, Right = ColRight, Preview = PreviewRegion }
end

CriarPagina("Geral", "SISTEMA PRINCIPAL & FILTROS")
CriarPagina("Aimbot", "TRAVAMENTO AUTOMÁTICO")
CriarPagina("Lock", "TRAVA MAGNÉTICA AVANÇADA")
CriarPagina("Fov", "CONFIGURAÇÃO DE CAMPO DE VISÃO")
CriarPagina("Crosshair", "RETÍCULAS PERSONALIZADAS")
CriarPagina("Hitbox", "EXPANSÃO ANATÔMICA")

local function CriarBotaoAba(nomeAba, emojiText, ordem)
    local BaseButton = Instance.new("TextButton")
    BaseButton.Name = nomeAba .. "Btn"; BaseButton.Size = UDim2.new(0, 32, 0, 32); BaseButton.BackgroundTransparency = 1; BaseButton.Text = ""; BaseButton.LayoutOrder = ordem; BaseButton.Parent = ButtonContainer; BaseButton.ZIndex = 16

    local EmojiLabel = Instance.new("TextLabel")
    EmojiLabel.Name = "Emoji"; EmojiLabel.Size = UDim2.new(1, 0, 1, 0); EmojiLabel.BackgroundTransparency = 1; BaseButton.Text = ""; EmojiLabel.Text = emojiText; EmojiLabel.TextSize = 18; EmojiLabel.Font = Enum.Font.GothamBold; EmojiLabel.ZIndex = 18; EmojiLabel.Parent = BaseButton
    EmojiLabel.TextTransparency = 0.55

    if ordem == 1 then
        BotaoAtivo = BaseButton; EmojiLabel.TextTransparency = 0
        Paginas[nomeAba].Group.Visible = true; Paginas[nomeAba].Group.GroupTransparency = 0
    end

    BaseButton.MouseButton1Click:Connect(function()
        if BotaoAtivo == BaseButton then return end
        if BotaoAtivo then
            local antigoNome = string.gsub(BotaoAtivo.Name, "Btn$", "")
            BotaoAtivo.Emoji.TextTransparency = 0.55
            local antigaPag = Paginas[antigoNome].Group
            TweenService:Create(antigaPag, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {GroupTransparency = 1}):Play()
            task.delay(0.15, function() antigaPag.Visible = false end)
        end
        BotaoAtivo = BaseButton; EmojiLabel.TextTransparency = 0
        local novaPag = Paginas[nomeAba].Group
        novaPag.Visible = true
        TweenService:Create(novaPag, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {GroupTransparency = 0}):Play()
    end)
end

CriarBotaoAba("Geral", "⚙️", 1)
CriarBotaoAba("Aimbot", "🎯", 2)
CriarBotaoAba("Lock", "🔒", 3)
CriarBotaoAba("Fov", "👁️", 4)
CriarBotaoAba("Crosshair", "✚", 5)
CriarBotaoAba("Hitbox", "📦", 6)

Instance.new("UIStroke", MainPanel).Color = Color3.fromRGB(38, 38, 42)

-- Previews da UI
local FovPreviewBox = Instance.new("CanvasGroup")
FovPreviewBox.Size = UDim2.new(0.95, 0, 0, 80); FovPreviewBox.BackgroundColor3 = Color3.fromRGB(20, 20, 24); FovPreviewBox.GroupTransparency = 0.3; FovPreviewBox.Parent = Paginas["Fov"].Preview
Instance.new("UICorner", FovPreviewBox).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", FovPreviewBox).Color = Color3.fromRGB(185, 28, 28)

local FovSimCircle = Instance.new("Frame")
FovSimCircle.AnchorPoint = Vector2.new(0.5, 0.5); FovSimCircle.Position = UDim2.new(0.5, 0, 0.5, 0); FovSimCircle.BackgroundTransparency = 1; FovSimCircle.Parent = FovPreviewBox
local FovSimStroke = Instance.new("UIStroke", FovSimCircle); FovSimStroke.Thickness = 1.5; FovSimStroke.Color = Color3.fromRGB(0, 180, 255)
Instance.new("UICorner", FovSimCircle).CornerRadius = UDim.new(1, 0)

local FlickSimCircle = Instance.new("Frame")
FlickSimCircle.AnchorPoint = Vector2.new(0.5, 0.5); FlickSimCircle.Position = UDim2.new(0.5, 0.5, 0.5, 0); FlickSimCircle.BackgroundTransparency = 1; FlickSimCircle.Parent = FovPreviewBox
local FlickSimStroke = Instance.new("UIStroke", FlickSimCircle); FlickSimStroke.Thickness = 1.5; FlickSimStroke.Color = Color3.fromRGB(255, 80, 80)
Instance.new("UICorner", FlickSimCircle).CornerRadius = UDim.new(1, 0)

local CrossPreviewBox = Instance.new("CanvasGroup")
CrossPreviewBox.Size = UDim2.new(0.95, 0, 0, 70); CrossPreviewBox.BackgroundColor3 = Color3.fromRGB(20, 20, 24); CrossPreviewBox.Parent = Paginas["Crosshair"].Preview
Instance.new("UICorner", CrossPreviewBox).CornerRadius = UDim.new(0, 4)
local CrossSimCenter = Instance.new("Frame")
CrossSimCenter.Position = UDim2.new(0.5, 0, 0.5, 0); CrossSimCenter.BackgroundTransparency = 1; CrossSimCenter.Parent = CrossPreviewBox
local SimDot = Instance.new("Frame"); SimDot.AnchorPoint = Vector2.new(0.5, 0.5); SimDot.BorderSizePixel = 0; SimDot.Parent = CrossSimCenter
Instance.new("UICorner", SimDot).CornerRadius = UDim.new(1, 0)
local SimLines = {}
for i = 1, 4 do local arm = Instance.new("Frame"); arm.BorderSizePixel = 0; arm.AnchorPoint = Vector2.new(0.5, 0.5); arm.Parent = CrossSimCenter; SimLines[i] = arm end

local HitboxPreviewBox = Instance.new("CanvasGroup")
HitboxPreviewBox.Size = UDim2.new(0.95, 0, 0, 100); HitboxPreviewBox.BackgroundColor3 = Color3.fromRGB(20, 20, 24); HitboxPreviewBox.Parent = Paginas["Hitbox"].Preview
Instance.new("UICorner", HitboxPreviewBox).CornerRadius = UDim.new(0, 4)
local Viewport = Instance.new("ViewportFrame")
Viewport.Size = UDim2.new(1, 0, 1, 0); Viewport.BackgroundTransparency = 1; Viewport.Parent = HitboxPreviewBox
local ViewWorld = Instance.new("WorldModel", Viewport)
local ViewCam = Instance.new("Camera"); ViewCam.FieldOfView = 40; Viewport.CurrentCamera = ViewCam; ViewCam.Parent = Viewport

local DummyModel = Instance.new("Model", ViewWorld)
local Head3D = Instance.new("Part", DummyModel); Head3D.Name = "Head"; Head3D.Size = Vector3.new(1.2, 1.2, 1.2); Head3D.Color = Color3.fromRGB(185, 28, 28); Head3D.Material = Enum.Material.Neon; Head3D.Anchored = true
local HeadMesh = Instance.new("SpecialMesh", Head3D); HeadMesh.MeshType = Enum.MeshType.Head
local UpperTorso = Instance.new("Part", DummyModel); UpperTorso.Name = "UpperTorso"; UpperTorso.Size = Vector3.new(2, 1.2, 1); UpperTorso.Position = Vector3.new(0, 0.4, 0); UpperTorso.Color = Color3.fromRGB(40, 40, 45); UpperTorso.Anchored = true
DummyModel.PrimaryPart = Head3D

local function RebuildAnatomicalDummyPreview(size)
    local baseScale = 1.2 + size
    Head3D.Size = Vector3.new(baseScale, baseScale, baseScale)
    Head3D.Position = Vector3.new(0, 1.4 + (size / 2), 0)
end

local currentAngle = 25
local function UpdateCamera3D()
    local rad = math.rad(currentAngle)
    local dDist = 6.5 + (Settings.HitboxSize * 0.8)
    ViewCam.CFrame = CFrame.new(Vector3.new(dDist * math.sin(rad), 0.8, dDist * math.cos(rad)), Vector3.new(0, 0.2, 0)) end

-- ==================== CRIADORES DE COMPONENTES DE UI ====================
local function AddSectionSeparator(text, parentCol)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 16); Frame.BackgroundTransparency = 1; Frame.Parent = parentCol
    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, 0, 1, 0); Label.BackgroundTransparency = 1; Label.Text = text; Label.TextColor3 = Color3.fromRGB(185, 28, 28); Label.Font = Enum.Font.GothamBold; Label.TextSize = 10; Label.TextXAlignment = Enum.TextXAlignment.Left; Label.Parent = Frame end

local function AddToggle(text, default, parentCol, descText, callback)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 36); Frame.BackgroundColor3 = Color3.fromRGB(22, 22, 26); Frame.Parent = parentCol
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 5)

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0.6, 0, 0, 16); Label.Position = UDim2.new(0, 6, 0, 2); Label.BackgroundTransparency = 1; Label.Text = text; Label.TextColor3 = Color3.fromRGB(230, 230, 230); Label.Font = Enum.Font.GothamBold; Label.TextSize = 10; Label.TextXAlignment = Enum.TextXAlignment.Left; Label.Parent = Frame
    local Desc = Instance.new("TextLabel")
    Desc.Size = UDim2.new(1, -12, 0, 14); Desc.Position = UDim2.new(0, 6, 0, 18); Desc.BackgroundTransparency = 1; Desc.Text = descText; Desc.TextColor3 = Color3.fromRGB(140, 140, 145); Desc.Font = Enum.Font.SourceSans; Desc.TextSize = 9; Desc.TextXAlignment = Enum.TextXAlignment.Left; Desc.Parent = Frame

    local Switch = Instance.new("TextButton")
    Switch.Size = UDim2.new(0, 26, 0, 12); Switch.Position = UDim2.new(1, -32, 0, 4); Switch.BackgroundColor3 = default and Color3.fromRGB(185, 28, 28) or Color3.fromRGB(50, 50, 55); Switch.Text = ""; Switch.Parent = Frame
    Instance.new("UICorner", Switch).CornerRadius = UDim.new(1, 0)
    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.new(0, 8, 0, 8); Knob.Position = default and UDim2.new(1, -11, 0.5, -4) or UDim2.new(0, 3, 0.5, -4); Knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255); Knob.Parent = Switch
    Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)

    AddConnection(Switch.MouseButton1Click:Connect(function()
        default = not default
        TweenService:Create(Switch, TweenInfo.new(0.1), {BackgroundColor3 = default and Color3.fromRGB(185, 28, 28) or Color3.fromRGB(50, 50, 55)}):Play()
        TweenService:Create(Knob, TweenInfo.new(0.1), {Position = default and UDim2.new(1, -11, 0.5, -4) or UDim2.new(0, 3, 0.5, -4)}):Play()
        callback(default)
    end))
end

local function AddSlider(text, min, max, default, parentCol, descText, callback)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 44); Frame.BackgroundColor3 = Color3.fromRGB(22, 22, 26); Frame.Parent = parentCol
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 5)

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -16, 0, 14); Label.Position = UDim2.new(0, 6, 0, 2); Label.BackgroundTransparency = 1; Label.Text = text .. ": " .. tostring(default); Label.TextColor3 = Color3.fromRGB(230, 230, 230); Label.Font = Enum.Font.GothamBold; Label.TextSize = 10; Label.TextXAlignment = Enum.TextXAlignment.Left; Label.Parent = Frame
    local Desc = Instance.new("TextLabel")
    Desc.Size = UDim2.new(1, -12, 0, 14); Desc.Position = UDim2.new(0, 6, 0, 16); Desc.BackgroundTransparency = 1; Desc.Text = descText; Desc.TextColor3 = Color3.fromRGB(140, 140, 145); Desc.Font = Enum.Font.SourceSans; Desc.TextSize = 9; Desc.TextXAlignment = Enum.TextXAlignment.Left; Desc.Parent = Frame

    local Track = Instance.new("TextButton")
    Track.Size = UDim2.new(1, -12, 0, 3); Track.Position = UDim2.new(0, 6, 1, -5); Track.BackgroundColor3 = Color3.fromRGB(45, 45, 50); Track.Text = ""; Track.Parent = Frame
    local Fill = Instance.new("Frame")
    Fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0); Fill.BackgroundColor3 = Color3.fromRGB(185, 28, 28); Fill.BorderSizePixel = 0; Fill.Parent = Track

    local active = false
    local function processScale(input)
        local scale = math.clamp((input.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
        Fill.Size = UDim2.new(scale, 0, 1, 0)
        local value = math.floor((min + (max - min) * scale) * 10) / 10
        Label.Text = text .. ": " .. tostring(value)
        callback(value)
    end
    AddConnection(Track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then active = true; processScale(input) end end))
    AddConnection(UserInputService.InputChanged:Connect(function(input)
        if active and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then processScale(input) end end))
    AddConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then active = false end end))
end

local function AddSelector(text, options, default, parentCol, descText, callback)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 38); Frame.BackgroundColor3 = Color3.fromRGB(22, 22, 26); Frame.Parent = parentCol
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 5)

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0.55, 0, 0, 14); Label.Position = UDim2.new(0, 6, 0, 2); Label.BackgroundTransparency = 1; Label.Text = text; Label.TextColor3 = Color3.fromRGB(230, 230, 230); Label.Font = Enum.Font.GothamBold; Label.TextSize = 10; Label.TextXAlignment = Enum.TextXAlignment.Left; Label.Parent = Frame
    local Desc = Instance.new("TextLabel")
    Desc.Size = UDim2.new(1, -12, 0, 14); Desc.Position = UDim2.new(0, 6, 0, 16); Desc.BackgroundTransparency = 1; Desc.Text = descText; Desc.TextColor3 = Color3.fromRGB(140, 140, 145); Desc.Font = Enum.Font.SourceSans; Desc.TextSize = 9; Desc.TextXAlignment = Enum.TextXAlignment.Left; Desc.Parent = Frame

    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(0, 70, 0, 16); Btn.Position = UDim2.new(1, -76, 0, 4); Btn.BackgroundColor3 = Color3.fromRGB(36, 36, 40); Btn.Text = default; Btn.TextColor3 = Color3.fromRGB(230, 230, 230); Btn.Font = Enum.Font.GothamBold; Btn.TextSize = 9; Btn.Parent = Frame
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 4)

    local currentIndex = table.find(options, default) or 1
    AddConnection(Btn.MouseButton1Click:Connect(function()
        currentIndex = currentIndex + 1; if currentIndex > #options then currentIndex = 1 end
        Btn.Text = options[currentIndex]
        callback(options[currentIndex])
    end))
end

local function UpdateCrosshairVisuals()
    if not Settings.CrosshairEnabled then CrosshairBase.Visible = false; return end
    CrosshairBase.Visible = true
    local color = Color3.fromRGB(Settings.CrosshairColorR, Settings.CrosshairColorG, Settings.CrosshairColorB)
    local size, gap, mode = Settings.CrosshairSize, Settings.CrosshairGap, Settings.CrosshairType

    if mode == "Ponto" then
        CrosshairObjects.Dot.Visible = true; CrosshairObjects.Dot.Size = UDim2.new(0, 4, 0, 4); CrosshairObjects.Dot.BackgroundColor3 = color
        for i = 1, 4 do CrosshairObjects.Lines[i].Visible = false end
    elseif mode == "X" or mode == "Padrão" then
        CrosshairObjects.Dot.Visible = (mode == "Padrão"); CrosshairObjects.Dot.Size = UDim2.new(0, 2, 0, 2); CrosshairObjects.Dot.BackgroundColor3 = color
        for i = 1, 4 do
            local arm = CrosshairObjects.Lines[i]; arm.Visible = true; arm.BackgroundColor3 = color
            if mode == "X" then
                arm.Size = UDim2.new(0, size, 0, 2)
                if i == 1 then arm.Position = UDim2.new(0.5, -gap - size/2, 0.5, -gap - size/2); arm.Rotation = 45
                elseif i == 2 then arm.Position = UDim2.new(0.5, gap + size/2, 0.5, -gap - size/2); arm.Rotation = -45
                elseif i == 3 then arm.Position = UDim2.new(0.5, -gap - size/2, 0.5, gap + size/2); arm.Rotation = -45
                elseif i == 4 then arm.Position = UDim2.new(0.5, gap + size/2, 0.5, gap + size/2); arm.Rotation = 45 end
            else
                arm.Rotation = 0
                if i == 1 then arm.Position = UDim2.new(0.5, -gap - size, 0.5, -1); arm.Size = UDim2.new(0, size, 0, 2)
                elseif i == 2 then arm.Position = UDim2.new(0.5, gap, 0.5, -1); arm.Size = UDim2.new(0, size, 0, 2)
                elseif i == 3 then arm.Position = UDim2.new(0.5, -1, 0.5, -gap - size); arm.Size = UDim2.new(0, 2, 0, size)
                elseif i == 4 then arm.Position = UDim2.new(0.5, -1, 0.5, gap); arm.Size = UDim2.new(0, 2, 0, size) end
            end
        end
    end
end

local function RedrawCrosshairPreview()
    local color = Color3.fromRGB(Settings.CrosshairColorR, Settings.CrosshairColorG, Settings.CrosshairColorB)
    local size, gap, mode = Settings.CrosshairSize, Settings.CrosshairGap, Settings.CrosshairType
    if mode == "Ponto" then
        SimDot.Visible = true; SimDot.Size = UDim2.new(0, 4, 0, 4); SimDot.BackgroundColor3 = color
        for i = 1, 4 do SimLines[i].Visible = false end
    else
        SimDot.Visible = (mode == "Padrão"); SimDot.Size = UDim2.new(0, 2, 0, 2); SimDot.BackgroundColor3 = color
        for i = 1, 4 do
            local arm = SimLines[i]; arm.Visible = true; arm.BackgroundColor3 = color
            if mode == "X" then
                arm.Size = UDim2.new(0, size, 0, 2)
                if i == 1 then arm.Position = UDim2.new(0, -gap - size/2, 0, -gap - size/2); arm.Rotation = 45
                elseif i == 2 then arm.Position = UDim2.new(0, gap + size/2, 0, -gap - size/2); arm.Rotation = -45
                elseif i == 3 then arm.Position = UDim2.new(0, -gap - size/2, 0, gap + size/2); arm.Rotation = -45
                elseif i == 4 then arm.Position = UDim2.new(0, gap + size/2, 0, gap + size/2); arm.Rotation = 45 end
            else
                arm.Rotation = 0
                if i == 1 then arm.Position = UDim2.new(0, -gap - size/2, 0, 0); arm.Size = UDim2.new(0, size, 0, 2)
                elseif i == 2 then arm.Position = UDim2.new(0, gap + size/2, 0, 0); arm.Size = UDim2.new(0, size, 0, 2)
                elseif i == 3 then arm.Position = UDim2.new(0, 0, 0, -gap - size/2); arm.Size = UDim2.new(0, 2, 0, size)
                elseif i == 4 then arm.Position = UDim2.new(0, 0, 0, gap + size/2); arm.Size = UDim2.new(0, 2, 0, size) end
            end
        end
    end
end

-- ==================== ELEMENTOS DO MENU ====================
local GLeft, GRight = Paginas["Geral"].Left, Paginas["Geral"].Right
AddSectionSeparator("GERAL", GLeft)
AddToggle("Checar Paredes", Settings.WallCheck, GLeft, "Raycast para obstruções.", function(v) Settings.WallCheck = v end)
AddToggle("Multi-Bone Scan", Settings.MultiBoneScan, GLeft, "Busca ossos alternativos.", function(v) Settings.MultiBoneScan = v end)
AddToggle("Wall Penetration", Settings.WallPenetration, GLeft, "Atravessa paredes finas.", function(v) Settings.WallPenetration = v end)
AddSlider("Max Penetration", 0.5, 10, Settings.MaxPenetrationThick, GLeft, "Espessura máx.", function(v) Settings.MaxPenetrationThick = v end)
AddSectionSeparator("PREDIÇÃO VETORIAL", GRight)
AddToggle("Previsão Ativa", Settings.MovementPrediction, GRight, "Antecipa movimentação.", function(v) Settings.MovementPrediction = v end)
AddToggle("Anti-Lag", Settings.AntiLagFiltering, GRight, "Filtra variações de rede.", function(v) Settings.AntiLagFiltering = v end)
AddToggle("Ignorar Time", Settings.TeamCheck, GRight, "Filtra jogadores aliados.", function(v) Settings.TeamCheck = v end)

local ALeft, ARight = Paginas["Aimbot"].Left, Paginas["Aimbot"].Right
AddSectionSeparator("AIMBOT ENGINE", ALeft)
AddToggle("Ativar Aimbot", Settings.AimbotEnabled, ALeft, "Ativa trava automática.", function(v) Settings.AimbotEnabled = v end)
AddSelector("Prioridade", {"Distancia FOV", "Menor Vida", "Proximidade"}, Settings.TargetPriority, ALeft, "Seleção de alvo.", function(v) Settings.TargetPriority = v end)
AddSelector("Hitbox Base", {"Head", "Torso", "HumanoidRootPart"}, Settings.Hitbox, ALeft, "Osso preferencial.", function(v) Settings.Hitbox = v end)
AddSlider("Smooth Value", 1, 25, Settings.SmoothValue, ALeft, "Suavidade (1 = instantâneo).", function(v) Settings.SmoothValue = v end)
AddToggle("Smooth Dinâmico", Settings.DynamicSmoothness, ALeft, "Ajusta por distância.", function(v) Settings.DynamicSmoothness = v end)
AddSlider("Intensidade Dinâmica", 1, 15, Settings.DynamicSmoothMultiplier, ALeft, "Multiplicador de smooth.", function(v) Settings.DynamicSmoothMultiplier = v end)
AddSlider("Sticky Strength", 5, 100, Settings.StickyStrength, ALeft, "Aderência ao alvo.", function(v) Settings.StickyStrength = v end)

AddSectionSeparator("FLICK ENGINE HÍBRIDO", ARight)
AddToggle("Ativar Flick Shot", Settings.FlickEnabled, ARight, "Puxa no clique/toque de tela.", function(v) Settings.FlickEnabled = v end)
AddSlider("Flick Smooth", 1, 10, Settings.FlickSmooth, ARight, "Suavidade do puxão rápido.", function(v) Settings.FlickSmooth = v end)
AddSlider("Flick FOV Graus", 1, 90, Settings.FlickFovDegrees, ARight, "Tamanho máximo do FOV do Flick.", function(v) Settings.FlickFovDegrees = v end)
AddSectionSeparator("BALÍSTICA AVANÇADA", ARight)
AddToggle("Compensar Queda", Settings.BallisticCorrection, ARight, "Ajusta arco balístico.", function(v) Settings.BallisticCorrection = v end)
AddToggle("Auto-Calibração Real", Settings.AutoCalibrateUniversal, ARight, "Sonda o Workspace em tempo real.", function(v) Settings.AutoCalibrateUniversal = v end)
AddSlider("Velocidade Manual", 100, 4000, Settings.MuzzleVelocity, ARight, "Usado se Auto-Calibração estiver OFF.", function(v) Settings.MuzzleVelocity = v end)

-- ==================== INJEÇÃO EXCLUSIVA: CORE RAGE ULTRA CINEMATIC UPGRADE ====================
AddSectionSeparator("CORE RAGE ENGINE", ALeft)
AddToggle("Aimbot Rage", Settings.RageEnabled, ALeft, "Ativa travamento agressivo sem FOV.", function(v) Settings.RageEnabled = v end)
AddSelector("Rage Hitbox", {"Head", "HumanoidRootPart", "UpperTorso"}, Settings.RageHitbox, ALeft, "Osso focado pelo motor Rage.", function(v) Settings.RageHitbox = v end)
AddToggle("Rage Wall Check", Settings.RageWallCheck, ALeft, "Verifica paredes para o modo Rage.", function(v) Settings.RageWallCheck = v end)
AddToggle("Instant Snap", Settings.RageInstantSnapping, ALeft, "Ignora suavidade física e teleporta a mira.", function(v) Settings.RageInstantSnapping = v end)
AddSlider("Cinematic Smooth", 1.0, 10.0, Settings.RageSmoothness, ALeft, "Suavidade física baseada em Bézier/Arrasto.", function(v) Settings.RageSmoothness = v end)
AddToggle("Estabilizador Kalman", Settings.RageStabilizer, ALeft, "Neutraliza o Jitter e Lag de rede do inimigo.", function(v) Settings.RageStabilizer = v end)
AddSlider("Alcance Máximo", 100, 5000, Settings.RageMaxDistance, ALeft, "Distância máxima operacional.", function(v) Settings.RageMaxDistance = v end)

local LLeft, LRight = Paginas["Lock"].Left, Paginas["Lock"].Right
AddSectionSeparator("TRAVA MAGNÉTICA", LLeft)
AddToggle("Magnetic Snap", Settings.MagneticVectorSnapping, LLeft, "Atração gravitacional fluida.", function(v) Settings.MagneticVectorSnapping = v end)
AddSlider("Expoente Grav.", 1.5, 4.5, Settings.GravitationalExponent, LLeft, "Intensidade da atração.", function(v) Settings.GravitationalExponent = v end)
AddToggle("Sticky Lock", Settings.StickyLock, LLeft, "Mantém alvo fora do FOV.", function(v) Settings.StickyLock = v end)
AddSlider("Breakout Force", 5, 50, Settings.BreakoutForce, LLeft, "Esforço para soltar trava.", function(v) Settings.BreakoutForce = v end)
AddSectionSeparator("ESTABILIZAÇÃO", LRight)
AddToggle("Redução de Perto", Settings.ProximityDampEnabled, LRight, "Suaviza quebras próximas.", function(v) Settings.ProximityDampEnabled = v end)
AddSlider("Força Mínima %", 10, 90, Settings.ProximityMinStrength, LRight, "Força residual.", function(v) Settings.ProximityMinStrength = v end)
AddToggle("Fricção Humana", Settings.HumanFriction, LRight, "Reduz por velocidade.", function(v) Settings.HumanFriction = v end)
AddToggle("Tremor Neuromuscular", Settings.NeuromuscularTremor, LRight, "Micro-oscilações orgânicas.", function(v) Settings.NeuromuscularTremor = v end)

local FLeft, FRight = Paginas["Fov"].Left, Paginas["Fov"].Right
AddSectionSeparator("DIMENSIONAMENTO", FLeft)
AddToggle("Exibir Raio FOV", Settings.ShowFOV, FLeft, "Desenha círculo em tempo real.", function(v) Settings.ShowFOV = v end)
AddSlider("Abertura (Graus)", 1, 180, Settings.FovDegrees, FLeft, "Escala angular da mira.", function(v) Settings.FovDegrees = v end)
AddSectionSeparator("ADAPTAÇÃO", FRight)
AddToggle("FOV Adaptativo", Settings.AdaptiveFovEnabled, FRight, "Modifica por velocidade/distância.", function(v) Settings.AdaptiveFovEnabled = v end)
AddSlider("Multiplicador", 0, 1, Settings.AdaptiveFovMultiplier, FRight, "Intensidade de adaptação.", function(v) Settings.AdaptiveFovMultiplier = v end)

local CLeft, CRight = Paginas["Crosshair"].Left, Paginas["Crosshair"].Right
AddSectionSeparator("RETÍCULA CENTRAL", CLeft)
AddToggle("Ativar Crosshair", Settings.CrosshairEnabled, CLeft, "Desenha sobreposição estável.", function(v) Settings.CrosshairEnabled = v; UpdateCrosshairVisuals(); RedrawCrosshairPreview() end)
AddSelector("Geometria", {"Padrão", "Ponto", "X"}, Settings.CrosshairType, CLeft, "Tipo estrutural.", function(v) Settings.CrosshairType = v; UpdateCrosshairVisuals(); RedrawCrosshairPreview() end)
AddSlider("Tamanho Protetor", 2, 40, Settings.CrosshairSize, CLeft, "Comprimento das linhas.", function(v) Settings.CrosshairSize = v; UpdateCrosshairVisuals(); RedrawCrosshairPreview() end)
AddSlider("Espaçamento (Gap)", 0, 20, Settings.CrosshairGap, CLeft, "Abertura central.", function(v) Settings.CrosshairGap = v; UpdateCrosshairVisuals(); RedrawCrosshairPreview() end)
AddSectionSeparator("MARCADORES", CRight)
AddToggle("Snap Markers", Settings.SnapMarkers, CRight, "Coloca brackets [] ao redor do alvo.", function(v) Settings.SnapMarkers = v end)

local HLeft = Paginas["Hitbox"].Left
AddSectionSeparator("HITBOX EXPANDER", HLeft)
AddToggle("Ativar Expansor", Settings.HitboxExpander, HLeft, "Injeta hitbox invisível.", function(v) Settings.HitboxExpander = v; for _, c in ipairs(CollectionService:GetTagged(TARGET_TAG)) do if validateCharacter(c) then UpdateExpandedHitboxes(c, Settings.HitboxSize) end end end)
AddSlider("Tamanho Adicional", 0, 15, Settings.HitboxSize, HLeft, "Studs agregados ao volume original.", function(v) Settings.HitboxSize = v; RebuildAnatomicalDummyPreview(v); UpdateCamera3D(); for _, c in ipairs(CollectionService:GetTagged(TARGET_TAG)) do if validateCharacter(c) then UpdateExpandedHitboxes(c, v) end end end)

UpdateCrosshairVisuals(); RedrawCrosshairPreview(); RebuildAnatomicalDummyPreview(Settings.HitboxSize); UpdateCamera3D()

-- ==================== GERENCIAMENTO DE TARGETS SÍNCRONOS ====================
local ActiveTargets = {}
local function tagCharacter(char)
    local humanoid = char:WaitForChild("Humanoid", 5)
    if humanoid then
        CollectionService:AddTag(char, TARGET_TAG)
        local diedConn; diedConn = humanoid.Died:Connect(function()
            CollectionService:RemoveTag(char, TARGET_TAG)
            diedConn:Disconnect()
            UpdateExpandedHitboxes(char, 0)
        end)
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then
        if p.Character then task.spawn(tagCharacter, p.Character); task.spawn(UpdateExpandedHitboxes, p.Character, Settings.HitboxSize) end
        AddConnection(p.CharacterAdded:Connect(function(char) tagCharacter(char); task.wait(0.5); UpdateExpandedHitboxes(char, Settings.HitboxSize) end))
    end
end
AddConnection(Players.PlayerAdded:Connect(function(p)
    AddConnection(p.CharacterAdded:Connect(function(char) tagCharacter(char); task.wait(0.5); UpdateExpandedHitboxes(char, Settings.HitboxSize) end)) end))
AddConnection(CollectionService:GetInstanceAddedSignal(TARGET_TAG):Connect(function(char) if not table.find(ActiveTargets, char) then table.insert(ActiveTargets, char); task.spawn(UpdateExpandedHitboxes, char, Settings.HitboxSize) end end))
AddConnection(CollectionService:GetInstanceRemovedSignal(TARGET_TAG):Connect(function(char) local idx = table.find(ActiveTargets, char); if idx then table.remove(ActiveTargets, idx) end end))
for _, char in ipairs(CollectionService:GetTagged(TARGET_TAG)) do table.insert(ActiveTargets, char) end

local TouchVelocity2D, ComputedPixelRadius, ComputedFlickPixelRadius, EscapeCooldown, DynamicUserWeight = 0, 55, 25, 0.0, 1.0
local FlickActiveThisFrame, LastFlickTime = false, 0

AddConnection(UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        TouchVelocity2D = input.Delta.Magnitude
        DynamicUserWeight = TouchVelocity2D > 1.5 and math.clamp(1.0 - (TouchVelocity2D / Settings.BreakoutForce), 0.05, 1.0) or 1.0
        if TouchVelocity2D > Settings.BreakoutForce then
            EscapeCooldown = 0.25
            if not Settings.StickyLock then CurrentTarget = nil; TargetPart = nil end
        end
    end end))

-- SCANNER ASSÍNCRONO DE ALVOS (OTIMIZADO COM PRÉ-FILTRO DE DISTÂNCIA VETORIAL)
task.spawn(function()
    local fc = 0
    while ENV.PremonitionLoopActive do
        task.wait(0.05); fc = fc + 1
        if fc % 20 == 0 then FovSimCircle.Size = UDim2.new(0, Settings.FovDegrees * 1.8, 0, Settings.FovDegrees * 1.8); FlickSimCircle.Size = UDim2.new(0, Settings.FlickFovDegrees * 1.8, 0, Settings.FlickFovDegrees * 1.8); FlickSimCircle.Visible = Settings.FlickEnabled end
        if fc % 40 == 0 then CleanMotionCache() end
        if Settings.HitboxExpander and Settings.HitboxSize > 0 and fc % 60 == 0 then
            for _, char in ipairs(ActiveTargets) do if validateCharacter(char) then UpdateExpandedHitboxes(char, Settings.HitboxSize) end end
        end

        local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

        -- ==================== MOTOR ISOLADO: CORE RAGE ENGINE DISPARADOR ====================
        if Settings.RageEnabled and localRoot then
            local closestRageTarget = nil
            local minRageDist = Settings.RageMaxDistance

            for _, char in ipairs(ActiveTargets) do
                if validateCharacter(char) then
                    local p = Players:GetPlayerFromCharacter(char)
                    if p and AdvancedTeamCheck(p) then
                        local rPart = char:FindFirstChild(Settings.RageHitbox)
                        if rPart and rPart:IsA("BasePart") then
                            local d3D = (rPart.Position - localRoot.Position).Magnitude
                            if d3D < minRageDist then
                                local isRageVisible = true
                                if Settings.RageWallCheck then
                                    UpdateIgnoreList()
                                    local rayResult = Workspace:Raycast(Camera.CFrame.Position, rPart.Position - Camera.CFrame.Position, WALL_CHECK_PARAMS)
                                    if rayResult and not rayResult.Instance:IsDescendantOf(char) then
                                        isRageVisible = false
                                    end
                                end
                                if isRageVisible then
                                    minRageDist = d3D
                                    closestRageTarget = rPart
                                end
                            end
                        end
                    end
                end
            end
            CoreRageTarget = closestRageTarget
        else
            CoreRageTarget = nil
        end

        -- MOTOR CONVENCIONAL DE PREDIÇÃO E AIMBOT
        if (Settings.AimbotEnabled or Settings.FlickEnabled) and EscapeCooldown <= 0 then
            ScreenCenter = GetTrueScreenCenter()
            local bestScore, selectedPlayer, selectedPart, ignoreScan = math.huge, nil, nil, false

            if Settings.StickyLock and CurrentTarget and TargetPart and TargetPart.Parent then
                if validateCharacter(CurrentTarget.Character) and AdvancedTeamCheck(CurrentTarget) then
                    local exp = ScanDynamicExposedMassa(CurrentTarget.Character)
                    if exp then ignoreScan = true; TargetPart = exp else CurrentTarget = nil; TargetPart = nil end
                else CurrentTarget = nil; TargetPart = nil end
            end

            if not ignoreScan then
                local radius = FlickActiveThisFrame and ComputedFlickPixelRadius or ComputedPixelRadius
                for _, char in ipairs(ActiveTargets) do
                    if validateCharacter(char) then
                        local p = Players:GetPlayerFromCharacter(char)
                        if p and AdvancedTeamCheck(p) then
                            local approxPart = char:FindFirstChild("HumanoidRootPart")
                            if approxPart and localRoot and (approxPart.Position - localRoot.Position).Magnitude > 600 then
                                continue
                            end

                            local exp = ScanDynamicExposedMassa(char)
                            if exp and exp.Parent then
                                TargetMotionCache[tostring(exp) .. "_" .. tostring(char)] = { lastVelocity = exp.AssemblyLinearVelocity or Vector3.zero, lastUpdate = os.clock() }
                                local screenPos, onScreen = Camera:WorldToViewportPoint(exp.Position)
                                if onScreen then
                                    local mDist = (Vector2.new(screenPos.X, screenPos.Y) - ScreenCenter).Magnitude
                                    if mDist <= radius then
                                        local score = Settings.TargetPriority == "Distancia FOV" and mDist or (localRoot and (exp.Position - localRoot.Position).Magnitude or mDist)
                                        if score < bestScore then bestScore = score; selectedPlayer = p; selectedPart = exp end
                                    end
                                end
                            end
                        end
                    end
                end
                if selectedPlayer then CurrentTarget = selectedPlayer; TargetPart = selectedPart
                elseif not Settings.StickyLock or FlickActiveThisFrame then CurrentTarget = nil; TargetPart = nil end
            end
        end
    end
end)

-- ==================== LAÇO DE RENDERIZAÇÃO PRINCIPAL (HEARTBEAT) ====================
AddConnection(RunService.Heartbeat:Connect(function(dt)
    dt = math.clamp(dt, 0.001, 0.033)
    ScreenCenter = GetTrueScreenCenter()

    if EscapeCooldown > 0 then EscapeCooldown = math.max(EscapeCooldown - dt, 0) end
    if TouchVelocity2D <= 1.5 then DynamicUserWeight = math.min(DynamicUserWeight + (dt * Settings.WeightRecoverySpeed), 1.0) end

    local currentFov = Settings.FovDegrees
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if Settings.AdaptiveFovEnabled and TargetPart and TargetPart.Parent and myRoot then
        currentFov = CalculateAdaptiveFov(Settings.FovDegrees, TargetPart, myRoot) 
    end

    ComputedPixelRadius = CalculateAngularRadius(currentFov)
    ComputedFlickPixelRadius = CalculateAngularRadius(Settings.FlickFovDegrees)

    if FOVCircle then 
        FOVCircle.Size = UDim2.new(0, ComputedPixelRadius * 2, 0, ComputedPixelRadius * 2)
        FOVCircle.Position = UDim2.new(0, ScreenCenter.X, 0, ScreenCenter.Y)
        FOVCircle.Visible = Settings.ShowFOV 
        Stroke.Color = Color3.fromRGB(Settings.FovColorR, Settings.FovColorG, Settings.FovColorB)
    end
    if FlickFOVCircle then 
        FlickFOVCircle.Size = UDim2.new(0, ComputedFlickPixelRadius * 2, 0, ComputedFlickPixelRadius * 2)
        FlickFOVCircle.Position = UDim2.new(0, ScreenCenter.X, 0, ScreenCenter.Y)
        FlickFOVCircle.Visible = Settings.FlickEnabled and Settings.ShowFOV 
        FlickSimStroke.Color = Color3.fromRGB(255, 80, 80)
    end
    if CrosshairBase then CrosshairBase.Position = UDim2.new(0, ScreenCenter.X, 0, ScreenCenter.Y) end

    -- ==================== PIPELINE EXECUTION: CORE RAGE MASTER UPGRADE ====================
    if Settings.RageEnabled and CoreRageTarget and CoreRageTarget.Parent then
        -- 1. Filtro Kalman atuando sobre a posição do osso alvo
        local rawTargetPos = CoreRageTarget.Position
        local filteredTargetPos = ProcessKalmanRage(CoreRageTarget)
        
        local targetCFrame = CFrame.new(Camera.CFrame.Position, filteredTargetPos)
        
        if Settings.RageInstantSnapping then
            Camera.CFrame = targetCFrame
        else
            -- 2. Sistema Quaternião Slerp nativo + Vetor de Arrasto Hidrodinâmico
            local camRot = Camera.CFrame.Rotation
            local targetRot = targetCFrame.Rotation
            
            -- Fatores de aceleração de fluido baseado na suavidade configurada
            local smoothnessFactor = math.max(Settings.RageSmoothness, 1.0)
            local fluidFriction = 0.18 / smoothnessFactor
            
            -- 3. Interpolação por Curva de Bézier Angular Cúbica Dinâmica
            local angleDiff = math.acos(math.clamp(Camera.CFrame.LookVector:Dot((filteredTargetPos - Camera.CFrame.Position).Unit), -1, 1))
            local bezierT = math.clamp(1.0 - (angleDiff / math.pi), 0.1, 1.0)
            -- Curva suavizadora estrutural s(t)
            local smoothT = GetBezierPoint(Vector3.new(0,0,0), Vector3.new(0.4, 0.8, 0), Vector3.new(1,1,0), bezierT).X
            
            local finalAlpha = math.clamp(fluidFriction * smoothT * (dt * 60), 0.01, 0.95)
            
            -- Executa o Slerp Quaternião via Lerp nativo de CFrame de Rotação Pura
            Camera.CFrame = CFrame.new(Camera.CFrame.Position) * camRot:Lerp(targetRot, finalAlpha)
        end
        return
    end

    -- SISTEMA ORIGINAL DE TRAVAMENTO E LERPS DO AIMBOT CONVENCIONAL
    if (Settings.AimbotEnabled or Settings.FlickEnabled) and CurrentTarget and TargetPart and TargetPart.Parent and validateCharacter(CurrentTarget.Character) and EscapeCooldown <= 0 then
        if myRoot then
            local targetWorldPos = Settings.MovementPrediction and CalculateAdvancedPrediction(TargetPart, dt) or TargetPart.Position
            local screenPos, onScreen = Camera:WorldToViewportPoint(targetWorldPos)
            if onScreen then
                if Settings.SnapMarkers then
                    SnapLeft.Visible = true; SnapRight.Visible = true
                    SnapLeft.Position = UDim2.new(0, screenPos.X - 16, 0, screenPos.Y - 14)
                    SnapRight.Position = UDim2.new(0, screenPos.X + 8, 0, screenPos.Y - 14)
                else SnapLeft.Visible = false; SnapRight.Visible = false end

                local targetCFrame = CFrame.new(Camera.CFrame.Position, targetWorldPos)
                local alpha = 0
                local isFlickPuxando = false

                if FlickActiveThisFrame and Settings.FlickEnabled then
                    local elapsed = os.clock() - LastFlickTime
                    if elapsed < 0.1 then
                        isFlickPuxando = true
                        alpha = math.clamp(1.0 / math.max(Settings.FlickSmooth, 1), 0.1, 1.0) * (1.0 - (elapsed / 0.1))
                        if alpha > 0.88 then Camera.CFrame = targetCFrame; FlickActiveThisFrame = false; return end
                    else FlickActiveThisFrame = false end
                end

                if not isFlickPuxando and Settings.AimbotEnabled then
                    local mDist = (Vector2.new(screenPos.X, screenPos.Y) - ScreenCenter).Magnitude
                    if mDist <= ComputedPixelRadius or Settings.StickyLock then
                        local baseSmooth = Settings.SmoothValue
                        if Settings.DynamicSmoothness then baseSmooth = Settings.SmoothValue * (1.0 + (math.clamp((targetWorldPos - myRoot.Position).Magnitude / 50, 0.5, 4.0) * (Settings.DynamicSmoothMultiplier / 10))) end
                        alpha = (1 / math.max(baseSmooth, 1)) * math.exp(-math.pow(math.clamp(mDist / ComputedPixelRadius, 0, 1), 2) / 0.405) * (Settings.StickyStrength / 100)

                        if Settings.MagneticVectorSnapping and alpha > 0.001 then
                            local pull = math.pow(1 - math.clamp(mDist / ComputedPixelRadius, 0, 1), Settings.GravitationalExponent) * 0.6
                            if pull > 0.05 then targetCFrame = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + Camera.CFrame.LookVector:Lerp((targetWorldPos - Camera.CFrame.Position).Unit, math.min(pull * 1.5, 0.9))) end
                        end
                        if Settings.HumanFriction then
                            local parentModel = TargetPart.Parent
                            if parentModel then
                                local motion = TargetMotionCache[tostring(TargetPart) .. "_" .. tostring(parentModel)]
                                if motion then alpha = alpha * (1.0 - math.clamp(motion.lastVelocity.Magnitude / 75, 0, 0.25)) end
                            end
                        end
                        if Settings.ProximityDampEnabled then alpha = alpha * math.clamp(((targetWorldPos - myRoot.Position).Magnitude - 6) / (Settings.ProximityMaxDistance - 6), Settings.ProximityMinStrength / 100, 1.0) end
                        alpha = alpha * DynamicUserWeight
                    end
                end

                alpha = math.clamp(alpha, 0.0, 0.92)
                if alpha > 0.005 then
                    if Settings.NeuromuscularTremor then
                        local time = os.clock(); local freq = 15.7 + (Settings.TremorIntensity * 0.3); local amp = (Settings.TremorIntensity / 2200) * (1.0 - (os.clock() % 2.5) / 5.0)
                        targetCFrame = targetCFrame * CFrame.Angles((math.sin(time * freq + 2.3) * 0.7) * amp, (math.cos(time * (freq * 1.3) + 1.7) * 0.6) * amp, 0)
                    end
                    Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, alpha)
                end
            end
        end
    else SnapLeft.Visible = false; SnapRight.Visible = false end
    TouchVelocity2D = 0; if not Settings.FlickEnabled then FlickActiveThisFrame = false end
end))

print("[PREMONITION ENGINE] Core Rage Master v2 Injetado com Sucesso!")