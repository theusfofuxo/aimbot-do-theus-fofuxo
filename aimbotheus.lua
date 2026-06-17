-- ====================================================================
-- PREMONITION ENGINE v87.5.0 - MOTOR DE FISICA E VERIFICAÇÃO RECONSTRUIDO
-- ====================================================================

if not game:IsLoaded() then
    game.Loaded:Wait()
end
task.wait(1)

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
local TargetMotionCache = {}

local function CleanOldUI(root)
    if not root then return end
    for _, child in ipairs(root:GetChildren()) do
        if child.Name == "PreonEngineUI" or child.Name == "MainPanelStructure" or child.Name == "PremonitionToggleUI" then
            pcall(function() child:Destroy() end)
        end
    end
end
CleanOldUI(CoreGui)

-- SCREEN GUI PRINCIPAL
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PreonEngineUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = CoreGui

local Settings = {
    ShowFOV = false,                    
    FovDegrees = 6.0, 
    FovColorR = 0, FovColorG = 255, FovColorB = 120, 
    TeamCheck = false, 
    WallCheck = false,                  
    MultiBoneScan = false,              
    WallPenetration = false,            
    MaxPenetrationThick = 2.5,  
    HitboxExpander = false,             
    HitboxSize = 0,                     
    MovementPrediction = false,         
    HumanFriction = false,              
    SmartScan = false,
    SnapMarkers = false,                
    AimbotEnabled = false,              
    Hitbox = "Head",         
    SmoothValue = 6,          
    StickyStrength = 55,       
    PredictStrength = 50,
    FlickEnabled = false,               
    FlickSmooth = 2,          
    FlickFovDegrees = 3.5,    
    BallisticCorrection = false,
    MuzzleVelocity = 1000,      
    BulletGravity = 196.2,     
    CrosshairEnabled = false,           
    CrosshairType = "Ponto", 
    CrosshairColorR = 0, CrosshairColorG = 255, CrosshairColorB = 120,
    CrosshairSize = 8,
    CrosshairGap = 2,
    StickyLock = false,                 
    ShowTracer = false, 
    FreeControlSmooth = 50,   
    BreakoutForce = 18,       
    DynamicTorque = false,              
    TorqueMultiplier = 40,
    ProximityDampEnabled = false,       
    ProximityMaxDistance = 25,
    ProximityMinStrength = 35,
    WeightRecoverySpeed = 3.0,
    NeuromuscularTremor = false,        
    TremorIntensity = 2,
    TargetPriority = "Distancia FOV", 
    DynamicSmoothness = false,
    DynamicSmoothMultiplier = 5
}

-- CONFIGURAÇÃO DO NOVO MOTOR RAYCAST (WALL CHECK DINÂMICO)
local WALL_CHECK_PARAMS = RaycastParams.new()
WALL_CHECK_PARAMS.FilterType = Enum.RaycastFilterType.Exclude
WALL_CHECK_PARAMS.IgnoreWater = true
WALL_CHECK_PARAMS.RespectCanCollide = true -- Ignora assessórios sem colisão física real

local function UpdateIgnoreList()
    local list = {Workspace.CurrentCamera, Workspace:FindFirstChild("Terrain")}
    if LocalPlayer.Character then 
        table.insert(list, LocalPlayer.Character) 
    end
    -- Ignorar pastas comuns de efeitos/partículas de jogos que bloqueiam raios
    for _, v in ipairs(Workspace:GetChildren()) do
        if v.Name:lower():find("ignore") or v.Name:lower():find("particle") or v.Name:lower():find("decap") or v.Name:lower():find("bullet") then
            table.insert(list, v)
        end
    end
    WALL_CHECK_PARAMS.FilterDescendantsInstances = list
end
UpdateIgnoreList()
AddConnection(LocalPlayer.CharacterAdded:Connect(function() task.wait(0.5); UpdateIgnoreList() end))

local CurrentTarget, TargetPart = nil, nil
local TouchVelocity2D, ComputedPixelRadius, ComputedFlickPixelRadius, EscapeCooldown, DynamicUserWeight = 0, 55, 25, 0.0, 1.0  
local FlickActiveThisFrame = false

local function GetTrueScreenCenter()
    Camera = Workspace.CurrentCamera
    if not Camera then return Vector2.new(0, 0) end
    return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
end
local ScreenCenter = GetTrueScreenCenter()

-- ELEMENTOS VISUAIS
local FOVCircle = Instance.new("Frame")
FOVCircle.Name = "AutonomousFOV"; FOVCircle.AnchorPoint = Vector2.new(0.5, 0.5); FOVCircle.BackgroundTransparency = 1; FOVCircle.ZIndex = 10; FOVCircle.Parent = ScreenGui
local Stroke = Instance.new("UIStroke", FOVCircle); Stroke.Thickness = 1.5; Stroke.Color = Color3.fromRGB(Settings.FovColorR, Settings.FovColorG, Settings.FovColorB); Stroke.Transparency = 0.2
Instance.new("UICorner", FOVCircle).CornerRadius = UDim.new(1, 0)

local FlickFOVCircle = Instance.new("Frame")
FlickFOVCircle.Name = "FlickFOV"; FlickFOVCircle.AnchorPoint = Vector2.new(0.5, 0.5); FlickFOVCircle.BackgroundTransparency = 1; FlickFOVCircle.ZIndex = 9; FlickFOVCircle.Parent = ScreenGui
local FlickStroke = Instance.new("UIStroke", FlickFOVCircle); FlickStroke.Thickness = 1.5; FlickStroke.Color = Color3.fromRGB(255, 0, 80); FlickStroke.Transparency = 0.2
Instance.new("UICorner", FlickFOVCircle).CornerRadius = UDim.new(1, 0)

local CrosshairBase = Instance.new("Frame")
CrosshairBase.Name = "CrosshairContainer"; CrosshairBase.Size = UDim2.new(0, 100, 0, 100); CrosshairBase.AnchorPoint = Vector2.new(0.5, 0.5); CrosshairBase.BackgroundTransparency = 1; CrosshairBase.ZIndex = 12; CrosshairBase.Parent = ScreenGui

local function CalculateAngularRadius(degrees)
    Camera = Workspace.CurrentCamera
    if not Camera then return 55 end
    return (math.tan(math.rad(degrees) / 2) / math.tan(math.rad(Camera.FieldOfView) / 2)) * (Camera.ViewportSize.Y / 2)
end

-- CONTROLE DE TAGS
local ActiveTargets = {}
local function tagCharacter(char)
    local humanoid = char:WaitForChild("Humanoid", 5)
    if humanoid then
        CollectionService:AddTag(char, TARGET_TAG)
        local diedConn; diedConn = humanoid.Died:Connect(function()
            CollectionService:RemoveTag(char, TARGET_TAG); diedConn:Disconnect()
        end)
    end
end

for _, p in ipairs(Players:GetPlayers()) do 
    if p ~= LocalPlayer then if p.Character then task.spawn(tagCharacter, p.Character) end AddConnection(p.CharacterAdded:Connect(tagCharacter)) end 
end
AddConnection(Players.PlayerAdded:Connect(function(p) AddConnection(p.CharacterAdded:Connect(tagCharacter)) end))

for _, char in ipairs(CollectionService:GetTagged(TARGET_TAG)) do if not table.find(ActiveTargets, char) then table.insert(ActiveTargets, char) end end
AddConnection(CollectionService:GetInstanceAddedSignal(TARGET_TAG):Connect(function(char) if not table.find(ActiveTargets, char) then table.insert(ActiveTargets, char) end end))
AddConnection(CollectionService:GetInstanceRemovedSignal(TARGET_TAG):Connect(function(char) local index = table.find(ActiveTargets, char) if index then table.remove(ActiveTargets, index) end end))

