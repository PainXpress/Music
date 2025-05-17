local tape = peripheral.find("tape_drive") or error("No tape drive found")
local args = {...}
local url = args[1]  -- Take the first argument as the YouTube URL

if not url or url == "" then
    print("Usage: Music2 <YouTube URL>")
    return
end

print("Sending URL to server: " .. url)

-- Send the URL to the Python server
local server_ip = "162.120.185.230"  -- Your public IP
local request_url = "http://" .. server_ip .. ":8080/music?url=" .. textutils.urlEncode(url)
local res, err = http.get(request_url, nil, true)
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
