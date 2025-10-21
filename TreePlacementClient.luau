-- Credits: Me (nrhneghqrg52) 
 
-- Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local remotes = replicatedStorage.Remotes
local UserInputService = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local tweenService = game:GetService("TweenService")
local starterGui = player:WaitForChild("PlayerGui")
local Helpers = require(script:WaitForChild("Helper Functions"))
 
-- Remotes
local placeTreeEvent = remotes.PlaceTree
 
-- Variables
local PlaceBTN : TextButton = starterGui:WaitForChild("PlacementUI"):WaitForChild("Place Tree"):WaitForChild("Place Tree BTN")
local treeModels : Folder = replicatedStorage:WaitForChild("TreeModels")
local activePlantMode = false
local currentGhost = nil
local isPlacing = false
local SELECTED_TREE = nil
local cam = workspace.CurrentCamera
local activeConnections = {}
 
-- Even More variables HAHAHAHA
local Arrows = starterGui:WaitForChild("PlacementUI"):WaitForChild("Mobile Placement"):WaitForChild("Arrows")
local UpBtn : ImageButton = Arrows:WaitForChild("Frame"):WaitForChild("Up")
local DownBtn : ImageButton = Arrows:WaitForChild("Frame"):WaitForChild("Down")
local RightBtn : ImageButton = Arrows:WaitForChild("Frame"):WaitForChild("Right")
local LeftBtn : ImageButton = Arrows:WaitForChild("Frame"):WaitForChild("Left")
local Confirm : TextButton = Arrows:WaitForChild("Confirm")
local Cancel : TextButton  = Arrows:WaitForChild("Cancel")
 
local PCFrame : Frame = starterGui:WaitForChild("PlacementUI"):WaitForChild("PC Placement"):WaitForChild("Frame")
local TreeControls = PCFrame:WaitForChild("Tree Controls").UI
 
-- Even Even EVEn more freaking variables
local mobileGhost = nil
local mobilePlotPosition = nil -- Vector2
local mobileIsland = nil
local mobilePlotsByPos = {} -- [Vector2] = PlotPart
local mobileRotY = 0
local ControlsFrameOpen = false
local ArrowsTable = {UpBtn, DownBtn, RightBtn, LeftBtn}
 
-- Seriously js dont ask me ik its more vars but what can I DOOO?!
local OnMobile, OnPc = Helpers.Init()
 
-- Pc functions section<|>
 
local function cleanUpPC(Bool : string)
    if Bool == "Start" then
        for _, conn in ipairs(activeConnections) do
            conn:Disconnect()
        end
        activeConnections = {}
    end
    if Bool == "End" then
        -- Clean up
        if currentGhost then currentGhost:Destroy() end
        isPlacing = false
        currentGhost = nil
        Helpers.ToggleOtherPlantModeUI(PlaceBTN, false)
 
        for _, conn in ipairs(activeConnections) do
            conn:Disconnect()
        end
        activeConnections = {}
    end
end
 
