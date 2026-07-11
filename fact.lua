-- ====================================================================
-- AUTONOMOUS PREMIUM HUD v20.0.0 (GLASSMORPHISM / VISIONOS UI OVERHAUL)
-- ====================================================================

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local function GetCurrentCamera()
    if not Workspace then return nil end
    return Workspace.CurrentCamera or Workspace:WaitForChild("Camera", 5)
end

local camera = GetCurrentCamera()
if camera and not _G.OriginalFOV then
    _G.OriginalFOV = camera.FieldOfView or 70
end

local TargetGui = nil
if gethui then
    TargetGui = gethui()
elseif pcall(function() game:GetService("CoreGui"):FindFirstChild("RobloxGui") end) then
    TargetGui = game:GetService("CoreGui")
else
    TargetGui = LocalPlayer:WaitForChild("PlayerGui", 15)
end

pcall(function() TargetGui:FindFirstChild("PureMagnetUI"):Destroy() end)
pcall(function() TargetGui:FindFirstChild("MagnetRingsFolder"):Destroy() end)

local RingsFolder = Instance.new("Folder")
RingsFolder.Name = "MagnetRingsFolder"
RingsFolder.Parent = TargetGui

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PureMagnetUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 999999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling 
ScreenGui.Parent = TargetGui

-- Paleta Temática Glassmorphism (Inspirada no macOS & Apple VisionOS)
local Theme = {
    Background = Color3.fromRGB(25, 28, 41),       -- Vidro Escuro Base
    BgTransparency = 0.35,                         -- Alta translucidez para efeito Glass
    CardBg = Color3.fromRGB(255, 255, 255),        -- Camada superior reflexiva esbranquiçada
    CardTransparency = 0.94,                       -- Quase invisível, apenas capta luz
    ColumnBg = Color3.fromRGB(0, 0, 0),            -- Fundo das listas para contraste
    ColTransparency = 0.85,
    DividerColor = Color3.fromRGB(255, 255, 255),  -- Linha sutil de reflexo
    Accent = Color3.fromRGB(0, 122, 255),          -- Azul Padrão Apple (iOS/macOS Native)
    TextWhite = Color3.fromRGB(255, 255, 255),     -- Texto de alta clareza
    TextMuted = Color3.fromRGB(160, 165, 185),     -- Subtítulos translúcidos
    TrackDark = Color3.fromRGB(120, 120, 128),     -- Trilhas cinza Apple nativo
    BorderColor = Color3.fromRGB(255, 255, 255),   -- Efeito de corte cristalino na borda
    RowHover = Color3.fromRGB(255, 255, 255)       -- Brilho ao passar o mouse
}

-- Configurações Ativas
local Config = {
    AimTracking = true,
    MagneticAssist = true,       
    MagneticLockRadius = 6.5,
    BaseSensitivity = 0.15,   
    DecoupleXY = true,
    SlowdownRing = 30.0,
    PullRingRadius = 120.0,      
    MagneticAcceleration = 4.0,
    MagneticCorrection = -2.0,
    WallCheck = false,       
    TeamCheck = false,           
    CustomFOV = false,        
    FOVValue = 90.0,
    ShowFOVCircle = true,     
    AimFOVRadius = 120.0,
    Prediction = true,
    BulletSpeed = 1100.0
}

-- Backup para restauração do Reset
local DefaultConfig = {}
for k, v in pairs(Config) do DefaultConfig[k] = v end

local VisualFOVCircle = Instance.new("Frame")
VisualFOVCircle.Name = "DynamicFOVCircle"
VisualFOVCircle.AnchorPoint = Vector2.new(0.5, 0.5)
VisualFOVCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
VisualFOVCircle.BackgroundTransparency = 1
VisualFOVCircle.Visible = Config.ShowFOVCircle
VisualFOVCircle.Parent = ScreenGui

Instance.new("UICorner", VisualFOVCircle).CornerRadius = UDim.new(1, 0)
local fovStroke = Instance.new("UIStroke", VisualFOVCircle)
fovStroke.Color = Theme.Accent
fovStroke.Thickness = 1.0
fovStroke.Transparency = 0.5

-- Botão Flutuante Estilo VisionOS Orb
local MenuButton = Instance.new("TextButton")
MenuButton.Name = "MagnetCoreButton"
MenuButton.Size = UDim2.new(0, 44, 0, 44)
MenuButton.Position = UDim2.new(0, 25, 0, 200)
MenuButton.BackgroundColor3 = Theme.Background
MenuButton.BackgroundTransparency = Theme.BgTransparency
MenuButton.Text = "🎯"
MenuButton.TextSize = 17
MenuButton.TextColor3 = Theme.Accent
MenuButton.Font = Enum.Font.GothamBold
MenuButton.Active = true
MenuButton.Parent = ScreenGui

Instance.new("UICorner", MenuButton).CornerRadius = UDim.new(1, 0)
local btnStroke = Instance.new("UIStroke", MenuButton)
btnStroke.Color = Theme.BorderColor
btnStroke.Transparency = 0.7
btnStroke.Thickness = 1.2

-- Painel Principal Mac/VisionOS
local MainPanel = Instance.new("Frame")
MainPanel.Size = UDim2.new(0, 160, 0, 320) 
MainPanel.Position = UDim2.new(0.5, -250, 0.5, -160)
MainPanel.BackgroundColor3 = Theme.Background
MainPanel.BackgroundTransparency = Theme.BgTransparency
MainPanel.ClipsDescendants = true 
MainPanel.Active = true
MainPanel.Visible = false
MainPanel.Parent = ScreenGui

Instance.new("UICorner", MainPanel).CornerRadius = UDim.new(0, 16)
local mainStroke = Instance.new("UIStroke", MainPanel)
mainStroke.Color = Theme.BorderColor
mainStroke.Transparency = 0.75
mainStroke.Thickness = 1.2

local UIUpdates = {}
local function RegisterUpdate(target, callback)
    if not UIUpdates[target] then UIUpdates[target] = {} end
    table.insert(UIUpdates[target], callback)
end
local function UpdateFeature(target, value)
    Config[target] = value
    if UIUpdates[target] then
        for _, cb in ipairs(UIUpdates[target]) do pcall(cb) end
    end
end

local dragging, dragInput, dragStart, startPos
MainPanel.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = MainPanel.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
MainPanel.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        TweenService:Create(MainPanel, TweenInfo.new(0.2, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
            Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        }):Play()
    end
end)

local LeftColumn = Instance.new("Frame", MainPanel)
LeftColumn.Size = UDim2.new(0, 140, 1, -24)
LeftColumn.Position = UDim2.new(0, 10, 0, 12)
LeftColumn.BackgroundTransparency = 1

local LeftList = Instance.new("UIListLayout", LeftColumn)
LeftList.Padding = UDim.new(0, 10)
LeftList.SortOrder = Enum.SortOrder.LayoutOrder

local NavContainer = Instance.new("Frame", LeftColumn)
NavContainer.Size = UDim2.new(1, 0, 0, 28)
NavContainer.BackgroundTransparency = 1
NavContainer.LayoutOrder = 1

