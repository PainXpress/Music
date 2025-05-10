-- ComputerCraft music player for YouTube audio
-- Requires: Speaker peripheral, HTTP enabled

local speaker = peripheral.find("speaker")
if not speaker then
    error("Speaker peripheral required")
end

-- Custom bitwise functions for Lua 5.1 compatibility
local function rshift(x, n)
    return math.floor(x / 2^n)
end

local function band(x, y)
    local p = 1
    local z = 0
    while p <= x and p <= y do
        if math.floor(x / p) % 2 == 1 and math.floor(y / p) % 2 == 1 then
            z = z + p
        end
        p = p * 2
    end
    return z
end

-- DFPWM decoder (adapted for Lua 5.1)
local function dfpwm_decoder()
    local filter = 0
    local level = 0
    local function decoder(bit)
        local target = bit * 128
        if filter < target then
            filter = math.min(filter + math.max((target - filter) / 2, 1), target)
        elseif filter > target then
            filter = math.max(filter - math.max((filter - target) / 2, 1), target)
        end
        local q = filter > level and 1 or 0
        level = level + (q * 256 - level) / 4
        return q
    end
    return function(data)
        local output = {}
        for i = 1, #data do
            local byte = data:byte(i)
            for j = 0, 7 do
                local bit = band(rshift(byte, 7 - j), 1) -- Replaced (byte >> (7 - j)) & 1
                output[#output + 1] = decoder(bit)
            end
        end
        return output
    end
end

-- Main program
print("Enter YouTube link:")
local youtube_url = read()

-- Replace with your server's IP and port
local server_url = "https://973d-2600-6c56-9940-21-ed65-22f1-aad0-ccaa.ngrok-free.app"
local response, err = http.post(server_url, textutils.serializeJSON({url = youtube_url}))

if not response then
    error("Failed to contact server: " .. (err or "Unknown error"))
end

local dfpwm_data = response.readAll()
response.close()

if not dfpwm_data or #dfpwm_data == 0 then
    error("No DFPWM data received")
end

-- Decode DFPWM
local decode = dfpwm_decoder()
local decoded = decode(dfpwm_data)

-- Play audio (also fixing the table.concat issue from earlier)
local buffer = ""
for i = 1, #decoded do
    buffer = buffer .. decoded[i]
    if #buffer >= 8192 then
        speaker.playAudio(buffer)
        while not speaker.playAudio("") do
            os.pullEvent("speaker_audio_empty")
        end
        buffer = ""
    end
end
-- Play any remaining data
if #buffer > 0 then
    speaker.playAudio(buffer)
    while not speaker.playAudio("") do
        os.pullEvent("speaker_audio_empty")
    end
end

print("Playback complete!")
