--[[ 
    Tree Placement System (Client Script)
    Author: nhrneghqrg52
    Description: Handles both PC and Mobile tree placement logic, including 
    ghost visualization, rotation, UI toggling, and communication with the server.
    Demonstrates knowledge of Roblox APIs such as UserInputService, RunService, 
    TweenService, ReplicatedStorage communication, and CFrame transformations.
]]

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage") -- Stores shared assets and remote events
local remotes = replicatedStorage.Remotes -- Folder containing RemoteEvents and RemoteFunctions
local UserInputService = game:GetService("UserInputService") -- Used to detect player input
local runService = game:GetService("RunService") -- Used for frame-based updates (RenderStepped)
local Players = game:GetService("Players") -- Provides access to the player list
local player = Players.LocalPlayer -- The current client player
local tweenService = game:GetService("TweenService") -- Used to create smooth transitions (tweens)
local starterGui = player:WaitForChild("PlayerGui") -- The player’s GUI hierarchy
local Helpers = require(script:WaitForChild("Helper Functions")) -- Module containing shared utility functions

--// Remote Events
local placeTreeEvent = remotes.PlaceTree -- RemoteEvent used to request the server to place a tree

--// UI References
local PlaceBTN : TextButton = starterGui:WaitForChild("PlacementUI"):WaitForChild("Place Tree"):WaitForChild("Place Tree BTN") -- Main button to start planting
local treeModels : Folder = replicatedStorage:WaitForChild("TreeModels") -- Folder containing tree model templates

--// Core State Variables
local activePlantMode = false -- Tracks whether planting mode is active
local currentGhost = nil -- Reference to the currently visible ghost tree model
local isPlacing = false -- Prevents overlapping placement attempts
local SELECTED_TREE = nil -- Stores which tree is currently selected for placement
local cam = workspace.CurrentCamera -- Reference to the current camera
local activeConnections = {} -- Holds all active input/event connections for cleanup

--// UI Components (Mobile + PC)
local Arrows = starterGui:WaitForChild("PlacementUI"):WaitForChild("Mobile Placement"):WaitForChild("Arrows") -- Mobile arrow controls UI
local UpBtn : ImageButton = Arrows:WaitForChild("Frame"):WaitForChild("Up") -- Moves ghost tree upward in grid
local DownBtn : ImageButton = Arrows:WaitForChild("Frame"):WaitForChild("Down") -- Moves ghost tree downward in grid
local RightBtn : ImageButton = Arrows:WaitForChild("Frame"):WaitForChild("Right") -- Moves ghost tree right in grid
local LeftBtn : ImageButton = Arrows:WaitForChild("Frame"):WaitForChild("Left") -- Moves ghost tree left in grid
local Confirm : TextButton = Arrows:WaitForChild("Confirm") -- Confirms placement
local Cancel : TextButton  = Arrows:WaitForChild("Cancel") -- Cancels placement

local PCFrame : Frame = starterGui:WaitForChild("PlacementUI"):WaitForChild("PC Placement"):WaitForChild("Frame")
local TreeControls = PCFrame:WaitForChild("Tree Controls").UI -- PC-specific controls UI

--// Mobile State Variables
local mobileGhost = nil -- Holds the cloned ghost tree for mobile
local mobilePlotPosition = nil -- Current grid position on mobile (Vector2)
local mobileIsland = nil -- The island currently being planted on
local mobilePlotsByPos = {} -- Dictionary mapping Vector2 positions to plot parts
local mobileRotY = 0 -- Rotation angle for mobile placement
local ControlsFrameOpen = false -- Whether the controls UI is visible
local ArrowsTable = {UpBtn, DownBtn, RightBtn, LeftBtn} -- For easy iteration over arrow buttons

--// Detect platform (PC or Mobile)
local OnMobile, OnPc = Helpers.Init() -- Returns platform flags