-- HEURÍSTICA AVANÇADA DE TEAM CHECK (CORRIGIDO)
local function AdvancedTeamCheck(targetPlayer)
    if not Settings.TeamCheck then return true end
    if not targetPlayer then return false end
    
    -- 1. Verificação nativa do sistema Roblox Teams
    if targetPlayer.Team and LocalPlayer.Team then
        if targetPlayer.Team ~= LocalPlayer.Team then return true end
    end
    
    -- 2. Verificação por atributos de jogo (Comum em motores de FPS modernos)
    local myTeamAttr = LocalPlayer:GetAttribute("Team") or LocalPlayer:GetAttribute("Equipe") or LocalPlayer:GetAttribute("Squad")
    local targTeamAttr = targetPlayer:GetAttribute("Team") or targetPlayer:GetAttribute("Equipe") or targetPlayer:GetAttribute("Squad")
    if myTeamAttr and targTeamAttr then
        return myTeamAttr ~= targTeamAttr
    end

    -- 3. Verificação por TeamColor reserva
    if targetPlayer.TeamColor and LocalPlayer.TeamColor then
        return targetPlayer.TeamColor ~= LocalPlayer.TeamColor
    end
    
    return true
end

-- PAINEL PRINCIPAL
local MainPanel = Instance.new("Frame")
MainPanel.Name = "MainPanelStructure"
MainPanel.Size = UDim2.new(0, 320, 0, 360)
MainPanel.Position = UDim2.new(0.5, -160, 0.5, -180)
MainPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
MainPanel.Active = true
MainPanel.Visible = false
MainPanel.ZIndex = 50
MainPanel.Parent = ScreenGui
Instance.new("UICorner", MainPanel).CornerRadius = UDim.new(0, 6)

local PanelStroke = Instance.new("UIStroke", MainPanel)
PanelStroke.Color = Color3.fromRGB(45, 45, 45)
PanelStroke.ZIndex = 51

local MenuButton = Instance.new("TextButton")
MenuButton.Name = "FloatingMenuButton"
MenuButton.Size = UDim2.new(0, 45, 0, 45)
MenuButton.Position = UDim2.new(0, 15, 0, 150)
MenuButton.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
MenuButton.Text = "⚙️"
MenuButton.TextColor3 = Color3.fromRGB(0, 255, 120)
MenuButton.TextSize = 20
MenuButton.Font = Enum.Font.GothamBold
MenuButton.Active = true
MenuButton.Draggable = true 
MenuButton.ZIndex = 100
MenuButton.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(1, 0)
Corner.Parent = MenuButton

local ButtonStroke = Instance.new("UIStroke")
ButtonStroke.Color = Color3.fromRGB(0, 255, 120)
ButtonStroke.Thickness = 2
ButtonStroke.Parent = MenuButton

AddConnection(MenuButton.MouseButton1Click:Connect(function() 
    MainPanel.Visible = not MainPanel.Visible 
end))

local dragToggle, dragStart, startPos
AddConnection(MainPanel.InputBegan:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
        dragToggle = true; dragStart = input.Position; startPos = MainPanel.Position
    end
end))
AddConnection(UserInputService.InputChanged:Connect(function(input)
    if dragToggle and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        MainPanel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end))
AddConnection(UserInputService.InputEnded:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
        dragToggle = false
    end
end))

local SnapLeft = Instance.new("TextLabel"); SnapLeft.BackgroundTransparency = 1; SnapLeft.Text = "["; SnapLeft.Font = Enum.Font.SourceSansBold; SnapLeft.TextSize = 20; SnapLeft.TextColor3 = Color3.fromRGB(0, 255, 120); SnapLeft.Visible = false; SnapLeft.ZIndex = 2; SnapLeft.Parent = ScreenGui
local SnapRight = Instance.new("TextLabel"); SnapRight.BackgroundTransparency = 1; SnapRight.Text = "]"; SnapRight.Font = Enum.Font.SourceSansBold; SnapRight.TextSize = 20; SnapRight.TextColor3 = Color3.fromRGB(0, 255, 120); SnapRight.Visible = false; SnapRight.ZIndex = 2; SnapRight.Parent = ScreenGui

local Pages = {}; local TabButtons = {}; local TotalTabs = 6
local TabBar = Instance.new("Frame"); TabBar.Name = "TabBar"; TabBar.Size = UDim2.new(1, 0, 0, 32); TabBar.BackgroundColor3 = Color3.fromRGB(22, 22, 22); TabBar.ZIndex = 53; TabBar.Parent = MainPanel; Instance.new("UICorner", TabBar).CornerRadius = UDim.new(0, 4)
local PagesContainer = Instance.new("Frame"); PagesContainer.Name = "PagesContainer"; PagesContainer.Size = UDim2.new(1, 0, 1, -32); PagesContainer.Position = UDim2.new(0, 0, 0, 32); PagesContainer.BackgroundTransparency = 1; PagesContainer.ZIndex = 53; PagesContainer.Parent = MainPanel

local function CreateTab(name, layoutOrder)
    local TabBtn = Instance.new("TextButton")
    TabBtn.Size = UDim2.new(1 / TotalTabs, 0, 1, 0); TabBtn.Position = UDim2.new((1 / TotalTabs) * (layoutOrder - 1), 0, 0, 0); TabBtn.BackgroundColor3 = Color3.fromRGB(22, 22, 22); TabBtn.BorderSizePixel = 0; TabBtn.Text = name; TabBtn.TextColor3 = Color3.fromRGB(140, 140, 140); TabBtn.Font = Enum.Font.SourceSansBold; TabBtn.TextSize = 10; TabBtn.ZIndex = 54; TabBtn.Parent = TabBar
    
    local PageScroll = Instance.new("ScrollingFrame")
    PageScroll.Size = UDim2.new(1, 0, 1, 0); PageScroll.BackgroundTransparency = 1; PageScroll.ScrollBarThickness = 2; PageScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80); PageScroll.Visible = false; PageScroll.ZIndex = 54; PageScroll.Parent = PagesContainer
    Instance.new("UIPadding", PageScroll).PaddingTop = UDim.new(0, 6)
    
    local ListLayout = Instance.new("UIListLayout", PageScroll); ListLayout.Padding = UDim.new(0, 6); ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    AddConnection(ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() PageScroll.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 15) end))
    
    AddConnection(TabBtn.MouseButton1Click:Connect(function()
        for tName, pFrame in pairs(Pages) do
            if tName == name then pFrame.Visible = true; TabButtons[tName].TextColor3 = Color3.fromRGB(0, 255, 120); TabButtons[tName].BackgroundColor3 = Color3.fromRGB(28, 28, 28)
            else pFrame.Visible = false; TabButtons[tName].TextColor3 = Color3.fromRGB(140, 140, 140); TabButtons[tName].BackgroundColor3 = Color3.fromRGB(22, 22, 22) end
        end
    end))
    Pages[name] = PageScroll; TabButtons[name] = TabBtn; return PageScroll
end

local PageGeral = CreateTab("GERAL", 1); local PageAimbot = CreateTab("AIMBOT", 2); local PageLock = CreateTab("LOCK", 3); local PageFovTab = CreateTab("FOV", 4); local PageCrosshair = CreateTab("CROSS", 5); local PageHitbox = CreateTab("HITBOX", 6)
Pages["GERAL"].Visible = true; TabButtons["GERAL"].TextColor3 = Color3.fromRGB(0, 255, 120); TabButtons["GERAL"].BackgroundColor3 = Color3.fromRGB(28, 28, 28)

local function TweenPreviewFade(canvasGroup, shouldShow)
    local targetTransparency = shouldShow and 0 or 1
    local targetSize = shouldShow and UDim2.new(1, -12, 0, canvasGroup:GetAttribute("TargetHeight") or 110) or UDim2.new(1, -12, 0, 0)
    if shouldShow then canvasGroup.Visible = true end
    TweenService:Create(canvasGroup, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {GroupTransparency = targetTransparency}):Play()
    local tSize = TweenService:Create(canvasGroup, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = targetSize})
    tSize:Play(); local compConn; compConn = tSize.Completed:Connect(function() if not shouldShow then canvasGroup.Visible = false end; compConn:Disconnect() end)
