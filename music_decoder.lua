-- music_decoder.lua

local decoder = {}

-- Reads a song file and returns a table of notes
function decoder.loadSong(filename)
    if not fs.exists(filename) then
        error("File not found: " .. filename)
    end

    local file = fs.open(filename, "r")
    local song = {}

    while true do
        local line = file.readLine()
        if not line then break end

        local side, delay = line:match("^(%S+)%s+(%S+)$")
        delay = tonumber(delay)
        if side and delay then
            table.insert(song, {side = side, delay = delay})
        end
    end

    file.close()
    return song
end

-- Plays a table of notes using redstone
function decoder.play(song)
    for _, note in ipairs(song) do
        redstone.setOutput(note.side, true)
        sleep(0.1)
        redstone.setOutput(note.side, false)
        sleep(note.delay)
    end
end

return decoder
