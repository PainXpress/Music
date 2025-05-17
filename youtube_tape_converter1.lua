-- Configuration variables
local SERVER_URL = "ec2-3-147-78-188.us-east-2.compute.amazonaws.com"  -- Replace with your AWS server URL
local CONVERT_ENDPOINT = "/convert"
local STATUS_ENDPOINT = "/status"
local DOWNLOAD_ENDPOINT = "/download"

-- Function to detect a tape drive
local function detectTapeDrive()
    for _, side in pairs(peripheral.getNames()) do
        if peripheral.getType(side) == "tape_drive" then
            return side
        end
    end
    return nil
end

-- Function to check conversion status
local function getConversionStatus(jobId)
    local url = SERVER_URL .. STATUS_ENDPOINT .. "?id=" .. jobId
    local response = http.get(url)
    if response then
        local status = response.readAll()
        response.close()
        return status
    else
        return nil, "Failed to check conversion status"
    end
end

-- Function to convert and download audio
local function convertAndDownload(youtubeUrl)
    print("Starting conversion for: " .. youtubeUrl)
    local url = SERVER_URL .. CONVERT_ENDPOINT .. "?url=" .. youtubeUrl
    local response = http.post(url)
    if not response then
        return nil, "Failed to start conversion"
    end

    local jobId = response.readAll()
    response.close()

    -- Poll status until complete
    while true do
        local status, err = getConversionStatus(jobId)
        if not status then
            return nil, err
        end
        if status == "complete" then
            break
        elseif status == "failed" then
            return nil, "Conversion failed on server"
        end
        print("Conversion in progress...")
        sleep(2)
    end

    -- Download the converted audio
    local downloadUrl = SERVER_URL .. DOWNLOAD_ENDPOINT .. "?id=" .. jobId
    response = http.get(downloadUrl)
    if response then
        local data = response.readAll()
        response.close()
        return data
    else
        return nil, "Failed to download audio"
    end
end

-- Function to write data to tape
local function writeTape(tapeSide, audioData, label)
    local tape = peripheral.wrap(tapeSide)
    if not tape then
        return false, "Tape drive not accessible"
    end

    tape.stop()
    tape.seek(-tape.getSize())  -- Rewind to start
    tape.write(audioData)
    tape.setLabel(label)
    return true
end

-- Main execution block
local function main()
    print("YouTube to Tape Converter")
    print("Enter YouTube URL:")
    local youtubeUrl = read()

    -- Validate URL (basic check)
    if not youtubeUrl:match("^https?://") then
        print("Error: Invalid URL. Please include http:// or https://")
        return
    end

    -- Detect tape drive
    local tapeSide = detectTapeDrive()
    if not tapeSide then
        print("Error: No tape drive found")
        return
    end
    print("Tape drive detected on side: " .. tapeSide)

    -- Convert and download
    local audioData, err = convertAndDownload(youtubeUrl)
    if not audioData then
        print("Error: " .. err)
        return
    end

    -- Write to tape
    print("Enter tape label (optional):")
    local label = read()
    if label == "" then label = "YouTube Audio" end

    local success, writeErr = writeTape(tapeSide, audioData, label)
    if success then
        print("Audio successfully written to tape: " .. label)
    else
        print("Error writing to tape: " .. writeErr)
    end
end

-- Run the script with error handling
local ok, err = pcall(main)
if not ok then
    print("Script error: " .. err)
end
