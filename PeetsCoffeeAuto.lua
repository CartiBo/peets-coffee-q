local ALLOWED_PLACE_ID = 94539932414164
local JOB_NAME = "Peets Coffee & Tea"
local WORK_RADIUS = 180

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local player = Players.LocalPlayer
local PROMPT_DISTANCE_TOLERANCE = 2.5

assert(game.PlaceId == ALLOWED_PLACE_ID, "This QA only works on the configured PlaceId")
assert(type(fireproximityprompt) == "function", "The executor does not support fireproximityprompt")

local previousControl = getgenv().PeetsCoffeeQA
if previousControl then
    previousControl.running = false
    if previousControl.restoreCamera then
        pcall(previousControl.restoreCamera)
    end
    if previousControl.releaseMovement then
        pcall(previousControl.releaseMovement)
    end
    if previousControl.restorePrompts then
        pcall(previousControl.restorePrompts)
    end
    if previousControl.connections then
        for _, connection in ipairs(previousControl.connections) do
            connection:Disconnect()
        end
    end
    if previousControl.gui then
        previousControl.gui:Destroy()
    end
end

for _, existingGui in ipairs(player:WaitForChild("PlayerGui"):GetChildren()) do
    if existingGui.Name == "PeetsCoffeeQA" then
        existingGui:Destroy()
    end
end

local control = {
    running = false,
    gui = nil,
    restoreCamera = nil,
    releaseMovement = nil,
    restorePrompts = nil,
    connections = {},
}
getgenv().PeetsCoffeeQA = control

local shownPrompts = setmetatable({}, { __mode = "k" })
table.insert(control.connections, ProximityPromptService.PromptShown:Connect(function(prompt)
    shownPrompts[prompt] = true
end))
table.insert(control.connections, ProximityPromptService.PromptHidden:Connect(function(prompt)
    shownPrompts[prompt] = nil
end))

local jobs = workspace:WaitForChild("Mojave"):WaitForChild("InteractiveJobs")
local job = jobs:WaitForChild(JOB_NAME)
local interactive = job:WaitForChild("Interactive")
local workHere = job:FindFirstChild("WorkHere")
local npcFolder = workspace:WaitForChild("NPCs")

local machineNames = {
    Coffee = "Coffee",
    Croissant = "Croissant",
    Milkshake = "Milkshake",
    EggSandwich = "EggSandwich",
}

local function normalize(value)
    return tostring(value or ""):gsub("%s+", ""):gsub("[^%w]", ""):lower()
end

local function promptPosition(prompt)
    local parent = prompt and prompt.Parent
    if not parent then return nil end
    if parent:IsA("Attachment") then return parent.WorldPosition end
    if parent:IsA("BasePart") then return parent.Position end
    local part = parent:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local function findPrompt(root)
    return root and root:FindFirstChildWhichIsA("ProximityPrompt", true) or nil
end

local activeHandPrompts = setmetatable({}, { __mode = "k" })
local configureInstantPrompt = nil
local function trackHandPrompt(item)
    if item:IsA("ProximityPrompt") and item.Name == "HandPrompt" then
        activeHandPrompts[item] = true
        if configureInstantPrompt and control.running then
            configureInstantPrompt(item)
        end
    end
end
for _, item in ipairs(npcFolder:GetDescendants()) do
    trackHandPrompt(item)
end
table.insert(control.connections, npcFolder.DescendantAdded:Connect(trackHandPrompt))
table.insert(control.connections, npcFolder.DescendantRemoving:Connect(function(item)
    activeHandPrompts[item] = nil
end))

local originalHoldDurations = setmetatable({}, { __mode = "k" })
local instantPromptsEnabled = false