end

local function AddSectionSeparator(text, parentPage)
    local Frame = Instance.new("Frame"); Frame.Size = UDim2.new(1, 0, 0, 18); Frame.BackgroundTransparency = 1; Frame.ZIndex = parentPage.ZIndex; Frame.Parent = parentPage
    local Label = Instance.new("TextLabel"); Label.Size = UDim2.new(1, 0, 1, 0); Label.BackgroundTransparency = 1; Label.Text = "- " .. text .. " -"; Label.TextColor3 = Color3.fromRGB(0, 255, 120); Label.Font = Enum.Font.SourceSansBold; Label.TextSize = 11; Label.TextXAlignment = Enum.TextXAlignment.Center; Label.ZIndex = parentPage.ZIndex + 1; Label.Parent = Frame
end

local function AddToggle(text, default, parentPage, descText, callback)
    local Frame = Instance.new("Frame"); Frame.Size = UDim2.new(1, 0, 0, 48); Frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20); Frame.ZIndex = parentPage.ZIndex; Frame.Parent = parentPage; Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 4)
    local Label = Instance.new("TextLabel"); Label.Size = UDim2.new(0.65, 0, 0, 18); Label.Position = UDim2.new(0, 8, 0, 3); Label.BackgroundTransparency = 1; Label.Text = text; Label.TextColor3 = Color3.fromRGB(180, 180, 180); Label.Font = Enum.Font.SourceSansBold; Label.TextSize = 11; Label.TextXAlignment = Enum.TextXAlignment.Left; Label.ZIndex = parentPage.ZIndex + 1; Label.Parent = Frame
    local Description = Instance.new("TextLabel"); Description.Size = UDim2.new(1, -16, 0, 22); Description.Position = UDim2.new(0, 8, 0, 20); Description.BackgroundTransparency = 1; Description.Text = descText; Description.TextColor3 = Color3.fromRGB(130, 135, 140); Description.Font = Enum.Font.SourceSans; Description.TextSize = 9; Description.TextWrapped = true; Description.TextXAlignment = Enum.TextXAlignment.Left; Description.TextYAlignment = Enum.TextYAlignment.Top; Description.ZIndex = parentPage.ZIndex + 1; Description.Parent = Frame
    local Btn = Instance.new("TextButton"); Btn.Size = UDim2.new(0, 32, 0, 16); Btn.Position = UDim2.new(1, -40, 0, 4); Btn.BackgroundColor3 = default and Color3.fromRGB(0, 255, 120) or Color3.fromRGB(45, 45, 45); Btn.Text = ""; Btn.ZIndex = parentPage.ZIndex + 1; Btn.Parent = Frame; Instance.new("UICorner", Btn).CornerRadius = UDim.new(1, 0)
    local Indicator = Instance.new("Frame"); Indicator.Size = UDim2.new(0, 10, 0, 10); Indicator.Position = default and UDim2.new(1, -13, 0.5, -5) or UDim2.new(0, 3, 0.5, -5); Indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255); Indicator.ZIndex = parentPage.ZIndex + 2; Indicator.Parent = Btn; Instance.new("UICorner", Indicator).CornerRadius = UDim.new(1, 0)
    AddConnection(Btn.MouseButton1Click:Connect(function() default = not default; TweenService:Create(Btn, TweenInfo.new(0.08), {BackgroundColor3 = default and Color3.fromRGB(0, 255, 120) or Color3.fromRGB(45, 45, 45)}):Play(); TweenService:Create(Indicator, TweenInfo.new(0.08), {Position = default and UDim2.new(1, -13, 0.5, -5) or UDim2.new(0, 3, 0.5, -5)}):Play(); callback(default) end))
end

local function AddSlider(text, min, max, default, parentPage, descText, callback)
    local Frame = Instance.new("Frame"); Frame.Size = UDim2.new(1, 0, 0, 64); Frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20); Frame.ZIndex = parentPage.ZIndex; Frame.Parent = parentPage; Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 4)
    local Label = Instance.new("TextLabel"); Label.Size = UDim2.new(1, -16, 0, 16); Label.Position = UDim2.new(0, 8, 0, 2); Label.BackgroundTransparency = 1; Label.Text = text .. ": " .. tostring(default); Label.TextColor3 = Color3.fromRGB(180, 180, 180); Label.Font = Enum.Font.SourceSansBold; Label.TextSize = 11; Label.TextXAlignment = Enum.TextXAlignment.Left; Label.ZIndex = parentPage.ZIndex + 1; Label.Parent = Frame
    local Description = Instance.new("TextLabel"); Description.Size = UDim2.new(1, -16, 0, 28); Description.Position = UDim2.new(0, 8, 0, 16); Description.BackgroundTransparency = 1; Description.Text = descText; Description.TextColor3 = Color3.fromRGB(130, 135, 140); Description.Font = Enum.Font.SourceSans; Description.TextSize = 9; Description.TextWrapped = true; Description.TextXAlignment = Enum.TextXAlignment.Left; Description.TextYAlignment = Enum.TextYAlignment.Top; Description.ZIndex = parentPage.ZIndex + 1; Description.Parent = Frame
    local SlideTrack = Instance.new("TextButton"); SlideTrack.Size = UDim2.new(1, -16, 0, 3); SlideTrack.Position = UDim2.new(0, 8, 1, -6); SlideTrack.BackgroundColor3 = Color3.fromRGB(45, 45, 45); SlideTrack.Text = ""; SlideTrack.ZIndex = parentPage.ZIndex + 1; SlideTrack.Parent = Frame; Instance.new("UICorner", SlideTrack).CornerRadius = UDim.new(1, 0)
    local Fill = Instance.new("Frame"); Fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0); Fill.BackgroundColor3 = Color3.fromRGB(0, 255, 120); Fill.BorderSizePixel = 0; Fill.ZIndex = parentPage.ZIndex + 2; Fill.Parent = SlideTrack; Instance.new("UICorner", Fill).CornerRadius = UDim.new(1, 0)
    local active = false
    local function processScale(input)
        local scale = math.clamp((input.Position.X - SlideTrack.AbsolutePosition.X) / SlideTrack.AbsoluteSize.X, 0, 1); Fill.Size = UDim2.new(scale, 0, 1, 0)
        local value = math.floor((min + (max - min) * scale) * 10) / 10
        Label.Text = text .. ": " .. tostring(value); callback(value)
    end
    AddConnection(SlideTrack.InputBegan:Connect(function(input) if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then active = true; processScale(input) end end))
    AddConnection(UserInputService.InputChanged:Connect(function(input) if active and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then processScale(input) end end))
    AddConnection(UserInputService.InputEnded:Connect(function(input) if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then active = false end end))
end

