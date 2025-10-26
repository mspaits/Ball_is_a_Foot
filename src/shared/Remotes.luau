local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Creates an array to list remotes? I assume.
local Remotes = {}

--[[ Gets remotes folder in replicated storage.  Why can't you just specify ReplicatedStorage.Remotes?  
Note: specifying <Remotes.> adds this function to the the table, making it usable across scripts. ]]
function Remotes.getFolder()
	return ReplicatedStorage:WaitForChild("Remotes")
end

-- Gets Remotes folder, finds remote corresponding to arguement name, checks if it is there, returns name of remote.
function Remotes.getRemote(name : string)
	local folder = Remotes.getFolder()
	local remote = folder:FindFirstChild(name)
	if not remote then
		warn(("[Remotes] Missing remote '%s'"):format(name))
	end
	return remote
end

-- Makes the module and functions contained in it reusable in any script
return Remotes