configureInstantPrompt = function(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    local belongsToJob = prompt:IsDescendantOf(job)
    local isCustomerPrompt = prompt.Name == "HandPrompt" and prompt:IsDescendantOf(npcFolder)
    if not belongsToJob and not isCustomerPrompt then return end
    if originalHoldDurations[prompt] == nil then
        originalHoldDurations[prompt] = prompt.HoldDuration
    end
    prompt.HoldDuration = 0
end

local function enableInstantPrompts()
    if instantPromptsEnabled then return end
    instantPromptsEnabled = true
    for _, item in ipairs(job:GetDescendants()) do
        configureInstantPrompt(item)
    end
    for prompt in pairs(activeHandPrompts) do
        configureInstantPrompt(prompt)
    end
end

local function restoreInstantPrompts()
    if not instantPromptsEnabled and next(originalHoldDurations) == nil then return end
    instantPromptsEnabled = false
    for prompt, holdDuration in pairs(originalHoldDurations) do
        if prompt.Parent then prompt.HoldDuration = holdDuration end
        originalHoldDurations[prompt] = nil
    end
end

control.restorePrompts = restoreInstantPrompts
table.insert(control.connections, job.DescendantAdded:Connect(function(item)
    if item.Parent == job and item.Name == "WorkHere" then workHere = item end
    if control.running then configureInstantPrompt(item) end
end))
table.insert(control.connections, job.ChildRemoved:Connect(function(item)
    if item == workHere then workHere = nil end
end))

local function findHandPrompt()
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local nearest = nil
    local nearestDistance = math.huge
    for prompt in pairs(activeHandPrompts) do
        if prompt.Parent and prompt.Enabled and prompt:IsDescendantOf(npcFolder) then
            local position = promptPosition(prompt)
            local distance = root and position and (root.Position - position).Magnitude or 0
            if distance < nearestDistance then
                nearest = prompt
                nearestDistance = distance
            end
        end
    end
    return nearest
end

local function isCurrentOrder(prompt, order)
    return prompt ~= nil
        and prompt.Parent ~= nil
        and prompt.Enabled
        and prompt:IsDescendantOf(npcFolder)
        and normalize(prompt.ObjectText) == normalize(order)
end

local machinePrompts = {}
for name in pairs(machineNames) do
    machinePrompts[normalize(name)] = findPrompt(interactive:FindFirstChild(name))
end

local function findMachinePrompt(order)
    local wanted = machineNames[order] or order
    local wantedNormalized = normalize(wanted)
    local prompt = machinePrompts[wantedNormalized]
    if prompt and prompt.Parent then return prompt end
    for name in pairs(machineNames) do
        local key = normalize(name)
        machinePrompts[key] = findPrompt(interactive:FindFirstChild(name))
    end
    return machinePrompts[wantedNormalized]
end

local function characterParts()
    local character = player.Character
    if not character then return nil end
    return character, character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
end

local function moveToPosition(position, stopDistance, arrivalCheck, progressCallback)
    local _, humanoid, root = characterParts()
    if not humanoid or not root then return false, "character unavailable" end
    stopDistance = stopDistance or 4

    local flatPosition = Vector3.new(position.X, root.Position.Y, position.Z)
    local direction = root.Position - flatPosition
    local target = flatPosition
    if direction.Magnitude > stopDistance then
        target = flatPosition + direction.Unit * stopDistance
    end

    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 4,
    })

    local computed = pcall(function()
        path:ComputeAsync(root.Position, target)
    end)
    local waypoints = computed and path.Status == Enum.PathStatus.Success
        and path:GetWaypoints()
        or { { Position = target } }

    for _, waypoint in ipairs(waypoints) do
        if not control.running then return false, "stopped" end
        if progressCallback then pcall(progressCallback, waypoint.Position) end
        if arrivalCheck and arrivalCheck() then
            humanoid:MoveTo(root.Position)
            return true
        end

        local function waypointDistance()
            local delta = Vector3.new(
                waypoint.Position.X - root.Position.X,
                0,
                waypoint.Position.Z - root.Position.Z
            )
            return delta.Magnitude
        end
        if waypointDistance() <= 0.8 then
            continue
        end

        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end

        local released = false
        local releaseMovement
        releaseMovement = function()
            if released then return end
            released = true
            pcall(function()
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
            end)
            humanoid:Move(Vector3.zero, false)
            if control.releaseMovement == releaseMovement then
                control.releaseMovement = nil
            end
        end
        control.releaseMovement = releaseMovement

        humanoid:MoveTo(waypoint.Position)
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)

        local arrived = false
        local deadline = os.clock() + 4
        repeat
            task.wait(0.03)
            if progressCallback then pcall(progressCallback, waypoint.Position) end
            arrived = arrivalCheck and arrivalCheck() or false
        until arrived or waypointDistance() <= 0.8
            or os.clock() >= deadline or not control.running
        releaseMovement()

        if arrived then
            humanoid:MoveTo(root.Position)
            return true
        end

        if not control.running then return false, "stopped" end
        if waypointDistance() > 1.5 then
            return false, "path blocked"
        end
    end

    return true