local NavHorizontalList = Instance.new("UIListLayout", NavContainer)
NavHorizontalList.FillDirection = Enum.FillDirection.Horizontal
NavHorizontalList.Padding = UDim.new(0, 6)
NavHorizontalList.SortOrder = Enum.SortOrder.LayoutOrder

local function StyleNavHeader(frame)
    frame.BackgroundColor3 = Theme.CardBg
    frame.BackgroundTransparency = Theme.CardTransparency
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
    local s = Instance.new("UIStroke", frame)
    s.Color = Theme.BorderColor
    s.Transparency = 0.85
end

local NavHeader1 = Instance.new("Frame", NavContainer)
NavHeader1.Size = UDim2.new(0, 28, 0, 28) 
NavHeader1.ClipsDescendants = true
NavHeader1.LayoutOrder = 1
StyleNavHeader(NavHeader1)

local NavLabel1 = Instance.new("ImageButton", NavHeader1)
NavLabel1.Size = UDim2.new(0, 18, 0, 18)
NavLabel1.Position = UDim2.new(0, 5, 0, 5)
NavLabel1.Image = "rbxthumb://type=Asset&id=136983535522319&w=420&h=420"
NavLabel1.ImageColor3 = Theme.TextWhite
NavLabel1.ScaleType = Enum.ScaleType.Fit 
NavLabel1.BackgroundTransparency = 1

local NavText1 = Instance.new("TextLabel", NavHeader1)
NavText1.Size = UDim2.new(1, -34, 1, 0)
NavText1.Position = UDim2.new(0, 32, 0, 0)
NavText1.Text = "Aim Assist"
NavText1.TextColor3 = Theme.TextWhite
NavText1.Font = Enum.Font.GothamBold
NavText1.TextSize = 10
NavText1.TextXAlignment = Enum.TextXAlignment.Left
NavText1.BackgroundTransparency = 1
NavText1.TextTransparency = 1

local NavHeader2 = Instance.new("Frame", NavContainer)
NavHeader2.Size = UDim2.new(0, 28, 0, 28) 
NavHeader2.ClipsDescendants = true
NavHeader2.LayoutOrder = 2
StyleNavHeader(NavHeader2)

local NavLabel2 = Instance.new("ImageButton", NavHeader2)
NavLabel2.Size = UDim2.new(0, 18, 0, 18)
NavLabel2.Position = UDim2.new(0, 5, 0, 5)
NavLabel2.Image = "rbxthumb://type=Asset&id=121527214348885&w=420&h=420"
NavLabel2.ImageColor3 = Theme.TextWhite
NavLabel2.ScaleType = Enum.ScaleType.Fit 
NavLabel2.BackgroundTransparency = 1

local NavText2 = Instance.new("TextLabel", NavHeader2)
NavText2.Size = UDim2.new(1, -34, 1, 0)
NavText2.Position = UDim2.new(0, 32, 0, 0)
NavText2.Text = "Owner"
NavText2.TextColor3 = Theme.TextWhite
NavText2.Font = Enum.Font.GothamBold
NavText2.TextSize = 10
NavText2.TextXAlignment = Enum.TextXAlignment.Left
NavText2.BackgroundTransparency = 1
NavText2.TextTransparency = 1

local function CreateGlassCard(order)
    local Card = Instance.new("Frame", LeftColumn)
    Card.Size = UDim2.new(1, 0, 0, 0) 
    Card.Visible = false
    Card.ClipsDescendants = true
    Card.BackgroundColor3 = Theme.CardBg
    Card.BackgroundTransparency = Theme.CardTransparency
    Card.LayoutOrder = order
    Instance.new("UICorner", Card).CornerRadius = UDim.new(0, 12)
    
    local s = Instance.new("UIStroke", Card)
    s.Color = Theme.BorderColor
    s.Transparency = 0.88
    return Card
end

local Card1 = CreateGlassCard(2)
local C1_Txt = Instance.new("TextLabel", Card1)
C1_Txt.Size = UDim2.new(1, -16, 0, 14)
C1_Txt.Position = UDim2.new(0, 8, 0, 8)
C1_Txt.Text = "Trava de Mira"
C1_Txt.TextColor3 = Theme.TextWhite
C1_Txt.Font = Enum.Font.GothamBold
C1_Txt.TextSize = 10
C1_Txt.TextXAlignment = Enum.TextXAlignment.Left
C1_Txt.BackgroundTransparency = 1

local C1_Sub = Instance.new("TextLabel", Card1)
C1_Sub.Size = UDim2.new(1, -16, 0, 24)
C1_Sub.Position = UDim2.new(0, 8, 0, 20)
C1_Sub.Text = "Ativa o motor principal de rastreamento de alvos."
C1_Sub.TextColor3 = Theme.TextMuted
C1_Sub.Font = Enum.Font.Gotham
C1_Sub.TextSize = 7.5
C1_Sub.TextXAlignment = Enum.TextXAlignment.Left
C1_Sub.TextWrapped = true
C1_Sub.BackgroundTransparency = 1

local C1_Btn = Instance.new("TextButton", Card1)
C1_Btn.Size = UDim2.new(1, -16, 0, 24)
C1_Btn.Position = UDim2.new(0, 8, 1, -30)
C1_Btn.Font = Enum.Font.GothamBold
C1_Btn.TextSize = 9
Instance.new("UICorner", C1_Btn).CornerRadius = UDim.new(0, 8)
local c1bStroke = Instance.new("UIStroke", C1_Btn)
c1bStroke.Color = Theme.BorderColor
c1bStroke.Transparency = 0.8

RegisterUpdate("AimTracking", function()
    local isActive = Config.AimTracking
    TweenService:Create(C1_Btn, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
        BackgroundColor3 = isActive and Theme.Accent or Theme.CardBg,
        BackgroundTransparency = isActive and 0.15 or 0.9,
        TextColor3 = isActive and Color3.new(1,1,1) or Theme.TextWhite
    }):Play()
    C1_Btn.Text = isActive and "Ligado" or "Desligado"
end)
C1_Btn.MouseButton1Click:Connect(function() UpdateFeature("AimTracking", not Config.AimTracking) end)

local Card2 = CreateGlassCard(3)
local C2_Txt = Instance.new("TextLabel", Card2)
C2_Txt.Size = UDim2.new(1, -16, 0, 14)
C2_Txt.Position = UDim2.new(0, 8, 0, 8)
C2_Txt.Text = "Assist. Magnético"
C2_Txt.TextColor3 = Theme.TextWhite
C2_Txt.Font = Enum.Font.GothamBold
C2_Txt.TextSize = 10
C2_Txt.TextXAlignment = Enum.TextXAlignment.Left
C2_Txt.BackgroundTransparency = 1

local C2_Sub = Instance.new("TextLabel", Card2)
C2_Sub.Size = UDim2.new(1, -16, 0, 24)
C2_Sub.Position = UDim2.new(0, 8, 0, 20)
C2_Sub.Text = "Controla a fricção e a exibição dos anéis ópticos."
C2_Sub.TextColor3 = Theme.TextMuted
C2_Sub.Font = Enum.Font.Gotham
C2_Sub.TextSize = 7.5
C2_Sub.TextXAlignment = Enum.TextXAlignment.Left
C2_Sub.TextWrapped = true
C2_Sub.BackgroundTransparency = 1

