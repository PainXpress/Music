-- Configuration
local speakerSide = "right" -- Change to "left" or other side if needed
local filename = "your_song.dfpwm" -- Ensure this matches your DFPWM file path

-- DFPWM decoder (standalone, Lua 5.1 compatible)
local function makeDFPWMDecoder()
    local state = {
        l = 0, -- Low-pass filter
        q = 0, -- Current output sample
        s = 0  -- Integrator state
    }

    return function(input)
        local output = {}
        for i = 1, #input do
            local byte = string.byte(input, i)
            for j = 0, 7 do
                -- Extract bit (Lua 5.1 compatible, no bit32)
                local bit = math.floor(byte / 2^(7 - j)) % 2 == 1
                local target = bit and 127 or -128
                local diff = target - state.q
                state.s = state.s + math.floor((diff * state.l + 128) / 256)
                if state.s > 127 then state.s = 127 elseif state.s < -128 then state.s = -128 end
                state.q = state.q + math.floor(state.s)
                if state.q > 127 then state.q = 127 elseif state.q < -128 then state.q = -128 end
                state.l = state.l + (bit and 1 or -1)
                if state.l > 127 then state.l = 127 elseif state.l < 0 then state.l = 0 end
                output[#output + 1] = string.char(state.q + 128)
            end
        end
        return table.concat(output)
    end
end

-- Playback function
local function playDFPWM(path, speakerSide)
    -- Verify speaker
    if not peripheral.isPresent(speakerSide) then
        error("No peripheral found on side: " .. speakerSide)
    end
    if peripheral.getType(speakerSide) ~= "speaker" then
        error("Peripheral on side " .. speakerSide .. " is not a speaker")
    end

    local speaker = peripheral.wrap(speakerSide)
    local decoder = makeDFPWMDecoder()

    -- Open file
    local file = fs.open(path, "rb")
    if not file then
        error("Failed to open file: " .. path .. ". Check if file exists and path is correct.")
    end

    -- Read and play in chunks
    local chunkSize = 256 -- Smaller chunk size for smoother playback
    while true do
        local chunk = file.read(chunkSize)
        if not chunk or #chunk == 0 then break end

        -- Decode chunk (1 byte DFPWM -> 8 bytes PCM)
        local decoded = decoder(chunk)
        if #decoded == 0 then
            print("Warning: Decoded chunk is empty, skipping.")
            break
        end

        -- Play audio, wait for speaker buffer to clear
        local success = speaker.playAudio(decoded)
        while not success do
            os.pullEvent("speaker_audio_empty")
            success = speaker.playAudio(decoded)
        end
    end

    file.close()
    print("Playback finished.")
end

-- Run with error handling
local success, err = pcall(function()
    playDFPWM(filename, speakerSide)
end)

if not success then
    printError("Error: " .. tostring(err))
end
