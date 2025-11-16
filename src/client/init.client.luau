local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local character

local REMOTE_KICK = Remotes.getRemote("KickRequest")
local REMOTE_SPRINT = Remotes.getRemote("SprintState")
local REMOTE_SCORE = Remotes.getRemote("ScoreUpdate")
local REMOTE_WINSCREEN = Remotes.getRemote("WinScreen")

-- Make a GUI
local gui = Instance.new("ScreenGui")

gui.Name = "BallIsAFootHud"

gui.ResetOnSpawn = false

gui.IgnoreGuiInset = true

gui.DisplayOrder = 10

gui.Parent = player:WaitForChild("PlayerGui")

-- Define properties and size of gui
local function createScoreLabel(name : string, anchorX : number)
	local label = Instance.new("TextLabel")
	label.Name = name .. "Score"
	label.AnchorPoint = Vector2.new(anchorX, 0)
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(anchorX, (anchorX == 0) and 20 or -20, 0, 200)
	label.Size = UDim2.new(0, 220, 0, 54)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = string.format("%s: 0", name)
	label.Parent = gui
	return label
end

local redLabel = createScoreLabel("Red", 0)
local blueLabel = createScoreLabel("Blue", 1)

local staminaMax = Config.SPRINT_STAMINA_MAX

local staminaContainer = Instance.new("Frame")
staminaContainer.Name = "StaminaBar"
staminaContainer.AnchorPoint = Vector2.new(0.5, 1)
staminaContainer.Position = UDim2.new(0.5, 0, 1, -40)
staminaContainer.Size = UDim2.new(0, 320, 0, 28)
staminaContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
staminaContainer.BackgroundTransparency = 0.3
staminaContainer.BorderSizePixel = 0
staminaContainer.ClipsDescendants = true
staminaContainer.Parent = gui

local staminaCorner = Instance.new("UICorner")
staminaCorner.CornerRadius = UDim.new(0, 12)
staminaCorner.Parent = staminaContainer

local staminaStroke = Instance.new("UIStroke")
staminaStroke.Thickness = 2
staminaStroke.Color = Color3.fromRGB(0, 170, 255)
staminaStroke.Transparency = 0.35
staminaStroke.Parent = staminaContainer

local staminaFill = Instance.new("Frame")
staminaFill.Name = "Fill"
staminaFill.AnchorPoint = Vector2.new(0, 0)
staminaFill.Position = UDim2.new(0, 0, 0, 0)
staminaFill.Size = UDim2.new(1, 0, 1, 0)
staminaFill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
staminaFill.BorderSizePixel = 0
staminaFill.Parent = staminaContainer

local staminaFillCorner = Instance.new("UICorner")
staminaFillCorner.CornerRadius = UDim.new(0, 12)
staminaFillCorner.Parent = staminaFill

local staminaText = Instance.new("TextLabel")
staminaText.Name = "Value"
staminaText.BackgroundTransparency = 1
staminaText.AnchorPoint = Vector2.new(0.5, 0.5)
staminaText.Position = UDim2.new(0.5, 0, 0.5, 0)
staminaText.Size = UDim2.new(1, -12, 1, -8)
staminaText.Font = Enum.Font.GothamBold
staminaText.TextColor3 = Color3.new(1, 1, 1)
staminaText.TextStrokeTransparency = 0.4
staminaText.TextScaled = true
staminaText.Text = "Stamina"
staminaText.Parent = staminaContainer

local function updateStaminaBar(amount : number)
        local ratio = 0
        if staminaMax > 0 then
                ratio = math.clamp(amount / staminaMax, 0, 1)
        end
        staminaFill.Size = UDim2.new(ratio, 0, 1, 0)
        staminaText.Text = string.format("Stamina %d%%", math.floor(ratio * 100 + 0.5))
end

-- Function that updates scores when REMOTE_SCORE happens
local function updateScores(payload)
        if typeof(payload) ~= "table" then
                return
        end

	local redScore = payload.Red or 0
	local blueScore = payload.Blue or 0

	redLabel.Text = string.format("Red: %d", redScore)
	blueLabel.Text = string.format("Blue: %d", blueScore)
end

if REMOTE_SCORE then
        REMOTE_SCORE.OnClientEvent:Connect(updateScores)
end

-- Adding win screen displaying winning team
local function displayWin(winningTeam)
	local winScreen = playerGui:WaitForChild("WinScreenGui")
	local guiText = winScreen.WinMessage
	guiText.Text = winningTeam .. " team wins!"
	winScreen.Enabled = true
	task.wait(10)
	winScreen.Enabled = false
end

