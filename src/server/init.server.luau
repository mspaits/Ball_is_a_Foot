local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TeamsService = game:GetService("Teams")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

-- Both module scripts in ReplicatedStorage
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local REMOTE_KICK = Remotes.getRemote("KickRequest")
local REMOTE_SPRINT = Remotes.getRemote("SprintState")
local REMOTE_SCORE = Remotes.getRemote("ScoreUpdate")
local REMOTE_WINSCREEN = Remotes.getRemote("WinScreen")

-- Define names of football and stinky foot
local FOOTBALL_NAME = "Football"
local FOOTBALL_TEMPLATE = "FootballTemplate"
local FOOT_NAME = "StinkyFoot"
local FOOT_TEMPLATE = "StinkyFootTemplate"

-- Get players on team
local function ensureTeam(name : string, color : BrickColor)
	local team = TeamsService:FindFirstChild(name)
	if team then
		return team
	end

	team = Instance.new("Team")
	team.Name = name
	team.TeamColor = color
	team.AutoAssignable = false
	team.Parent = TeamsService
	return team
end

local TEAM_RED = ensureTeam("Red", BrickColor.new("Bright red"))
local TEAM_BLUE = ensureTeam("Blue", BrickColor.new("Bright blue"))

-- Creating dictionary to hold team score
local scoreByTeam = {
	[TEAM_RED] = 0,
	[TEAM_BLUE] = 0,
}

local gameOver = false

local SPINNER_CONTAINER_NAMES = {
	"SpinnerWedge",
	"Spinner",
	"SpinnerWedgeMover",
}

local SPINNER_RAGDOLL_DURATION = 2.5
local SPINNER_RAGDOLL_COOLDOWN = 1
local SPINNER_FLING_HORIZONTAL = 75
local SPINNER_FLING_UP = 55
local spinnerContainersHooked : {[Instance]: boolean} = {}

-- Adding points to team
local function broadcastScore()
	if REMOTE_SCORE then
		REMOTE_SCORE:FireAllClients({
			[TEAM_RED.Name] = scoreByTeam[TEAM_RED],
			[TEAM_BLUE.Name] = scoreByTeam[TEAM_BLUE],
		})
	end
end

