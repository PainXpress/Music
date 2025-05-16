local tape = peripheral.find("tape_drive") or error("No tape drive found")
local args = {...}
local song = table.concat(args, " ")

if not song or song == "" then
    print("Usage: ytplay <search query>")
    return
end

local server_ip = "<YOUR_PC_IP>"  -- Replace with your server's IP
local url = "http://" .. server_ip .. ":8080/music?q=" .. textutils.urlEncode(song)
print("Requesting song: " .. song)

local res, err = http.get(url, nil, true)
if not res then
    print("Failed to get response from server: " .. (err or "Unknown error"))
    return
end

if res.getResponseCode() ~= 200 then
    print("Server error: " .. res.readAll())
    res.close()
    return
end

print("Writing to tape...")
tape.stop()
tape.rewind()
tape.seek(-tape.getSize()) -- Clear tape by rewinding to start
while true do
    local chunk = res.read(8192)
    if not chunk then break end
    tape.write(chunk)
end

res.close()
tape.rewind()
print("Playing song!")
tape.play()