end

local function beginCameraFocus(positionProvider, forceFocus)
    local camera = workspace.CurrentCamera
    local position = positionProvider()
    if not camera or not position then return nil, nil end

    local viewportPoint, onScreen = camera:WorldToViewportPoint(position)
    if not forceFocus and onScreen and viewportPoint.Z > 0 then
        return nil, nil
    end
    if control.restoreCamera then
        pcall(control.restoreCamera)
    end

    local oldCameraType = camera.CameraType
    local oldCameraCFrame = camera.CFrame
    local oldCameraSubject = camera.CameraSubject
    local restored = false
    local restoreCamera

    restoreCamera = function()
        if restored then return end
        restored = true
        camera.CameraType = oldCameraType
        camera.CameraSubject = oldCameraSubject
        camera.CFrame = oldCameraCFrame
        if control.restoreCamera == restoreCamera then
            control.restoreCamera = nil
        end
    end

    local function updateCamera(targetOverride)
        if restored then return end
        local target = targetOverride or positionProvider()
        local _, _, root = characterParts()
        if not target or not root then return end
        camera.CameraType = Enum.CameraType.Scriptable
        local cameraPosition = root.Position + Vector3.new(0, 2.5, 0)
        local horizontalTarget = Vector3.new(target.X, cameraPosition.Y, target.Z)
        camera.CFrame = CFrame.lookAt(cameraPosition, horizontalTarget)
    end

    control.restoreCamera = restoreCamera
    updateCamera()
    return updateCamera, restoreCamera
end

local function moveToPrompt(prompt)
    local function inRange()
        if not prompt or not prompt.Parent or not prompt.Enabled then return false end
        local livePosition = promptPosition(prompt)
        local _, _, liveRoot = characterParts()
        return liveRoot ~= nil
            and livePosition ~= nil
            and (liveRoot.Position - livePosition).Magnitude <= prompt.MaxActivationDistance - 0.25
    end

    if inRange() then return true end
    local lastError = "out of range"
    for _ = 1, 2 do
        if not prompt.Parent or not prompt.Enabled then return false, "prompt changed" end
        local position = promptPosition(prompt)
        if not position then return false, "prompt has no position" end
        local stopDistance = math.max(2, math.min(8, prompt.MaxActivationDistance - 2))
        local updateCamera, restoreCamera = beginCameraFocus(function()
            return promptPosition(prompt)
        end, true)
        local moved, moveError = moveToPosition(position, stopDistance, inRange, updateCamera)
        if restoreCamera then restoreCamera() end
        if inRange() then return true end
        if not moved then lastError = moveError or "out of range" end
    end
    return false, lastError
end

local function activatePrompt(prompt, stillValid, allowResolution)
    if not prompt or not prompt.Parent then return false, "prompt disappeared" end
    if not prompt.Enabled then return false, "prompt disabled" end

    local _, _, root = characterParts()
    local position = promptPosition(prompt)
    if not root or not position then return false, "no position" end
    if not shownPrompts[prompt]
        and (root.Position - position).Magnitude
            > prompt.MaxActivationDistance + PROMPT_DISTANCE_TOLERANCE then
        return false, "out of range"
    end

    local oldMaxDistance = prompt.MaxActivationDistance
    local oldLineOfSight = prompt.RequiresLineOfSight
    local oldExclusivity = prompt.Exclusivity
    local updateCamera, restoreCamera = beginCameraFocus(function()
        return promptPosition(prompt)
    end, false)
    local needsCameraFocus = restoreCamera ~= nil

    prompt.MaxActivationDistance = math.max(oldMaxDistance, 25)
    prompt.RequiresLineOfSight = false
    prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow

    local ok, err = pcall(function()
        task.wait(needsCameraFocus and 0.2 or 0.05)
        prompt:InputHoldBegin()
        local deadline = os.clock() + math.max(0.12, prompt.HoldDuration + 0.15)
        repeat
            task.wait(0.05)
            if updateCamera then updateCamera() end
        until os.clock() >= deadline
            or not control.running
            or (stillValid and not stillValid())
    end)
    pcall(function()
        if prompt.Parent then prompt:InputHoldEnd() end
    end)

    if prompt.Parent then
        prompt.MaxActivationDistance = oldMaxDistance
        prompt.RequiresLineOfSight = oldLineOfSight
        prompt.Exclusivity = oldExclusivity
    end
    if restoreCamera then restoreCamera() end

    if not ok and prompt.Parent then
        ok, err = pcall(fireproximityprompt, prompt)
    end

    if stillValid and not stillValid() and not allowResolution then
        return false, "order changed"
    end
    return ok, err