local function ragdollCharacter(character : Model, duration : number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if character:FindFirstChild("__TempRagdoll") then
		return
	end

	local tag = Instance.new("Folder")
	tag.Name = "__TempRagdoll"
	tag.Parent = character

	local constraintsFolder = Instance.new("Folder")
	constraintsFolder.Name = "RagdollConstraints"
	constraintsFolder.Parent = tag

	for _, motor in ipairs(character:GetDescendants()) do
		if motor:IsA("Motor6D") then
			local part0 = motor.Part0
			local part1 = motor.Part1
			if part0 and part1 then
				local att0 = Instance.new("Attachment")
				att0.Name = "__RagdollAttachment0"
				att0.CFrame = motor.C0
				att0.Parent = part0

				local att1 = Instance.new("Attachment")
				att1.Name = "__RagdollAttachment1"
				att1.CFrame = motor.C1
				att1.Parent = part1

				local socket = Instance.new("BallSocketConstraint")
				socket.Attachment0 = att0
				socket.Attachment1 = att1
				socket.LimitsEnabled = true
				socket.TwistLimitsEnabled = true
				socket.UpperAngle = 45
				socket.TwistLowerAngle = -45
				socket.TwistUpperAngle = 45
				socket.Parent = constraintsFolder

				motor.Enabled = false
			end
		end
	end

	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	humanoid.PlatformStand = true

	task.delay(duration, function()
		if humanoid.Parent and humanoid.Health > 0 then
			for _, motor in ipairs(character:GetDescendants()) do
				if motor:IsA("Motor6D") then
					motor.Enabled = true
				end
			end

			for _, attachment in ipairs(character:GetDescendants()) do
				if attachment:IsA("Attachment") and (attachment.Name == "__RagdollAttachment0" or attachment.Name == "__RagdollAttachment1") then
					attachment:Destroy()
				end
			end

			if tag.Parent then
				tag:Destroy()
			end

			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

local function flingCharacterFromPart(character : Model, spinnerPart : BasePart)
	local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
	if not root or not root:IsA("BasePart") then
		return
	end

	local dir = root.Position - spinnerPart.Position
	if dir.Magnitude < 0.1 then
		dir = spinnerPart.CFrame.LookVector
	end
	dir = dir.Unit

	local impulse = (dir * SPINNER_FLING_HORIZONTAL + Vector3.new(0, SPINNER_FLING_UP, 0)) * root.AssemblyMass
	root:ApplyImpulse(impulse)
end

local recentSpinnerHits : {[Model]: number} = {}

local function onSpinnerTouched(spinnerPart : BasePart, hit : BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = tick()
	local lastHit = recentSpinnerHits[character]
	if lastHit and now - lastHit < SPINNER_RAGDOLL_COOLDOWN then
		return
	end
	recentSpinnerHits[character] = now

	ragdollCharacter(character, SPINNER_RAGDOLL_DURATION)
	flingCharacterFromPart(character, spinnerPart)
end

local function hookSpinnerContainer(container : Instance)
	if spinnerContainersHooked[container] then
		return
	end
	spinnerContainersHooked[container] = true

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Touched:Connect(function(hit)
				onSpinnerTouched(descendant, hit)
			end)
		end
	end

	container.DescendantAdded:Connect(function(instance)
		if instance:IsA("BasePart") then
			instance.Touched:Connect(function(hit)
				onSpinnerTouched(instance, hit)
			end)
		end
	end)
end

for _, name in ipairs(SPINNER_CONTAINER_NAMES) do
	for _, child in ipairs(Workspace:GetChildren()) do
		if child.Name == name then
			hookSpinnerContainer(child)
		end
	end
end

Workspace.ChildAdded:Connect(function(child)
	for _, name in ipairs(SPINNER_CONTAINER_NAMES) do
		if child.Name == name then
			hookSpinnerContainer(child)
			break
		end
	end
end)

local function explodeCharacter(character : Model)
	local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
	if not root or not root:IsA("BasePart") then
		return
	end

	local explosion = Instance.new("Explosion")
	explosion.Position = root.Position
	explosion.BlastRadius = 10
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = Workspace
	Debris:AddItem(explosion, 2)
end

local function killLosingTeam(winningTeam : Team)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Team ~= winningTeam then
			local character = player.Character
			if character then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					explodeCharacter(character)
					humanoid.Health = 0
				else
					character:Destroy()
				end
			end
		end
	end
end

local function displayWin(winningTeam : Team)
	if gameOver then
		return
	end

	gameOver = true
	print(winningTeam.Name .. " wins")

	if REMOTE_WINSCREEN then
		REMOTE_WINSCREEN:FireAllClients(winningTeam.Name)
	end

	-- Let the win register on-screen, then eliminate the losing team
	task.wait(3)
	killLosingTeam(winningTeam)

	-- Keep the win screen up a bit longer before resetting scores
	task.wait(7)
	scoreByTeam[TEAM_RED] = 0
	scoreByTeam[TEAM_BLUE] = 0
	broadcastScore()
	gameOver = false
end

local function addScore(team : Team, points : number)
	if gameOver then
		return
	end

	if not scoreByTeam[team] then
		return
	end

	scoreByTeam[team] += points
	print(('[Score] %s +%d | Red=%d Blue=%d'):format(team.Name, points, scoreByTeam[TEAM_RED], scoreByTeam[TEAM_BLUE]))
	broadcastScore()

	for team, score in pairs(scoreByTeam) do
		if team == TEAM_RED and score >= Config.POINT_END_GAME then
			displayWin(TEAM_RED)
		elseif team == TEAM_BLUE and score >= Config.POINT_END_GAME then
			displayWin(TEAM_BLUE)
		end
	end
end

-- Assigning joining players to a team, removing disconnecting players
Players.PlayerAdded:Connect(function(player)
	local redCount = #TEAM_RED:GetPlayers()
	local blueCount = #TEAM_BLUE:GetPlayers()
	player.Team = (blueCount <= redCount) and TEAM_BLUE or TEAM_RED
	player.Neutral = false
	player:SetAttribute("Sprinting", false)
end)

Players.PlayerRemoving:Connect(function(player)
	player:SetAttribute("Sprinting", nil)
end)

local TEAM_INDICATOR_NAME = "TeamIndicator"

local function getTeamColor(team : Team?)
	if team and team.TeamColor then
		return team.TeamColor.Color
	end
	return Color3.fromRGB(200, 200, 200)
end

local function applyTeamIndicator(player : Player, character : Model)
	local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 5)
	if not head or not head:IsA("BasePart") then
		return
	end

	local existing = head:FindFirstChild(TEAM_INDICATOR_NAME)
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = TEAM_INDICATOR_NAME
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(16, 16)
	billboard.StudsOffset = Vector3.new(0, 1.2, 0)
	billboard.Parent = head

	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromScale(1, 1)
	dot.BackgroundColor3 = getTeamColor(player.Team)
	dot.BorderSizePixel = 0
	dot.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		applyTeamIndicator(player, character)
	end)
	if player.Character then
		applyTeamIndicator(player, player.Character)
	end

	player:GetPropertyChangedSignal("Team"):Connect(function()
		local character = player.Character
		if not character then
			return
		end
		local head = character:FindFirstChild("Head")
		if not head then
			return
		end
		local indicator = head:FindFirstChild(TEAM_INDICATOR_NAME)
		if indicator then
			local dot = indicator:FindFirstChildWhichIsA("Frame")
			if dot then
				dot.BackgroundColor3 = getTeamColor(player.Team)
			end
		else
			applyTeamIndicator(player, character)
		end
	end)
end)

