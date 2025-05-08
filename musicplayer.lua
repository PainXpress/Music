-- MusicPlayer.lua
-- A ComputerCraft music player (no GUI) using DFPWM1a files, queue, playlists, and Rednet-driven multi-speaker support

-- CONFIGURATION --
local config = {
  modemSide        = "back",      -- side with modem
  speakersChannel  = 65535,        -- Rednet channel for audio streams
  songDir          = "songs/",    -- directory with .dfpwm audio files
  playlistDir      = "playlists/",-- directory with playlist files (serialized Lua tables)
  chunkSize        = 8192,         -- bytes per audio chunk
  volume           = 0.5,          -- default volume (0.0 to 1.0)
  repeatMode       = "none",      -- none | one | all
}

-- DEPENDENCIES --
local fs     = fs
local rednet = rednet
local dfpwm  = require("cc.audio.dfpwm")

-- STATE --
local queue = {}
local currentIndex = 1
local playing = false
local paused = false

--------------------------------------------------------------------------------
-- Initialization --
--------------------------------------------------------------------------------
local function initRednet()
  if not rednet.isOpen(config.modemSide) then rednet.open(config.modemSide) end
end

--------------------------------------------------------------------------------
-- Audio Streaming to Speakers --
--------------------------------------------------------------------------------
local function streamAudio(filename)
  local path = config.songDir .. filename
  if not fs.exists(path) then error("Song not found: " .. filename) end

  local file = fs.open(path, "rb")
  local decoder = dfpwm.makeDecoder()

  while playing do
    if not paused then
      local chunk = file.read(config.chunkSize)
      if not chunk or #chunk == 0 then break end

      -- Broadcast raw DFPWM chunk
      rednet.broadcast({ type = "dfpwm", data = chunk, vol = config.volume }, config.speakersChannel)

      -- Optional local preview
      local pcm = decoder(chunk)
      speaker.playAudio(pcm, config.volume)
    end
    sleep(0.05)
  end

  file.close()
end

--------------------------------------------------------------------------------
-- Playback Control --
--------------------------------------------------------------------------------
local function startSong(name)
  playing = true
  paused = false
  print("Playing: " .. name)
  streamAudio(name)

  -- After stream ends
  if playing then
    if config.repeatMode == "one" then
      startSong(name)
    else
      currentIndex = currentIndex + 1
      if currentIndex > #queue then
        if config.repeatMode == "all" then
          currentIndex = 1
        else
          playing = false
          return
        end
      end
      startSong(queue[currentIndex])
    end
  end
end

local function pauseSong()
  if playing then paused = true; print("Paused") end
end

local function resumeSong()
  if playing and paused then paused = false; print("Resumed") end
end

local function stopSong()
  if playing then
    playing = false
    print("Stopped")
  end
end

local function nextSong()
  stopSong()
  currentIndex = currentIndex + 1
  if currentIndex > #queue then
    if config.repeatMode == "all" then currentIndex = 1 else return end
  end
  startSong(queue[currentIndex])
end

local function prevSong()
  stopSong()
  currentIndex = math.max(1, currentIndex - 1)
  startSong(queue[currentIndex])
end

local function addSong(name)
  table.insert(queue, name)
  print("Added: " .. name)
end

local function loadPlaylist(name)
  local path = config.playlistDir .. name
  if not fs.exists(path) then error("Playlist not found: " .. name) end
  local content = fs.open(path, "r"):readAll()
  local list    = textutils.unserialize(content)
  if type(list) ~= "table" then error("Invalid playlist format") end
  queue = list
  currentIndex = 1
  print("Playlist loaded: " .. name)
end

--------------------------------------------------------------------------------
-- CLI Interface --
--------------------------------------------------------------------------------
local function showHelp()
  print("Commands:")
  print(" play <file|playlist>  - start file or load playlist")
  print(" pause                 - pause current song")
  print(" resume                - resume paused song")
  print(" stop                  - stop playback")
  print(" next                  - skip to next song")
  print(" prev                  - back to previous song")
  print(" add <file>            - add a file to queue")
  print(" list                  - list available .dfpwm files")
  print(" queue                 - show current queue")
  print(" mode <none|one|all>   - set repeat mode")
  print(" search <pattern>      - search songs by filename")
  print(" volume <0.0-1.0>      - set volume level")
  print(" save <name>           - save current queue as playlist")
  print(" help                  - this help")
  print(" exit                  - quit player")
end

local function listSongs()
  for _,f in ipairs(fs.list(config.songDir)) do
    if f:sub(-6):lower() == ".dfpwm" then print(f) end
  end
end

local function listQueue()
  for i,name in ipairs(queue) do
    print((i == currentIndex and ">") or " ", name)
  end
end

local function savePlaylist(name)
  local path = config.playlistDir .. name
  local f = fs.open(path, "w")
  f.write(textutils.serialize(queue))
  f.close()
  print("Playlist saved: " .. name)
end

local function handleCommand(input)
  local args = {}
  for w in input:gmatch("%S+") do table.insert(args, w) end
  local cmd = table.remove(args, 1)
  if cmd == "play" then
    local t = args[1]
    if t and t:sub(-6):lower() == ".dfpwm" then
      queue = { t }
      currentIndex = 1
      startSong(t)
    else
      loadPlaylist(t)
      startSong(queue[1])
    end
  elseif cmd == "pause" then
    pauseSong()
  elseif cmd == "resume" then
    resumeSong()
  elseif cmd == "stop" then
    stopSong()
  elseif cmd == "next" then
    nextSong()
  elseif cmd == "prev" then
    prevSong()
  elseif cmd == "add" then
    addSong(args[1])
  elseif cmd == "list" then
    listSongs()
  elseif cmd == "queue" then
    listQueue()
  elseif cmd == "mode" then
    config.repeatMode = args[1]
  elseif cmd == "volume" then
    local v = tonumber(args[1])
    if v and v >= 0 and v <= 1 then
      config.volume = v
      print("Volume set to " .. v)
    else
      print("Invalid volume. Use 0.0 to 1.0")
    end
  elseif cmd == "search" then
    for _,f in ipairs(fs.list(config.songDir)) do
      if f:lower():find(args[1]:lower()) then print(f) end
    end
  elseif cmd == "save" then
    savePlaylist(args[1])
  elseif cmd == "help" then
    showHelp()
  elseif cmd == "exit" then
    stopSong()
    rednet.close(config.modemSide)
    return false
  else
    print("Unknown command. Type 'help'.")
  end
  return true
end

--------------------------------------------------------------------------------
-- Main --
--------------------------------------------------------------------------------
initRednet()
print("DFPWM Music Player Ready. Type 'help'.")
while true do
  write("> ")
  local line = read()
  if not handleCommand(line) then break end
end

-- Speaker-side listener (run on each speaker machine):
--
-- rednet.open(config.modemSide)
-- local decoder = dfpwm.makeDecoder()
-- while true do
--   local id,msg = rednet.receive(config.speakersChannel)
--   if msg.type=="dfpwm" then
--     local pcm = decoder(msg.data)
--     speaker.playAudio(pcm, msg.vol)
--   end
-- end
