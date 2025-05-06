-- music_player.lua - Full Music Downloader & Player for CC: Tweaked
local username = "PainXpress"
local repo = "Music"
local branch = "main"
local songsTxtPath = "songs.txt"
local baseRaw = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(username, repo, branch)

local musicDir = "/music"
local songQueue, songs = {}, {}
local selectedIndex, isPaused, currentSong = 1, false, nil

-- Detect and wrap speakers
local speakers = {}
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "speaker" then
        table.insert(speakers, peripheral.wrap(name))
    end
end
if #speakers == 0 then print("No speakers found!") return end

-- Download songs.txt
local function downloadSongList()
    local url = baseRaw .. songsTxtPath
    local res = http.get(url)
    if not res then print("Failed to fetch songs.txt") return false end

    local list = res.readAll()
    res.close()
    songs = {}
    for song in list:gmatch("[^\r\n]+") do
        if song:match("%.dfpwm$") then table.insert(songs, song) end
    end
    return true
end

-- Download a single song
local function downloadSong(song)
    local songURL = baseRaw .. song
    local savePath = fs.combine(musicDir, fs.getName(song))
    if fs.exists(savePath) then return true end

    local res = http.get(songURL)
    if not res then print("Failed: " .. song) return false end
    local data = res.readAll()
    res.close()

    local f = fs.open(savePath, "wb")
    f.write(data)
    f.close()
    print("Downloaded: " .. song)
    return true
end

-- Download all songs in list
local function syncSongs()
    if not fs.exists(musicDir) then fs.makeDir(musicDir) end
    for _, song in ipairs(songs) do
        downloadSong(song)
    end
end

-- GUI
local function drawUI()
    term.clear()
    term.setCursorPos(1, 1)
    print("🎵 DFPWM Music Player")
    print("---------------------")
    for i, song in ipairs(songs) do
        if i == selectedIndex then
            term.setTextColor(colors.yellow)
            print("> " .. song)
            term.setTextColor(colors.white)
        else
            print("  " .. song)
        end
    end
    print("\n[Enter] Play  [Q] Queue  [Space] Pause/Resume  [Up/Down] Scroll")
    if currentSong then print("Now Playing: " .. currentSong) end
end

-- Song player
local function playSong(filename)
    currentSong = filename
    local path = fs.combine(musicDir, filename)
    if not fs.exists(path) then return end

    local decoder = require("cc.audio.dfpwm").make_decoder()
    local file = fs.open(path, "rb")

    while true do
        if isPaused then os.sleep(0.1)
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

-- Queue manager
local function queueManager()
    while true do
        if #songQueue > 0 then
            local next = table.remove(songQueue, 1)
            playSong(next)
        else
            os.sleep(0.2)
        end
    end
end

-- Input handler
local function inputHandler()
    while true do
        local e, k = os.pullEvent("key")
        if k == keys.up then
            selectedIndex = math.max(1, selectedIndex - 1)
        elseif k == keys.down then
            selectedIndex = math.min(#songs, selectedIndex + 1)
        elseif k == keys.enter then
            table.insert(songQueue, 1, songs[selectedIndex])
        elseif k == keys.q then
            table.insert(songQueue, songs[selectedIndex])
        elseif k == keys.space then
            isPaused = not isPaused
        end
        drawUI()
    end
end

-- Main
print("Fetching song list...")
if not downloadSongList() then return end
print("Syncing music files...")
syncSongs()
drawUI()
parallel.waitForAny(queueManager, inputHandler)