local C2_Btn = Instance.new("TextButton", Card2)
C2_Btn.Size = UDim2.new(1, -16, 0, 24)
C2_Btn.Position = UDim2.new(0, 8, 1, -30)
C2_Btn.Font = Enum.Font.GothamBold
C2_Btn.TextSize = 9
Instance.new("UICorner", C2_Btn).CornerRadius = UDim.new(0, 8)
local c2bStroke = Instance.new("UIStroke", C2_Btn)
c2bStroke.Color = Theme.BorderColor
c2bStroke.Transparency = 0.8

RegisterUpdate("MagneticAssist", function()
    local isActive = Config.MagneticAssist
    TweenService:Create(C2_Btn, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
        BackgroundColor3 = isActive and Theme.Accent or Theme.CardBg,
        BackgroundTransparency = isActive and 0.15 or 0.9,
        TextColor3 = isActive and Color3.new(1,1,1) or Theme.TextWhite
    }):Play()
    C2_Btn.Text = isActive and "Ligado" or "Desligado"
end)
C2_Btn.MouseButton1Click:Connect(function() UpdateFeature("MagneticAssist", not Config.MagneticAssist) end)

local PresetContainer = Instance.new("Frame", LeftColumn)
PresetContainer.Size = UDim2.new(1, 0, 0, 0)
PresetContainer.BackgroundTransparency = 1
PresetContainer.ClipsDescendants = true
PresetContainer.LayoutOrder = 4

local PresetTitle = Instance.new("TextLabel", PresetContainer)
PresetTitle.Size = UDim2.new(1, 0, 0, 12)
PresetTitle.Position = UDim2.new(0, 4, 0, 0)
PresetTitle.Text = "PRE-CONFIGURAÇÕES"
PresetTitle.TextColor3 = Theme.TextMuted
PresetTitle.Font = Enum.Font.GothamBold
PresetTitle.TextSize = 8
PresetTitle.TextXAlignment = Enum.TextXAlignment.Left
PresetTitle.BackgroundTransparency = 1

local PresetButtonsFrame = Instance.new("Frame", PresetContainer)
PresetButtonsFrame.Size = UDim2.new(1, 0, 0, 36)
PresetButtonsFrame.Position = UDim2.new(0, 0, 0, 16)
PresetButtonsFrame.BackgroundTransparency = 1

local PresetLayout = Instance.new("UIListLayout", PresetButtonsFrame)
PresetLayout.FillDirection = Enum.FillDirection.Horizontal
PresetLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
PresetLayout.Padding = UDim.new(0, 8)

local PresetProfiles = {
    Legit = {
        AimTracking = true, MagneticAssist = true, MagneticLockRadius = 2.0, BaseSensitivity = 0.12,
        DecoupleXY = true, WallCheck = true, TeamCheck = true, SlowdownRing = 20.0, PullRingRadius = 75.0,
        MagneticAcceleration = 2.0, MagneticCorrection = 4.0, ShowFOVCircle = true, AimFOVRadius = 55.0,
        CustomFOV = false, FOVValue = 90.0, Prediction = true, BulletSpeed = 1600.0
    },
    SemiLegit = {
        AimTracking = true, MagneticAssist = true, MagneticLockRadius = 6.5, BaseSensitivity = 0.35,
        DecoupleXY = true, WallCheck = true, TeamCheck = true, SlowdownRing = 35.0, PullRingRadius = 130.0,
        MagneticAcceleration = 5.0, MagneticCorrection = -1.5, ShowFOVCircle = true, AimFOVRadius = 125.0,
        CustomFOV = false, FOVValue = 90.0, Prediction = true, BulletSpeed = 1100.0
    },
    Rage = {
        AimTracking = true, MagneticAssist = true, MagneticLockRadius = 24.0, BaseSensitivity = 2.2,
        DecoupleXY = false, WallCheck = false, TeamCheck = true, SlowdownRing = 70.0, PullRingRadius = 350.0,
        MagneticAcceleration = 18.0, MagneticCorrection = -6.0, ShowFOVCircle = true, AimFOVRadius = 400.0,
        CustomFOV = true, FOVValue = 115.0, Prediction = true, BulletSpeed = 2400.0
    }
}

local presetButtonsMap = {}

local function ApplyPresetProfile(selectedName)
    local profile = PresetProfiles[selectedName]
    if not profile then return end
    for featureName, value in pairs(profile) do
        UpdateFeature(featureName, value)
    end
    for name, button in pairs(presetButtonsMap) do
        if name == selectedName then
            TweenService:Create(button, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.15}):Play()
            TweenService:Create(button.TextLabel, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {TextColor3 = Color3.new(1,1,1)}):Play()
        else
            TweenService:Create(button, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {BackgroundColor3 = Theme.CardBg, BackgroundTransparency = Theme.CardTransparency}):Play()
            TweenService:Create(button.TextLabel, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {TextColor3 = Theme.TextMuted}):Play()
        end
    end
end

local function CreatePresetCircle(name, displayName)
    local Circle = Instance.new("TextButton", PresetButtonsFrame)
    Circle.Size = UDim2.new(0, 38, 0, 36)
    Circle.Text = ""
    Circle.BackgroundColor3 = Theme.CardBg
    Circle.BackgroundTransparency = Theme.CardTransparency
    Circle.Active = true
    Instance.new("UICorner", Circle).CornerRadius = UDim.new(0, 10)
    
    local stroke = Instance.new("UIStroke", Circle)
    stroke.Color = Theme.BorderColor
    stroke.Transparency = 0.88
    
    local label = Instance.new("TextLabel", Circle)
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Text = displayName
    label.TextColor3 = Theme.TextMuted
    label.Font = Enum.Font.GothamBold
    label.TextSize = 8
    label.BackgroundTransparency = 1
    
    presetButtonsMap[name] = Circle
    Circle.MouseButton1Click:Connect(function() ApplyPresetProfile(name) end)
end

CreatePresetCircle("Legit", "LEGIT")
CreatePresetCircle("SemiLegit", "SEMI")
CreatePresetCircle("Rage", "RAGE")

local ResetBtn = Instance.new("TextButton", LeftColumn)
ResetBtn.Name = "ResetSettingsButton"
ResetBtn.Size = UDim2.new(1, 0, 0, 26)
ResetBtn.BackgroundColor3 = Theme.CardBg
ResetBtn.BackgroundTransparency = Theme.CardTransparency
ResetBtn.Text = "Restaurar Padrões"
ResetBtn.TextColor3 = Theme.TextMuted
ResetBtn.Font = Enum.Font.GothamBold
ResetBtn.TextSize = 9.5
ResetBtn.LayoutOrder = 5
ResetBtn.Visible = false
ResetBtn.ClipsDescendants = true

Instance.new("UICorner", ResetBtn).CornerRadius = UDim.new(0, 8)
local resetStroke = Instance.new("UIStroke", ResetBtn)
resetStroke.Color = Theme.BorderColor
resetStroke.Transparency = 0.85
resetStroke.Thickness = 1.0