-- A function for randomly assigning a kick vector?
local function randomUnitXZ()
	local theta = math.random() * math.pi * 2
	return Vector3.new(math.cos(theta), 0, math.sin(theta))
end

-- Moves up in ancestry from the specified instance until it finds the instance that matches the specified target name.  Otherwise it returns nil.
local function findAncestorNamed(inst : Instance, target : string)
	local current = inst
	while current do
		if current.Name == target then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Identify the thing to kick and its asemply info
local function getAssemblyInfo(part : BasePart)
	local footModel = findAncestorNamed(part, FOOT_NAME)
	if footModel and footModel:IsA("Model") then
		local primary = footModel.PrimaryPart or footModel:FindFirstChildWhichIsA("BasePart") or part
		return "StinkyFoot", footModel, primary
	end

	if part.Name == FOOT_NAME then
		return "StinkyFoot", nil, part
	end

	local footballModel = findAncestorNamed(part, FOOTBALL_NAME)
	if footballModel and footballModel:IsA("Model") then
		local primary = footballModel.PrimaryPart or footballModel:FindFirstChildWhichIsA("BasePart") or part
		return "Football", footballModel, primary
	end

	if part.Name == FOOTBALL_NAME then
		return "Football", nil, part
	end

	return nil, nil, part
end

