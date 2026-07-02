--[[
    ============================================================
    FULLY LOCAL AIMBOT + ESP + SILENT AIM SYSTEM (Luau / Roblox)
    Uso estritamente privado, educacional e em ambientes próprios
    ============================================================
    
    Features:
    - Aimbot com suavização
    - Silent Aim (redirecionamento de projéteis)
    - Bullet Prediction (predição de movimento + drop)
    - ESP completo (Box, Name, Distance, Health, Tracer, Skeleton)
    - Menu UI interativo com botão de toggle
    - FOV Circle dinâmico
    - Team Check / Wall Check
    - Configurações em tempo real via menu
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Camera = Workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- ==================== CONFIGURAÇÕES GLOBAIS ====================
getgenv().AimbotESP = {
    -- Teclas
    MenuToggleKey = Enum.KeyCode.Insert,      -- Abrir/fechar menu
    AimbotToggleKey = Enum.KeyCode.F,         -- Toggle aimbot
    ESPToggleKey = Enum.KeyCode.G,            -- Toggle ESP
    AimKey = Enum.UserInputType.MouseButton2, -- Botão de mira (RMB)
    
    -- Aimbot
    AimbotEnabled = true,
    AimbotSmoothness = 0.12,
    AimbotFOV = 180,
    AimbotTargetPart = "Head", -- Head, HumanoidRootPart, UpperTorso, Torso
    AimbotTeamCheck = true,
    AimbotWallCheck = false,
    AimbotMaxDistance = 500,
    
    -- Silent Aim
    SilentAimEnabled = false,
    SilentAimHitChance = 100, -- % de chance de acertar (0-100)
    SilentAimFOV = 120,
    SilentAimTeamCheck = true,
    SilentAimWallCheck = false,
    SilentAimMaxDistance = 400,
    
    -- Bullet Prediction
    PredictionEnabled = false,
    BulletSpeed = 2500,      -- Velocidade do projétil (studs/segundo)
    BulletDrop = 0,          -- Gravidade do projétil (0 = sem drop)
    
    -- ESP
    ESPEnabled = true,
    ESPBox = true,
    ESPBoxFilled = false,
    ESPName = true,
    ESPDistance = true,
    ESPTracer = true,
    ESPSkeleton = false,
    ESPHealth = true,
    ESPHealthBar = true,
    ESPWeapon = false,
    ESPTeamCheck = true,
    ESPMaxDistance = 1500,
    ESPShowTeam = false,     -- Mostrar ESP em teammates com cor diferente
    
    -- Cores
    ESPEnemyColor = Color3.fromRGB(255, 60, 60),
    ESPFriendColor = Color3.fromRGB(60, 255, 60),
    ESPTracerColor = Color3.fromRGB(255, 255, 255),
    ESPSkeletonColor = Color3.fromRGB(255, 255, 255),
    FOVColor = Color3.fromRGB(255, 255, 255),
    SilentAimFOVColor = Color3.fromRGB(255, 0, 255),
    MenuAccentColor = Color3.fromRGB(0, 170, 255),
    
    -- Menu
    MenuVisible = true,
    MenuPosition = UDim2.new(0, 100, 0, 100),
}

local Settings = getgenv().AimbotESP

-- ==================== VARIÁVEIS INTERNAS ====================
local AimbotActive = false
local ESPObjects = {}
local FOV_Circle = nil
local SilentAim_FOV_Circle = nil
local ScreenGui = nil
local MenuFrame = nil
local MenuButton = nil
local Connections = {}
local SilentAim_Connection = nil

-- ==================== UTILITÁRIOS ====================
local function IsPlayerAlive(player)
    if not player then return false end
    local character = player.Character
    if not character then return false end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health > 0
end

local function IsTeammate(player)
    if not player or not LocalPlayer then return false end
    if player == LocalPlayer then return true end
    if player.Team and LocalPlayer.Team then
        return player.Team == LocalPlayer.Team
    end
    return false
end

local function GetCharacterPart(player, partName)
    if not player then return nil end
    local character = player.Character
    if not character then return nil end
    return character:FindFirstChild(partName)
end

local function WorldToScreen(position)
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    return Vector2.new(screenPos.X, screenPos.Y), onScreen, screenPos.Z
end

local function GetDistance2D(posA, posB)
    return (posA - posB).Magnitude
end

local function GetDistance3D(posA, posB)
    return (posA - posB).Magnitude
end

local function RaycastWallCheck(origin, target)
    local direction = (target - origin)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    local result = Workspace:Raycast(origin, direction, raycastParams)
    if result then
        return false
    end
    return true
end

local function PredictPosition(targetPlayer, targetPartName)
    if not Settings.PredictionEnabled then
        local part = GetCharacterPart(targetPlayer, targetPartName)
        return part and part.Position
    end
    
    local part = GetCharacterPart(targetPlayer, targetPartName)
    if not part then return nil end
    
    local targetPos = part.Position
    local targetVel = part.Velocity
    local distance = GetDistance3D(Camera.CFrame.Position, targetPos)
    
    if Settings.BulletSpeed <= 0 then return targetPos end
    
    local timeToTarget = distance / Settings.BulletSpeed
    local predictedPos = targetPos + (targetVel * timeToTarget)
    
    -- Aplicar bullet drop (gravidade)
    if Settings.BulletDrop > 0 then
        predictedPos = predictedPos - Vector3.new(0, Settings.BulletDrop * timeToTarget * timeToTarget, 0)
    end
    
    return predictedPos
end

-- ==================== DRAWING CIRCLES ====================
local function CreateCircle(radius, color)
    local circle = Drawing.new("Circle")
    circle.Visible = false
    circle.Thickness = 1.5
    circle.NumSides = 64
    circle.Radius = radius
    circle.Filled = false
    circle.Transparency = 1
    circle.Color = color
    return circle
end

local function UpdateCircles()
    if not FOV_Circle then
        FOV_Circle = CreateCircle(Settings.AimbotFOV, Settings.FOVColor)
    end
    if not SilentAim_FOV_Circle then
        SilentAim_FOV_Circle = CreateCircle(Settings.SilentAimFOV, Settings.SilentAimFOVColor)
    end
    
    local mousePos = Vector2.new(Mouse.X, Mouse.Y + 36)
    
    FOV_Circle.Visible = Settings.AimbotEnabled
    FOV_Circle.Radius = Settings.AimbotFOV
    FOV_Circle.Color = Settings.FOVColor
    FOV_Circle.Position = mousePos
    
    SilentAim_FOV_Circle.Visible = Settings.SilentAimEnabled
    SilentAim_FOV_Circle.Radius = Settings.SilentAimFOV
    SilentAim_FOV_Circle.Color = Settings.SilentAimFOVColor
    SilentAim_FOV_Circle.Position = mousePos
end

-- ==================== ESP SYSTEM ====================
local SKELETON_CONNECTIONS = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"},
    -- Fallbacks R6
    {"Head", "Torso"},
    {"Torso", "Left Arm"},
    {"Torso", "Right Arm"},
    {"Torso", "Left Leg"},
    {"Torso", "Right Leg"},
}

local function CreateESPObject(player)
    local esp = {
        Player = player,
        Box = Drawing.new("Square"),
        BoxOutline = Drawing.new("Square"),
        BoxFill = Drawing.new("Square"),
        Name = Drawing.new("Text"),
        Distance = Drawing.new("Text"),
        Health = Drawing.new("Text"),
        Weapon = Drawing.new("Text"),
        Tracer = Drawing.new("Line"),
        HealthBar = Drawing.new("Line"),
        HealthBarOutline = Drawing.new("Line"),
        SkeletonLines = {},
    }
    
    -- Box
    esp.Box.Thickness = 1
    esp.Box.Filled = false
    esp.Box.Transparency = 1
    esp.Box.Visible = false
    
    -- Box Outline
    esp.BoxOutline.Thickness = 3
    esp.BoxOutline.Filled = false
    esp.BoxOutline.Transparency = 1
    esp.BoxOutline.Color = Color3.fromRGB(0, 0, 0)
    esp.BoxOutline.Visible = false
    
    -- Box Fill
    esp.BoxFill.Thickness = 1
    esp.BoxFill.Filled = true
    esp.BoxFill.Transparency = 0.15
    esp.BoxFill.Visible = false
    
    -- Name
    esp.Name.Size = 14
    esp.Name.Center = true
    esp.Name.Outline = true
    esp.Name.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.Name.Visible = false
    
    -- Distance
    esp.Distance.Size = 13
    esp.Distance.Center = true
    esp.Distance.Outline = true
    esp.Distance.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.Distance.Visible = false
    
    -- Health
    esp.Health.Size = 13
    esp.Health.Center = true
    esp.Health.Outline = true
    esp.Health.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.Health.Visible = false
    
    -- Weapon
    esp.Weapon.Size = 12
    esp.Weapon.Center = true
    esp.Weapon.Outline = true
    esp.Weapon.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.Weapon.Visible = false
    
    -- Tracer
    esp.Tracer.Thickness = 1
    esp.Tracer.Transparency = 1
    esp.Tracer.Visible = false
    
    -- Health Bar
    esp.HealthBar.Thickness = 2
    esp.HealthBar.Transparency = 1
    esp.HealthBar.Visible = false
    
    esp.HealthBarOutline.Thickness = 4
    esp.HealthBarOutline.Color = Color3.fromRGB(0, 0, 0)
    esp.HealthBarOutline.Transparency = 1
    esp.HealthBarOutline.Visible = false
    
    -- Skeleton
    for i = 1, #SKELETON_CONNECTIONS do
        local line = Drawing.new("Line")
        line.Thickness = 1.5
        line.Transparency = 1
        line.Visible = false
        table.insert(esp.SkeletonLines, line)
    end
    
    return esp
end

local function RemoveESPObject(player)
    if ESPObjects[player] then
        local esp = ESPObjects[player]
        esp.Box:Remove()
        esp.BoxOutline:Remove()
        esp.BoxFill:Remove()
        esp.Name:Remove()
        esp.Distance:Remove()
        esp.Health:Remove()
        esp.Weapon:Remove()
        esp.Tracer:Remove()
        esp.HealthBar:Remove()
        esp.HealthBarOutline:Remove()
        for _, line in ipairs(esp.SkeletonLines) do
            line:Remove()
        end
        ESPObjects[player] = nil
    end
end

local function UpdateESP()
    for player, esp in pairs(ESPObjects) do
        local shouldShow = false
        
        if Settings.ESPEnabled 
           and player ~= LocalPlayer 
           and IsPlayerAlive(player) 
           and player.Character then
            
            local isTeammate = IsTeammate(player)
            
            if not isTeammate or Settings.ESPShowTeam then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                local head = player.Character:FindFirstChild("Head")
                local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                
                if hrp and head and humanoid then
                    local rootPos = hrp.Position
                    local headPos = head.Position
                    local screenPos, onScreen, depth = WorldToScreen(rootPos)
                    local headScreen, headOnScreen = WorldToScreen(headPos + Vector3.new(0, 0.5, 0))
                    local footScreen, footOnScreen = WorldToScreen(rootPos - Vector3.new(0, 3, 0))
                    
                    local distance = GetDistance3D(Camera.CFrame.Position, rootPos)
                    
                    if onScreen and distance <= Settings.ESPMaxDistance then
                        shouldShow = true
                        
                        local color = isTeammate and Settings.ESPFriendColor or Settings.ESPEnemyColor
                        local healthPercent = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                        
                        -- Calcular tamanho da box
                        local boxHeight = math.abs(footScreen.Y - headScreen.Y)
                        local boxWidth = boxHeight * 0.55
                        
                        local boxPosition = Vector2.new(
                            screenPos.X - boxWidth / 2,
                            headScreen.Y
                        )
                        
                        -- Box
                        if Settings.ESPBox then
                            esp.Box.Size = Vector2.new(boxWidth, boxHeight)
                            esp.Box.Position = boxPosition
                            esp.Box.Color = color
                            esp.Box.Visible = true
                            
                            esp.BoxOutline.Size = Vector2.new(boxWidth, boxHeight)
                            esp.BoxOutline.Position = boxPosition
                            esp.BoxOutline.Visible = true
                            
                            esp.BoxFill.Size = Vector2.new(boxWidth, boxHeight)
                            esp.BoxFill.Position = boxPosition
                            esp.BoxFill.Color = color
                            esp.BoxFill.Visible = Settings.ESPBoxFilled
                        else
                            esp.Box.Visible = false
                            esp.BoxOutline.Visible = false
                            esp.BoxFill.Visible = false
                        end
                        
                        -- Name
                        if Settings.ESPName then
                            esp.Name.Text = player.Name
                            esp.Name.Position = Vector2.new(screenPos.X, headScreen.Y - 20)
                            esp.Name.Color = color
                            esp.Name.Visible = true
                        else
                            esp.Name.Visible = false
                        end
                        
                        -- Distance
                        if Settings.ESPDistance then
                            esp.Distance.Text = string.format("%.0fm", distance)
                            esp.Distance.Position = Vector2.new(screenPos.X, footScreen.Y + 6)
                            esp.Distance.Color = Color3.fromRGB(255, 255, 255)
                            esp.Distance.Visible = true
                        else
                            esp.Distance.Visible = false
                        end
                        
                        -- Health Text
                        if Settings.ESPHealth then
                            esp.Health.Text = string.format("%.0f HP", humanoid.Health)
                            esp.Health.Position = Vector2.new(screenPos.X, footScreen.Y + 20)
                            esp.Health.Color = Color3.fromRGB(255 * (1 - healthPercent), 255 * healthPercent, 0)
                            esp.Health.Visible = true
                        else
                            esp.Health.Visible = false
                        end
                        
                        -- Health Bar
                        if Settings.ESPHealthBar then
                            local barHeight = boxHeight
                            local barX = boxPosition.X - 6
                            local barTop = boxPosition.Y
                            local barBottom = barTop + barHeight
                            
                            esp.HealthBarOutline.From = Vector2.new(barX, barTop)
                            esp.HealthBarOutline.To = Vector2.new(barX, barBottom)
                            esp.HealthBarOutline.Visible = true
                            
                            local healthHeight = barHeight * healthPercent
                            esp.HealthBar.From = Vector2.new(barX, barBottom - healthHeight)
                            esp.HealthBar.To = Vector2.new(barX, barBottom)
                            esp.HealthBar.Color = Color3.fromRGB(255 * (1 - healthPercent), 255 * healthPercent, 0)
                            esp.HealthBar.Visible = true
                        else
                            esp.HealthBar.Visible = false
                            esp.HealthBarOutline.Visible = false
                        end
                        
                        -- Weapon
                        if Settings.ESPWeapon then
                            local tool = player.Character:FindFirstChildOfClass("Tool")
                            esp.Weapon.Text = tool and tool.Name or "None"
                            esp.Weapon.Position = Vector2.new(screenPos.X, footScreen.Y + 34)
                            esp.Weapon.Color = Color3.fromRGB(200, 200, 200)
                            esp.Weapon.Visible = true
                        else
                            esp.Weapon.Visible = false
                        end
                        
                        -- Tracer
                        if Settings.ESPTracer then
                            local tracerOrigin = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                            esp.Tracer.From = tracerOrigin
                            esp.Tracer.To = Vector2.new(screenPos.X, footScreen.Y)
                            esp.Tracer.Color = Settings.ESPTracerColor
                            esp.Tracer.Visible = true
                        else
                            esp.Tracer.Visible = false
                        end
                        
                        -- Skeleton
                        if Settings.ESPSkeleton then
                            for i, connection in ipairs(SKELETON_CONNECTIONS) do
                                local line = esp.SkeletonLines[i]
                                local partA = player.Character:FindFirstChild(connection[1])
                                local partB = player.Character:FindFirstChild(connection[2])
                                
                                if partA and partB then
                                    local posA, onA = WorldToScreen(partA.Position)
                                    local posB, onB = WorldToScreen(partB.Position)
                                    
                                    if onA and onB then
                                        line.From = posA
                                        line.To = posB
                                        line.Color = Settings.ESPSkeletonColor
                                        line.Visible = true
                                    else
                                        line.Visible = false
                                    end
                                else
                                    line.Visible = false
                                end
                            end
                        else
                            for _, line in ipairs(esp.SkeletonLines) do
                                line.Visible = false
                            end
                        end
                    end
                end
            end
        end
        
        if not shouldShow then
            esp.Box.Visible = false
            esp.BoxOutline.Visible = false
            esp.BoxFill.Visible = false
            esp.Name.Visible = false
            esp.Distance.Visible = false
            esp.Health.Visible = false
            esp.Weapon.Visible = false
            esp.Tracer.Visible = false
            esp.HealthBar.Visible = false
            esp.HealthBarOutline.Visible = false
            for _, line in ipairs(esp.SkeletonLines) do
                line.Visible = false
            end
        end
    end
end

-- ==================== AIMBOT SYSTEM ====================
local function GetClosestPlayerToMouse(useSilentAim)
    local closestPlayer = nil
    local closestDistance = useSilentAim and Settings.SilentAimFOV or Settings.AimbotFOV
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local teamCheck = useSilentAim and Settings.SilentAimTeamCheck or Settings.AimbotTeamCheck
    local wallCheck = useSilentAim and Settings.SilentAimWallCheck or Settings.AimbotWallCheck
    local maxDist = useSilentAim and Settings.SilentAimMaxDistance or Settings.AimbotMaxDistance
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and IsPlayerAlive(player) then
            local isTeammate = IsTeammate(player)
            
            if not (teamCheck and isTeammate) then
                local targetPart = GetCharacterPart(player, Settings.AimbotTargetPart)
                if targetPart then
                    local predictedPos = PredictPosition(player, Settings.AimbotTargetPart)
                    if not predictedPos then continue end
                    
                    local screenPos, onScreen, depth = WorldToScreen(predictedPos)
                    
                    if onScreen then
                        local distance2D = GetDistance2D(mousePos, screenPos)
                        local distance3D = GetDistance3D(Camera.CFrame.Position, predictedPos)
                        
                        if distance2D < closestDistance and distance3D <= maxDist then
                            local wallClear = true
                            if wallCheck then
                                wallClear = RaycastWallCheck(Camera.CFrame.Position, predictedPos)
                            end
                            
                            if wallClear then
                                closestDistance = distance2D
                                closestPlayer = player
                            end
                        end
                    end
                end
            end
        end
    end
    
    return closestPlayer
end

local function AimAt(targetPlayer)
    if not targetPlayer then return end
    
    local predictedPos = PredictPosition(targetPlayer, Settings.AimbotTargetPart)
    if not predictedPos then return end
    
    local currentCF = Camera.CFrame
    local targetDirection = (predictedPos - currentCF.Position).Unit
    
    local smoothFactor = math.clamp(Settings.AimbotSmoothness, 0.01, 1)
    local newLookVector = currentCF.LookVector:Lerp(targetDirection, smoothFactor)
    
    Camera.CFrame = CFrame.new(currentCF.Position, currentCF.Position + newLookVector)
end

-- ==================== SILENT AIM SYSTEM ====================
local function SetupSilentAim()
    if SilentAim_Connection then
        SilentAim_Connection:Disconnect()
        SilentAim_Connection = nil
    end
    
    if not Settings.SilentAimEnabled then return end
    
    -- Hook no mouse para silent aim
    SilentAim_Connection = RunService.RenderStepped:Connect(function()
        if not Settings.SilentAimEnabled then return end
        
        local target = GetClosestPlayerToMouse(true)
        if target then
            local predictedPos = PredictPosition(target, Settings.AimbotTargetPart)
            if predictedPos then
                -- Hit chance check
                if math.random(1, 100) <= Settings.SilentAimHitChance then
                    local screenPos = WorldToScreen(predictedPos)
                    -- Atualiza a posição do mouse internamente para o jogo
                    -- Nota: Isso é um método simplificado. Alguns jogos podem requerer hooks mais profundos.
                    Mouse.Target = GetCharacterPart(target, Settings.AimbotTargetPart)
                end
            end
        end
    end)
end

-- ==================== MENU UI ====================
local function CreateToggle(parent, text, settingKey, yPos, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -20, 0, 28)
    frame.Position = UDim2.new(0, 10, 0, yPos)
    frame.BackgroundTransparency = 1
    frame.Parent = parent
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.Font = Enum.Font.Gotham
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(0, 44, 0, 20)
    toggleBtn.Position = UDim2.new(1, -44, 0.5, -10)
    toggleBtn.BackgroundColor3 = Settings[settingKey] and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(200, 50, 50)
    toggleBtn.Text = Settings[settingKey] and "ON" or "OFF"
    toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 11
    toggleBtn.AutoButtonColor = true
    toggleBtn.Parent = frame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = toggleBtn
    
    toggleBtn.MouseButton1Click:Connect(function()
        Settings[settingKey] = not Settings[settingKey]
        toggleBtn.BackgroundColor3 = Settings[settingKey] and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(200, 50, 50)
        toggleBtn.Text = Settings[settingKey] and "ON" or "OFF"
        if callback then callback(Settings[settingKey]) end
    end)
    
    return toggleBtn
end

local function CreateSlider(parent, text, settingKey, min, max, yPos, isFloat)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -20, 0, 45)
    frame.Position = UDim2.new(0, 10, 0, yPos)
    frame.BackgroundTransparency = 1
    frame.Parent = parent
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 18)
    label.BackgroundTransparency = 1
    label.Text = text .. ": " .. tostring(Settings[settingKey])
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    
    local sliderBg = Instance.new("Frame")
    sliderBg.Size = UDim2.new(1, 0, 0, 8)
    sliderBg.Position = UDim2.new(0, 0, 0, 28)
    sliderBg.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    sliderBg.BorderSizePixel = 0
    sliderBg.Parent = frame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = sliderBg
    
    local fill = Instance.new("Frame")
    local percent = (Settings[settingKey] - min) / (max - min)
    fill.Size = UDim2.new(percent, 0, 1, 0)
    fill.BackgroundColor3 = Settings.MenuAccentColor
    fill.BorderSizePixel = 0
    fill.Parent = sliderBg
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 4)
    fillCorner.Parent = fill
    
    local dragging = false
    
    sliderBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
        end
    end)
    
    sliderBg.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local pos = math.clamp((input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
            local value = min + (max - min) * pos
            if not isFloat then
                value = math.floor(value)
            else
                value = math.round(value * 100) / 100
            end
            Settings[settingKey] = value
            fill.Size = UDim2.new(pos, 0, 1, 0)
            label.Text = text .. ": " .. tostring(value)
        end
    end)
end

local function CreateMenuButton()
    if MenuButton then MenuButton:Destroy() end
    
    MenuButton = Instance.new("TextButton")
    MenuButton.Name = "MenuToggleBtn"
    MenuButton.Size = UDim2.new(0, 50, 0, 50)
    MenuButton.Position = UDim2.new(1, -70, 0, 20)
    MenuButton.BackgroundColor3 = Settings.MenuAccentColor
    MenuButton.Text = "☰"
    MenuButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    MenuButton.Font = Enum.Font.GothamBold
    MenuButton.TextSize = 24
    MenuButton.Parent = ScreenGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = MenuButton
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 2
    stroke.Transparency = 0.5
    stroke.Parent = MenuButton
    
    MenuButton.MouseButton1Click:Connect(function()
        Settings.MenuVisible = not Settings.MenuVisible
        MenuFrame.Visible = Settings.MenuVisible
        
        local targetPos = Settings.MenuVisible and Settings.MenuPosition or UDim2.new(0, -400, 0, Settings.MenuPosition.Y.Offset)
        TweenService:Create(MenuFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {Position = targetPos}):Play()
    end)
end

local function CreateMenu()
    if ScreenGui then ScreenGui:Destroy() end
    
    ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "AimbotESP_Menu"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    
    -- Menu Frame
    MenuFrame = Instance.new("Frame")
    MenuFrame.Name = "MenuFrame"
    MenuFrame.Size = UDim2.new(0, 320, 0, 520)
    MenuFrame.Position = Settings.MenuPosition
    MenuFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    MenuFrame.BorderSizePixel = 0
    MenuFrame.Visible = Settings.MenuVisible
    MenuFrame.Active = true
    MenuFrame.Draggable = true
    MenuFrame.Parent = ScreenGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = MenuFrame
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Settings.MenuAccentColor
    stroke.Thickness = 1.5
    stroke.Parent = MenuFrame
    
    -- Title Bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 36)
    titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = MenuFrame
    
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 10)
    titleCorner.Parent = titleBar
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -10, 1, 0)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "🔥 AIMBOT + ESP SYSTEM"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = titleBar
    
    -- Close Button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -35, 0, 3)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 16
    closeBtn.Parent = titleBar
    
    closeBtn.MouseButton1Click:Connect(function()
        Settings.MenuVisible = false
        MenuFrame.Visible = false
    end)
    
    -- Scroll Frame
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Size = UDim2.new(1, -10, 1, -46)
    scrollFrame.Position = UDim2.new(0, 5, 0, 41)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.ScrollBarThickness = 4
    scrollFrame.ScrollBarImageColor3 = Settings.MenuAccentColor
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 900)
    scrollFrame.Parent = MenuFrame
    
    local yOffset = 5
    
    -- Função helper para criar seções
    local function AddSection(titleText)
        local section = Instance.new("TextLabel")
        section.Size = UDim2.new(1, -10, 0, 22)
        section.Position = UDim2.new(0, 5, 0, yOffset)
        section.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        section.Text = "  " .. titleText
        section.TextColor3 = Settings.MenuAccentColor
        section.Font = Enum.Font.GothamBold
        section.TextSize = 13
        section.TextXAlignment = Enum.TextXAlignment.Left
        section.Parent = scrollFrame
        
        local sc = Instance.new("UICorner")
        sc.CornerRadius = UDim.new(0, 6)
        sc.Parent = section
        
        yOffset = yOffset + 28
    end
    
    -- AIMBOT SECTION
    AddSection("🎯 AIMBOT")
    CreateToggle(scrollFrame, "Enable Aimbot", "AimbotEnabled", yOffset, function()
        if not Settings.AimbotEnabled then AimbotActive = false end
    end)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Team Check", "AimbotTeamCheck", yOffset)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Wall Check", "AimbotWallCheck", yOffset)
    yOffset = yOffset + 32
    CreateSlider(scrollFrame, "Smoothness", "AimbotSmoothness", 0.01, 1, yOffset, true)
    yOffset = yOffset + 50
    CreateSlider(scrollFrame, "FOV Radius", "AimbotFOV", 30, 500, yOffset)
    yOffset = yOffset + 50
    CreateSlider(scrollFrame, "Max Distance", "AimbotMaxDistance", 50, 2000, yOffset)
    yOffset = yOffset + 55
    
    -- SILENT AIM SECTION
    AddSection("🔇 SILENT AIM")
    CreateToggle(scrollFrame, "Enable Silent Aim", "SilentAimEnabled", yOffset, function(val)
        SetupSilentAim()
    end)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Silent Team Check", "SilentAimTeamCheck", yOffset)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Silent Wall Check", "SilentAimWallCheck", yOffset)
    yOffset = yOffset + 32
    CreateSlider(scrollFrame, "Hit Chance %", "SilentAimHitChance", 1, 100, yOffset)
    yOffset = yOffset + 50
    CreateSlider(scrollFrame, "Silent FOV", "SilentAimFOV", 30, 300, yOffset)
    yOffset = yOffset + 55
    
    -- PREDICTION SECTION
    AddSection("🧮 BULLET PREDICTION")
    CreateToggle(scrollFrame, "Enable Prediction", "PredictionEnabled", yOffset)
    yOffset = yOffset + 32
    CreateSlider(scrollFrame, "Bullet Speed", "BulletSpeed", 100, 10000, yOffset)
    yOffset = yOffset + 50
    CreateSlider(scrollFrame, "Bullet Drop", "BulletDrop", 0, 500, yOffset)
    yOffset = yOffset + 55
    
    -- ESP SECTION
    AddSection("👁️ ESP")
    CreateToggle(scrollFrame, "Enable ESP", "ESPEnabled", yOffset)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "ESP Box", "ESPBox", yOffset)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Box Filled", "ESPBoxFilled", yOffset)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Show Names", "ESPName", yOffset)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Show Distance", "ESPDistance", yOffset)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Show Health", "ESPHealth", yOffset)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Health Bar", "ESPHealthBar", yOffset)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Show Tracers", "ESPTracer", yOffset)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Skeleton", "ESPSkeleton", yOffset)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Show Weapon", "ESPWeapon", yOffset)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Team Check", "ESPTeamCheck", yOffset)
    yOffset = yOffset + 32
    CreateToggle(scrollFrame, "Show Teammates", "ESPShowTeam", yOffset)
    yOffset = yOffset + 32
    CreateSlider(scrollFrame, "ESP Max Distance", "ESPMaxDistance", 100, 5000, yOffset)
    yOffset = yOffset + 50
    
    -- INFO SECTION
    AddSection("ℹ️ INFO")
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, -20, 0, 80)
    infoLabel.Position = UDim2.new(0, 10, 0, yOffset)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Text = "[F] Toggle Aimbot\n[G] Toggle ESP\n[Insert] Toggle Menu\n[RMB] Aimbot Lock\n\nUse only in private environments!"
    infoLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextSize = 12
    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
    infoLabel.TextYAlignment = Enum.TextYAlignment.Top
    infoLabel.Parent = scrollFrame
    
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, yOffset + 90)
    
    -- Botão flutuante para abrir menu
    CreateMenuButton()