ResetBtn.MouseEnter:Connect(function()
    TweenService:Create(ResetBtn, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {BackgroundTransparency = 0.8, TextColor3 = Theme.TextWhite}):Play()
end)
ResetBtn.MouseLeave:Connect(function()
    TweenService:Create(ResetBtn, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {BackgroundTransparency = Theme.CardTransparency, TextColor3 = Theme.TextMuted}):Play()
end)

ResetBtn.MouseButton1Click:Connect(function()
    for featureName, defaultValue in pairs(DefaultConfig) do
        UpdateFeature(featureName, defaultValue)
    end
    for _, button in pairs(presetButtonsMap) do
        TweenService:Create(button, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {BackgroundColor3 = Theme.CardBg, BackgroundTransparency = Theme.CardTransparency}):Play()
        TweenService:Create(button.TextLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {TextColor3 = Theme.TextMuted}):Play()
    end
end)

local function CreateGridColumn(xOffset)
    local Scroller = Instance.new("ScrollingFrame", MainPanel)
    Scroller.Size = UDim2.new(0, 180, 1, -24)
    Scroller.Position = UDim2.new(0, xOffset, 0, 12)
    Scroller.BackgroundTransparency = 1
    Scroller.BorderSizePixel = 0
    Scroller.ScrollBarThickness = 2
    Scroller.ScrollBarImageColor3 = Theme.Accent
    Scroller.ScrollBarImageTransparency = 0.7
    Scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
    Scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y 
    Scroller.ClipsDescendants = true
    Scroller.Visible = false 
    
    local ColumnCard = Instance.new("Frame", Scroller)
    ColumnCard.Size = UDim2.new(1, -8, 0, 0)
    ColumnCard.BackgroundColor3 = Theme.ColumnBg
    ColumnCard.BackgroundTransparency = Theme.ColTransparency
    ColumnCard.BorderSizePixel = 0
    ColumnCard.AutomaticSize = Enum.AutomaticSize.Y
    Instance.new("UICorner", ColumnCard).CornerRadius = UDim.new(0, 14)
    
    local cStroke = Instance.new("UIStroke", ColumnCard)
    cStroke.Color = Theme.BorderColor
    cStroke.Transparency = 0.9
    
    local List = Instance.new("UIListLayout", ColumnCard)
    List.Padding = UDim.new(0, 8) 
    List.SortOrder = Enum.SortOrder.LayoutOrder
    
    local Pad = Instance.new("UIPadding", ColumnCard)
    Pad.PaddingTop = UDim.new(0, 12)
    Pad.PaddingBottom = UDim.new(0, 12)
    Pad.PaddingLeft = UDim.new(0, 10)
    Pad.PaddingRight = UDim.new(0, 10)
    
    return ColumnCard, Scroller
end

local CenterPane, CenterScroller = CreateGridColumn(165)
local RightPane, RightScroller = CreateGridColumn(360)

-- ====================================================================
-- SEÇÃO OWNER MODIFICADA: DESIGN FIEL AO PERFIL DO INSTAGRAM
-- ====================================================================
local OwnerContainer = Instance.new("Frame", MainPanel)
OwnerContainer.Size = UDim2.new(0, 365, 1, -24)
OwnerContainer.Position = UDim2.new(0, 165, 0, 12)
OwnerContainer.BackgroundTransparency = 1
OwnerContainer.Visible = false

-- 1. Retângulo do Instagram (Design de Cartão Superior Estilo Profile)
local InstagramCard = Instance.new("Frame", OwnerContainer)
InstagramCard.Size = UDim2.new(1, 0, 0, 120)
InstagramCard.Position = UDim2.new(0, 0, 0, 0)
InstagramCard.BackgroundColor3 = Theme.ColumnBg
InstagramCard.BackgroundTransparency = Theme.ColTransparency
Instance.new("UICorner", InstagramCard).CornerRadius = UDim.new(0, 14)

local instaStroke = Instance.new("UIStroke", InstagramCard)
instaStroke.Color = Theme.BorderColor
instaStroke.Transparency = 0.9

-- Anel do Insta Story (Borda Colorida com Degradê Oficial)
local ProfileRing = Instance.new("Frame", InstagramCard)
ProfileRing.Size = UDim2.new(0, 56, 0, 56)
ProfileRing.Position = UDim2.new(0, 16, 0, 16)
ProfileRing.BackgroundTransparency = 1
Instance.new("UICorner", ProfileRing).CornerRadius = UDim.new(1, 0)

local ringStroke = Instance.new("UIStroke", ProfileRing)
ringStroke.Thickness = 2
ringStroke.Color = Color3.fromRGB(255, 255, 255)

local ringGradient = Instance.new("UIGradient", ringStroke)
ringGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(251, 173, 80)),   -- Laranja/Amarelo
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(221, 42, 123)),  -- Rosa Insta
    ColorSequenceKeypoint.new(1, Color3.fromRGB(129, 52, 175))    -- Roxo Insta
})

-- Foto de Perfil Redonda (Alinhada perfeitamente dentro do anel)
local ProfilePic = Instance.new("ImageLabel", ProfileRing)
ProfilePic.Size = UDim2.new(0, 48, 0, 48)
ProfilePic.AnchorPoint = Vector2.new(0.5, 0.5)
ProfilePic.Position = UDim2.new(0.5, 0, 0.5, 0)
ProfilePic.BackgroundTransparency = 1
ProfilePic.ImageColor3 = Color3.fromRGB(255, 255, 255)
ProfilePic.Image = "rbxthumb://type=Asset&id=88591182072713&w=420&h=420" 
Instance.new("UICorner", ProfilePic).CornerRadius = UDim.new(1, 0)

-- Nome de Usuário Principal (Instagram Handle) - Centralizado perfeitamente com a foto
local DevUser = Instance.new("TextLabel", InstagramCard)
DevUser.Size = UDim2.new(1, -95, 0, 18)
DevUser.Position = UDim2.new(0, 84, 0, 35)
DevUser.Text = "fallenovermind"
DevUser.TextColor3 = Theme.TextWhite
DevUser.Font = Enum.Font.GothamBold
DevUser.TextSize = 13.5
DevUser.TextXAlignment = Enum.TextXAlignment.Left
DevUser.BackgroundTransparency = 1

-- Botão de Link Funcional Estilo Mac Blur Button (Texto em Branco e Fonte Ubuntu)
local LinkBtn = Instance.new("TextButton", InstagramCard)
LinkBtn.Size = UDim2.new(1, -32, 0, 30)
LinkBtn.Position = UDim2.new(0, 16, 1, -44)
LinkBtn.BackgroundColor3 = Theme.CardBg
LinkBtn.BackgroundTransparency = 0.92
LinkBtn.Text = "Copiar Link do Instagram"
LinkBtn.TextColor3 = Theme.TextWhite
LinkBtn.Font = Enum.Font.Ubuntu
LinkBtn.TextSize = 10
Instance.new("UICorner", LinkBtn).CornerRadius = UDim.new(0, 8)

