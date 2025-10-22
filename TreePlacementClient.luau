-- Credits: Me (nrhneghqrg52)

--[[ 
    Tree Placement System Demo (Client Side)
    ----------------------------------------
    This client script handles the logic for placing trees in the demo game. 
    It manages both PC and Mobile placement systems, ghost previews, rotation, 
    UI toggles, and communicates placement actions to the server via RemoteEvents.
]]

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage") -- Access shared storage
local remotes = replicatedStorage.Remotes -- Folder containing RemoteEvents
local UserInputService = game:GetService("UserInputService") -- Detects user input
local runService = game:GetService("RunService") -- Provides RenderStepped for frame updates
local Players = game:GetService("Players") -- Access player-related data
local player = Players.LocalPlayer -- Reference to the local player
local tweenService = game:GetService("TweenService") -- For smooth UI/ghost transitions
local starterGui = player:WaitForChild("PlayerGui") -- Player's GUI
local Helpers = require(script:WaitForChild("Helper Functions")) -- Require helper module

--// Remote Event for placing a tree
local placeTreeEvent = remotes.PlaceTree

--// UI and game variables
local PlaceBTN : TextButton = starterGui:WaitForChild("PlacementUI"):WaitForChild("Place Tree"):WaitForChild("Place Tree BTN")
local treeModels : Folder = replicatedStorage:WaitForChild("TreeModels")
local activePlantMode = false -- Indicates whether player is in planting mode
local currentGhost = nil -- Ghost tree model reference
local isPlacing = false -- Used to prevent overlapping placement attempts
local SELECTED_TREE = nil -- Currently selected tree type (unused but reserved)
local cam = workspace.CurrentCamera -- Reference to active camera
local activeConnections = {} -- Stores all temporary connections for cleanup

--// UI references for Mobile Placement
local Arrows = starterGui:WaitForChild("PlacementUI"):WaitForChild("Mobile Placement"):WaitForChild("Arrows")
local UpBtn : ImageButton = Arrows:WaitForChild("Frame"):WaitForChild("Up")
local DownBtn : ImageButton = Arrows:WaitForChild("Frame"):WaitForChild("Down")
local RightBtn : ImageButton = Arrows:WaitForChild("Frame"):WaitForChild("Right")
local LeftBtn : ImageButton = Arrows:WaitForChild("Frame"):WaitForChild("Left")
local Confirm : TextButton = Arrows:WaitForChild("Confirm")
local Cancel : TextButton  = Arrows:WaitForChild("Cancel")

--// UI references for PC Placement
local PCFrame : Frame = starterGui:WaitForChild("PlacementUI"):WaitForChild("PC Placement"):WaitForChild("Frame")
local TreeControls = PCFrame:WaitForChild("Tree Controls").UI

--// Mobile-specific variables
local mobileGhost = nil
local mobilePlotPosition = nil -- Current selected plot position (Vector2)
local mobileIsland = nil -- Island the player is on
local mobilePlotsByPos = {} -- Maps Vector2 -> PlotPart
local mobileRotY = 0 -- Current rotation of the tree
local ControlsFrameOpen = false
local ArrowsTable = {UpBtn, DownBtn, RightBtn, LeftBtn} -- Cached for convenience

--// Detect platform (returns OnMobile, OnPc)
local OnMobile, OnPc = Helpers.Init()

---------------------------------------------------------
--// PC FUNCTIONS SECTION
---------------------------------------------------------

-- Cleans up all placement-related data and event connections
local function cleanUpPC(Bool : string)
    if Bool == "Start" then
        for _, conn in ipairs(activeConnections) do conn:Disconnect() end
        activeConnections = {}
    end

    if Bool == "End" then
        if currentGhost then currentGhost:Destroy() end
        isPlacing = false
        currentGhost = nil
        Helpers.ToggleOtherPlantModeUI(PlaceBTN, false)

        for _, conn in ipairs(activeConnections) do conn:Disconnect() end
        activeConnections = {}
    end
end