if REMOTE_WINSCREEN then
	REMOTE_WINSCREEN.OnClientEvent:Connect(displayWin)
end

updateStaminaBar(player:GetAttribute("Stamina") or staminaMax)

player:GetAttributeChangedSignal("Stamina"):Connect(function()
        updateStaminaBar(player:GetAttribute("Stamina") or 0)
end)

-- Something to sense if there is a character and its primary part near a kickable object
local function awaitCharacter()
	repeat
		task.wait()
		character = player.Character
	until character and character.PrimaryPart
	return character
end

local function getKickOrigin()
	character = player.Character
	if not character or not character.PrimaryPart then
		character = awaitCharacter()
	end
	return character and character.PrimaryPart or nil
end

local FOOTBALL_NAME = "Football"
local FOOT_NAME = "StinkyFoot"

-- Figuring out where the nearest ball is and if it is in kick range
local function findNearestBall()
	local origin = getKickOrigin()
	if not origin then
		return nil
	end

	local closest
	local closestDist = Config.KICK_RANGE + 1

	local function consider(part)
		if not part or not part:IsA("BasePart") then
			return
		end
		local dist = (part.Position - origin.Position).Magnitude
		if dist < closestDist then
			closestDist = dist
			closest = part
		end
	end

	for _, inst in ipairs(workspace:GetChildren()) do
		if inst:IsA("BasePart") then
			if inst.Name == FOOTBALL_NAME or inst.Name == FOOT_NAME then
				consider(inst)
			end
		elseif inst:IsA("Model") and inst.Name == FOOT_NAME then
			consider(inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart"))
		end
	end

	return closest
end

-- Functions for connecting remote kick to target and registering to serve?
local function kick()
	if not REMOTE_KICK then
		return
	end

	local target = findNearestBall()
	if target then
		REMOTE_KICK:FireServer(target)
	end
end

-- For some reason taking into account if they are sprinting or not?
local sprinting = false

local function setSprinting(state : boolean)
	if sprinting == state then
		return
	end
	sprinting = state
	if REMOTE_SPRINT then
		REMOTE_SPRINT:FireServer(state)
	end
end

local function onKickAction(_, state, input)
	if state == Enum.UserInputState.Begin then
		kick()
	end
	return Enum.ContextActionResult.Sink
end

local function onSprintAction(_, state)
	if state == Enum.UserInputState.Begin then
		setSprinting(true)
	elseif state == Enum.UserInputState.End then
		setSprinting(false)
	end
	return Enum.ContextActionResult.Sink
end

-- Declaring key binding for PC and Console
ContextActionService:BindAction("KickBall", onKickAction, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonA)
ContextActionService:BindAction("Sprint", onSprintAction, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)

if UserInputService.TouchEnabled then
	local touchButtonKick = Instance.new("TextButton")
	touchButtonKick.Name = "KickButton"
	touchButtonKick.AnchorPoint = Vector2.new(1, 1)
	touchButtonKick.Position = UDim2.new(1, -32, .75, -32)
	touchButtonKick.Size = UDim2.new(0, 130, 0, 64)
	touchButtonKick.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
	touchButtonKick.TextScaled = true
	touchButtonKick.TextColor3 = Color3.new(1, 1, 1)
	touchButtonKick.Text = "KICK"
	touchButtonKick.Parent = gui

	local kickCorner = Instance.new("UICorner")
	kickCorner.CornerRadius = UDim.new(0, 12)
	kickCorner.Parent = touchButtonKick

	touchButtonKick.MouseButton1Down:Connect(kick)

	local touchButtonSprint = Instance.new("TextButton")
	touchButtonSprint.Name = "SprintButton"
	touchButtonSprint.AnchorPoint = Vector2.new(1, 1)
	touchButtonSprint.Position = UDim2.new(0.88, -32, 0.75, -10)
	touchButtonSprint.Size = UDim2.new(0, 130, 0, 64)
	touchButtonSprint.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
	touchButtonSprint.TextScaled = true
	touchButtonSprint.TextColor3 = Color3.new(1, 1, 1)
	touchButtonSprint.Text = "SPRINT"
	touchButtonSprint.Parent = gui

	local sprintCorner = Instance.new("UICorner")
	sprintCorner.CornerRadius = UDim.new(0, 12)
	sprintCorner.Parent = touchButtonSprint

	touchButtonSprint.MouseButton1Down:Connect(function()
		setSprinting(true)
	end)
	touchButtonSprint.MouseButton1Up:Connect(function()
		setSprinting(false)
	end)
end

player.CharacterAdded:Connect(function(newChar)
	character = newChar
	setSprinting(false)
end)

awaitCharacter()
updateScores({})