end

local function findOrderTool(order)
    local wanted = normalize(order)
    local character = player.Character
    local backpack = player:FindFirstChildOfClass("Backpack")
    for _, container in ipairs({ character, backpack }) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") and normalize(item.Name) == wanted then
                    return item
                end
            end
        end
    end
    return nil
end

local function findAnyTool()
    local character = player.Character
    local backpack = player:FindFirstChildOfClass("Backpack")
    for _, container in ipairs({ character, backpack }) do
        if container then
            local tool = container:FindFirstChildOfClass("Tool")
            if tool then return tool end
        end
    end
    return nil
end

local function findObsoleteTool(order)
    local wanted = normalize(order)
    local character = player.Character
    local backpack = player:FindFirstChildOfClass("Backpack")
    for _, container in ipairs({ character, backpack }) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and normalize(tool.Name) ~= wanted then
                    return tool
                end
            end
        end
    end
    return nil
end

local function discardTool(tool)
    if not tool or not tool.Parent then return true end
    local binPrompt = findPrompt(interactive:FindFirstChild("Bin"))
    if not binPrompt then return false, "bin not found" end

    local character, humanoid = characterParts()
    if not humanoid or not character then return false, "character unavailable" end
    if tool.Parent ~= character then
        humanoid:EquipTool(tool)
        task.wait(0.25)
    end

    local moved, moveError = moveToPrompt(binPrompt)
    if not moved then return false, moveError end

    local activated, activationError = activatePrompt(binPrompt)
    if not activated then return false, activationError end

    local deadline = os.clock() + 4
    repeat task.wait(0.15) until not tool.Parent or os.clock() >= deadline or not control.running
    if tool.Parent then return false, "the bin did not remove the tool" end
    return true
end

local function disconnectAll(connections)
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
end

local function waitForTool(order, machinePrompt, handPrompt, stillValid)
    local timeout = math.max(2, machinePrompt.HoldDuration + 2)
    local deadline = os.clock() + timeout
    local wake = Instance.new("BindableEvent")
    local connections = {}
    local character = player.Character
    local backpack = player:FindFirstChildOfClass("Backpack")

    local function signalChange()
        pcall(function() wake:Fire() end)
    end

    for _, container in ipairs({ character, backpack }) do
        if container then
            table.insert(connections, container.ChildAdded:Connect(signalChange))
        end
    end
    if handPrompt and handPrompt.Parent then
        table.insert(connections, handPrompt:GetPropertyChangedSignal("Enabled"):Connect(signalChange))
        table.insert(connections, handPrompt:GetPropertyChangedSignal("ObjectText"):Connect(signalChange))
        table.insert(connections, handPrompt.AncestryChanged:Connect(signalChange))
    end
    local timer = task.delay(timeout, signalChange)

    while control.running do
        if stillValid and not stillValid() then
            disconnectAll(connections)
            pcall(task.cancel, timer)
            wake:Destroy()
            return nil, "order changed"
        end
        local tool = findOrderTool(order)
        if tool then
            local currentCharacter, humanoid = characterParts()
            if humanoid and tool.Parent ~= currentCharacter then
                humanoid:EquipTool(tool)
                task.wait(0.2)
            end
            disconnectAll(connections)
            pcall(task.cancel, timer)
            wake:Destroy()
            return tool
        end
        if os.clock() >= deadline then break end
        wake.Event:Wait()
    end

    disconnectAll(connections)
    pcall(task.cancel, timer)
    wake:Destroy()
    return nil, "no tool"
end

