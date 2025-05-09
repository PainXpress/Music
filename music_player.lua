-- Music Player for ComputerCraft 1.80
-- Supports DFPWM playback, downloading from catbox.moe, playlists, and more

local function initDirectories()
    fs.makeDir("/music/songs")
    fs.makeDir("/music/playlists")
end

local function findSpeakers()
    local speakers = {}
    local modems = {}
    print("Scanning for modems...")
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "modem" then
            local modem = peripheral.wrap(side)
            if not modem.isOpen(0) then
                modem.open(0)
                print("Opened modem on: " .. side)
            else
                print("Modem already open on: " .. side)
            end
            table.insert(modems, modem)
        end
    end
    print("Scanning for speakers...")
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "speaker" then
            local speaker = peripheral.wrap(side)
            print("Found speaker on: " .. side)
            print("Speaker methods:")
            for k, v in pairs(speaker) do
                print("  " .. k .. ": " .. type(v))
            end
            if speaker.playAudio then
                print("Speaker supports playback")
                table.insert(speakers, speaker)
            else
                print("Speaker does NOT support playback (missing playAudio)")
                print("This may indicate an incompatible speaker or version mismatch.")
                print("Expected: ComputerCraft 1.80+ speaker (crafted with 4 iron ingots and 1 note block).")
            end
        end
    end
    if #speakers == 0 then
        print("WARNING: No compatible speakers found. Playback will not work.")
        print("You can still use download, playlist, and other features.")
    end
    return speakers
end

local function sanitizeName(name)
    return name:gsub("[^%w%-_]", ""):gsub("^%s*(.-)%s*$", "%1")
end

local function downloadSong(url, name)
    if not http.checkURL(url) then
        print("Invalid URL format: " .. url)
        return false
    end
    local response, err = http.get(url)
    if not response then
        print("Download failed: " .. (err or "Unknown error"))
        return false
    end
    local sanitizedName = sanitizeName(name)
    if sanitizedName == "" then
        print("Invalid song name")
        response.close()
        return false
    end
    local filePath = "/music/songs/" .. sanitizedName .. ".dfpwm"
    if fs.exists(filePath) then
        print("Song already exists: " .. sanitizedName)
        response.close()
        return false
    end
    local file = fs.open(filePath, "wb")
    file.write(response.readAll())
    file.close()
    response.close()
    print("Downloaded: " .. sanitizedName)
    return true
end

local function playSong(speakers, songPath, playbackState)
    if #speakers == 0 then
        print("Cannot play: No compatible speakers available.")
        return false
    end
    if not fs.exists(songPath) then
        print("Song not found: " .. songPath)
        return false
    end
    local file = fs.open(songPath, "rb")
    if not file then
        print("Failed to open song: " .. songPath)
        return false
    end
    playbackState.playing = true
    playbackState.paused = false
    local bufferSize = 8192
    while playbackState.playing do
        if not playbackState.paused then
            local chunk = {}
            for i = 1, bufferSize do
                local byte = file.read()
                if not byte then
                    playbackState.playing = false
                    break
                end
                chunk[i] = byte
            end
            if #chunk > 0 then
                for _, speaker in ipairs(speakers) do
                    if speaker.playAudio then
                        speaker.playAudio(chunk)
                    else
                        print("Playback failed: Speaker lacks playAudio method.")
                        playbackState.playing = false
                        break
                    end
                end
            end
        end
        coroutine.yield()
    end
    file.close()
    playbackState.playing = false
    playbackState.paused = false
    return true
end

local function createPlaylist(name)
    local sanitizedName = sanitizeName(name)
    if sanitizedName == "" then
        print("Invalid playlist name")
        return
    end
    local file = fs.open("/music/playlists/" .. sanitizedName .. ".txt", "w")
    file.close()
    print("Created playlist: " .. sanitizedName)
end

local function addToPlaylist(playlist, song)
    local playlistPath = "/music/playlists/" .. sanitizeName(playlist) .. ".txt"
    local songPath = "/music/songs/" .. sanitizeName(song) .. ".dfpwm"
    if not fs.exists(playlistPath) then
        print("Playlist not found: " .. playlist)
        return
    end
    if not fs.exists(songPath) then
        print("Song not found: " .. song)
        return
    end
    local file = fs.open(playlistPath, "a")
    file.writeLine(sanitizeName(song))
    file.close()
    print("Added " .. song .. " to " .. playlist)
end

local function getPlaylistSongs(playlist)
    local songs = {}
    local playlistPath = "/music/playlists/" .. sanitizeName(playlist) .. ".txt"
    if not fs.exists(playlistPath) then
        return songs
    end
    local file = fs.open(playlistPath, "r")
    while true do
        local line = file.readLine()
        if not line then break end
        table.insert(songs, line)
    end
    file.close()
    return songs
