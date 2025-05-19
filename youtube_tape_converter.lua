-- --- Configuration ---
local server_hostname = "ec2-18-191-56-206.us-east-2.compute.amazonaws.com"  -- ** HARDCODE YOUR EC2 PUBLIC DNS HERE **
local server_port = 5000  -- ** HARDCODE YOUR SERVER PORT HERE (usually 5000) **
local tape_label = "youtube_music"  -- The label for the music tapes
local youtube_url = "https://www.youtube.com/watch?v=Bf01riuiJWA"  -- ** HARDCODED YouTube URL for now **
-- --- End Configuration ---

-- Helper function to print errors to stderr
local function printError(message)
    io.stderr:write("ERROR CC: " .. message .. "\n")
end

-- Function to send a request to the server and retrieve raw DFPWM data
local function getDFPWMDataFromServer(youtube_url)
    local url = "http://" .. server_hostname .. ":" .. server_port .. "/convert_and_get"
    print("DEBUG CC: Requesting DFPWM for: " .. youtube_url .. " from " .. url)

    local headers = {
        ["Content-Type"] = "application/json"
    }
    local json_data = textutils.serializeJSON({youtube_url = youtube_url}, false)
    headers["Content-Length"] = string.len(json_data)

    local raw_response_body = nil
    local status_code = nil
    local status_text = nil
    local http_error = nil

    local function doHttpRequest()
        return http.post(url, json_data, headers)
    end

    local success = pcall(doHttpRequest)
    if success then
        raw_response_body, _, status_code, status_text = doHttpRequest()  -- Only care about body and status
    else
        http_error = raw_response_body  -- pcall's second return value is the error message
        printError("HTTP request failed: " .. tostring(http_error))
        return nil  -- Return nil on pcall failure
    end

    if status_code and raw_response_body then
        if status_code >= 200 and status_code < 300 then
            print("DEBUG CC: Successfully received DFPWM data (HTTP Status: " .. tostring(status_code) .. ")")
            return raw_response_body  -- Return the raw binary DFPWM data
        else
            printError("Server returned error status: " .. tostring(status_code) .. " " .. tostring(status_text or ""))
            printError("Server error details: " .. tostring(raw_response_body))
            return nil
        end
    else
        printError("Failed to get a valid response (no status or body).")
        return nil
    end
end

-- NEWLY MODIFIED FUNCTION TO AUTO-DETECT TAPE SIDE
local function findDiskDriveWithTape()
    local modem = peripheral.find("modem")
    if not modem then
        printError("No wired modem found. Please attach one.")
        return nil, nil  -- Return nil for peripheral and side
    end

    local peripheral_names = peripheral.getNames()

    for _, name in ipairs(peripheral_names) do
        local peri = peripheral.wrap(name)
        -- Check if it's a disk drive (has setLabel method) and if it has a disk present on any side
        if peri and peri.setLabel then
            if peri.isDiskPresent("left") then
                print("DEBUG CC: Found tape in 'left' slot.")
                return peri, "left"
            elseif peri.isDiskPresent("right") then
                print("DEBUG CC: Found tape in 'right' slot.")
                return peri, "right"
            end
        end
    end

    printError("No disk drive found with a tape inserted in either 'left' or 'right' slot.")
    return nil, nil  -- Return nil for peripheral and side if no tape is found
end


-- Function to write DFPWM data to a tape
local function writeDFPWMToTape(dfpwm_data)  -- tape_side removed
    local disk_drive, tape_side = findDiskDriveWithTape()
    if not disk_drive then
        return false
    end

    local tape_id = disk_drive.getDiskID(tape_side)
    if not tape_id then
        printError("Could not get tape ID from detected tape on side '" .. tape_side .. "'.")
        return false
    end

    print("Formatting tape ID: " .. tostring(tape_id) .. " on side '" .. tape_side .. "'")
    disk_drive.format(tape_side)  -- Format the tape
    disk_drive.setLabel(tape_side, tape_label)  -- Set the label

    print("Writing DFPWM data to tape...")
    local file = fs.open(disk_drive.getMount(tape_side) .. "/dfpwm_data", "wb")  -- "wb" for binary write
    if not file then
        printError("Could not open file on tape for writing on side '" .. tape_side .. "'.")
        return false
    end

    file.write(dfpwm_data)
    file.close()

    print("DFPWM data written to tape on side '" .. tape_side .. "'.")
    return true
end

-- Function to read DFPWM data from a tape
local function readDFPWMFromTape()  -- tape_side removed
    local disk_drive, tape_side = findDiskDriveWithTape()
    if not disk_drive then
        return nil
    end

    -- We need to check the label on the *detected* side
    if disk_drive.getLabel(tape_side) ~= tape_label then
        printError("Tape on side '" .. tape_side .. "' does not have the expected label: '" .. tape_label .. "'")
        return nil
    end

    local file_path = disk_drive.getMount(tape_side) .. "/dfpwm_data"
    if not fs.exists(file_path) then
        printError("DFPWM data file not found on tape on side '" .. tape_side .. "'.")
        return nil
    end

    print("Reading DFPWM data from tape on side '" .. tape_side .. "'...")
    local file = fs.open(file_path, "rb")  -- "rb" for binary read
    if not file then
        printError("Could not open file on tape for reading on side '" .. tape_side .. "'.")
        return nil
    end

    local dfpwm_data = file.readAll()
    file.close()

    print("DFPWM data read from tape on side '" .. tape_side .. "'.")
    return dfpwm_data
end

-- Function to play DFPWM data
local function playDFPWM(dfpwm_data)
    local speaker = peripheral.find("speaker")
    if not speaker then
        printError("No speaker found. Please ensure a speaker peripheral is attached.")
        return false
    end
    print("Playing DFPWM data...")
    speaker.playDFPWM(dfpwm_data)
    print("Playback finished.")
    return true
end

-- Main execution logic
local args = {...}
local command = args[1]

if command == "play" then
    local dfpwm_data = readDFPWMFromTape()
    if dfpwm_data then
        playDFPWM(dfpwm_data)
    end
elseif command == "write" then
    local dfpwm_data = getDFPWMDataFromServer(youtube_url)  -- Use the hardcoded youtube_url
    if dfpwm_data then
        if writeDFPWMToTape(dfpwm_data) then  -- tape_side removed
            print("Successfully wrote DFPWM data to tape.")
            -- Optionally play immediately after writing
            -- playDFPWM(dfpwm_data)
        else
            printError("Failed to write DFPWM data to tape.")
        end
    else
        printError("Failed to retrieve DFPWM data from server.")
    end
else
    print("Usage: youtube_tape_converter <command>")
    print("Commands:")
    print("  write - Get DFPWM from server, write to auto-detected tape using hardcoded YouTube URL.")
    print("  play - Read DFPWM from auto-detected tape and play.")
end