local function waitForDelivery(order, handPrompt, seconds)
    local deadline = os.clock() + seconds
    local wake = Instance.new("BindableEvent")
    local connections = {}
    local character = player.Character
    local backpack = player:FindFirstChildOfClass("Backpack")
    local function signalChange()
        pcall(function() wake:Fire() end)
    end

    for _, container in ipairs({ character, backpack }) do
        if container then
            table.insert(connections, container.ChildAdded:Connect(signalChange))
            table.insert(connections, container.ChildRemoved:Connect(signalChange))
        end
    end
    if handPrompt.Parent then
        table.insert(connections, handPrompt:GetPropertyChangedSignal("Enabled"):Connect(signalChange))
        table.insert(connections, handPrompt:GetPropertyChangedSignal("ObjectText"):Connect(signalChange))
        table.insert(connections, handPrompt.AncestryChanged:Connect(signalChange))
    end
    local timer = task.delay(seconds, signalChange)

    while control.running do
        local toolGone = findOrderTool(order) == nil
        local promptResolved = handPrompt.Parent == nil
            or not handPrompt.Enabled
            or normalize(handPrompt.ObjectText) ~= normalize(order)
        if toolGone and promptResolved then
            disconnectAll(connections)
            pcall(task.cancel, timer)
            wake:Destroy()
            return true
        end
        if os.clock() >= deadline then break end
        wake.Event:Wait()
    end

    local promptResolved = handPrompt.Parent == nil
        or not handPrompt.Enabled
        or normalize(handPrompt.ObjectText) ~= normalize(order)
    local toolGone = findOrderTool(order) == nil
    disconnectAll(connections)
    pcall(task.cancel, timer)
    wake:Destroy()
    if promptResolved and not toolGone then
        return false, "order changed but the tool is still equipped"
    end
    return false, "tool or prompt is still active"
end

local gui = Instance.new("ScreenGui")
gui.Name = "PeetsCoffeeQA"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 20
gui.Parent = player:WaitForChild("PlayerGui")
control.gui = gui

local function makeUi(className, parent, properties)
    local instance = Instance.new(className)
    for property, value in pairs(properties) do instance[property] = value end
    instance.Parent = parent
    return instance
end

local shell = makeUi("Frame", gui, {
    Name = "Shell", Size = UDim2.new(0.32, 0, 0, 188), AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 18, 0.5, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
})
makeUi("UISizeConstraint", shell, { MinSize = Vector2.new(310, 188), MaxSize = Vector2.new(370, 188) })

local shadow = makeUi("Frame", shell, {
    Name = "Shadow", Size = UDim2.new(1, 8, 1, 10), Position = UDim2.fromOffset(-1, 6),
    BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.48,
    BorderSizePixel = 0, ZIndex = 1,
})
makeUi("UICorner", shadow, { CornerRadius = UDim.new(0, 11) })

local railAura = makeUi("Frame", shell, {
    Name = "RailAura", Size = UDim2.new(0, 28, 1, 12), Position = UDim2.fromOffset(-10, -6),
    BackgroundColor3 = Color3.fromRGB(117, 35, 255), BackgroundTransparency = 0.78,
    BorderSizePixel = 0, Visible = false, ZIndex = 1,
})
makeUi("UICorner", railAura, { CornerRadius = UDim.new(0, 12) })
makeUi("UIGradient", railAura, {
    Rotation = 0,
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.45, 0.45),
        NumberSequenceKeypoint.new(1, 1),
    }),
})

local panel = makeUi("Frame", shell, {
    Name = "Panel", Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.fromRGB(10, 10, 15), BorderSizePixel = 0,
    ClipsDescendants = true, ZIndex = 2,
})
makeUi("UICorner", panel, { CornerRadius = UDim.new(0, 10) })
makeUi("UIGradient", panel, {
    Rotation = 90,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 15, 27)),
        ColorSequenceKeypoint.new(0.48, Color3.fromRGB(11, 11, 17)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 8, 12)),
    }),
})
local panelOutline = makeUi("UIStroke", panel, {
    Color = Color3.fromRGB(116, 112, 126), Transparency = 0.18, Thickness = 1.25,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
})

local accentGlow = makeUi("Frame", panel, {
    Name = "AccentGlow", Size = UDim2.new(0, 34, 1, 0),
    BackgroundColor3 = Color3.fromRGB(113, 34, 255), BackgroundTransparency = 0.68,
    BorderSizePixel = 0, Visible = false, ZIndex = 3,
})
makeUi("UIGradient", accentGlow, {
    Rotation = 0,
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.3, 0.48),
        NumberSequenceKeypoint.new(1, 1),
    }),
})
local accent = makeUi("Frame", panel, {
    Name = "Accent", Size = UDim2.new(0, 5, 1, 0),
    BackgroundColor3 = Color3.fromRGB(92, 31, 214), BorderSizePixel = 0, ZIndex = 4,
})
local accentGradient = makeUi("UIGradient", accent, {
    Rotation = 90,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 12, 55)),
        ColorSequenceKeypoint.new(0.52, Color3.fromRGB(104, 32, 236)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(141, 48, 255)),
    }),
})