local lnkStroke = Instance.new("UIStroke", LinkBtn)
lnkStroke.Color = Theme.BorderColor
lnkStroke.Transparency = 0.85

LinkBtn.MouseEnter:Connect(function()
    TweenService:Create(LinkBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {BackgroundTransparency = 0.85, TextColor3 = Theme.TextWhite}):Play()
end)
LinkBtn.MouseLeave:Connect(function()
    TweenService:Create(LinkBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {BackgroundTransparency = 0.92, TextColor3 = Theme.TextWhite}):Play()
end)

LinkBtn.MouseButton1Click:Connect(function()
    local url = "https://www.instagram.com/fallenovermind?igsh=MTdkNW40MHJwYnZvbA=="
    if setclipboard then
        setclipboard(url)
        LinkBtn.Text = "¡Link Copiado com Sucesso!"
        LinkBtn.TextColor3 = Color3.fromRGB(52, 199, 89) -- Verde nativo iOS
        task.delay(2, function()
            LinkBtn.Text = "Copiar Link do Instagram"
            LinkBtn.TextColor3 = Theme.TextWhite
        end)
    else
        LinkBtn.Text = "Erro: Executor não suporta cópia."
    end
end)

-- 2. Caixa do Usuário Executor (Abaixo e à esquerda)
local UserCard = Instance.new("Frame", OwnerContainer)
UserCard.Size = UDim2.new(0, 175, 0, 140)
UserCard.Position = UDim2.new(0, 0, 0, 135)
UserCard.BackgroundColor3 = Theme.ColumnBg
UserCard.BackgroundTransparency = Theme.ColTransparency
Instance.new("UICorner", UserCard).CornerRadius = UDim.new(0, 14)

local usrStroke = Instance.new("UIStroke", UserCard)
usrStroke.Color = Theme.BorderColor
usrStroke.Transparency = 0.9

-- Foto de Perfil Dinâmica do Usuário do Roblox
local UserAvatar = Instance.new("ImageLabel", UserCard)
UserAvatar.Size = UDim2.new(0, 36, 0, 36)
UserAvatar.Position = UDim2.new(0, 12, 0, 14)
UserAvatar.BackgroundColor3 = Theme.CardBg
UserAvatar.BackgroundTransparency = 0.95
UserAvatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=150&h=150"
Instance.new("UICorner", UserAvatar).CornerRadius = UDim.new(1, 0)

local avStroke = Instance.new("UIStroke", UserAvatar)
avStroke.Color = Theme.BorderColor
avStroke.Transparency = 0.8

-- Informações Básicas do Usuário
local UserLabel = Instance.new("TextLabel", UserCard)
UserLabel.Size = UDim2.new(1, -60, 0, 14)
UserLabel.Position = UDim2.new(0, 56, 0, 16)
UserLabel.Text = "EXECUTADO POR:"
UserLabel.TextColor3 = Theme.TextMuted
UserLabel.Font = Enum.Font.GothamBold
UserLabel.TextSize = 7.5
UserLabel.TextXAlignment = Enum.TextXAlignment.Left
UserLabel.BackgroundTransparency = 1

local Username = Instance.new("TextLabel", UserCard)
Username.Size = UDim2.new(1, -60, 0, 18)
Username.Position = UDim2.new(0, 56, 0, 28)
Username.Text = LocalPlayer.DisplayName
Username.TextColor3 = Theme.TextWhite
Username.Font = Enum.Font.GothamBold
Username.TextSize = 11
Username.TextXAlignment = Enum.TextXAlignment.Left
Username.TextTruncate = Enum.TextTruncate.AtEnd
Username.BackgroundTransparency = 1

-- Divisor interno estético
local CardDivider = Instance.new("Frame", UserCard)
CardDivider.Size = UDim2.new(1, -24, 0, 1)
CardDivider.Position = UDim2.new(0, 12, 0, 62)
CardDivider.BackgroundColor3 = Theme.DividerColor
CardDivider.BackgroundTransparency = 0.94
CardDivider.BorderSizePixel = 0

-- Metadados Inferiores
local function AddMetaData(parent, labelText, valText, yPos)
    local Lbl = Instance.new("TextLabel", parent)
    Lbl.Size = UDim2.new(0, 60, 0, 14)
    Lbl.Position = UDim2.new(0, 12, 0, yPos)
    Lbl.Text = labelText
    Lbl.TextColor3 = Theme.TextMuted
    Lbl.Font = Enum.Font.Gotham
    Lbl.TextSize = 8
    Lbl.TextXAlignment = Enum.TextXAlignment.Left
    Lbl.BackgroundTransparency = 1

    local Val = Instance.new("TextLabel", parent)
    Val.Size = UDim2.new(1, -76, 0, 14)
    Val.Position = UDim2.new(0, 72, 0, yPos)
    Val.Text = valText
    Val.TextColor3 = Theme.TextWhite
    Val.Font = Enum.Font.GothamBold
    Val.TextSize = 8
    Val.TextXAlignment = Enum.TextXAlignment.Right
    Val.BackgroundTransparency = 1
end

local dateString = os.date("%d/%m/%Y")
AddMetaData(UserCard, "Plano Ativo", "Premium", 74)
AddMetaData(UserCard, "Data Reg.", dateString, 92)
AddMetaData(UserCard, "Id Cliente", "v20-" .. tostring(LocalPlayer.UserId):sub(1,4), 110)

-- ====================================================================

local activeTab = "AimAssist"
local animInfo = TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

local function SwitchTab(tabName)
    activeTab = tabName
    if activeTab == "AimAssist" then
        TweenService:Create(MainPanel, animInfo, {Size = UDim2.new(0, 550, 0, 320)}):Play()
        TweenService:Create(NavHeader1, animInfo, {Size = UDim2.new(0, 95, 0, 28), BackgroundTransparency = 0.8}):Play()
        TweenService:Create(NavText1, animInfo, {TextTransparency = 0}):Play()
        TweenService:Create(NavHeader2, animInfo, {Size = UDim2.new(0, 28, 0, 28), BackgroundTransparency = Theme.CardTransparency}):Play()
        TweenService:Create(NavText2, animInfo, {TextTransparency = 1}):Play()
        
        Card1.Visible = true; Card2.Visible = true; PresetContainer.Visible = true; ResetBtn.Visible = true
        CenterScroller.Visible = true; RightScroller.Visible = true
        OwnerContainer.Visible = false
        
        TweenService:Create(Card1, animInfo, {Size = UDim2.new(1, 0, 0, 75)}):Play()
        TweenService:Create(Card2, animInfo, {Size = UDim2.new(1, 0, 0, 75)}):Play()
        TweenService:Create(PresetContainer, animInfo, {Size = UDim2.new(1, 0, 0, 60)}):Play()
        TweenService:Create(ResetBtn, animInfo, {Size = UDim2.new(1, 0, 0, 26)}):Play()
    elseif activeTab == "Owner" then
        TweenService:Create(MainPanel, animInfo, {Size = UDim2.new(0, 550, 0, 320)}):Play()
        TweenService:Create(NavHeader1, animInfo, {Size = UDim2.new(0, 28, 0, 28), BackgroundTransparency = Theme.CardTransparency}):Play()
        TweenService:Create(NavText1, animInfo, {TextTransparency = 1}):Play()
        TweenService:Create(NavHeader2, animInfo, {Size = UDim2.new(0, 75, 0, 28), BackgroundTransparency = 0.8}):Play()
        TweenService:Create(NavText2, animInfo, {TextTransparency = 0}):Play()
        
        TweenService:Create(Card1, animInfo, {Size = UDim2.new(1, 0, 0, 0)}):Play()
        TweenService:Create(Card2, animInfo, {Size = UDim2.new(1, 0, 0, 0)}):Play()
        TweenService:Create(PresetContainer, animInfo, {Size = UDim2.new(1, 0, 0, 0)}):Play()
        TweenService:Create(ResetBtn, animInfo, {Size = UDim2.new(1, 0, 0, 0)}):Play()
        
        OwnerContainer.Visible = true
        
        task.delay(0.35, function()
            if activeTab == "Owner" then
                Card1.Visible = false; Card2.Visible = false; PresetContainer.Visible = false; ResetBtn.Visible = false
                CenterScroller.Visible = false; RightScroller.Visible = false
            end
        end)
    end
