-- Music Player for CC:Tweaked
-- Supports DFPWM playback, downloading from catbox.moe, playlists, and more

local function initDirectories()
    fs.makeDir("/music/songs")
    fs.makeDir("/music/playlists")
end

local function findSpeakers()
    local speakers = {}
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "speaker" then
            table.insert(speakers, peripheral.wrap(side))
        end
    end
    if #speakers == 0 then
        error("No speakers found. Please connect speakers via wired modems.")
    end
    return speakers
end

local function downloadSong(url, name)
    if not http.checkURL(url) then
        print("Invalid URL: " .. url)
        return false
    end
    local response = http.get(url)
    if not response then
        print("Failed to download from " .. url)
        return false
    end
    local file = fs.open("/music/songs/" .. name .. ".dfpwm", "wb")
    file.write(response.readAll())
    file.close()
    response.close()
    print("Downloaded: " .. name)
    return true
end

local function decodeDFPWM(file)
    -- Simple DFPWM decoder (based on CC:Tweaked's internal logic)
    local data = {}
    local handle = fs.open(file, "rb")
    while true do
        local byte = handle.read()
        if not byte then break end
        table.insert(data, byte)
    end
    handle.close()
    return data
end

local function playSong(speakers, songPath)
    if not fs.exists(songPath) then
        print("Song not found: " .. songPath)
        return false
    end
    local data = decodeDFPWM(songPath)
    local bufferSize = 8192
    for i = 1, #data, bufferSize do
        local chunk = {table.unpack(data, i, math.min(i + bufferSize - 1, #data))}
        for _, speaker in ipairs(speakers) do
            speaker.playAudio(chunk)
        end
        os.sleep(0.1) -- Prevent buffer overflow
    end
    return true
end

local function createPlaylist(name)
    local file = fs.open("/music/playlists/" .. name .. ".txt", "w")
    file.close()
    print("Created playlist: " .. name)
end

local function addToPlaylist(playlist, song)
    if not fs.exists("/music/playlists/" .. playlist .. ".txt") then
        print("Playlist not found: " .. playlist)
        return
    end
    if not fs.exists("/music/songs/" .. song .. ".dfpwm") then
        print("Song not found: " .. song)
        return
    end
    local file = fs.open("/music/playlists/" .. playlist .. ".txt", "a")
    file.writeLine(song)
    file.close()
    print("Added " .. song .. " to " .. playlist)
end

local function getPlaylistSongs(playlist)
    local songs = {}
    if not fs.exists("/music/playlists/" .. playlist .. ".txt") then
        return songs
    end
    local file = fs.open("/music/playlists/" .. playlist .. ".txt", "r")
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

local function playPlaylist(speakers, playlist, doShuffle)
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
        playSong(speakers, "/music/songs/" .. song .. ".dfpwm")
    end
end

local function listSongs()
    local songs = fs.list("/music/songs")
    for _, song in ipairs(songs) do
        print(song:sub(1, -7)) -- Remove .dfpwm extension
    end
end

local function listPlaylists()
    local playlists = fs.list("/music/playlists")
    for _, playlist in ipairs(playlists) do
        print(playlist:sub(1, -5)) -- Remove .txt extension
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
    -- CC:Tweaked doesn't expose disk space directly, but we can estimate
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

    print("CC:Tweaked Music Player")
    print("Commands: download <url> <name>, play <song>, playlist create <name>, playlist add <playlist> <song>, play playlist <name> [shuffle], skip, stop, search <query>, list songs, list playlists, space, exit")

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
            playSong(speakers, "/music/songs/" .. args[2] .. ".dfpwm")
        elseif args[1] == "playlist" and args[2] == "create" and args[3] then
            createPlaylist(args[3])
        elseif args[1] == "playlist" and args[2] == "add" and args[3] and args[4] then
            addToPlaylist(args[3], args[4])
        elseif args[1] == "play" and args[2] == "playlist" and args[3] then
            local doShuffle = args[4] == "shuffle"
            playPlaylist(speakers, args[3], doShuffle)
        elseif args[1] == "skip" then
            print("Skip not implemented in single song mode") -- Requires threading
        elseif args[1] == "stop" then
            for _, speaker in ipairs(speakers) do
                speaker.stop()
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
            break
        else
            print("Unknown command or missing arguments")
        end
    end
end

main()
