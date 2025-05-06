-- music_player.lua - All-in-one DFPWM Music Player for CC: Tweaked

local speakerNames = peripheral.getNames()
local speakers = {}

for _, name in ipairs(speakerNames) do
    if peripheral.getType(name) == "speaker" then
        table.insert(speakers, peripheral.wrap(name))
    end
end

if #speakers == 0 then
    print("No speakers found.")
    return
end

local musicDir = "/music"
local songQueue = {}
local isPaused = false
local currentSong = nil

-- GUI Variables
local w, h = term.getSize()
local selectedIndex = 1
local songs = {}

local function loadSongs()
    songs = {}
    if fs.exists(musicDir) and fs.isDir(musicDir) then
        for _, file in ipairs(fs.list(musicDir)) do
            if file:match("%.dfpwm$") then
                table.insert(songs, file)
            end
        end
        table.sort(songs)
    end
end

local function drawUI()
    term.clear()
    term.setCursorPos(1, 1)
    print("🎵 DFPWM Music Player")
    print("--------------------")
    for i, song in ipairs(songs) do
        if i == selectedIndex then
            term.setTextColor(colors.yellow)
            print("> " .. song)
            term.setTextColor(colors.white)
        else
            print("  " .. song)
        end
    end

    print("\n[Enter] Play   [Q] Queue   [Space] Pause/Resume   [Up/Down] Navigate")
    if currentSong then
        print("Now Playing: " .. currentSong)
    end
end

local function playSong(filename)
    currentSong = filename
    local path = fs.combine(musicDir, filename)
    if not fs.exists(path) then return end

    local file = fs.open(path, "rb")
    local decoder = require("cc.audio.dfpwm").make_decoder()
    while true do
        if isPaused then
            os.sleep(0.1)
        else
            local chunk = file.read(16 * 1024)
            if not chunk then break end
            local audio = decoder(chunk)
            for _, sp in ipairs(speakers) do
                while not sp.playAudio(audio) do
                    os.pullEvent("speaker_audio_empty")
                end
            end
        end
    end
    file.close()
    currentSong = nil
end

local function queueManager()
    while true do
        if #songQueue > 0 then
            local nextSong = table.remove(songQueue, 1)
            playSong(nextSong)
        else
            os.sleep(0.5)
        end
    end
end

local function handleInput()
    while true do
        local event, key = os.pullEvent("key")
        if key == keys.up then
            selectedIndex = math.max(1, selectedIndex - 1)
        elseif key == keys.down then
            selectedIndex = math.min(#songs, selectedIndex + 1)
        elseif key == keys.enter then
            table.insert(songQueue, 1, songs[selectedIndex]) -- Play immediately
        elseif key == keys.q then
            table.insert(songQueue, songs[selectedIndex]) -- Add to queue
        elseif key == keys.space then
            isPaused = not isPaused
        end
        drawUI()
    end
end

-- Initial Load
loadSongs()
drawUI()

-- Run GUI and queue manager in parallel
parallel.waitForAny(queueManager, handleInput)