-- Starts the PC placement mode
local function startPCPlantMode(TreeName)
    -- Cleanup any ongoing placement
    if isPlacing then
        if currentGhost then currentGhost:Destroy() end
        cleanUpPC("Start")
    end

    local first = true
    isPlacing = true
    Helpers.ToggleOtherPlantModeUI(PlaceBTN, true)
    Helpers.ToggleControlsUI(TreeControls, true)

    local cachedTarget : Part
    local ghostTree: Model = treeModels:FindFirstChild(TreeName):Clone() -- Clone tree model for preview
    ghostTree.PromptPart:FindFirstChildOfClass("ProximityPrompt"):Destroy() -- Remove prompt to prevent interaction
    currentGhost = ghostTree

    -- Store original color/materials for visual reset
    local partOriginals = {}
    for _, part in ipairs(ghostTree:GetDescendants()) do
        if part:IsA("BasePart") then
            partOriginals[part] = { Color = part.Color, Material = part.Material }
            part.Transparency = 0.5
            part.CanCollide = false
        end
    end

    ghostTree.Parent = workspace:FindFirstChild("GhostTrees")

    local rotY = 0
    local mouse = player:GetMouse()

    -- Input detection for rotation and cancel
    table.insert(activeConnections, UserInputService.InputBegan:Connect(function(key, gp)
        if gp then return end
        if key.KeyCode == Enum.KeyCode.Q then rotY -= 90 end
        if key.KeyCode == Enum.KeyCode.E then rotY += 90 end
        if key.KeyCode == Enum.KeyCode.C then
            cleanUpPC("End")
            Helpers.ToggleControlsUI(TreeControls, false)
        end
    end))

    local currentCFrame = ghostTree.PrimaryPart.CFrame
    local targetCFrame = currentCFrame

    -- Render loop for ghost movement and placement
    table.insert(activeConnections, runService.RenderStepped:Connect(function()
        local hit = mouse.Hit
        if not hit then return end

        local selectionThreshold = 0.05 -- prevents flickering between plots
        local target
        local bestDist = math.huge
        local ClosestIsland = Helpers.checkClosestIsland(hit.Position)

        -- Loop through all plots in the island and find the closest one
        for _, plot in ipairs(ClosestIsland.MainGrid:GetDescendants()) do
            if plot:IsA("BasePart") and not (plot.Parent.Name == "Arrow") then
                local dist = (hit.Position - plot.Position).Magnitude

                if not target or dist < bestDist then
                    bestDist = dist
                    target = plot
                end
            end
        end

        if not target then return end
        cachedTarget = target

        targetCFrame = target.CFrame * CFrame.Angles(0, math.rad(rotY), 0)

        -- Smoothly move ghost tree to the target
        if first then
            ghostTree:PivotTo(targetCFrame)
            currentCFrame = targetCFrame
            first = false
        else
            local alpha = 0.20
            currentCFrame = currentCFrame:Lerp(targetCFrame, alpha)
            ghostTree.PrimaryPart.CFrame = currentCFrame

            -- Change ghost color if plot is occupied
            local occupied = target:GetAttribute("Occupied")
            for part, original in pairs(partOriginals) do
                if occupied then
                    part.Color = Color3.fromRGB(255, 80, 80)
                    part.Material = Enum.Material.ForceField
                    part.Transparency = 0.3
                else
                    part.Color = original.Color
                    part.Material = original.Material
                    part.Transparency = 0.5
                end
            end
        end
    end))

    -- Left click to confirm placement
    table.insert(activeConnections, mouse.Button1Down:Connect(function()
        if not cachedTarget then return end
        local IslandName = cachedTarget.Parent.Parent.Parent.Name
        if not cachedTarget:GetAttribute("Occupied") then
            placeTreeEvent:FireServer(cachedTarget.Name, TreeName, rotY, IslandName)
            cleanUpPC("End")
            Helpers.ToggleControlsUI(TreeControls, false)
        else
            print("Cannot place tree because plot is already occupied")
        end
    end))
end

---------------------------------------------------------
--// MOBILE FUNCTIONS SECTION
---------------------------------------------------------

-- Updates which arrows are visible based on ghost's position
local function updateArrowVisibilitys(ghostTree: Model)
    local slotName = ghostTree:GetAttribute("Slot")
    if typeof(slotName) ~= "string" then return end

    local letter = string.sub(slotName, 1, 1)
    local number = tonumber(string.sub(slotName, 3))

    if not letter or not number then return end

    RightBtn.Visible = (letter ~= "A")
    LeftBtn.Visible = (letter ~= "F")
    UpBtn.Visible = (number ~= 1)
    DownBtn.Visible = (number ~= 6)
end

-- Cleans up all mobile placement data
local function cleanUpMobile(Bool : string)
    if Bool == "Start" then
        for _, conn in ipairs(activeConnections) do conn:Disconnect() end
        activeConnections = {}
    end

    if Bool == "End" then
        if mobileGhost then mobileGhost:Destroy() end
        isPlacing = false
        mobileGhost = nil
        PlaceBTN.Visible = true
        Confirm.Visible = false
        Cancel.Visible = false

        for _, conn in ipairs(activeConnections) do conn:Disconnect() end
        activeConnections = {}

        Helpers.TurnMobileArrowsOn_Off("Off", ArrowsTable)
        if cam.CameraType == Enum.CameraType.Scriptable then
            cam.CameraType = Enum.CameraType.Custom
        end
    end
