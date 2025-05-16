local http = require("http")
local tape = peripheral.find("tape_drive") or error("No tape drive found")
local song = ...

if not song then
    print("Usage: ytplay <search query>")
    return
end

local url = "http://47.32.232.30:8080/music?q=" .. textutils.urlEncode(song)
print("Requesting song from server...")

local res = http.get(url, nil, true)
if not res then
    print("Failed to get response from server.")
    return
end

print("Writing to tape...")
tape.stop()
tape.rewind()
tape.seek(-tape.getSize()) -- Clear tape
while true do
    local chunk = res.read(8192)
    if not chunk then break end
    tape.write(chunk)
end

res.close()
tape.rewind()
print("Playing!")
tape.play()