local function startPCPlantMode(TreeName)
    if isPlacing then
        if currentGhost then currentGhost:Destroy() end
        cleanUpPC("Start")
    end
 
    local first = true
    isPlacing = true
    Helpers.ToggleOtherPlantModeUI(PlaceBTN, true)
 
    Helpers.ToggleControlsUI(TreeControls, true)
 
    local cachedTarget : Part
    local ghostTree: Model = treeModels:FindFirstChild(TreeName):Clone()
    ghostTree.PromptPart:FindFirstChildOfClass("ProximityPrompt"):Destroy()
    currentGhost = ghostTree
 
    -- Remove ProximityPrompt if it exists
    if ghostTree:FindFirstChild("PromptPart") then
        local prompt = ghostTree.PromptPart:FindFirstChildOfClass("ProximityPrompt")
        if prompt then prompt:Destroy() end
    end
 
    -- Store original material and color
    local partOriginals = {}
    for _, part in ipairs(ghostTree:GetDescendants()) do
        if part:IsA("BasePart") then
            partOriginals[part] = {
                Color = part.Color,
                Material = part.Material,
            }
            part.Transparency = 0.5
            part.CanCollide = false
        end
    end
 
    ghostTree.Parent = workspace:FindFirstChild("GhostTrees")
 
    local rotY = 0
    local mouse = Players.LocalPlayer:GetMouse()
 
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
 
    table.insert(activeConnections, runService.RenderStepped:Connect(function()
        local hit = mouse.Hit
        if not hit then print("Execution stopped") return end
 
        local selectionThreshold = 0.05 -- don't switch targets unless it's clearly closer
 
        local target
        local bestDist = math.huge
        local ClosestIsland = Helpers.checkClosestIsland(hit.Position)
 
        for _, plot in ipairs(ClosestIsland.MainGrid:GetDescendants()) do
            if plot:IsA("BasePart") and not (plot.Parent.Name == "Arrow") then
                local dist = math.floor((hit.Position - plot.Position).Magnitude * 1000) / 1000
 
                if not target then
                    bestDist = dist
                    target = plot
                else
                    local diff = dist - bestDist
 
                    if diff < -selectionThreshold then
                        -- Clearly closer, replace
                        bestDist = dist
                        target = plot
                    elseif math.abs(diff) <= selectionThreshold then
                        -- Distances are nearly equal, use name as tie-breaker
                        if plot.Name < target.Name then
                            bestDist = dist
                            target = plot
                        end
                    end
                end
            end
        end
 
        if not target then print("Execution Stopped") return end
        cachedTarget = target
 
        targetCFrame = target.CFrame * CFrame.Angles(0, math.rad(rotY), 0)
 
        if first then
            ghostTree:PivotTo(targetCFrame)
            currentCFrame = targetCFrame
            first = false
        else
            local alpha = 0.20
            currentCFrame = currentCFrame:Lerp(targetCFrame, alpha)
            ghostTree.PrimaryPart.CFrame = currentCFrame
 
            local occupied = target:GetAttribute("Occupied")
            for part, original in pairs(partOriginals) do
                if part:IsA("BasePart") then
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
        end
    end))
 
    table.insert(activeConnections, mouse.Button1Down:Connect(function()
        if not cachedTarget then print("Execution Stopped") return end
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
 
-- Mobile functions section<|>
 
-- Clamp arrows
local function updateArrowVisibilitys(ghostTree: Model)
    local slotName = ghostTree:GetAttribute("Slot")
    if typeof(slotName) ~= "string" then
        warn("Ghost tree Slot attribute missing or not a string")
        return
    end
 
    -- Example slotName: "A_3"
    local letter = string.sub(slotName, 1, 1) -- A–F
    local number = tonumber(string.sub(slotName, 3)) -- 1–6
 
    -- Safety check
    if not letter or not number then
        warn("Invalid Slot format: " .. tostring(slotName))
        return
    end
 
    -- Right arrow disappears if at any of the A's (A_1–A_6)
    RightBtn.Visible = (letter ~= "A")
 
    -- Left arrow disappears if at any of the F's (F_1–F_6)
    LeftBtn.Visible = (letter ~= "F")
 
    -- Up arrow disappears if at any _1 (A_1–F_1)
    UpBtn.Visible = (number ~= 1)
 
    -- Down arrow disappears if at any _6 (A_6–F_6)
    DownBtn.Visible = (number ~= 6)
end
 
local function cleanUpMobile(Bool : string)
    if Bool == "Start" then
        for _, conn in ipairs(activeConnections) do
            conn:Disconnect()
        end
        activeConnections = {}
    end
    if Bool == "End" then
        -- Clean up
        if mobileGhost then mobileGhost:Destroy() end
        isPlacing = false
        mobileGhost = nil
        PlaceBTN.Visible = true
        Confirm.Visible = false
        Cancel.Visible = false
 
        for _, conn in ipairs(activeConnections) do
            conn:Disconnect()
        end
 
        activeConnections = {}
 
        Helpers.TurnMobileArrowsOn_Off("Off", ArrowsTable)
        if cam.CameraType == Enum.CameraType.Scriptable then
            cam.CameraType = Enum.CameraType.Custom
        end
    end
end
 
-- Mobile startPlantMode
function startMobilePlantMode(treeName)
    cleanUpMobile("Start")
 
    isPlacing = true
    PlaceBTN.Visible = false
    Confirm.Visible = true
    Cancel.Visible = true
    Helpers.TurnMobileArrowsOn_Off("On", ArrowsTable)
 
    -- Get closest island from HumanoidRootPart
    local char: Model = player.Character
    if not char then return print("Stopped Execution!") end
    local hrp: Part? = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return print("Stopped Execution!") end
 
    mobileIsland = Helpers.checkClosestIsland(hrp.Position)
    if not mobileIsland then return print("Stopped Execution!") end
 
    -- Camera Positioning
    local camPart = mobileIsland:FindFirstChild("CameraPart")
    if camPart then
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = camPart.CFrame
    end
 
    -- Get valid plots
    mobilePlotsByPos = {}
    for _, plot in ipairs(mobileIsland.MainGrid:GetDescendants()) do
        if plot:IsA("BasePart") and not plot:GetAttribute("Occupied") then
            local vec = Helpers.plotNameToVector2(plot.Name)
            if vec then
                mobilePlotsByPos[Helpers.vector2Key(vec)] = plot
            end
        end
    end
 
    -- Pick closest plot
    local bestDist = math.huge
    for key, part in pairs(mobilePlotsByPos) do
        local dist = math.floor((hrp.Position - part.Position).Magnitude * 1000) / 1000
        if dist < bestDist then
            bestDist = dist
            mobilePlotPosition = Helpers.keyToVector2(key)
        end
    end
    if not mobilePlotPosition then return print("Stopped Execution!") end
 
    -- Clone ghost
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
    --updateArrowVisibility(mobilePlotPosition)
    mobileGhost:SetAttribute("Slot", mobilePlotsByPos[Helpers.vector2Key(mobilePlotPosition)].Name)
    updateArrowVisibilitys(mobileGhost)
    Helpers.updateMobileGhost(mobileGhost, mobilePlotsByPos, mobilePlotPosition, mobileRotY)
 
    -- Arrow click logic
    local function moveGhost(dir: Vector2)
        local tempPos = mobilePlotPosition + dir
        local key = Helpers.vector2Key(tempPos)
 
        if mobilePlotsByPos[key] then
            local success = Helpers.updateMobileGhost(mobileGhost, mobilePlotsByPos, tempPos, mobileRotY)
            if success then
                mobilePlotPosition = tempPos -- ✅ commit the move
                --updateArrowVisibility(mobilePlotPosition)
                mobileGhost:SetAttribute("Slot", mobilePlotsByPos[Helpers.vector2Key(mobilePlotPosition)].Name)
                updateArrowVisibilitys(mobileGhost)
            end
        end
    end
 
    table.insert(activeConnections, UpBtn.MouseButton1Click:Connect(function() moveGhost(Vector2.new(-1, 0)) end))
    table.insert(activeConnections, DownBtn.MouseButton1Click:Connect(function() moveGhost(Vector2.new(1, 0)) end))
    table.insert(activeConnections, RightBtn.MouseButton1Click:Connect(function() moveGhost(Vector2.new(0, -1)) end))
    table.insert(activeConnections, LeftBtn.MouseButton1Click:Connect(function() moveGhost(Vector2.new(0, 1)) end))
 
    -- Confirm placement
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
 
 
PlaceBTN.MouseButton1Click:Connect(function()
    local modelName = "Lvl1"
 
    if OnPc then print("on pc plant mode initiating") startPCPlantMode(modelName) end
 
    if OnMobile then print("on mobile plant mode initiating") startMobilePlantMode(modelName) end
end)
 
PlaceBTN.Visible = true
