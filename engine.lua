-- [[ SIMPAN FILE INI SEBAGAI: engine.lua DI GITHUB ]]
local Engine = {} -- Module Table

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
local SavedCP = 0
local SavedFrame = 1
local END_CP = 1000
local CurrentRepoURL = ""

-- [[ INTERNAL HELPER FUNCTIONS ]] --

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
    local myPos = LocalPlayer.Character.HumanoidRootPart.Position
    local bestCP = SavedCP
    local bestFrame = SavedFrame
    local bestPos = myPos
    local minDist = math.huge
    
    for i = 0, #TASDataCache do
        local data = TASDataCache[i]
        if data then
            for f = 1, #data, 10 do
                local frame = data[f]
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
    return bestCP, bestFrame, bestPos, minDist
end

local function WalkToTarget(targetPos)
    local Char = LocalPlayer.Character
    local Hum = Char:FindFirstChild("Humanoid")
    local Root = Char:FindFirstChild("HumanoidRootPart")
    
    Hum.AutoRotate = true
    Hum.PlatformStand = false
    Root.Anchored = false
    local oldSpeed = Hum.WalkSpeed 
    Hum.WalkSpeed = 60 -- Lari ke titik start
    
    while isPlaying do
        local dist = (Root.Position - targetPos).Magnitude
        if dist < 5 then break end 
        Hum:MoveTo(targetPos)
        if Root.Position.Y < -50 then Root.CFrame = CFrame.new(targetPos) break end
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
        local success, response = pcall(function() return game:HttpGet(url) end)
        if success then
            local decodeSuccess, data = pcall(function() return HttpService:JSONDecode(response) end)
            if decodeSuccess then TASDataCache[i] = data end
        else
            break -- File habis/404
        end
        if i % 5 == 0 then RunService.Heartbeat:Wait() end
        count = count + 1
    end
    return count > 0
end

local function RunPlaybackLogic()
    local foundCP, foundFrame, foundPos, dist = FindClosestPoint()
    if dist > 5 then WalkToTarget(foundPos) end
    
    SavedCP = foundCP
    SavedFrame = foundFrame
    
    local Char = LocalPlayer.Character
    local Hum = Char:FindFirstChild("Humanoid")
    local Root = Char:FindFirstChild("HumanoidRootPart")

    while isPlaying do
        Root.Anchored = false
        Hum.PlatformStand = false 
        Hum.AutoRotate = false
        
        for i = SavedCP, #TASDataCache do
            if not isPlaying then break end
            SavedCP = i
            local data = TASDataCache[i]
            if not data then continue end
            
            for f = SavedFrame, #data do
                if not isPlaying then break end
                SavedFrame = f 
                local frame = data[f]
                if not Char or not Root then isPlaying = false break end

                -- 1. Auto Height Fix
                local recordedHip = frame.HIP or 2
                local currentHip = Hum.HipHeight
                if currentHip <= 0 then currentHip = 2 end
                local heightDiff = currentHip - recordedHip
                
                -- 2. Posisi CFrame
                local posX = frame.POS.x
                local posY = frame.POS.y + heightDiff 
                local posZ = frame.POS.z
                local rotY = frame.ROT or 0
                Root.CFrame = CFrame.new(posX, posY, posZ) * CFrame.Angles(0, rotY, 0)

                -- 3. FORCE ANIMASI LARI (Velocity + State)
                if frame.VEL then
                    Root.AssemblyLinearVelocity = Vector3.new(frame.VEL.x, frame.VEL.y, frame.VEL.z)
                else
                    Root.AssemblyLinearVelocity = Vector3.zero
                end
                
                -- FORCE STATE RUNNING DI SETIAP FRAME
                Hum:ChangeState(Enum.HumanoidStateType.Running)

                -- Handle Jump/Freefall jika diperlukan
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
            if isPlaying then SavedFrame = 1 end 
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

-- [[ EXPOSED FUNCTIONS (YANG DIPANGGIL UI) ]] --

function Engine.SetURL(url)
    if CurrentRepoURL ~= url then
        CurrentRepoURL = url
        isCached = false -- Reset cache jika ganti track
        SavedCP = 0
        TASDataCache = {}
    end
end

function Engine.SetLoop(state)
    isLooping = state
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
                return "Error"
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
        task.wait(0.1)
        ResetCharacter()
        return "Stopped"
    end
    return "AlreadyStopped"
end

return Engine