local function AddSelector(text, options, default, parentPage, descText, callback)
    local Frame = Instance.new("Frame"); Frame.Size = UDim2.new(1, 0, 0, 48); Frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20); Frame.ZIndex = parentPage.ZIndex; Frame.Parent = parentPage; Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 4)
    local Label = Instance.new("TextLabel"); Label.Size = UDim2.new(0.5, 0, 0, 18); Label.Position = UDim2.new(0, 8, 0, 3); Label.BackgroundTransparency = 1; Label.Text = text; Label.TextColor3 = Color3.fromRGB(180, 180, 180); Label.Font = Enum.Font.SourceSansBold; Label.TextSize = 11; Label.TextXAlignment = Enum.TextXAlignment.Left; Label.ZIndex = parentPage.ZIndex + 1; Label.Parent = Frame
    local Description = Instance.new("TextLabel"); Description.Size = UDim2.new(1, -16, 0, 22); Description.Position = UDim2.new(0, 8, 0, 20); Description.BackgroundTransparency = 1; Description.Text = descText; Description.TextColor3 = Color3.fromRGB(130, 135, 140); Description.Font = Enum.Font.SourceSans; Description.TextSize = 9; Description.TextWrapped = true; Description.TextXAlignment = Enum.TextXAlignment.Left; Description.TextYAlignment = Enum.TextYAlignment.Top; Description.ZIndex = parentPage.ZIndex + 1; Description.Parent = Frame
    local Btn = Instance.new("TextButton"); Btn.Size = UDim2.new(0, 110, 0, 18); Btn.Position = UDim2.new(1, -120, 0, 3); Btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30); Btn.Text = default; Btn.TextColor3 = Color3.fromRGB(255, 255, 255); Btn.Font = Enum.Font.SourceSansBold; Btn.TextSize = 10; Btn.ZIndex = parentPage.ZIndex + 1; Btn.Parent = Frame; Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 4)
    Instance.new("UIStroke", Btn).Color = Color3.fromRGB(50, 50, 50)
    local currentIndex = table.find(options, default) or 1
    AddConnection(Btn.MouseButton1Click:Connect(function() currentIndex = currentIndex + 1; if currentIndex > #options then currentIndex = 1 end; Btn.Text = options[currentIndex]; callback(options[currentIndex]) end))
end

-- PREVIEWS MÓVEIS
local FovPreviewBox = Instance.new("CanvasGroup"); FovPreviewBox.Name = "FovPreviewBox"; FovPreviewBox.Size = UDim2.new(1, -12, 0, 0); FovPreviewBox.GroupTransparency = 1; FovPreviewBox.Visible = false; FovPreviewBox.BackgroundColor3 = Color3.fromRGB(10, 10, 10); FovPreviewBox.ZIndex = 55; FovPreviewBox:SetAttribute("TargetHeight", 110); Instance.new("UICorner", FovPreviewBox).CornerRadius = UDim.new(0, 4); Instance.new("UIStroke", FovPreviewBox).Color = Color3.fromRGB(35, 35, 35)
local CrossPreviewBox = Instance.new("CanvasGroup"); CrossPreviewBox.Name = "CrossPreviewBox"; CrossPreviewBox.Size = UDim2.new(1, -12, 0, 0); CrossPreviewBox.GroupTransparency = 1; CrossPreviewBox.Visible = false; CrossPreviewBox.BackgroundColor3 = Color3.fromRGB(10, 10, 10); CrossPreviewBox.ZIndex = 55; CrossPreviewBox:SetAttribute("TargetHeight", 110); Instance.new("UICorner", CrossPreviewBox).CornerRadius = UDim.new(0, 4); Instance.new("UIStroke", CrossPreviewBox).Color = Color3.fromRGB(35, 35, 35)
local HitboxPreviewBox = Instance.new("CanvasGroup"); HitboxPreviewBox.Name = "HitboxPreviewBox"; HitboxPreviewBox.Size = UDim2.new(1, -12, 0, 0); HitboxPreviewBox.GroupTransparency = 1; HitboxPreviewBox.Visible = false; HitboxPreviewBox.BackgroundColor3 = Color3.fromRGB(10, 10, 10); HitboxPreviewBox.ZIndex = 55; HitboxPreviewBox:SetAttribute("TargetHeight", 140); Instance.new("UICorner", HitboxPreviewBox).CornerRadius = UDim.new(0, 4); Instance.new("UIStroke", HitboxPreviewBox).Color = Color3.fromRGB(35, 35, 35)

-- MOTOR DE WALL CHECK DINÂMICO RECONSTRUÍDO
local function ScanDynamicExposedMassa(character)
    if not character then return nil end
    local myChar = LocalPlayer.Character; if not myChar or not myChar:FindFirstChild("Head") then return nil end
    local origin = Camera.CFrame.Position -- Origem da perspectiva real do jogador (Câmera)
    local boneCandidates = {Settings.Hitbox, "Head", "UpperTorso", "Torso", "HumanoidRootPart"}
    if not Settings.MultiBoneScan then boneCandidates = {Settings.Hitbox} end
    local bestPart = nil; local minMouseDist = math.huge; local screenCenter = GetTrueScreenCenter()
    
    for _, boneName in ipairs(boneCandidates) do
        local part = character:FindFirstChild(boneName)
        if part and part:IsA("BasePart") then
            local targetPos = part.Position; local direction = targetPos - origin; local hitVisible = false
            if not Settings.WallCheck then 
                hitVisible = true
            else
                -- Realiza o disparo do raio ignorando o próprio bone e assessórios sem colisão
                local result = Workspace:Raycast(origin, direction, WALL_CHECK_PARAMS)
                if result and result.Instance then
                    -- Se bater no próprio alvo ou em partes transparentes/sem colisão física, está visível
                    if result.Instance:IsDescendantOf(character) or result.Instance.Transparency >= 0.75 or not result.Instance.CanCollide then 
                        hitVisible = true
                    elseif Settings.WallPenetration then 
                        -- Algoritmo de dupla checagem para atravessar cantos de paredes finas
                        local reverseResult = Workspace:Raycast(targetPos, origin - targetPos, WALL_CHECK_PARAMS)
                        if reverseResult and reverseResult.Instance == result.Instance then
                            if (result.Position - reverseResult.Position).Magnitude <= Settings.MaxPenetrationThick then 
                                hitVisible = true 
                            end
                        end
                    end
                else 
                    hitVisible = true 
                end
            end
            if hitVisible then
                local screenPos, onScreen = Camera:WorldToViewportPoint(targetPos)
                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                    if dist < minMouseDist then minMouseDist = dist; bestPart = part end
                end
            end
        end
    end
    return bestPart
end

local function CalculateAdvancedPrediction(targetPart, deltaTime)
    if not Settings.MovementPrediction or not targetPart then return targetPart.Position end
    local partName = targetPart:GetDebugId(); local currentPos = targetPart.Position; local currentTime = os.clock()
    if not TargetMotionCache[partName] then
        TargetMotionCache[partName] = { lastPosition = currentPos, lastVelocity = Vector3.zero, lastTime = currentTime }
        return currentPos
    end
    local cache = TargetMotionCache[partName]; local timeDelta = currentTime - cache.lastTime; if timeDelta <= 0 then timeDelta = deltaTime end
    local currentVelocity = (currentPos - cache.lastPosition) / timeDelta; local acceleration = (currentVelocity - cache.lastVelocity) / timeDelta
    cache.lastPosition = currentPos; cache.lastVelocity = currentVelocity; cache.lastTime = currentTime
    local ping = 0.03; pcall(function() ping = game:GetService("Stats").Network.ServerToClientPing:GetValue() / 1000 end)
    local timeProjection = ping * (Settings.PredictStrength / 50)
    local predictedPosition = currentPos + (currentVelocity * timeProjection) + (0.5 * acceleration * (timeProjection ^ 2))
    if (predictedPosition - currentPos).Magnitude > 15 then predictedPosition = currentPos + (currentVelocity * 0.05) end
    return predictedPosition
end

local function validateCharacter(char)
    if not char or not char.Parent then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    return true
end

-- POPULA INTERFACE DO MENU
AddSectionSeparator("COGNITIVO & EVOLUÇÃO GERAL", PageGeral)
AddToggle("Checar Paredes (Multi-Ponto)", Settings.WallCheck, PageGeral, "Habilita varredura física anatômica avançada por Raycast.", function(v) Settings.WallCheck = v end)
AddToggle("Multi-Bone Scan Dinâmico", Settings.MultiBoneScan, PageGeral, "Muda dinamicamente o alvo do osso se a obstrução esconder a cabeça.", function(v) Settings.MultiBoneScan = v end)
AddToggle("Wall Penetration por Calibre", Settings.WallPenetration, PageGeral, "Identifica a ferramenta activa e adapta a varada para snipers/rifles.", function(v) Settings.WallPenetration = v end)
AddSlider("Max Varada Espessura", 0.5, 10, Settings.MaxPenetrationThick, PageGeral, "Espessura de colisão física limite calculada em studs.", function(v) Settings.MaxPenetrationThick = v end)
AddToggle("Ignorar Time (Heurística)", Settings.TeamCheck, PageGeral, "Filtra aliados usando dados nativos.", function(v) Settings.TeamCheck = v end)
AddToggle("Previsão Vetorial Dinâmica", Settings.MovementPrediction, PageGeral, "Antecipa trajetórias complexas usando aceleração angular de 2ª ordem.", function(v) Settings.MovementPrediction = v end)

AddSectionSeparator("MOTOR DE AIMBOT PRINCIPAL", PageAimbot)
AddToggle("Ativar Mecanismo Aimbot", Settings.AimbotEnabled, PageAimbot, "Conecta o travamento automático do centro focal.", function(v) Settings.AimbotEnabled = v; TweenPreviewFade(FovPreviewBox, Settings.AimbotEnabled and Settings.ShowFOV) end)
AddSelector("Prioridade de Alvo", {"Distancia FOV", "Menor Vida", "Proximidade"}, Settings.TargetPriority, PageAimbot, "Modo inteligente de seleção e ordenação de alvos.", function(v) Settings.TargetPriority = v end)
AddSelector("Alvo Principal (Hitbox)", {"Head", "Torso", "HumanoidRootPart"}, Settings.Hitbox, PageAimbot, "Osso preferencial inicial do escaneamento.", function(v) Settings.Hitbox = v end)
AddSlider("Suavidade da Câmera", 1, 25, Settings.SmoothValue, PageAimbot, "Controle de amortecimento de curva linear padrão.", function(v) Settings.SmoothValue = v end)
AddToggle("Suavidade Dinâmica", Settings.DynamicSmoothness, PageAimbot, "Ajusta a suavidade baseado na distância física do inimigo.", function(v) Settings.DynamicSmoothness = v end)
AddSlider("Multiplicador Dist.", 1, 15, Settings.DynamicSmoothMultiplier, PageAimbot, "Intensidade do freio mecânico para inimigos distantes.", function(v) Settings.DynamicSmoothMultiplier = v end)
AddSlider("Ímã do Aimbot (Sticky)", 5, 100, Settings.StickyStrength, PageAimbot, "Magnetismo applied no frame interno.", function(v) Settings.StickyStrength = v end)
AddSectionSeparator("SISTEMA FLICK ASSIST INDEPENDENTE", PageAimbot)
AddToggle("Ativar Mecanismo Flick", Settings.FlickEnabled, PageAimbot, "Ativa a puxada balística instantânea ao disparar o gatilho.", function(v) Settings.FlickEnabled = v end)
AddSlider("Suavização do Flick", 1, 10, Settings.FlickSmooth, PageAimbot, "1 = Teleporte Seco. Valores maiores imitam reflexo humano.", function(v) Settings.FlickSmooth = v end)
AddSlider("Campo do Flick (Graus)", 1, 35, Settings.FlickFovDegrees, PageAimbot, "Circunferência exclusiva onde o Flick detecta e puxa.", function(v) Settings.FlickFovDegrees = v end)

AddSectionSeparator("INTERRUPÇÃO DE VETOR & LOCK", PageLock)
AddToggle("Trava Magnética Permanente", Settings.StickyLock, PageLock, "Mantém o alvo travado mesmo se ele correr para fora do círculo do FOV.", function(v) Settings.StickyLock = v end)
AddSlider("Força de Escape (Breakout)", 5, 50, Settings.BreakoutForce, PageLock, "Quantidade de effort manual necessário para ejetar o Lock.", function(v) Settings.BreakoutForce = v end)
AddSectionSeparator("AMORTECIMENTO EM CORPO A CORPO", PageLock)
AddToggle("Ativar Redução de Perto", Settings.ProximityDampEnabled, PageLock, "Reduz automaticamente o magnetismo quando o inimigo gruda em você.", function(v) Settings.ProximityDampEnabled = v end)
AddSlider("Distância de Ativação (Studs)", 10, 60, Settings.ProximityMaxDistance, PageLock, "Distância limite para começar a amolecer o travamento.", function(v) Settings.ProximityMaxDistance = v end)
AddSlider("Força Retida Mínima (%)", 10, 90, Settings.ProximityMinStrength, PageLock, "Porcentagem de força de imã que restará no ponto mais colado do alvo.", function(v) Settings.ProximityMinStrength = v end)
AddSectionSeparator("SUAVIZAÇÃO HUMANA AVANÇADA", PageLock)
AddSlider("Retorno de Peso Humano", 1, 10, Settings.WeightRecoverySpeed, PageLock, "Velocidade com que recupera a mira após um desengajamento manual.", function(v) Settings.WeightRecoverySpeed = v end)
AddToggle("Fricção de Movimento", Settings.HumanFriction, PageLock, "Amolece a mira proporcionalmente à velocidade angular do inimigo.", function(v) Settings.HumanFriction = v end)
AddToggle("Tremor Neuromuscular", Settings.NeuromuscularTremor, PageLock, "Gera micro-oscilações imperceptíveis na câmera.", function(v) Settings.NeuromuscularTremor = v end)
AddSlider("Intensidade do Tremor", 1, 10, Settings.TremorIntensity, PageLock, "Amplitude física das micro-vibrações simuladas na câmera.", function(v) Settings.TremorIntensity = v end)

local CrosshairObjects = {}
local function BuildCrosshairInstances()
    CrosshairBase:ClearAllChildren(); CrosshairObjects = {}
    local dot = Instance.new("Frame"); dot.AnchorPoint = Vector2.new(0.5, 0.5); dot.BorderSizePixel = 0; dot.ZIndex = 3; dot.Parent = CrosshairBase; Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0); CrosshairObjects.Dot = dot
    CrosshairObjects.Lines = {}
    for i = 1, 4 do local arm = Instance.new("Frame"); arm.BorderSizePixel = 0; arm.AnchorPoint = Vector2.new(0.5, 0.5); arm.ZIndex = 3; arm.Parent = CrosshairBase; CrosshairObjects.Lines[i] = arm end
end
BuildCrosshairInstances()

AddSectionSeparator("PROJEÇÃO DE CAMPO DE VISÃO", PageFovTab)
AddToggle("Exibir Círculo FOV", Settings.ShowFOV, PageFovTab, "Renderiza a circunferência óptica na tela.", function(v) Settings.ShowFOV = v; FOVCircle.Visible = v; TweenPreviewFade(FovPreviewBox, v) end)
AddSlider("Ângulo do Campo (Graus)", 1, 50, Settings.FovDegrees, PageFovTab, "Abertura focal em graus angulares.", function(v) Settings.FovDegrees = v end)

FovPreviewBox.Parent = PageFovTab
local FovPreviewLabel = Instance.new("TextLabel"); FovPreviewLabel.Size = UDim2.new(1, 0, 0, 14); FovPreviewLabel.Position = UDim2.new(0, 6, 0, 4); FovPreviewLabel.BackgroundTransparency = 1; FovPreviewLabel.Text = "PREVIEW DO ESCANER 2D"; FovPreviewLabel.TextColor3 = Color3.fromRGB(100, 105, 110); FovPreviewLabel.Font = Enum.Font.SourceSansBold; FovPreviewLabel.TextSize = 10; FovPreviewLabel.ZIndex = 56; FovPreviewLabel.Parent = FovPreviewBox
local FovSimCircle = Instance.new("Frame"); FovSimCircle.AnchorPoint = Vector2.new(0.5, 0.5); FovSimCircle.Position = UDim2.new(0.5, 0, 0.5, 6); FovSimCircle.BackgroundTransparency = 1; FovSimCircle.ZIndex = 56; FovSimCircle.Parent = FovPreviewBox
local FovSimStroke = Instance.new("UIStroke", FovSimCircle); FovSimStroke.Thickness = 1.5; FovSimStroke.Color = Color3.fromRGB(Settings.FovColorR, Settings.FovColorG, Settings.FovColorB); FovSimStroke.Transparency = 0.3; Instance.new("UICorner", FovSimCircle).CornerRadius = UDim.new(1, 0)
local FlickSimCircle = Instance.new("Frame"); FlickSimCircle.AnchorPoint = Vector2.new(0.5, 0.5); FlickSimCircle.Position = UDim2.new(0.5, 0, 0.5, 6); FlickSimCircle.BackgroundTransparency = 1; FlickSimCircle.ZIndex = 56; FlickSimCircle.Parent = FovPreviewBox
local FlickSimStroke = Instance.new("UIStroke", FlickSimCircle); FlickSimStroke.Thickness = 1.5; FlickSimStroke.Color = Color3.fromRGB(255, 0, 80); FlickSimStroke.Transparency = 0.4; Instance.new("UICorner", FlickSimCircle).CornerRadius = UDim.new(1, 0)

local function DynamicUpdateFovPreviews()
    local scaleFactor = 2.2; FovSimCircle.Size = UDim2.new(0, Settings.FovDegrees * scaleFactor * 2, 0, Settings.FovDegrees * scaleFactor * 2)
    FlickSimCircle.Size = UDim2.new(0, Settings.FlickFovDegrees * scaleFactor * 2, 0, Settings.FlickFovDegrees * scaleFactor * 2)
    FlickSimCircle.Visible = Settings.FlickEnabled
end

local UpdateCrosshairVisuals
AddSectionSeparator("RETÍCULA HUD CENTRAL", PageCrosshair)
AddToggle("Ativar Retícula Central", Settings.CrosshairEnabled, PageCrosshair, "Desenha elementos vetoriais fixos no centro.", function(v) Settings.CrosshairEnabled = v; UpdateCrosshairVisuals(); TweenPreviewFade(CrossPreviewBox, v) end)
AddSelector("Modelo", {"Padrão", "Ponto", "X"}, Settings.CrosshairType, PageCrosshair, "Geometria da retícula.", function(v) Settings.CrosshairType = v; UpdateCrosshairVisuals() end)
AddSlider("Tamanho das Linhas", 2, 40, Settings.CrosshairSize, PageCrosshair, "Comprimento dos eixos ou diâmetro do ponto.", function(v) Settings.CrosshairSize = v; UpdateCrosshairVisuals() end)
AddSlider("Espaçamento (Gap)", 0, 20, Settings.CrosshairGap, PageCrosshair, "Distância interna do centro até as lines.", function(v) Settings.CrosshairGap = v; UpdateCrosshairVisuals() end)

CrossPreviewBox.Parent = PageCrosshair
local CrossPreviewLabel = Instance.new("TextLabel"); CrossPreviewLabel.Size = UDim2.new(1, 0, 0, 14); CrossPreviewLabel.Position = UDim2.new(0, 6, 0, 4); CrossPreviewLabel.BackgroundTransparency = 1; CrossPreviewLabel.Text = "PREVIEW DA RETÍCULA CUSTOM"; CrossPreviewLabel.TextColor3 = Color3.fromRGB(100, 105, 110); CrossPreviewLabel.Font = Enum.Font.SourceSansBold; CrossPreviewLabel.TextSize = 10; CrossPreviewLabel.ZIndex = 56; CrossPreviewLabel.Parent = CrossPreviewBox
local CrossSimCenter = Instance.new("Frame"); CrossSimCenter.Position = UDim2.new(0.5, 0, 0.5, 6); CrossSimCenter.BackgroundTransparency = 1; CrossSimCenter.ZIndex = 56; CrossSimCenter.Parent = CrossPreviewBox
local SimDot = Instance.new("Frame"); SimDot.AnchorPoint = Vector2.new(0.5, 0.5); SimDot.BorderSizePixel = 0; SimDot.ZIndex = 57; SimDot.Parent = CrossSimCenter; Instance.new("UICorner", SimDot).CornerRadius = UDim.new(1, 0)
local SimLines = {} for i = 1, 4 do local arm = Instance.new("Frame"); arm.BorderSizePixel = 0; arm.AnchorPoint = Vector2.new(0.5, 0.5); arm.ZIndex = 57; arm.Parent = CrossSimCenter; SimLines[i] = arm end

local function RedrawCrosshairPreviewInsideMenu()
    local color = Color3.fromRGB(Settings.CrosshairColorR, Settings.CrosshairColorG, Settings.CrosshairColorB); local size = Settings.CrosshairSize; local gap = Settings.CrosshairGap; local mode = Settings.CrosshairType
    if mode == "Ponto" then
        SimDot.Visible = true; SimDot.Size = UDim2.new(0, 4, 0, 4); SimDot.BackgroundColor3 = color; for i = 1, 4 do SimLines[i].Visible = false end
    elseif mode == "X" then
        SimDot.Visible = false
        for i = 1, 4 do
            local arm = SimLines[i]; arm.Visible = true; arm.Size = UDim2.new(0, size, 0, 2); arm.BackgroundColor3 = color
            if i == 1 then arm.Position = UDim2.new(0, -gap - size/2, 0, -gap - size/2); arm.Rotation = 45
            elseif i == 2 then arm.Position = UDim2.new(0, gap + size/2, 0, -gap - size/2); arm.Rotation = -45
            elseif i == 3 then arm.Position = UDim2.new(0, -gap - size/2, 0, gap + size/2); arm.Rotation = -45
            elseif i == 4 then arm.Position = UDim2.new(0, gap + size/2, 0, gap + size/2); arm.Rotation = 45 end
        end
    elseif mode == "Padrão" then
        SimDot.Visible = true; SimDot.Size = UDim2.new(0, 2, 0, 2); SimDot.BackgroundColor3 = color
        local layouts = {{UDim2.new(0, -gap - size/2, 0, 0), UDim2.new(0, size, 0, 2)}, {UDim2.new(0, gap + size/2, 0, 0), UDim2.new(0, size, 0, 2)}, {UDim2.new(0, 0, 0, -gap - size/2), UDim2.new(0, 2, 0, size)}, {UDim2.new(0, 0, 0, gap + size/2), UDim2.new(0, 2, 0, size)}}
        for i = 1, 4 do local arm = SimLines[i]; arm.Visible = true; arm.Position = layouts[i][1]; arm.Size = layouts[i][2]; arm.BackgroundColor3 = color; arm.Rotation = 0 end
    end
end

UpdateCrosshairVisuals = function()
    RedrawCrosshairPreviewInsideMenu()
    if not Settings.CrosshairEnabled then CrosshairBase.Visible = false; return end
    CrosshairBase.Visible = true; local color = Color3.fromRGB(Settings.CrosshairColorR, Settings.CrosshairColorG, Settings.CrosshairColorB); local size = Settings.CrosshairSize; local gap = Settings.CrosshairGap; local mode = Settings.CrosshairType
    if mode == "Ponto" then
        CrosshairObjects.Dot.Visible = true; CrosshairObjects.Dot.Size = UDim2.new(0, 4, 0, 4); CrosshairObjects.Dot.Position = UDim2.new(0.5, 0, 0.5, 0); CrosshairObjects.Dot.BackgroundColor3 = color
        for i = 1, 4 do CrosshairObjects.Lines[i].Visible = false end
    elseif mode == "X" then
        CrosshairObjects.Dot.Visible = false
        for i = 1, 4 do
            local arm = CrosshairObjects.Lines[i]; arm.Visible = true; arm.Size = UDim2.new(0, size, 0, 2); arm.BackgroundColor3 = color
            if i == 1 then arm.Position = UDim2.new(0.5, -gap - size/2, 0.5, -gap - size/2); arm.Rotation = 45
            elseif i == 2 then arm.Position = UDim2.new(0.5, gap + size/2, 0.5, -gap - size/2); arm.Rotation = -45
            elseif i == 3 then arm.Position = UDim2.new(0.5, -gap - size/2, 0.5, gap + size/2); arm.Rotation = -45
            elseif i == 4 then arm.Position = UDim2.new(0.5, gap + size/2, 0.5, gap + size/2); arm.Rotation = 45 end
        end
    elseif mode == "Padrão" then
        CrosshairObjects.Dot.Visible = true; CrosshairObjects.Dot.Size = UDim2.new(0, 2, 0, 2); CrosshairObjects.Dot.Position = UDim2.new(0.5, 0, 0.5, 0); CrosshairObjects.Dot.BackgroundColor3 = color
        local layouts = {{UDim2.new(0.5, -gap - size, 0.5, -1), UDim2.new(0, size, 0, 2)}, {UDim2.new(0.5, gap, 0.5, -1), UDim2.new(0, size, 0, 2)}, {UDim2.new(0.5, -1, 0.5, -gap - size), UDim2.new(0, 2, 0, size)}, {UDim2.new(0.5, -1, 0.5, gap), UDim2.new(0, 2, 0, size)}}
        for i = 1, 4 do local arm = CrosshairObjects.Lines[i]; arm.Visible = true; arm.Position = layouts[i][1]; arm.Size = layouts[i][2]; arm.BackgroundColor3 = color; arm.Rotation = 0 end
    end
end
UpdateCrosshairVisuals()

AddSectionSeparator("HITBOX EXPANDER MOTOR", PageHitbox)
AddToggle("Ativar Expander Global", Settings.HitboxExpander, PageHitbox, "Aumenta e força a colisão física real da hitbox de forma constante.", function(v) Settings.HitboxExpander = v; TweenPreviewFade(HitboxPreviewBox, v) end)

-- PREVIEW DUMMY ANATÔMICO
HitboxPreviewBox.Parent = PageHitbox
local HitboxPreviewLabel = Instance.new("TextLabel"); HitboxPreviewLabel.Size = UDim2.new(1, 0, 0, 14); HitboxPreviewLabel.Position = UDim2.new(0, 6, 0, 4); HitboxPreviewLabel.BackgroundTransparency = 1; HitboxPreviewLabel.Text = "PREVIEW DA HITBOX ANATÔMICA"; HitboxPreviewLabel.TextColor3 = Color3.fromRGB(100, 105, 110); HitboxPreviewLabel.Font = Enum.Font.SourceSansBold; HitboxPreviewLabel.TextSize = 10; HitboxPreviewLabel.ZIndex = 56; HitboxPreviewLabel.Parent = HitboxPreviewBox

local Viewport = Instance.new("ViewportFrame"); Viewport.Size = UDim2.new(1, 0, 1, -20); Viewport.Position = UDim2.new(0, 0, 0, 20); Viewport.BackgroundColor3 = Color3.fromRGB(12, 12, 12); Viewport.BorderSizePixel = 0; Viewport.ZIndex = 55; Viewport.Parent = HitboxPreviewBox
local ViewWorld = Instance.new("WorldModel", Viewport)
local ViewCam = Instance.new("Camera"); ViewCam.FieldOfView = 42; Viewport.CurrentCamera = ViewCam; ViewCam.Parent = Viewport

local DummyModel = Instance.new("Model", ViewWorld)
local HumRoot = Instance.new("Part", DummyModel); HumRoot.Name = "HumanoidRootPart"; HumRoot.Size = Vector3.new(2, 2, 1); HumRoot.Position = Vector3.new(0, 0, 0); HumRoot.Color = Color3.fromRGB(24, 24, 24); HumRoot.Transparency = 0.5; HumRoot.Anchored = true
local LowerTorso = Instance.new("Part", DummyModel); LowerTorso.Name = "LowerTorso"; LowerTorso.Size = Vector3.new(2, 0.8, 1); LowerTorso.Position = Vector3.new(0, -0.6, 0); LowerTorso.Color = Color3.fromRGB(30, 30, 30); LowerTorso.Anchored = true
local UpperTorso = Instance.new("Part", DummyModel); UpperTorso.Name = "UpperTorso"; UpperTorso.Size = Vector3.new(2, 1.2, 1); UpperTorso.Position = Vector3.new(0, 0.4, 0); UpperTorso.Color = Color3.fromRGB(35, 35, 35); UpperTorso.Anchored = true
local Head3D = Instance.new("Part", DummyModel); Head3D.Name = "Head"; Head3D.Size = Vector3.new(1.2, 1.2, 1.2); Head3D.Color = Color3.fromRGB(0, 255, 120); Head3D.Material = Enum.Material.Neon; Head3D.Anchored = true
local HeadMesh = Instance.new("SpecialMesh", Head3D); HeadMesh.MeshType = Enum.MeshType.Head

local function RebuildAnatomicalDummyPreview(size)
    Settings.HitboxSize = size
    local baseScale = 1.2 + size
    Head3D.Size = Vector3.new(baseScale, baseScale, baseScale)
    Head3D.Position = Vector3.new(0, 1.4 + (size / 2), 0)
    if HeadMesh then HeadMesh.Scale = Vector3.new(1, 1, 1) end
end

local currentAngle = 25
local function UpdateCamera3D()
    local rad = math.rad(currentAngle)
    local dDist = 6.8 + (Settings.HitboxSize * 0.85)
    ViewCam.CFrame = CFrame.new(Vector3.new(dDist * math.sin(rad), 0.8, dDist * math.cos(rad)), Vector3.new(0, 0.2, 0))
end

AddSlider("Aumento da Hitbox", 0, 15, Settings.HitboxSize, PageHitbox, "Multiplicador incremental em studs.", function(v) 
    RebuildAnatomicalDummyPreview(v)
    UpdateCamera3D()
end)
RebuildAnatomicalDummyPreview(Settings.HitboxSize)
UpdateCamera3D()

local isRotating = false; local lastMouseX = 0
AddConnection(Viewport.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then isRotating = true; lastMouseX = input.Position.X end end))
AddConnection(UserInputService.InputChanged:Connect(function(input) if isRotating and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then local deltaX = input.Position.X - lastMouseX; lastMouseX = input.Position.X; currentAngle = currentAngle - (deltaX * 0.75); UpdateCamera3D() end end))
AddConnection(UserInputService.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then isRotating = false end end))

