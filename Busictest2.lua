-- Check for HTTP API
if not http then
    print("Error: HTTP API not available.")
    print("Enable http in ComputerCraft.cfg (http_enable=true)")
    return
end

-- Function to URL encode a string (basic version for typical YouTube URLs)
local function urlEncode(str)
    if str then
        str = string.gsub(str, "([^%w %-%_%.%~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

-- Server details (IMPORTANT: Change this to your server's actual address and port)
-- If running Next.js locally on default port 3000, and your computer can reach it:
local serverAddress = "http://localhost:9002" -- Or your server's IP if on a different machine

-- Get YouTube URL from user
term.write("Enter YouTube URL: ")
local youtubeUrl = read()

if not youtubeUrl or youtubeUrl == "" then
    print("No URL entered. Aborting.")
    return
end

-- Construct the request URL
local requestUrl = serverAddress .. "/api/music?url=" .. urlEncode(youtubeUrl)

print("Requesting audio from: " .. requestUrl)

-- Make the HTTP request
local handle, reason = http.get(requestUrl, nil, true) -- true for binary mode

if not handle then
    print("HTTP request failed: " .. tostring(reason))
    return
end

print("Receiving data...")

-- Read the binary data
local fileData = handle.readAll()
handle.close()

if not fileData then
    print("Failed to read data from server.")
    return
end

-- Save the data to a file
local filePath = "music.dfpwm"
local file = fs.open(filePath, "wb") -- "wb" for binary write

if not file then
    print("Error opening file for writing: " .. filePath)
    return
end

file.write(fileData)
file.close()

print("Audio data saved to: " .. filePath)
print("Size: " .. string.len(fileData) .. " bytes")
print("Done!")

-- You would then use a program like `play` from `plethora` (if available)
-- or a custom Computercraft program to write this file to a cassette tape
-- and play it. For example: `play music.dfpwm`