end

NavLabel1.MouseButton1Click:Connect(function() SwitchTab("AimAssist") end)
NavLabel2.MouseButton1Click:Connect(function() SwitchTab("Owner") end)

-- Elementos de Toggles e Filtros Fluídos (Estilo Apple System Preferences)
local function AddMenuToggle(parent, titleText, descText, target)
    local RowFrame = Instance.new("Frame")
    RowFrame.Size = UDim2.new(1, 0, 0, 46) 
    RowFrame.BackgroundTransparency = 1
    
    local Label = Instance.new("TextLabel", RowFrame)
    Label.Size = UDim2.new(1, -45, 0, 14)
    Label.Position = UDim2.new(0, 4, 0, 4)
    Label.Text = titleText
    Label.TextColor3 = Theme.TextWhite
    Label.Font = Enum.Font.GothamBold
    Label.TextSize = 9.5
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.BackgroundTransparency = 1
    
    local Sub = Instance.new("TextLabel", RowFrame)
    Sub.Size = UDim2.new(1, -45, 0, 22)
    Sub.Position = UDim2.new(0, 4, 0, 18)
    Sub.Text = descText
    Sub.TextColor3 = Theme.TextMuted
    Sub.Font = Enum.Font.Gotham
    Sub.TextSize = 7.5
    Sub.TextXAlignment = Enum.TextXAlignment.Left
    Sub.TextWrapped = true
    Sub.BackgroundTransparency = 1
    
    local Switch = Instance.new("TextButton", RowFrame)
    Switch.Size = UDim2.new(0, 32, 0, 18)
    Switch.Position = UDim2.new(1, -34, 0, 14)
    Switch.Text = ""
    Instance.new("UICorner", Switch).CornerRadius = UDim.new(1, 0)
    
    local swSt = Instance.new("UIStroke", Switch)
    swSt.Color = Color3.fromRGB(255, 255, 255)
    swSt.Transparency = 0.9
    
    local Knob = Instance.new("Frame", Switch)
    Knob.Size = UDim2.new(0, 14, 0, 14)
    Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)
    
    local Divider = Instance.new("Frame", RowFrame)
    Divider.Size = UDim2.new(1, -8, 0, 1)
    Divider.Position = UDim2.new(0, 4, 1, -1)
    Divider.BackgroundColor3 = Theme.DividerColor
    Divider.BackgroundTransparency = 0.95
    Divider.BorderSizePixel = 0
    
    local function Refresh()
        local enabled = Config[target]
        local targetColor = enabled and Theme.Accent or Color3.fromRGB(60, 60, 65)
        local targetTrans = enabled and 0.1 or 0.4
        local targetPos = enabled and UDim2.new(1, -16, 0, 2) or UDim2.new(0, 2, 0, 2)
        local knobColor = Color3.new(1, 1, 1)
        
        TweenService:Create(Switch, TweenInfo.new(0.25, Enum.EasingStyle.Cubic), {BackgroundColor3 = targetColor, BackgroundTransparency = targetTrans}):Play()
        TweenService:Create(Knob, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = targetPos, BackgroundColor3 = knobColor}):Play()
    end
    
    Switch.MouseButton1Click:Connect(function() UpdateFeature(target, not Config[target]) end)
    RegisterUpdate(target, Refresh)
    Refresh()
    
    RowFrame.Parent = parent
end