end

-- ==================== EVENTOS ====================
local function SetupEvents()
    -- Adicionar ESP para jogadores existentes
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not ESPObjects[player] then
            ESPObjects[player] = CreateESPObject(player)
        end
    end
    
    -- Novo jogador
    table.insert(Connections, Players.PlayerAdded:Connect(function(player)
        if not ESPObjects[player] then
            ESPObjects[player] = CreateESPObject(player)
        end
    end))
    
    -- Jogador saiu
    table.insert(Connections, Players.PlayerRemoving:Connect(function(player)
        RemoveESPObject(player)
    end))
    
    -- Input Began
    table.insert(Connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.KeyCode == Settings.MenuToggleKey then
            Settings.MenuVisible = not Settings.MenuVisible
            if MenuFrame then
                MenuFrame.Visible = Settings.MenuVisible
                local targetPos = Settings.MenuVisible and Settings.MenuPosition or UDim2.new(0, -400, 0, Settings.MenuPosition.Y.Offset)
                TweenService:Create(MenuFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {Position = targetPos}):Play()
            end
        elseif input.KeyCode == Settings.AimbotToggleKey then
            Settings.AimbotEnabled = not Settings.AimbotEnabled
            if not Settings.AimbotEnabled then AimbotActive = false end
        elseif input.KeyCode == Settings.ESPToggleKey then
            Settings.ESPEnabled = not Settings.ESPEnabled
        elseif input.UserInputType == Settings.AimKey then
            if Settings.AimbotEnabled then
                AimbotActive = true
            end
        end
    end))
    
    -- Input Ended
    table.insert(Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Settings.AimKey then
            AimbotActive = false
        end
    end))
    
    -- Render Step
    table.insert(Connections, RunService.RenderStepped:Connect(function()
        UpdateCircles()
        UpdateESP()
        
        if AimbotActive and Settings.AimbotEnabled then
            local target = GetClosestPlayerToMouse(false)
            if target then
                AimAt(target)
            end
        end
    end))
    
    -- Setup Silent Aim
    SetupSilentAim()