end

-- Starts mobile placement mode
function startMobilePlantMode(treeName)
    cleanUpMobile("Start")

    isPlacing = true
    PlaceBTN.Visible = false
    Confirm.Visible = true
    Cancel.Visible = true
    Helpers.TurnMobileArrowsOn_Off("On", ArrowsTable)

    -- Detect player's island based on position
    local char: Model = player.Character
    if not char then return end
    local hrp: Part? = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    mobileIsland = Helpers.checkClosestIsland(hrp.Position)
    if not mobileIsland then return end

    -- Set up camera to focus on island
    local camPart = mobileIsland:FindFirstChild("CameraPart")
    if camPart then
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = camPart.CFrame
    end

    -- Collect all available plots
    mobilePlotsByPos = {}
    for _, plot in ipairs(mobileIsland.MainGrid:GetDescendants()) do
        if plot:IsA("BasePart") and not plot:GetAttribute("Occupied") then
            local vec = Helpers.plotNameToVector2(plot.Name)
            if vec then
                mobilePlotsByPos[Helpers.vector2Key(vec)] = plot
            end
        end
    end

    -- Find the closest available plot
    local bestDist = math.huge
    for key, part in pairs(mobilePlotsByPos) do
        local dist = (hrp.Position - part.Position).Magnitude
        if dist < bestDist then
            bestDist = dist
            mobilePlotPosition = Helpers.keyToVector2(key)
        end
    end

    -- Clone ghost model
    mobileGhost = treeModels:FindFirstChild(treeName):Clone()
    mobileGhost.PromptPart:FindFirstChildOfClass("ProximityPrompt"):Destroy()
    mobileGhost.Parent = workspace.GhostTrees
    for _, p in ipairs(mobileGhost:GetDescendants()) do
        if p:IsA("BasePart") then
            p.Transparency = 0.5
            p.CanCollide = false
        end
    end

    mobileRotY = 0
    mobileGhost:SetAttribute("Slot", mobilePlotsByPos[Helpers.vector2Key(mobilePlotPosition)].Name)
    updateArrowVisibilitys(mobileGhost)
    Helpers.updateMobileGhost(mobileGhost, mobilePlotsByPos, mobilePlotPosition, mobileRotY)

    -- Handle arrow button inputs
    local function moveGhost(dir: Vector2)
        local tempPos = mobilePlotPosition + dir
        local key = Helpers.vector2Key(tempPos)

        if mobilePlotsByPos[key] then
            local success = Helpers.updateMobileGhost(mobileGhost, mobilePlotsByPos, tempPos, mobileRotY)
            if success then
                mobilePlotPosition = tempPos
                mobileGhost:SetAttribute("Slot", mobilePlotsByPos[Helpers.vector2Key(mobilePlotPosition)].Name)
                updateArrowVisibilitys(mobileGhost)
            end
        end
    end

    table.insert(activeConnections, UpBtn.MouseButton1Click:Connect(function() moveGhost(Vector2.new(-1, 0)) end))
    table.insert(activeConnections, DownBtn.MouseButton1Click:Connect(function() moveGhost(Vector2.new(1, 0)) end))
    table.insert(activeConnections, RightBtn.MouseButton1Click:Connect(function() moveGhost(Vector2.new(0, -1)) end))
    table.insert(activeConnections, LeftBtn.MouseButton1Click:Connect(function() moveGhost(Vector2.new(0, 1)) end))

    -- Confirm and cancel buttons
    table.insert(activeConnections, Confirm.MouseButton1Click:Connect(function()
        local key = Helpers.vector2Key(mobilePlotPosition)
        local plot = mobilePlotsByPos[key]
        if not plot or plot:GetAttribute("Occupied") then return end

        local islandName = mobileIsland.Name
        local plotName = Helpers.vector2ToPlotName(mobilePlotPosition)
        placeTreeEvent:FireServer(plotName, treeName, mobileRotY, islandName)
        cleanUpMobile("End")
    end))

    table.insert(activeConnections, Cancel.MouseButton1Click:Connect(function()
        cleanUpMobile("End")
    end))
end

---------------------------------------------------------
--// CONNECTIONS
---------------------------------------------------------

-- Handles placement button click (entry point)
PlaceBTN.MouseButton1Click:Connect(function()
    local modelName = "Lvl1"
    if OnPc then startPCPlantMode(modelName) end
    if OnMobile then startMobilePlantMode(modelName) end
end)

PlaceBTN.Visible = true -- Make sure placing button is visible when starting the game