-- Sliders Fluídos de Vidro Lapidado
local function AddMenuSlider(parent, titleText, descText, min, max, target)
    local RowFrame = Instance.new("Frame")
    RowFrame.Size = UDim2.new(1, 0, 0, 64) 
    RowFrame.BackgroundTransparency = 1
    
    local Label = Instance.new("TextLabel", RowFrame)
    Label.Size = UDim2.new(1, -42, 0, 14)
    Label.Position = UDim2.new(0, 4, 0, 4)
    Label.Text = titleText
    Label.TextColor3 = Theme.TextWhite
    Label.Font = Enum.Font.GothamBold
    Label.TextSize = 9.5
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.BackgroundTransparency = 1
    
    local Sub = Instance.new("TextLabel", RowFrame)
    Sub.Size = UDim2.new(1, -42, 0, 22)
    Sub.Position = UDim2.new(0, 4, 0, 18)
    Sub.Text = descText
    Sub.TextColor3 = Theme.TextMuted
    Sub.Font = Enum.Font.Gotham
    Sub.TextSize = 7.5
    Sub.TextXAlignment = Enum.TextXAlignment.Left
    Sub.TextWrapped = true
    Sub.BackgroundTransparency = 1
    
    local ValLabel = Instance.new("TextLabel", RowFrame)
    ValLabel.Size = UDim2.new(0, 36, 0, 14)
    ValLabel.Position = UDim2.new(1, -40, 0, 4)
    ValLabel.TextColor3 = Theme.Accent
    ValLabel.Font = Enum.Font.GothamBold
    ValLabel.TextSize = 9.5
    ValLabel.TextXAlignment = Enum.TextXAlignment.Right
    ValLabel.BackgroundTransparency = 1
    
    local Track = Instance.new("TextButton", RowFrame)
    Track.Size = UDim2.new(1, -8, 0, 4)
    Track.Position = UDim2.new(0, 4, 0, 48)
    Track.BackgroundColor3 = Theme.TrackDark
    Track.BackgroundTransparency = 0.7
    Track.Text = ""
    Instance.new("UICorner", Track).CornerRadius = UDim.new(1, 0)
    
    local Fill = Instance.new("Frame", Track)
    Fill.BackgroundColor3 = Theme.Accent
    Fill.BackgroundTransparency = 0.1
    Fill.Size = UDim2.new(0, 0, 1, 0)
    Instance.new("UICorner", Fill).CornerRadius = UDim.new(1, 0)
    
    local Knob = Instance.new("Frame", Track)
    Knob.Size = UDim2.new(0, 10, 0, 10)
    Knob.AnchorPoint = Vector2.new(0.5, 0.5)
    Knob.BackgroundColor3 = Color3.new(1, 1, 1)
    Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)
    
    local knSt = Instance.new("UIStroke", Knob)
    knSt.Color = Color3.fromRGB(0,0,0)
    knSt.Transparency = 0.85
    
    local Divider = Instance.new("Frame", RowFrame)
    Divider.Size = UDim2.new(1, -8, 0, 1)
    Divider.Position = UDim2.new(0, 4, 1, -1)
    Divider.BackgroundColor3 = Theme.DividerColor
    Divider.BackgroundTransparency = 0.95
    Divider.BorderSizePixel = 0
    
    local focusTweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local glideTweenInfo = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    
    local function GetVisualPositions(scale, currentWidth)
        local width = (currentWidth > 0) and currentWidth or 162
        local minX = 0; local maxX = width
        local knobX = minX + (maxX - minX) * scale
        return UDim2.new(0, knobX, 0.5, 0), UDim2.new(0, math.clamp(knobX, 0, width), 1, 0)
    end
    
    local active = false
    local function update(input)
        local scale = math.clamp((input.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
        local val = math.round((min + (max - min) * scale) * 10) / 10
        Config[target] = val
        
        local kPos, fSize = GetVisualPositions(scale, Track.AbsoluteSize.X)
        TweenService:Create(Knob, glideTweenInfo, {Position = kPos}):Play()
        TweenService:Create(Fill, glideTweenInfo, {Size = fSize}):Play()
        ValLabel.Text = string.format("%.1f", val)
    end
    
    Track.InputBegan:Connect(function(input) 
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
            active = true
            TweenService:Create(Knob, focusTweenInfo, {Size = UDim2.new(0, 13, 0, 13)}):Play()
            update(input) 
        end 
    end)
    UserInputService.InputChanged:Connect(function(input) if active and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then update(input) end end)
    
    UserInputService.InputEnded:Connect(function(input) 
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
            active = false 
            TweenService:Create(Knob, focusTweenInfo, {Size = UDim2.new(0, 10, 0, 10)}):Play()
        end 
    end)
    
    local function refreshVisuals()
        local scale = math.clamp((Config[target] - min) / (max - min), 0, 1)
        local kPos, fSize = GetVisualPositions(scale, Track.AbsoluteSize.X)
        Knob.Position = kPos; Fill.Size = fSize
        ValLabel.Text = string.format("%.1f", Config[target])
    end
    
    Track:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshVisuals)
    RegisterUpdate(target, refreshVisuals)
    refreshVisuals()
    
    RowFrame.Parent = parent
end

AddMenuSlider(CenterPane, "Raio de Trava (Lock)", "Tamanho do círculo vermelho interno onde a mira fixa totalmente no inimigo.", 0.5, 30.0, "MagneticLockRadius")
AddMenuSlider(CenterPane, "Sensibilidade Base", "Ajusta a velocidade geral e a agilidade física de resposta do movimento de câmera.", 0.1, 3.0, "BaseSensitivity")
AddMenuToggle(CenterPane, "Desacoplar Eixos X/Y", "Separa os eixos horizontal e vertical para suavizar e eliminar travamentos.", "DecoupleXY")
AddMenuToggle(CenterPane, "Checagem de Parede", "Evita que o system puxe a mira em adversários escondidos atrás de construções.", "WallCheck")
AddMenuToggle(CenterPane, "Filtro de Equipe", "Ignora companheiros de equipe, focando exclusivamente nos oponentes.", "TeamCheck")

AddMenuToggle(RightPane, "Predição de Movimento", "Calcula a velocidade vetorial do alvo para antecipar a mira em inimigos correndo.", "Prediction")
AddMenuSlider(RightPane, "Intensidade da Predição", "Fator de avanço de mira. Menores valores = Maior antecipação à frente do alvo.", 200.0, 3000.0, "BulletSpeed")
AddMenuSlider(RightPane, "Anel de Redução", "Área do círculo amarelo que desacelera a velocidade da mira ao chegar perto do alvo.", 5.0, 150.0, "SlowdownRing")
AddMenuSlider(RightPane, "Anel de Atração", "Distância limite máxima tridimensional no mapa para o magnetismo começar a agir.", 10.0, 500.0, "PullRingRadius")
AddMenuSlider(RightPane, "Força Magnética", "Multiplicador de aceleração de puxada gerado ao entrar na zona de alcance.", 0.5, 20.0, "MagneticAcceleration")
AddMenuSlider(RightPane, "Correção de Fricção", "Amortece o balanço interno para estabilizar os eixos e remover tremores.", -10.0, 10.0, "MagneticCorrection")
AddMenuToggle(RightPane, "Exibir Círculo FOV", "Renderiza a linha circular central de segurança na tela.", "ShowFOVCircle")
AddMenuSlider(RightPane, "Limite do FOV 2D", "Tamanho do círculo cinza na tela que determina onde os alvos podem ser calculados.", 10.0, 450.0, "AimFOVRadius")
AddMenuToggle(RightPane, "Substituir FOV", "Permite que o painel force uma abertura de câmera customizada.", "CustomFOV")
AddMenuSlider(RightPane, "Valor do FOV Angular", "Modifica diretamente o campo de visão (Field of View) nativo do jogo.", 30.0, 120.0, "FOVValue")

local dragToggle, dragStart, startPos = false, nil, nil
MenuButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragToggle = true; dragStart = input.Position; startPos = MenuButton.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragToggle and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        MenuButton.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragToggle = false end
end)

MenuButton.MouseButton1Click:Connect(function() 
    MainPanel.Visible = not MainPanel.Visible 
    if MainPanel.Visible then SwitchTab(activeTab) end
end)