end

local function shuffle(t)
    local n = #t
    for i = n, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function playPlaylist(speakers, playlist, doShuffle, playbackState)
    if #speakers == 0 then
        print("Cannot play: No compatible speakers available.")
        return
    end
    local songs = getPlaylistSongs(playlist)
    if #songs == 0 then
        print("Playlist is empty: " .. playlist)
        return
    end
    if doShuffle then
        songs = shuffle(songs)
    end
    for i, song in ipairs(songs) do
        print("Playing: " .. song)
        playSong(speakers, "/music/songs/" .. song .. ".dfpwm", playbackState)
        if playbackState.skip then
            playbackState.skip = false
        end
    end
end

local function listSongs()
    local songs = fs.list("/music/songs")
    for _, song in ipairs(songs) do
        print(song:sub(1, -7))
    end
end

local function listPlaylists()
    local playlists = fs.list("/music/playlists")
    for _, playlist in ipairs(playlists) do
        print(playlist:sub(1, -5))
    end
end

local function searchSongs(query)
    local songs = fs.list("/music/songs")
    for _, song in ipairs(songs) do
        if string.find(song:lower(), query:lower()) then
            print(song:sub(1, -7))
        end
    end
end

local function checkSpace()
    local songs = fs.list("/music/songs")
    local totalSize = 0
    for _, song in ipairs(songs) do
        totalSize = totalSize + fs.getSize("/music/songs/" .. song)
    end
    print("Total size of songs: " .. totalSize .. " bytes")
end

local function main()
    initDirectories()
    local speakers = findSpeakers()
    math.randomseed(os.time())
    local playbackState = { playing = false, paused = false, skip = false }
    local playbackThread = nil

    local function startPlayback(fn)
        if playbackState.playing then
            print("Stopping current playback")
            playbackState.playing = false
            playbackState.skip = false
            playbackState.paused = false
        end
        playbackThread = coroutine.create(fn)
        coroutine.resume(playbackThread)
    end

    print("ComputerCraft Music Player")
    print("Commands: download <url> <name>, play <song>, playlist create <name>, playlist add <playlist> <song>, play playlist <name> [shuffle], pause, skip, stop, search <query>, list songs, list playlists, space, exit")

    while true do
        write("> ")
        local input = read()
        local args = {}
        for word in input:gmatch("%S+") do
            table.insert(args, word)
        end

        if args[1] == "download" and args[2] and args[3] then
            downloadSong(args[2], args[3])
        elseif args[1] == "play" and args[2] then
            startPlayback(function()
                playSong(speakers, "/music/songs/" .. sanitizeName(args[2]) .. ".dfpwm", playbackState)
            end)
        elseif args[1] == "playlist" and args[2] == "create" and args[3] then
            createPlaylist(args[3])
        elseif args[1] == "playlist" and args[2] == "add" and args[3] and args[4] then
            addToPlaylist(args[3], args[4])
        elseif args[1] == "play" and args[2] == "playlist" and args[3] then
            local doShuffle = args[4] == "shuffle"
            startPlayback(function()
                playPlaylist(speakers, args[3], doShuffle, playbackState)
            end)
        elseif args[1] == "pause" then
            if playbackState.playing then
                playbackState.paused = not playbackState.paused
                print(playbackState.paused and "Paused" or "Resumed")
            else
                print("No song is playing")
            end
        elseif args[1] == "skip" then
            if playbackState.playing then
                playbackState.skip = true
                playbackState.paused = false
                print("Skipping")
            else
                print("No song is playing")
            end
        elseif args[1] == "stop" then
            if playbackState.playing then
                playbackState.playing = false
                playbackState.paused = false
                playbackState.skip = false
                for _, speaker in ipairs(speakers) do
                    if speaker.stop then
                        speaker.stop()
                    end
                end
                print("Stopped")
            else
                print("No song is playing")
            end
        elseif args[1] == "search" and args[2] then
            searchSongs(args[2])
        elseif args[1] == "list" and args[2] == "songs" then
            listSongs()
        elseif args[1] == "list" and args[2] == "playlists" then
            listPlaylists()
        elseif args[1] == "space" then
            checkSpace()
        elseif args[1] == "exit" then
            if playbackState.playing then
                playbackState.playing = false
                for _, speaker in ipairs(speakers) do
                    if speaker.stop then
                        speaker.stop()
                    end
                end
            end
            break
        else
            print("Unknown command or missing arguments")
        end

        if playbackThread and coroutine.status(playbackThread) == "suspended" then
            coroutine.resume(playbackThread)
        end
    end
end

main()
