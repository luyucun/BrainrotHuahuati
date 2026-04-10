--[[
Script: ModuleLoader
Type: ModuleScript
Studio path: ReplicatedStorage/Shared/ModuleLoader
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModuleLoader = {}

local function resolveSharedModuleScript(moduleName)
    local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
    if sharedFolder then
        local moduleInShared = sharedFolder:FindFirstChild(moduleName)
        if moduleInShared and moduleInShared:IsA("ModuleScript") then
            return moduleInShared
        end
    end

    local moduleInRoot = ReplicatedStorage:FindFirstChild(moduleName)
    if moduleInRoot and moduleInRoot:IsA("ModuleScript") then
        return moduleInRoot
    end

    return nil
end

function ModuleLoader.requireSharedModule(requesterName, moduleName)
    local moduleScript = resolveSharedModuleScript(moduleName)
    if moduleScript then
        return require(moduleScript)
    end

    error(string.format(
        "[%s] Missing shared module %s (expected in ReplicatedStorage/Shared or ReplicatedStorage root)",
        tostring(requesterName or "ModuleLoader"),
        tostring(moduleName or "")
    ))
end

function ModuleLoader.resolveSharedModuleScript(moduleName)
    return resolveSharedModuleScript(moduleName)
end

return ModuleLoader
