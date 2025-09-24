local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local character

local REMOTE_KICK = Remotes.getRemote("KickRequest")
local REMOTE_SPRINT = Remotes.getRemote("SprintState")
local REMOTE_SCORE = Remotes.getRemote("ScoreUpdate")

local gui = Instance.new("ScreenGui")

gui.Name = "BallIsAFootHud"

gui.ResetOnSpawn = false

gui.IgnoreGuiInset = true

gui.DisplayOrder = 10

gui.Parent = player:WaitForChild("PlayerGui")

local function createScoreLabel(name : string, anchorX : number)
	local label = Instance.new("TextLabel")
	label.Name = name .. "Score"
	label.AnchorPoint = Vector2.new(anchorX, 0)
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(anchorX, (anchorX == 0) and 20 or -20, 0, 20)
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

local function findNearestBall()
	local origin = getKickOrigin()
	if not origin then
		return nil
	end

	local closest
	local closestDist = Config.KICK_RANGE + 1

	for _, inst in ipairs(workspace:GetChildren()) do
		if inst:IsA("BasePart") and (inst.Name == "Football" or inst.Name == "StinkyFoot") then
			local dist = (inst.Position - origin.Position).Magnitude
			if dist < closestDist then
				closestDist = dist
				closest = inst
			end
		end
	end

	return closest
end

local function kick()
	if not REMOTE_KICK then
		return
	end

	local target = findNearestBall()
	if target then
		REMOTE_KICK:FireServer(target)
	end
end

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

ContextActionService:BindAction("KickBall", onKickAction, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonA)
ContextActionService:BindAction("Sprint", onSprintAction, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)

if UserInputService.TouchEnabled then
	local touchButtonKick = Instance.new("TextButton")
	touchButtonKick.Name = "KickButton"
	touchButtonKick.AnchorPoint = Vector2.new(1, 1)
	touchButtonKick.Position = UDim2.new(1, -32, 1, -32)
	touchButtonKick.Size = UDim2.new(0, 130, 0, 64)
	touchButtonKick.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
	touchButtonKick.TextScaled = true
	touchButtonKick.TextColor3 = Color3.new(1, 1, 1)
	touchButtonKick.Text = "KICK"
	touchButtonKick.Parent = gui
	touchButtonKick.MouseButton1Down:Connect(kick)

	local touchButtonSprint = Instance.new("TextButton")
	touchButtonSprint.Name = "SprintButton"
	touchButtonSprint.AnchorPoint = Vector2.new(0, 1)
	touchButtonSprint.Position = UDim2.new(0, 32, 1, -32)
	touchButtonSprint.Size = UDim2.new(0, 130, 0, 64)
	touchButtonSprint.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
	touchButtonSprint.TextScaled = true
	touchButtonSprint.TextColor3 = Color3.new(1, 1, 1)
	touchButtonSprint.Text = "SPRINT"
	touchButtonSprint.Parent = gui
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