local TitleLabel = Instance.new("TextLabel"); TitleLabel.Size = UDim2.new(1, 0, 0, 35); TitleLabel.BackgroundTransparency = 1; TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255); TitleLabel.Text = "PREMONITION ENGINE v87.5.0"; TitleLabel.Font = Enum.Font.SourceSansBold; TitleLabel.TextSize = 13; TitleLabel.ZIndex = 52; TitleLabel.Parent = MainPanel

AddConnection(UserInputService.InputBegan:Connect(function(input, processed) if not processed and Settings.FlickEnabled and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then FlickActiveThisFrame = true end end))
AddConnection(UserInputService.InputChanged:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        TouchVelocity2D = input.Delta.Magnitude
        if TouchVelocity2D > 1.5 then DynamicUserWeight = math.clamp(1.0 - (TouchVelocity2D / Settings.BreakoutForce), 0.05, 1.0) else DynamicUserWeight = 1.0 end
        if TouchVelocity2D > Settings.BreakoutForce then EscapeCooldown = 0.25; CurrentTarget = nil; TargetPart = nil end
    end
end))

-- LOOP CORE DE FLUXO CONTÍNUO REFORMULADO
task.spawn(function()
    local lastLoopTime = os.clock()
    while ENV.PremonitionLoopActive do
        local currentLoopTime = os.clock()
        local loopDelta = currentLoopTime - lastLoopTime
        lastLoopTime = currentLoopTime
        
        task.wait(0.01)

        DynamicUpdateFovPreviews()

        -- NOVO ALGORITMO FISICO DO HITBOX EXPANDER (FORÇA REPLICAÇÃO LOCAL)
        for _, char in ipairs(ActiveTargets) do
            if validateCharacter(char) then
                local targetBone = char:FindFirstChild(Settings.Hitbox) or char:FindFirstChild("HumanoidRootPart")
                if targetBone and targetBone:IsA("BasePart") then
                    if Settings.HitboxExpander and Settings.HitboxSize > 0 then
                        local sizeIncrement = Settings.HitboxSize
                        targetBone.Size = Vector3.new(sizeIncrement, sizeIncrement, sizeIncrement)
                        targetBone.Transparency = 0.65
                        targetBone.Color = Color3.fromRGB(0, 255, 120)
                        targetBone.Material = Enum.Material.Neon
                        targetBone.CanCollide = false -- Evita que os inimigos empurrem você ao andar perto
                    else
                        -- Reseta para o tamanho original e propriedades padrão se desligado
                        if targetBone.Name == "Head" then
                            targetBone.Size = Vector3.new(2, 1, 1)
                        else
                            targetBone.Size = Vector3.new(2, 2, 1)
                        end
                        targetBone.Transparency = 0
                        targetBone.Material = Enum.Material.Plastic
                    end
                end
            end
        end

        if (Settings.AimbotEnabled or Settings.FlickEnabled) and EscapeCooldown <= 0 then
            ScreenCenter = GetTrueScreenCenter(); local center = ScreenCenter
            local bestScore = math.huge; local selectedPlayer, selectedPart = nil, nil
            local ignoreScan = false

            if Settings.StickyLock and CurrentTarget and TargetPart then
                local pChar = CurrentTarget.Character
                if validateCharacter(pChar) and AdvancedTeamCheck(CurrentTarget) and ScanDynamicExposedMassa(pChar) then 
                    ignoreScan = true 
                else
                    CurrentTarget = nil; TargetPart = nil
                end
            end

            if not ignoreScan then
                local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                for _, char in ipairs(ActiveTargets) do
                    if validateCharacter(char) then
                        local p = Players:GetPlayerFromCharacter(char); local hum = char:FindFirstChildOfClass("Humanoid")
                        if p and AdvancedTeamCheck(p) and hum then
                            local exposedPart = ScanDynamicExposedMassa(char)
                            if exposedPart then
                                local screenPos, onScreen = Camera:WorldToViewportPoint(exposedPart.Position)
                                if onScreen then
                                    local mouseDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                                    if mouseDist <= (FlickActiveThisFrame and ComputedFlickPixelRadius or ComputedPixelRadius) then
                                        local currentScore = Settings.TargetPriority == "Distancia FOV" and mouseDist or (Settings.TargetPriority == "Menor Vida" and hum.Health or (localRoot and (exposedPart.Position - localRoot.Position).Magnitude or mouseDist))
                                        if currentScore < bestScore then bestScore = currentScore; selectedPlayer = p; selectedPart = exposedPart end
                                    end
                                end
                            end
                        end
                    end
                end
                if selectedPlayer then 
                    CurrentTarget = selectedPlayer; TargetPart = selectedPart 
                elseif not Settings.StickyLock or FlickActiveThisFrame then 
                    CurrentTarget = nil; TargetPart = nil 
                end
            end
        end
    end
end)