local title = makeUi("TextLabel", panel, {
    Size = UDim2.new(1, -126, 0, 28), Position = UDim2.fromOffset(23, 13),
    BackgroundTransparency = 1, Text = "PEETS COFFEE  |  QA",
    TextColor3 = Color3.fromRGB(250, 249, 253), Font = Enum.Font.GothamBold, TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
    TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4,
})

local modeBadge = makeUi("Frame", panel, {
    Name = "ModeBadge", Size = UDim2.fromOffset(70, 25), Position = UDim2.new(1, -90, 0, 14),
    BackgroundColor3 = Color3.fromRGB(25, 25, 32), BorderSizePixel = 0, ZIndex = 4,
})
makeUi("UICorner", modeBadge, { CornerRadius = UDim.new(1, 0) })
local modeBadgeStroke = makeUi("UIStroke", modeBadge, {
    Color = Color3.fromRGB(102, 99, 111), Transparency = 0.48, Thickness = 1,
})
local modeDot = makeUi("Frame", modeBadge, {
    Size = UDim2.fromOffset(7, 7), Position = UDim2.fromOffset(10, 9),
    BackgroundColor3 = Color3.fromRGB(115, 112, 124), BorderSizePixel = 0, ZIndex = 5,
})
makeUi("UICorner", modeDot, { CornerRadius = UDim.new(1, 0) })
local modeText = makeUi("TextLabel", modeBadge, {
    Size = UDim2.new(1, -23, 1, 0), Position = UDim2.fromOffset(22, 0),
    BackgroundTransparency = 1, Text = "IDLE", TextColor3 = Color3.fromRGB(185, 182, 193),
    Font = Enum.Font.GothamBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5,
})

makeUi("Frame", panel, {
    Name = "Divider", Size = UDim2.new(1, -40, 0, 1), Position = UDim2.fromOffset(20, 49),
    BackgroundColor3 = Color3.fromRGB(94, 89, 106), BackgroundTransparency = 0.5,
    BorderSizePixel = 0, ZIndex = 4,
})

local status = makeUi("TextLabel", panel, {
    Size = UDim2.new(1, -40, 0, 52), Position = UDim2.fromOffset(20, 60),
    BackgroundColor3 = Color3.fromRGB(23, 23, 31), BorderSizePixel = 0,
    Text = "Status: stopped", TextColor3 = Color3.fromRGB(207, 205, 217),
    Font = Enum.Font.Gotham, TextSize = 13, TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
    ClipsDescendants = true, ZIndex = 4,
})
makeUi("UICorner", status, { CornerRadius = UDim.new(0, 7) })
makeUi("UIStroke", status, { Color = Color3.fromRGB(102, 96, 116), Transparency = 0.58, Thickness = 1 })
makeUi("UIPadding", status, { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 12) })

local orderLabel = makeUi("TextLabel", panel, {
    Size = UDim2.new(1, -178, 0, 46), Position = UDim2.fromOffset(20, 126),
    BackgroundTransparency = 1, Text = "Order: waiting",
    TextColor3 = Color3.fromRGB(209, 192, 250), Font = Enum.Font.GothamMedium, TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
    TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4,
})
local toggle = makeUi("TextButton", panel, {
    Size = UDim2.fromOffset(132, 44), Position = UDim2.new(1, -152, 0, 127),
    BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
    Text = "", TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = true, ZIndex = 6,
})
makeUi("UICorner", toggle, { CornerRadius = UDim.new(0, 7) })
local toggleFill = makeUi("Frame", toggle, {
    Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0, ZIndex = 4,
})
makeUi("UICorner", toggleFill, { CornerRadius = UDim.new(0, 7) })
local toggleText = makeUi("TextLabel", toggle, {
    Name = "Label", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
    Text = "ACTIVATE", TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 5,
})
local toggleStroke = makeUi("UIStroke", toggle, {
    Color = Color3.fromRGB(190, 218, 204), Transparency = 0.55, Thickness = 1,
})
local toggleGradient = makeUi("UIGradient", toggleFill, {
    Rotation = 90,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(58, 151, 105)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(39, 119, 82)),
    }),
})

