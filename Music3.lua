local tape = peripheral.find("tape_drive") or error("No tape drive found")
print("[DEBUG] Tape drive found: " .. tostring(tape))

local args = {...}
print("[DEBUG] Raw args received: " .. textutils.serialize(args))

local url = args[1]
print("[DEBUG] Extracted URL: " .. (url or "nil"))

if not url or url == "" then
    print("[DEBUG] URL is empty or nil, triggering usage message")
    print("Usage: Music2 <YouTube URL>")
    return
end

print("[DEBUG] URL is valid, proceeding with request")
local server_ip = "162.120.185.230"
print("[DEBUG] Server IP set to: " .. server_ip)
local request_url = "http://" .. server_ip .. ":8080/music?url=" .. textutils.urlEncode(url)
print("[DEBUG] Constructed request URL: " .. request_url)

local res, err = http.get(request_url, nil, true)
print("[DEBUG] HTTP request completed, res: " .. tostring(res) .. ", err: " .. tostring(err))

if not res then
    print("[DEBUG] Failed to get response, error details: " .. (err or "Unknown error"))
    print("Failed to get response from server: " .. (err or "Unknown error"))
    return
end

print("[DEBUG] Response object obtained, getting response code")
local response_code = res.getResponseCode()
print("[DEBUG] Response code: " .. tostring(response_code))

if response_code ~= 200 then
    print("[DEBUG] Non-200 response code detected")
    print("Server error: " .. res.readAll())
    res.close()
    print("[DEBUG] Response closed due to error")
    return
end

print("[DEBUG] Response is OK (200), starting tape write")
print("Writing to tape...")
tape.stop()
print("[DEBUG] Tape stopped")
tape.rewind()
print("[DEBUG] Tape rewound")
tape.seek(-tape.getSize())
print("[DEBUG] Tape cleared to start")
while true do
    local chunk = res.read(8192)
    print("[DEBUG] Read chunk, length: " .. tostring(#chunk or 0))
    if not chunk then
        print("[DEBUG] No more chunks to read, breaking loop")
        break
    end
    tape.write(chunk)
    print("[DEBUG] Wrote chunk to tape")
end

res.close()
print("[DEBUG] Response closed")
tape.rewind()
print("[DEBUG] Tape rewound for playback")
print("Playing song!")
tape.play()
print("[DEBUG] Tape play command issued")