-- LOOP DE RENDERIZAÇÃO DA CÂMERA
AddConnection(RunService.PreRender:Connect(function(deltaTime)
    deltaTime = math.clamp(deltaTime, 0.001, 0.033); ScreenCenter = GetTrueScreenCenter(); local center = ScreenCenter
    if EscapeCooldown > 0 then EscapeCooldown = EscapeCooldown - deltaTime end
    if TouchVelocity2D <= 1.5 then DynamicUserWeight = math.min(DynamicUserWeight + (deltaTime * Settings.WeightRecoverySpeed), 1.0) end

    ComputedPixelRadius = CalculateAngularRadius(Settings.FovDegrees)
    ComputedFlickPixelRadius = CalculateAngularRadius(Settings.FlickFovDegrees)
    
    if FOVCircle then FOVCircle.Size = UDim2.new(0, ComputedPixelRadius * 2, 0, ComputedPixelRadius * 2); FOVCircle.Position = UDim2.new(0, center.X, 0, center.Y); FOVCircle.Visible = Settings.ShowFOV end
    if FlickFOVCircle then FlickFOVCircle.Size = UDim2.new(0, ComputedFlickPixelRadius * 2, 0, ComputedFlickPixelRadius * 2); FlickFOVCircle.Position = UDim2.new(0, center.X, 0, center.Y); FlickFOVCircle.Visible = Settings.FlickEnabled and Settings.ShowFOV end
    if CrosshairBase then CrosshairBase.Position = UDim2.new(0, center.X, 0, center.Y) end

    if CurrentTarget and TargetPart and validateCharacter(CurrentTarget.Character) and EscapeCooldown <= 0 then
        local myChar = LocalPlayer.Character; local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if myChar and myRoot then
            local distance3D = (TargetPart.Position - myRoot.Position).Magnitude
            local proximityProportion = Settings.ProximityDampEnabled and math.clamp((distance3D - 6) / (Settings.ProximityMaxDistance - 6), Settings.ProximityMinStrength / 100, 1.0) or 1.0
            local targetWorldPos = CalculateAdvancedPrediction(TargetPart, deltaTime)
            local screenPos, onScreen = Camera:WorldToViewportPoint(targetWorldPos)
            
            if onScreen then
                if Settings.SnapMarkers then SnapLeft.Visible, SnapRight.Visible = true, true; SnapLeft.Position = UDim2.new(0, screenPos.X - 16, 0, screenPos.Y - 14); SnapRight.Position = UDim2.new(0, screenPos.X + 8, 0, screenPos.Y - 14) else SnapLeft.Visible, SnapRight.Visible = false, false end
                local targetCFrame = CFrame.new(Camera.CFrame.Position, targetWorldPos); local finalAlpha = 0
                
                if FlickActiveThisFrame and Settings.FlickEnabled then finalAlpha = math.clamp(1 / math.max(Settings.FlickSmooth, 1), 0.1, 1.0); FlickActiveThisFrame = false
                elseif Settings.AimbotEnabled then
                    local baseSmooth = Settings.DynamicSmoothness and (Settings.SmoothValue * (1.0 + (math.clamp(distance3D / 50, 0.5, 4.0) * (Settings.DynamicSmoothMultiplier / 10)))) or Settings.SmoothValue
                    finalAlpha = math.clamp((1 / math.max(baseSmooth, 1)) * (Settings.StickyStrength / 100) * DynamicUserWeight * proximityProportion, 0.001, 0.8)
                end

                if Settings.HumanFriction then local motionData = TargetMotionCache[TargetPart:GetDebugId()]; finalAlpha = finalAlpha * (1.0 - (math.clamp((motionData and motionData.lastVelocity.Magnitude or 0) / 75, 0, 0.25))) end
                if finalAlpha > 0 then
                    if Settings.NeuromuscularTremor then local tIntensity = (Settings.TremorIntensity / 1000) * (1.1 - proximityProportion); targetCFrame = targetCFrame * CFrame.Angles(math.noise(tick() * 25, 0) * tIntensity, math.noise(0, tick() * 25) * tIntensity, 0) end
                    Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, finalAlpha)
                end
            end
        end
    else SnapLeft.Visible, SnapRight.Visible = false, false end
    TouchVelocity2D = 0; FlickActiveThisFrame = false
end))

print("[PREMONITION V87.5.0] Atualização Crítica Concluída. Team Check & Wall Check Estabilizados.")