-- Defines kick impulse to apply to the football or foot.
local function applyImpulseToAssembly(part : BasePart, impulse : Vector3)
	local _, footModel, primaryPart = getAssemblyInfo(part)
	local target = primaryPart or part
	target:ApplyImpulse(impulse * target.AssemblyMass)

	if footModel then
		for _, descendant in ipairs(footModel:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant ~= target then
				descendant:ApplyImpulse(impulse * descendant:GetMass())
			end
		end
	end
end

-- Defines angle of impulse to apply to football or foot.
local function applyAngularImpulse(part : BasePart, angularImpulse : Vector3)
	local _, footModel, primaryPart = getAssemblyInfo(part)
	local target = primaryPart or part
	target:ApplyAngularImpulse(angularImpulse * target.AssemblyMass)

	if footModel then
		for _, descendant in ipairs(footModel:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant ~= target then
				descendant:ApplyAngularImpulse(angularImpulse * descendant:GetMass())
			end
		end
	end
end

-- Applies the kick in predefined amount and angle
local function applyKick(targetPart : BasePart, forceDirection : Vector3, style : string?)
	local normalized = forceDirection.Magnitude > 0 and forceDirection.Unit or randomUnitXZ()

	local sidewaysScalar = Config.KICK_RANDOM_SIDE
	local upwardBias = Config.KICK_UPWARD_BIAS
	local forceMultiplier = 1

	if style == "straight" then
		sidewaysScalar = sidewaysScalar * 0.5
		upwardBias = Config.KICK_STRAIGHT_UPWARD_BIAS or Config.KICK_UPWARD_BIAS * 0.25
		forceMultiplier = Config.KICK_STRAIGHT_FORCE_MULTIPLIER or 1
	end

	local base = normalized * Config.KICK_BASE_FORCE * forceMultiplier
	local sideways = randomUnitXZ() * sidewaysScalar * Config.KICK_BASE_FORCE * forceMultiplier
	local upward = Vector3.new(0, upwardBias * Config.KICK_BASE_FORCE * forceMultiplier, 0)
	local impulse = base + sideways + upward

	applyImpulseToAssembly(targetPart, impulse)

	local axis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	if axis.Magnitude < 1e-3 then
		axis = Vector3.new(0, 1, 0)
	end
	local angularImpulse = axis.Unit * Config.KICK_RANDOM_TORQUE
	applyAngularImpulse(targetPart, angularImpulse)
end

--  Handles and approves remote kick request
if REMOTE_KICK then
	REMOTE_KICK.OnServerEvent:Connect(function(player, target, style)
		if typeof(target) ~= "Instance" or not target:IsA("BasePart") then
			return
		end

		local kind = select(1, getAssemblyInfo(target))
		if kind ~= "Football" and kind ~= "StinkyFoot" then
			return
		end

		local character = player.Character
		local primary = character and character.PrimaryPart
		if not primary then
			return
		end

		local distance = (target.Position - primary.Position).Magnitude
		if distance > Config.KICK_RANGE then
			return
		end

		local direction = (target.Position - primary.Position)
		if style ~= "straight" then
			style = "lob"
		end
		applyKick(target, direction, style)
	end)
end

-- Manages sprint mechanic and stamina
local staminaByPlayer : {[Player]: number} = {}

local function setWalkSpeed(player : Player, speed : number)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

-- Handles setting sprint stats and stamina for joining players
Players.PlayerAdded:Connect(function(player)
        staminaByPlayer[player] = Config.SPRINT_STAMINA_MAX
        player:SetAttribute("Stamina", Config.SPRINT_STAMINA_MAX)
        player.CharacterAdded:Connect(function()
                staminaByPlayer[player] = Config.SPRINT_STAMINA_MAX
                player:SetAttribute("Stamina", Config.SPRINT_STAMINA_MAX)
                setWalkSpeed(player, 16)
        end)
end)

Players.PlayerRemoving:Connect(function(player)
        staminaByPlayer[player] = nil
        player:SetAttribute("Stamina", nil)
end)

-- Lets player sprint if they have enough stamina
if REMOTE_SPRINT then
	REMOTE_SPRINT.OnServerEvent:Connect(function(player, isSprinting)
		if staminaByPlayer[player] and staminaByPlayer[player] > 0 then
			player:SetAttribute("Sprinting", isSprinting and true or false)
		end
	end)
end

-- Drains stamina from sprinting person
task.spawn(function()
	while true do
		task.wait(0.1)
		for player, current in pairs(staminaByPlayer) do
			local sprinting = player:GetAttribute("Sprinting") == true
			if sprinting then
				current = math.max(0, current - Config.SPRINT_STAMINA_DRAIN * 0.1)
				if current <= 0 then
					player:SetAttribute("Sprinting", false)
					setWalkSpeed(player, 16)
				else
					setWalkSpeed(player, Config.SPRINT_SPEED)
				end
			else
				current = math.min(Config.SPRINT_STAMINA_MAX, current + Config.SPRINT_STAMINA_REGEN * 0.1)
				setWalkSpeed(player, 16)
                        end
                        staminaByPlayer[player] = current
                        local replicated = player:GetAttribute("Stamina")
                        if replicated ~= current then
                                player:SetAttribute("Stamina", current)
                        end
                end
        end
end)

-- Ball and foot spawing position
local spawnFolder = Workspace:FindFirstChild("BallSpawnPoints")

local function chooseSpawnCFrame()
	if not spawnFolder then
		return CFrame.new(0, 6, 0)
	end
	local children = spawnFolder:GetChildren()
	if #children == 0 then
		return CFrame.new(0, 6, 0)
	end
	local marker = children[math.random(1, #children)]
	if marker:IsA("BasePart") then
		return marker.CFrame
	elseif marker:IsA("Attachment") then
		return marker.WorldCFrame
	end
	return CFrame.new(0, 6, 0)
end

local recentRespawns : {[BasePart]: number} = {}

-- ??  This seems like a lot of code for managing ball and foot spawning.
local function resetAssembly(target : Instance)
	if target:IsA("BasePart") then
		target.AssemblyLinearVelocity = Vector3.zero
		target.AssemblyAngularVelocity = Vector3.zero
	elseif target:IsA("Model") then
		for _, descendant in ipairs(target:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.AssemblyLinearVelocity = Vector3.zero
				descendant.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end

local function tagRecent(target : Instance, timestamp : number)
	if target:IsA("BasePart") then
		recentRespawns[target] = timestamp
	elseif target:IsA("Model") then
		for _, descendant in ipairs(target:GetDescendants()) do
			if descendant:IsA("BasePart") then
				recentRespawns[descendant] = timestamp
			end
		end
	end
end

local function respawnBall(part : BasePart)
	local kind, footModel, primary = getAssemblyInfo(part)
	local now = tick()

	if kind == "StinkyFoot" and footModel then
		footModel:PivotTo(Config.RESPAWN_CFRAME)
		resetAssembly(footModel)
		tagRecent(footModel, now)
		return
	end

	local basePart = primary or part
	basePart.CFrame = Config.RESPAWN_CFRAME
	resetAssembly(basePart)
	recentRespawns[basePart] = now
end

local function spawnTemplate(templateName : string, desiredName : string)
	local template = ServerStorage:FindFirstChild(templateName)
	if not template then
		warn(('[Spawner] Missing template %s in ServerStorage'):format(templateName))
		return nil
	end

	local clone = template:Clone()
	clone.Name = desiredName
	clone.Parent = Workspace

	local spawnCFrame = chooseSpawnCFrame()
	local now = tick()

	if clone:IsA("BasePart") then
		clone.CFrame = spawnCFrame
		resetAssembly(clone)
		tagRecent(clone, now)
		return clone
	elseif clone:IsA("Model") then
		local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
		if not primary then
			warn(('[Spawner] Template %s has no BasePart to position'):format(templateName))
			clone:Destroy()
			return nil
		end
		clone.PrimaryPart = primary
		clone:PivotTo(spawnCFrame)
		resetAssembly(clone)
		tagRecent(clone, now)
		return clone
	else
		warn(('[Spawner] Template %s must be a BasePart or Model'):format(templateName))
		clone:Destroy()
		return nil
	end
end

-- Spawn ball and foot
local function spawnFootball()
	return spawnTemplate(FOOTBALL_TEMPLATE, FOOTBALL_NAME)
end

local function spawnStinkyFoot()
	return spawnTemplate(FOOT_TEMPLATE, FOOT_NAME)
end

-- Adds balls and feet to spawn
local function countActiveBalls()
	local total = 0
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("BasePart") and child.Name == FOOTBALL_NAME then
			total += 1
		elseif child:IsA("Model") and child.Name == FOOT_NAME then
			total += 1
		end
	end
	return total
end

-- Controls timing of spawning and number of balls in play
task.spawn(function()
	while true do
		task.wait(Config.FOOTBALL_SPAWN_INTERVAL)

		local count = countActiveBalls()
		if count >= Config.MAX_FOOTBALLS then
			continue
		end

		if math.random() < Config.STINKY_FOOT_CHANCE then
			spawnStinkyFoot()
		else
			spawnFootball()
		end
	end
end)

local function hookGoal(goalPart : BasePart?, team : Team, basePoints : number, stinkyFootPoints : number?)
	if not goalPart then
		warn(('[Goals] Missing goal part for %s'):format(team.Name))
		return
	end

	goalPart.Touched:Connect(function(hit)
		if not hit:IsA("BasePart") then
			return
		end

		local kind, _footModel, rootPart = getAssemblyInfo(hit)
		if not kind then
			return
		end
		
		local keyPart = rootPart or hit
		local lastRespawn = recentRespawns[hit] or recentRespawns[keyPart]
		if lastRespawn and tick() - lastRespawn < Config.BALL_RESPAWN_LOCK then
			return
		end

		local points = basePoints
		if kind == "StinkyFoot" then
			points = stinkyFootPoints
			if not points then
				return
			end
		end

		addScore(team, points)
		respawnBall(keyPart)
	end)
end
hookGoal(Workspace:FindFirstChild("Goal_Red_Soccer"), TEAM_RED, Config.POINT_SOCCER_GOAL, Config.POINT_STINKY_FOOT)
hookGoal(Workspace:FindFirstChild("Goal_Blue_Soccer"), TEAM_BLUE, Config.POINT_SOCCER_GOAL, Config.POINT_STINKY_FOOT)
hookGoal(Workspace:FindFirstChild("Goal_Red_Posts"), TEAM_RED, Config.POINT_FIELD_GOAL_FOOTBALL, Config.POINT_FIELD_GOAL_STINKY_FOOT)
hookGoal(Workspace:FindFirstChild("Goal_Blue_Posts"), TEAM_BLUE, Config.POINT_FIELD_GOAL_FOOTBALL, Config.POINT_FIELD_GOAL_STINKY_FOOT)

broadcastScore()