--=====================================================
--// PC TREE PLACEMENT LOGIC
--=====================================================

--[[
    Function: cleanUpPC
    Purpose: Disconnects all active event connections and resets placement state.
    Parameters:
        Bool (string) – Determines whether cleanup is for starting or ending placement.
]]
local function cleanUpPC(Bool : string)
    if Bool == "Start" then
        -- Disconnect all active input/event connections before restarting placement
        for _, conn in ipairs(activeConnections) do
            conn:Disconnect()
        end
        activeConnections = {}
    end

    if Bool == "End" then
        -- Remove ghost and reset all placement-related variables
        if currentGhost then currentGhost:Destroy() end
        isPlacing = false
        currentGhost = nil

        -- Re-enable UI buttons
        Helpers.ToggleOtherPlantModeUI(PlaceBTN, false)

        -- Disconnect all events safely
        for _, conn in ipairs(activeConnections) do
            conn:Disconnect()
        end
        activeConnections = {}
    end
end


--[[
    Function: startPCPlantMode
    Purpose: Begins the placement process for PC users.
    Handles:
        • Creating a transparent ghost tree
        • Detecting valid grid plots
        • Allowing rotation and placement confirmation
        • Sending final placement data to the server
]]
local function startPCPlantMode(TreeName)
    -- If already placing, clean up previous ghost/tree state
    if isPlacing then
        if currentGhost then currentGhost:Destroy() end
        cleanUpPC("Start")
    end

    local first = true -- Tracks if this is the first frame of placement
    isPlacing = true

    -- Hide Place button and show controls
    Helpers.ToggleOtherPlantModeUI(PlaceBTN, true)
    Helpers.ToggleControlsUI(TreeControls, true)

    -- Clone the selected tree model as a ghost
    local ghostTree: Model = treeModels:FindFirstChild(TreeName):Clone()
    ghostTree.PromptPart:FindFirstChildOfClass("ProximityPrompt"):Destroy()
    currentGhost = ghostTree

    -- Store original part materials/colors for restoring later
    local partOriginals = {}
    for _, part in ipairs(ghostTree:GetDescendants()) do
        if part:IsA("BasePart") then
            partOriginals[part] = {
                Color = part.Color,
                Material = part.Material
            }
            part.Transparency = 0.5 -- Make ghost semi-transparent
            part.CanCollide = false
        end
    end

    ghostTree.Parent = workspace:FindFirstChild("GhostTrees")

    local rotY = 0 -- Rotation angle for tree (Y-axis)
    local mouse = Players.LocalPlayer:GetMouse() -- For tracking mouse raycast hits

    -- Connect key inputs for rotation and cancellation
    table.insert(activeConnections, UserInputService.InputBegan:Connect(function(key, gp)
        if gp then return end -- Ignore if input is captured by UI
        if key.KeyCode == Enum.KeyCode.Q then rotY -= 90 end -- Rotate left
        if key.KeyCode == Enum.KeyCode.E then rotY += 90 end -- Rotate right
        if key.KeyCode == Enum.KeyCode.C then -- Cancel placement
            cleanUpPC("End")
            Helpers.ToggleControlsUI(TreeControls, false)
        end
    end))

    -- Initialize CFrames for smooth lerping
    local currentCFrame = ghostTree.PrimaryPart.CFrame
    local targetCFrame = currentCFrame
    local cachedTarget : Part

    -- Render loop (runs every frame)
    table.insert(activeConnections, runService.RenderStepped:Connect(function()
        local hit = mouse.Hit -- Current mouse world position (Raycast)
        if not hit then return end

        local selectionThreshold = 0.05 -- Helps prevent rapid switching between similar-distance plots
        local target
        local bestDist = math.huge
        local ClosestIsland = Helpers.checkClosestIsland(hit.Position) -- Finds nearest island to hit point

        -- Search for closest available plot
        for _, plot in ipairs(ClosestIsland.MainGrid:GetDescendants()) do
            if plot:IsA("BasePart") and not (plot.Parent.Name == "Arrow") then
                local dist = math.floor((hit.Position - plot.Position).Magnitude * 1000) / 1000

                if not target then
                    bestDist = dist
                    target = plot
                else
                    local diff = dist - bestDist

                    if diff < -selectionThreshold then
                        bestDist = dist
                        target = plot
                    elseif math.abs(diff) <= selectionThreshold and plot.Name < target.Name then
                        bestDist = dist
                        target = plot
                    end
                end
            end
        end

        if not target then return end
        cachedTarget = target

        -- Align ghost tree rotation and position
        targetCFrame = target.CFrame * CFrame.Angles(0, math.rad(rotY), 0)

        if first then
            ghostTree:PivotTo(targetCFrame)
            currentCFrame = targetCFrame
            first = false
        else
            -- Smooth interpolation (lerp) to new target position
            local alpha = 0.20
            currentCFrame = currentCFrame:Lerp(targetCFrame, alpha)
            ghostTree.PrimaryPart.CFrame = currentCFrame

            -- Update ghost color/material depending on plot occupancy
            local occupied = target:GetAttribute("Occupied")
            for part, original in pairs(partOriginals) do
                if part:IsA("BasePart") then
                    if occupied then
                        part.Color = Color3.fromRGB(255, 80, 80) -- Red ghost if blocked
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

    -- Handle actual placement when left-clicking
    table.insert(activeConnections, mouse.Button1Down:Connect(function()
        if not cachedTarget then return end
        local IslandName = cachedTarget.Parent.Parent.Parent.Name

        -- Only allow placement if plot is not occupied
        if not cachedTarget:GetAttribute("Occupied") then
            placeTreeEvent:FireServer(cachedTarget.Name, TreeName, rotY, IslandName)
            cleanUpPC("End")
            Helpers.ToggleControlsUI(TreeControls, false)
        else
            print("Cannot place tree because plot is already occupied")
        end
    end))
end

--=====================================================
--// MOBILE TREE PLACEMENT LOGIC
--=====================================================

--[[
    Function: updateArrowVisibilitys
    Purpose: Controls the visibility of movement arrows in mobile placement mode
             depending on the current plot position (e.g., hides arrows at grid edges).
    Parameters:
        ghostTree (Model) – The current transparent tree model being positioned
]]
local function updateArrowVisibilitys(ghostTree: Model)
    -- Retrieve the slot name stored as an attribute (e.g., "A_3")
    local slotName = ghostTree:GetAttribute("Slot")
    if typeof(slotName) ~= "string" then
        warn("Ghost tree Slot attribute missing or not a string")
        return
    end

    -- Extract letter and number from slot name
    local letter = string.sub(slotName, 1, 1) -- Row (A–F)
    local number = tonumber(string.sub(slotName, 3)) -- Column (1–6)

    if not letter or not number then
        warn("Invalid Slot format: " .. tostring(slotName))
        return
    end

    -- Disable directional arrows based on plot edge
    RightBtn.Visible = (letter ~= "A") -- Hide Right if at column A
    LeftBtn.Visible  = (letter ~= "F") -- Hide Left if at column F
    UpBtn.Visible    = (number ~= 1)   -- Hide Up if at row 1
    DownBtn.Visible  = (number ~= 6)   -- Hide Down if at row 6
end


--[[
    Function: cleanUpMobile
    Purpose: Disconnects all connections and resets the mobile placement interface
             (ghost model, camera, and buttons).
    Parameters:
        Bool (string) – "Start" for early cleanup or "End" for full teardown
]]
local function cleanUpMobile(Bool : string)
    if Bool == "Start" then
        -- Disconnect event listeners before starting a new placement
        for _, conn in ipairs(activeConnections) do
            conn:Disconnect()
        end
        activeConnections = {}
    end

    if Bool == "End" then
        -- Full cleanup after placement or cancellation
        if mobileGhost then mobileGhost:Destroy() end
        isPlacing = false
        mobileGhost = nil

        -- Restore UI visibility
        PlaceBTN.Visible = true
        Confirm.Visible = false
        Cancel.Visible = false

        -- Disconnect any leftover connections
        for _, conn in ipairs(activeConnections) do
            conn:Disconnect()
        end
        activeConnections = {}

        -- Turn off arrows and restore normal camera control
        Helpers.TurnMobileArrowsOn_Off("Off", ArrowsTable)
        if cam.CameraType == Enum.CameraType.Scriptable then
            cam.CameraType = Enum.CameraType.Custom
        end
    end
end


--[[
    Function: startMobilePlantMode
    Purpose: Handles the entire mobile tree placement process.
    Steps:
        1. Cleans previous state.
        2. Spawns a ghost tree model.
        3. Locks the camera on the island grid.
        4. Lets the player move the ghost via UI arrows.
        5. Fires the placement event when confirmed.
    Parameters:
        treeName (string) – Name of the tree model to be placed.
]]
function startMobilePlantMode(treeName)
    -- Reset any previous placement
    cleanUpMobile("Start")

    -- Enable placement state
    isPlacing = true
    PlaceBTN.Visible = false
    Confirm.Visible = true
    Cancel.Visible = true

    -- Activate mobile arrows
    Helpers.TurnMobileArrowsOn_Off("On", ArrowsTable)

    -- Get player's character and HRP for proximity reference
    local char: Model = player.Character
    if not char then return print("Stopped Execution!") end
    local hrp: Part? = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return print("Stopped Execution!") end

    -- Determine the closest island to player position
    mobileIsland = Helpers.checkClosestIsland(hrp.Position)
    if not mobileIsland then return print("Stopped Execution!") end

    -- Focus camera on island camera part
    local camPart = mobileIsland:FindFirstChild("CameraPart")
    if camPart then
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = camPart.CFrame
    end

    -- Gather all valid plots (non-occupied BaseParts)
    mobilePlotsByPos = {}
    for _, plot in ipairs(mobileIsland.MainGrid:GetDescendants()) do
        if plot:IsA("BasePart") and not plot:GetAttribute("Occupied") then
            local vec = Helpers.plotNameToVector2(plot.Name)
            if vec then
                mobilePlotsByPos[Helpers.vector2Key(vec)] = plot
            end
        end
    end

    -- Choose the plot closest to the player as the initial position
    local bestDist = math.huge
    for key, part in pairs(mobilePlotsByPos) do
        local dist = math.floor((hrp.Position - part.Position).Magnitude * 1000) / 1000
        if dist < bestDist then
            bestDist = dist
            mobilePlotPosition = Helpers.keyToVector2(key)
        end
    end
    if not mobilePlotPosition then return print("Stopped Execution!") end

    -- Clone the ghost model for preview
    mobileGhost = treeModels:FindFirstChild(treeName):Clone()
    mobileGhost.PromptPart:FindFirstChildOfClass("ProximityPrompt"):Destroy()
    mobileGhost.Parent = workspace.GhostTrees

    -- Make ghost model semi-transparent and non-collidable
    for _, p in ipairs(mobileGhost:GetDescendants()) do
        if p:IsA("BasePart") then
            p.Transparency = 0.5
            p.CanCollide = false
        end
    end

    mobileRotY = 0 -- Initial rotation
    mobileGhost:SetAttribute("Slot", mobilePlotsByPos[Helpers.vector2Key(mobilePlotPosition)].Name)

    -- Update UI arrows based on boundaries
    updateArrowVisibilitys(mobileGhost)

    -- Move ghost to selected plot
    Helpers.updateMobileGhost(mobileGhost, mobilePlotsByPos, mobilePlotPosition, mobileRotY)

        --=====================================================
    --// MOBILE MOVEMENT AND CONFIRMATION LOGIC
    --=====================================================

    --[[
        Local Function: moveGhost
        Purpose: Handles directional movement of the ghost tree on mobile.
        Takes a Vector2 offset, checks for valid plots, and updates
        both the ghost position and the UI arrow visibility accordingly.
        Parameters:
            dir (Vector2) – The directional movement delta (e.g., Vector2.new(-1, 0) for Up)
    ]]
    local function moveGhost(dir: Vector2)
        local tempPos = mobilePlotPosition + dir
        local key = Helpers.vector2Key(tempPos)

        -- Only move if the plot exists and is valid
        if mobilePlotsByPos[key] then
            local success = Helpers.updateMobileGhost(mobileGhost, mobilePlotsByPos, tempPos, mobileRotY)
            if success then
                -- Update current position
                mobilePlotPosition = tempPos
                -- Update ghost attributes for consistency
                mobileGhost:SetAttribute("Slot", mobilePlotsByPos[Helpers.vector2Key(mobilePlotPosition)].Name)
                -- Refresh arrow visibility (handles boundaries)
                updateArrowVisibilitys(mobileGhost)
            end
        end
    end

    --=====================================================
    --// EVENT CONNECTIONS FOR ARROW BUTTONS
    --=====================================================

    -- Connect directional buttons to movement logic
    table.insert(activeConnections, UpBtn.MouseButton1Click:Connect(function()
        moveGhost(Vector2.new(-1, 0)) -- Move upward on the grid
    end))

    table.insert(activeConnections, DownBtn.MouseButton1Click:Connect(function()
        moveGhost(Vector2.new(1, 0)) -- Move downward on the grid
    end))

    table.insert(activeConnections, RightBtn.MouseButton1Click:Connect(function()
        moveGhost(Vector2.new(0, -1)) -- Move rightward (decreasing letter index)
    end))

    table.insert(activeConnections, LeftBtn.MouseButton1Click:Connect(function()
        moveGhost(Vector2.new(0, 1)) -- Move leftward (increasing letter index)
    end))


    --=====================================================
    --// CONFIRMATION AND CANCELLATION HANDLING
    --=====================================================

    -- Confirm placement button
    table.insert(activeConnections, Confirm.MouseButton1Click:Connect(function()
        local key = Helpers.vector2Key(mobilePlotPosition)
        local plot = mobilePlotsByPos[key]

        -- Validate plot before placement
        if not plot or plot:GetAttribute("Occupied") then
            return
        end

        -- Retrieve identifiers for server placement
        local islandName = mobileIsland.Name
        local plotName = Helpers.vector2ToPlotName(mobilePlotPosition)

        -- Fire placement request to server
        placeTreeEvent:FireServer(plotName, treeName, mobileRotY, islandName)

        -- Cleanup after successful placement
        cleanUpMobile("End")
    end))

    -- Cancel button logic
    table.insert(activeConnections, Cancel.MouseButton1Click:Connect(function()
        -- Clean up and revert all placement changes
        cleanUpMobile("End")
    end))
end


--=====================================================
--// FINAL UI BUTTON CONNECTION
--=====================================================

--[[
    Event: PlaceBTN.MouseButton1Click
    Purpose: Determines whether to run PC or Mobile placement mode
             depending on the player’s platform (detected through Helpers.Init()).
]]
PlaceBTN.MouseButton1Click:Connect(function()
    local modelName = "Lvl1" -- Default model to place (can be changed later)

    -- Determine platform mode and start respective placement handler
    if OnPc then
        print("on pc plant mode initiating")
        startPCPlantMode(modelName)
    end

    if OnMobile then
        print("on mobile plant mode initiating")
        startMobilePlantMode(modelName)
    end
end)

-- Ensure the button starts visible upon loading
PlaceBTN.Visible = true

--=====================================================
--// END OF SCRIPT
--=====================================================
