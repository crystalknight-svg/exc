-- [[ ENGINE START - SAFE MODE ]]
local Engine = {} 

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- Internal Variables
local TASDataCache = {}
local isCached = false
local isPlaying = false
local isLooping = false
local isFlipped = false
local SavedCP = 0
local SavedFrame = 1
local END_CP = 1000
local CurrentRepoURL = ""

-- [[ INTERNAL FUNCTIONS ]] --

local function ResetCharacter()
    local Char = LocalPlayer.Character
    if Char then
        local Hum = Char:FindFirstChild("Humanoid")
        local Root = Char:FindFirstChild("HumanoidRootPart")
        if Hum then
            Hum.PlatformStand = false
            Hum.AutoRotate = true
            Hum:ChangeState(Enum.HumanoidStateType.Running)
        end
        if Root then
            Root.Anchored = false
            Root.AssemblyLinearVelocity = Vector3.zero
            Root.AssemblyAngularVelocity = Vector3.zero
        end
    end
end

local function FindClosestPoint()
    local Char = LocalPlayer.Character
    if not Char then
        return SavedCP, SavedFrame, Vector3.zero, math.huge
    end

    local Root = Char:FindFirstChild("HumanoidRootPart")
    if not Root then
        return SavedCP, SavedFrame, Vector3.zero, math.huge
    end

    local myPos = Root.Position
    local bestCP = SavedCP
    local bestFrame = SavedFrame
    local bestPos = myPos
    local minDist = math.huge
    
    for i, data in pairs(TASDataCache) do
        if data then
            for f = 1, #data, 10 do
                local frame = data[f]
                if frame and frame.POS then
                    local fPos = Vector3.new(frame.POS.x, frame.POS.y, frame.POS.z)
                    local dist = (myPos - fPos).Magnitude
                    if dist < minDist then
                        minDist = dist
                        bestCP = i
                        bestFrame = f
                        bestPos = fPos
                    end
                end
            end
        end
    end

    return bestCP, bestFrame, bestPos, minDist
end

local function WalkToTarget(targetPos)
    local Char = LocalPlayer.Character
    if not Char then return end
    
    local Hum = Char:FindFirstChild("Humanoid")
    local Root = Char:FindFirstChild("HumanoidRootPart")
    if not Hum or not Root then return end

    Hum.AutoRotate = true
    Hum.PlatformStand = false
    Root.Anchored = false

    local oldSpeed = Hum.WalkSpeed 
    Hum.WalkSpeed = 60 
    
    while isPlaying do
        if not Root.Parent then break end
        
        local dist = (Root.Position - targetPos).Magnitude
        if dist < 5 then break end 
        
        Hum:MoveTo(targetPos)
        
        if Root.Position.Y < -50 then 
            Root.CFrame = CFrame.new(targetPos) 
            break 
        end
        RunService.Heartbeat:Wait()
    end

    Hum.WalkSpeed = oldSpeed 
end

local function DownloadData(repoURL)
    local count = 0
    TASDataCache = {}
    
    for i = 0, END_CP do
        if not isPlaying then return false end

        local url = repoURL .. "cp_" .. i .. ".json"
        local success, response = pcall(function()
            return game:HttpGet(url)
        end)
        
        if success then
            local decodeSuccess, data = pcall(function()
                return HttpService:JSONDecode(response)
            end)
            if decodeSuccess then
                TASDataCache[i] = data
                count = count + 1
            end
        else
            break
        end
        
        if i % 10 == 0 then
            RunService.Heartbeat:Wait()
        end
    end

    return count > 0
end

local function RunPlaybackLogic()
    local foundCP, foundFrame, foundPos, dist = FindClosestPoint()
    if dist > 5 then
        WalkToTarget(foundPos)
    end
    
    SavedCP = foundCP
    SavedFrame = foundFrame
    
    local Char = LocalPlayer.Character
    if not Char then return end

    local Hum = Char:FindFirstChild("Humanoid")
    local Root = Char:FindFirstChild("HumanoidRootPart")
    if not Hum or not Root then return end

    while isPlaying do
        Root.Anchored = false
        Hum.PlatformStand = false
        Hum.AutoRotate = false
        
        for i, data in pairs(TASDataCache) do
            if not isPlaying then break end
            SavedCP = i
            
            if data then
                for f = SavedFrame, #data do
                    if not isPlaying then break end
                    SavedFrame = f
                    
                    local frame = data[f]
                    if not frame or not frame.POS then continue end
                    
                    -- [LOGIC 1] Auto Height
                    local recordedHip = frame.HIP or 2
                    local currentHip = Hum.HipHeight
                    if currentHip <= 0 then currentHip = 2 end
                    local heightDiff = currentHip - recordedHip
                    
                    -- [LOGIC 2] Position & Rotation
                    local posX = frame.POS.x
                    local posY = frame.POS.y + heightDiff
                    local posZ = frame.POS.z
                    local rotY = frame.ROT or 0
                    
                    if isFlipped then
                        rotY = rotY + math.pi
                    end
                    
                    Root.CFrame =
                        CFrame.new(posX, posY, posZ)
                        * CFrame.Angles(0, rotY, 0)

                    -- [LOGIC 3] Velocity
                    if frame.VEL then
                        local vel = Vector3.new(frame.VEL.x, frame.VEL.y, frame.VEL.z)
                        if isFlipped then
                            vel = Vector3.new(-vel.X, vel.Y, -vel.Z)
                        end
                        Root.AssemblyLinearVelocity = vel
                    else
                        Root.AssemblyLinearVelocity = Vector3.zero
                    end
                    
                    -- Force Running State
                    if Hum:GetState() ~= Enum.HumanoidStateType.Running then
                        Hum:ChangeState(Enum.HumanoidStateType.Running)
                    end
                    
                    if frame.STA then
                        local s = frame.STA
                        if s == "Jumping" then
                            Hum:ChangeState(Enum.HumanoidStateType.Jumping)
                            Hum.Jump = true
                        elseif s == "Freefall" then
                            Hum:ChangeState(Enum.HumanoidStateType.Freefall)
                        elseif s == "Landed" then
                            Hum:ChangeState(Enum.HumanoidStateType.Landed)
                        end
                    end
                    
                    RunService.Heartbeat:Wait()
                end
                
                if isPlaying then
                    SavedFrame = 1
                end
            end
        end

        if isPlaying then
            if isLooping then
                SavedCP = 0
                SavedFrame = 1
            else
                isPlaying = false
                SavedCP = 0
                SavedFrame = 1
                ResetCharacter()
                break
            end
        else
            break
        end
    end
end

-- [[ EXPOSED FUNCTIONS ]] --

function Engine.SetURL(url)
    if CurrentRepoURL ~= url then
        CurrentRepoURL = url
        isCached = false
        SavedCP = 0
        SavedFrame = 1
        TASDataCache = {}
    end
end

function Engine.SetLoop(state)
    isLooping = state
end

function Engine.SetFlip(state)
    isFlipped = state
end

function Engine.Play()
    if isPlaying then return "Running" end
    if CurrentRepoURL == "" then return "NoURL" end
    
    isPlaying = true
    
    task.spawn(function()
        if not isCached then
            local success = DownloadData(CurrentRepoURL)
            if not success then
                isPlaying = false
                return
            end
            isCached = true
        end
        RunPlaybackLogic()
    end)

    return "Started"
end

function Engine.Stop()
    if isPlaying then
        isPlaying = false
        task.wait()
        ResetCharacter()
        return "Stopped"
    end
    return "AlreadyStopped"
end

return Engine