local defaultStatusColor = Color3.fromRGB(198, 204, 210)
local lastStatusText = status.Text
local lastStatusColor = status.TextColor3
local lastOrderText = orderLabel.Text

local function setStatus(text, color)
    local fullText = "Status: " .. text
    local nextColor = color or defaultStatusColor
    if fullText == lastStatusText and nextColor == lastStatusColor then return end
    lastStatusText = fullText
    lastStatusColor = nextColor
    status.Text = fullText
    status.TextColor3 = nextColor
end

local function setOrderText(text)
    if text == lastOrderText then return end
    lastOrderText = text
    orderLabel.Text = text
end

local function isWorking()
    return player.Team and player.Team.Name == JOB_NAME
end

local function insideWorkArea()
    local _, _, root = characterParts()
    if not root then return false end
    local prompt = workHere and findPrompt(workHere)
    local center = prompt and promptPosition(prompt)
    if not center then
        local anchor = interactive:FindFirstChild("orderSpot")
            or interactive:FindFirstChild("walkSpot")
            or interactive:FindFirstChildWhichIsA("BasePart", true)
        center = anchor and anchor.Position
    end
    return center ~= nil and (root.Position - center).Magnitude <= WORK_RADIUS
end

local function updateRunningVisuals(running)
    toggleText.Text = running and "STOP" or "ACTIVATE"
    toggleGradient.Color = running and ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(202, 77, 72)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(144, 43, 47)),
    }) or ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(58, 151, 105)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(39, 119, 82)),
    })
    toggleStroke.Color = running and Color3.fromRGB(244, 165, 160) or Color3.fromRGB(190, 218, 204)
    toggleStroke.Transparency = running and 0.42 or 0.55

    railAura.Visible = running
    accentGlow.Visible = running
    accentGradient.Color = running and ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(43, 10, 92)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(118, 35, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(177, 71, 255)),
    }) or ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 12, 55)),
        ColorSequenceKeypoint.new(0.52, Color3.fromRGB(83, 31, 176)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(112, 43, 196)),
    })
    modeText.Text = running and "LIVE" or "IDLE"
    modeText.TextColor3 = running and Color3.fromRGB(226, 211, 255) or Color3.fromRGB(185, 182, 193)
    modeDot.BackgroundColor3 = running and Color3.fromRGB(151, 65, 255) or Color3.fromRGB(115, 112, 124)
    modeBadgeStroke.Color = running and Color3.fromRGB(143, 70, 255) or Color3.fromRGB(102, 99, 111)
    modeBadgeStroke.Transparency = running and 0.16 or 0.48
    panelOutline.Transparency = running and 0.1 or 0.18
end

updateRunningVisuals(control.running)

task.spawn(function()
    local elapsed = 0
    while gui.Parent do
        local delta = task.wait(0.05)
        if control.running then
            elapsed += delta
            local pulse = (math.sin(elapsed * 3.2) + 1) * 0.5
            railAura.BackgroundTransparency = 0.84 - pulse * 0.13
            accentGlow.BackgroundTransparency = 0.75 - pulse * 0.16
            modeDot.BackgroundTransparency = 0.25 - pulse * 0.2
        else
            elapsed = 0
            railAura.BackgroundTransparency = 0.78
            accentGlow.BackgroundTransparency = 0.68
            modeDot.BackgroundTransparency = 0
        end
    end
end)

toggle.MouseButton1Click:Connect(function()
    control.running = not control.running
    updateRunningVisuals(control.running)
    if not control.running then
        if control.restoreCamera then pcall(control.restoreCamera) end
        if control.releaseMovement then pcall(control.releaseMovement) end
        restoreInstantPrompts()
        local _, humanoid, root = characterParts()
        if humanoid and root then humanoid:MoveTo(root.Position) end
        setStatus("stopped")
        setOrderText("Order: waiting")
    end
end)

