--[[ DFPWM decoder ported for CC:Tweaked by Computronics team and CC community ]]
local speakerSide = "right" -- or "left", depending on where your speaker is
local filename = "your_song.dfpwm" -- update this to the correct file path

-- DFPWM decoder implementation (standalone)
local function makeDFPWMDecoder()
    local c = {
        l = 0,
        q = 0,
        s = 0
    }

    return function(b)
        local o = {}
        for i = 0, #b - 1 do
            local byte = string.byte(b, i + 1)
            for j = 0, 7 do
                local bit = (bit32.extract(byte, 7 - j, 1) == 1)
                local target = bit and 127 or -128
                local diff = target - c.q
                c.s = c.s + math.floor((diff * c.l + 128) / 256)
                if c.s > 127 then c.s = 127 elseif c.s < -128 then c.s = -128 end
                c.q = c.q + math.floor(c.s)
                if c.q > 127 then c.q = 127 elseif c.q < -128 then c.q = -128 end
                c.l = c.l + (bit and 1 or -1)
                if c.l > 127 then c.l = 127 elseif c.l < 0 then c.l = 0 end
                o[#o+1] = string.char(c.q + 128)
            end
        end
        return table.concat(o)
    end
end

-- Playback function
local function playDFPWM(path, speakerSide)
    if not peripheral.isPresent(speakerSide) or not peripheral.getType(speakerSide):find("speaker") then
        error("No speaker found on side: " .. speakerSide)
    end

    local speaker = peripheral.wrap(speakerSide)
    local decoder = makeDFPWMDecoder()
    local file = fs.open(path, "rb")
    if not file then error("Failed to open file: " .. path) end

    while true do
        local chunk = file.read(512)
        if not chunk then break end
        local decoded = decoder(chunk)
        while not speaker.playAudio(decoded) do
            os.pullEvent("speaker_audio_empty")
        end
    end

    file.close()
end

-- Start playback
playDFPWM(filename, speakerSide)
