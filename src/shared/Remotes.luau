local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

function Remotes.getFolder()
	return ReplicatedStorage:WaitForChild("Remotes")
end

function Remotes.getRemote(name : string)
	local folder = Remotes.getFolder()
	local remote = folder:FindFirstChild(name)
	if not remote then
		warn(("[Remotes] Missing remote '%s'"):format(name))
	end
	return remote
end

return Remotes
