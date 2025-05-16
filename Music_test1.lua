-- Configuration
local filename = "encoded-20250417030525.txt" -- Updated to new DFPWM file path

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
                -- Extract bit (Lua 5.1 compatible)
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

-- Auto-detect speaker
local function findSpeaker()
    local sides = peripheral.getNames()
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "speaker" then
            print("Speaker found on side: " .. side)
            return side
        end
    end
    return nil
end

-- Playback function using playSound with note block sounds
local function playDFPWM(path)
    -- Find speaker
    local speakerSide = findSpeaker()
    if not speakerSide then
        error("No speaker peripheral found. Use the 'peripherals' command to check connected devices.")
    end

    local speaker = peripheral.wrap(speakerSide)
    if not speaker then
        error("Failed to wrap speaker peripheral on side: " .. speakerSide)
    end

    -- Check for playSound support
    if not speaker.playSound then
        error("Speaker peripheral does not support playSound method. Check speaker compatibility.")
    end
    print("playSound method supported")

    local decoder = makeDFPWMDecoder()

    -- Open file
    local file = fs.open(path, "rb")
    if not file then
        error("Failed to open file: " .. path .. ". Check if file exists and path is correct. Use 'ls' to list files.")
    end

    -- Read and play in chunks
    local chunkSize = 256
    while true do
        local chunk = file.read(chunkSize)
        if not chunk or #chunk == 0 then break end

        local decoded = decoder(chunk)
        if #decoded == 0 then
            print("Warning: Decoded chunk is empty, skipping.")
            break
        end

        -- Approximate audio with note block sounds
        for i = 1, #decoded do
            local sample = string.byte(decoded, i) - 128 -- Convert back to signed (-128 to 127)
            -- Map sample to pitch (0.5 to 2.0, corresponding to note block pitches)
            local pitch = 0.5 + (sample + 128) / 255 * 1.5 -- Range: 0.5 to 2.0
            -- Play a note using a Minecraft note block sound
            speaker.playSound("minecraft:block.note_block.harp", 1.0, pitch)
            print("Decoding chunk " .. i) -- Debugging print
            os.sleep(0.001) -- Small delay to prevent overlap
        end
    end

    file.close()
    print("Playback finished (note approximation).")
end

-- Run with error handling
local success, err = pcall(function()
    playDFPWM(filename)
end)

if not success then
    printError("Error: " .. tostring(err))
end
