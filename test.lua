-- Music Player for CC:Tweaked
-- Supports direct DFPWM playback through speakers, downloading from catbox.moe, playlists, and more

local dfpwm = require("cc.audio.dfpwm")

local function initDirectories()
    fs.makeDir("/music/songs")
    fs.makeDir("/music/playlists")
end

local function findSpeakers()
    local speakers = {}
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
            end
        end
    end
    if #speakers == 0 then
        error("No compatible speakers found. Playback requires a speaker with playAudio support.")
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
    if not fs.exists(songPath) then
        print("Song not found: " .. songPath)
        return false
    end
    local file = fs.open(songPath, "rb")
    if not file then
        print("Failed to open song: " .. songPath)
        return false
    end
    local decoder = dfpwm.make_decoder()
    playbackState.playing = true
    playbackState.paused = false
    local bufferSize = 8192
    while playbackState.playing do
        if not playbackState.paused then
            local chunk = file.read(bufferSize)
            if not chunk then
                playbackState.playing = false
                break
            end
            local decoded = decoder(chunk)
            if #decoded > 0 then
                for _, speaker in ipairs(speakers) do
                    speaker.playAudio(decoded)
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

    print("CC:Tweaked Music Player (Direct Playback)")
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
                    speaker.stop()
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
                    speaker.stop()
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