-- ====================================================================
-- MAGNET ENGINE + PHYSICAL PREDICTION VECTOR SYSTEM
-- ====================================================================
task.spawn(function()
    local ENV = (getgenv and getgenv()) or _G
    if ENV.MagnetConnections then
        for _, conn in ipairs(ENV.MagnetConnections) do pcall(function() conn:Disconnect() end) end
    end
    ENV.MagnetConnections = {}
    
    local RingPool = {}
    
    local function ClearPlayerRings(player)
        if RingPool[player] then
            pcall(function() RingPool[player].PullGui:Destroy() end)
            pcall(function() RingPool[player].SlowGui:Destroy() end)
            pcall(function() RingPool[player].LockGui:Destroy() end)
            RingPool[player] = nil
        end
    end

    local function GetCharacterRings(player)
        if RingPool[player] then return RingPool[player] end
        
        local function CreateHudRing(name, color)
            local bbgui = Instance.new("BillboardGui")
            bbgui.Name = "MagnetRing_" .. name .. "_" .. player.Name
            bbgui.AlwaysOnTop = true; bbgui.ResetOnSpawn = false
            bbgui.Enabled = false; bbgui.Parent = RingsFolder

            local frame = Instance.new("Frame", bbgui)
            frame.Size = UDim2.new(1, 0, 1, 0); frame.AnchorPoint = Vector2.new(0.5, 0.5)
            frame.Position = UDim2.new(0.5, 0, 0.5, 0); frame.BackgroundTransparency = 1
            
            Instance.new("UICorner", frame).CornerRadius = UDim.new(1, 0)
            local stroke = Instance.new("UIStroke", frame)
            stroke.Color = color; stroke.Thickness = 1.2
            return bbgui, frame
        end
        
        local pullGui = CreateHudRing("Pull", Theme.Accent)                      
        local slowGui = CreateHudRing("Slow", Color3.fromRGB(255, 180, 0))       
        local lockGui = CreateHudRing("Lock", Color3.fromRGB(255, 60, 100))      
        
        RingPool[player] = { PullGui = pullGui, SlowGui = slowGui, LockGui = lockGui }
        return RingPool[player]
    end

    table.insert(ENV.MagnetConnections, Players.PlayerRemoving:Connect(ClearPlayerRings))
    for _, p in ipairs(Players:GetPlayers()) do
        table.insert(ENV.MagnetConnections, p.CharacterAdded:Connect(function() ClearPlayerRings(p) end))
    end
    table.insert(ENV.MagnetConnections, Players.PlayerAdded:Connect(function(p)
        table.insert(ENV.MagnetConnections, p.CharacterAdded:Connect(function() ClearPlayerRings(p) end))
    end))

    local function IsValidTarget(player)
        if not player or player == LocalPlayer or not player.Character then return false end
        if Config.TeamCheck and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then return false end
        local head = player.Character:FindFirstChild("Head")
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if not head or not humanoid or humanoid.Health <= 0 then return false end
        
        if Config.WallCheck then
            local cam = GetCurrentCamera()
            if not cam then return false end
            local ignoreList = {LocalPlayer.Character, player.Character, cam}
            local obscuringParts = cam:GetPartsObscuringTarget({head.Position}, ignoreList)
            for _, part in ipairs(obscuringParts) do
                if part.Transparency < 0.75 and part.CanCollide then return false end
            end
        end
        return true
    end

    local function DisableRings(rings)
        rings.PullGui.Enabled = false; rings.SlowGui.Enabled = false; rings.LockGui.Enabled = false
    end

    local function GetScreenDiameterOfRadius(radiusInStuds, distance3D, cam)
        local fovRad = math.rad(cam.FieldOfView / 2)
        local screenHeightAtDist = 2 * distance3D * math.tan(fovRad)
        if screenHeightAtDist <= 0 then return 0 end
        return ((radiusInStuds * 2) * cam.ViewportSize.Y) / screenHeightAtDist
    end

    local runConnection = RunService.PreRender:Connect(function(deltaTime)
        local cam = GetCurrentCamera()
        if not cam then return end
        
        if Config.CustomFOV then cam.FieldOfView = Config.FOVValue else cam.FieldOfView = _G.OriginalFOV or 70 end

        VisualFOVCircle.Visible = Config.ShowFOVCircle
        local fovDiameter = Config.AimFOVRadius * 2
        VisualFOVCircle.Size = UDim2.new(0, fovDiameter, 0, fovDiameter)

        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        local closestTarget = nil; local shortestDist2D = Config.AimFOVRadius

        for _, player in ipairs(Players:GetPlayers()) do
            local rings = GetCharacterRings(player)
            local valid = IsValidTarget(player)
            
            if valid and player.Character then
                local targetRoot = player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Head")
                local targetHead = player.Character:FindFirstChild("Head")
                
                if targetRoot and targetHead then
                    local distance3D = (targetHead.Position - (myRoot and myRoot.Position or cam.CFrame.Position)).Magnitude
                    local screenPos, onScreen = cam:WorldToViewportPoint(targetHead.Position)
                    
                    if onScreen then
                        local screenCenter = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
                        local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                        if dist2D <= Config.AimFOVRadius and dist2D < shortestDist2D then
                            shortestDist2D = dist2D; closestTarget = targetHead
                        end
                    end
                    
                    if Config.MagneticAssist and onScreen then
                        rings.PullGui.Adornee = targetRoot; rings.SlowGui.Adornee = targetRoot; rings.LockGui.Adornee = targetHead  
                        rings.PullGui.Enabled = true; rings.SlowGui.Enabled = true; rings.LockGui.Enabled = true
                        
                        local pxLock = math.clamp(GetScreenDiameterOfRadius(1.4, distance3D, cam), 4, 120)  
                        local pxSlow = math.clamp(GetScreenDiameterOfRadius(3.2, distance3D, cam), 10, 250) 
                        local pxPull = math.clamp(GetScreenDiameterOfRadius(5.8, distance3D, cam), 16, 450) 
                        
                        rings.LockGui.Size = UDim2.new(0, pxLock, 0, pxLock)
                        rings.SlowGui.Size = UDim2.new(0, pxSlow, 0, pxSlow)
                        rings.PullGui.Size = UDim2.new(0, pxPull, 0, pxPull)
                    else
                        DisableRings(rings)
                    end
                else
                    DisableRings(rings)
                end
            else
                if rings then DisableRings(rings) end
            end
        end

        if Config.AimTracking and closestTarget and myRoot then
            local distance3D = (closestTarget.Position - myRoot.Position).Magnitude
            local forceFactor = 1.0
            
            if distance3D <= Config.MagneticLockRadius then
                forceFactor = (Config.MagneticCorrection + 16) * Config.BaseSensitivity
            elseif distance3D <= Config.SlowdownRing then
                forceFactor = (Config.MagneticAcceleration / 20) * (distance3D / Config.SlowdownRing) * Config.BaseSensitivity
            else
                forceFactor = (Config.MagneticAcceleration / 50) * Config.BaseSensitivity
            end
            
            local finalAimPosition = closestTarget.Position
            if Config.Prediction then
                local enemyChar = closestTarget.Parent
                local enemyRoot = enemyChar and enemyChar:FindFirstChild("HumanoidRootPart")
                if enemyRoot then
                    local targetVelocity = enemyRoot.AssemblyLinearVelocity or enemyRoot.Velocity or Vector3.new(0,0,0)
                    local timeToTarget = distance3D / math.max(Config.BulletSpeed, 1)
                    finalAimPosition = closestTarget.Position + (targetVelocity * timeToTarget)
                end
            end
            
            local targetCFrame = CFrame.new(cam.CFrame.Position, finalAimPosition)
            local finalAlpha = math.clamp(forceFactor * deltaTime * 14, 0.001, 0.99)
            
            if Config.DecoupleXY then
                local currentY, currentX = cam.CFrame:ToEulerAnglesYXZ()
                local targetY, targetX = targetCFrame:ToEulerAnglesYXZ()
                local deltaY = math.atan2(math.sin(targetY - currentY), math.cos(targetY - currentY))
                local deltaX = math.atan2(math.sin(targetX - currentX), math.cos(targetX - currentX))
                cam.CFrame = CFrame.new(cam.CFrame.Position) * CFrame.fromEulerAnglesYXZ(currentY + deltaY * finalAlpha, currentX + deltaX * finalAlpha, 0)
            else
                cam.CFrame = cam.CFrame:Lerp(targetCFrame, finalAlpha)
            end
        end
    end)
    table.insert(ENV.MagnetConnections, runConnection)
end)