task.spawn(function()
    while gui.Parent do
        if not control.running then
            restoreInstantPrompts()
            task.wait(0.2)
            continue
        end

        enableInstantPrompts()

        if not isWorking() then
            setStatus("select Work Here first", Color3.fromRGB(255, 177, 74))
            task.wait(0.5)
            continue
        end

        if not insideWorkArea() then
            setStatus("outside work area", Color3.fromRGB(255, 177, 74))
            task.wait(0.5)
            continue
        end

        local handPrompt = findHandPrompt()
        if not handPrompt then
            local leftoverTool = findAnyTool()
            if leftoverTool then
                setOrderText("Obsolete tool: " .. leftoverTool.Name)
                setStatus("carrying " .. leftoverTool.Name .. " to bin")
                local discarded, discardError = discardTool(leftoverTool)
                setStatus(discarded and "Tool removed; waiting for order"
                    or "bin: " .. tostring(discardError),
                    discarded and Color3.fromRGB(107, 221, 154) or Color3.fromRGB(255, 110, 95))
                task.wait(discarded and 0.4 or 1)
                continue
            end
            setStatus("waiting for a valid order")
            setOrderText("Order: waiting")
            task.wait(0.25)
            continue
        end

        local order = handPrompt.ObjectText
        local function stillCurrent()
            return isCurrentOrder(handPrompt, order)
        end
        local function staleOrder()
            if stillCurrent() then return false end
            setStatus("order changed; recalculating", Color3.fromRGB(255, 177, 74))
            task.wait(0.2)
            return true
        end
        setOrderText("Order: " .. tostring(order))

        local obsoleteTool = findObsoleteTool(order)
        if obsoleteTool then
            setStatus("carrying " .. obsoleteTool.Name .. " to bin")
            local discarded, discardError = discardTool(obsoleteTool)
            setStatus(discarded and "Obsolete tool removed; recalculating"
                or "bin: " .. tostring(discardError),
                discarded and Color3.fromRGB(107, 221, 154) or Color3.fromRGB(255, 110, 95))
            task.wait(discarded and 0.4 or 1)
            continue
        end

        local machinePrompt = findMachinePrompt(order)
        if not machinePrompt then
            setStatus("machine not found: " .. tostring(order), Color3.fromRGB(255, 110, 95))
            task.wait(1)
            continue
        end

        local tool = findOrderTool(order)
        local moved, moveError
        local activated, activationError
        if not tool then
            if staleOrder() then continue end
            setStatus("going to machine")
            moved, moveError = moveToPrompt(machinePrompt)
            if not moved then
                setStatus(moveError, Color3.fromRGB(255, 110, 95))
                task.wait(0.8)
                continue
            end

            if staleOrder() then continue end
            for attempt = 1, 2 do
                setStatus("holding E on " .. tostring(order)
                    .. (attempt == 2 and " (retry)" or ""))
                activated, activationError = activatePrompt(machinePrompt, stillCurrent)
                if not activated or not stillCurrent() then break end
                tool, activationError = waitForTool(order, machinePrompt, handPrompt, stillCurrent)
                if tool then break end
                task.wait(0.25)
            end
        else
            local character, humanoid = characterParts()
            if humanoid and tool.Parent ~= character then
                humanoid:EquipTool(tool)
                task.wait(0.2)
            end
        end

        if not tool then
            local changed = not stillCurrent()
            setStatus(changed and "order changed; recalculating" or "the machine did not deliver the tool",
                changed and Color3.fromRGB(255, 177, 74) or Color3.fromRGB(255, 110, 95))
            task.wait(1)
            continue
        end

        if staleOrder() then continue end

        setStatus("going to customer")
        moved, moveError = moveToPrompt(handPrompt)
        if not moved then
            setStatus(moveError, Color3.fromRGB(255, 110, 95))
            task.wait(0.8)
            continue
        end

        if staleOrder() then continue end
        local delivered = false
        local deliveryError = nil
        for attempt = 1, 2 do
            setStatus("holding E to deliver " .. tostring(order)
                .. (attempt == 2 and " (retry)" or ""))
            activated, activationError = activatePrompt(handPrompt, stillCurrent, true)
            if not activated then
                deliveryError = activationError
                break
            end
            delivered, deliveryError = waitForDelivery(order, handPrompt, 4)
            if delivered or not stillCurrent() then break end
            task.wait(0.25)
        end

        if delivered then
            setStatus("delivery confirmed", Color3.fromRGB(107, 221, 154))
            setOrderText("Order: completed")
            task.wait(1)
        else
            setStatus("delivery not confirmed: " .. tostring(deliveryError),
                Color3.fromRGB(255, 110, 95))
            task.wait(0.8)
        end
    end
end)

print("[PeetsCoffee QA v5] UI loaded; select work and press ACTIVATE")