end

-- ==================== CLEANUP ====================
local function Cleanup()
    for _, conn in ipairs(Connections) do
        conn:Disconnect()
    end
    Connections = {}
    
    if SilentAim_Connection then
        SilentAim_Connection:Disconnect()
        SilentAim_Connection = nil
    end
    
    for player, _ in pairs(ESPObjects) do
        RemoveESPObject(player)
    end
    
    if FOV_Circle then
        FOV_Circle:Remove()
        FOV_Circle = nil
    end
    
    if SilentAim_FOV_Circle then
        SilentAim_FOV_Circle:Remove()
        SilentAim_FOV_Circle = nil
    end
    
    if ScreenGui then
        ScreenGui:Destroy()
        ScreenGui = nil
    end
end

-- ==================== INICIALIZAÇÃO ====================
local function Initialize()
    print("[AimbotESP] Inicializando sistema v2.0...")
    
    Cleanup()
    CreateMenu()
    SetupEvents()
    
    print("[AimbotESP] Sistema carregado com sucesso!")
    print(string.format("[AimbotESP] Teclas - Menu: %s | Aimbot: %s | ESP: %s | Aim: RMB", 
        tostring(Settings.MenuToggleKey), 
        tostring(Settings.AimbotToggleKey),
        tostring(Settings.ESPToggleKey)
    ))
end

Initialize()

-- Exports globais
getgenv().AimbotESP_Cleanup = Cleanup
getgenv().AimbotESP_Reload = Initialize
getgenv().AimbotESP_UpdateSettings = function(newSettings)
    for k, v in pairs(newSettings) do
        Settings[k] = v
    end
    print("[AimbotESP] Settings atualizadas!")
end

print("[AimbotESP] Comandos disponíveis:")
print("  getgenv().AimbotESP - Tabela de configurações")
print("  getgenv().AimbotESP_Cleanup() - Limpar sistema")
print("  getgenv().AimbotESP_Reload() - Recarregar sistema")
print("  getgenv().AimbotESP_UpdateSettings({...}) - Atualizar configs")
