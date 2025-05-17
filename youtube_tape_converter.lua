-- Configuration
local server_ip = "ec2-3-147-78-217.us-east-2.compute.amazonaws.com" -- !!! REPLACE THIS with your EC2 instance's PUBLIC IP address !!!
local server_port = 5000             -- The port your Flask server is listening on
local endpoint = "/convert"          -- The API endpoint on your Flask server
local tape_drive_side = "right"      -- The side the Tape Drive is connected to (e.g., "right", "left", "front", "back")
local output_tape_label = "youtube_music" -- Optional: Label for the tape


-- Function to send request to EC2 server and get DFPWM data
function getDFPWM(youtube_url)
    print("Sending request to server...")
    local url = "http://" .. server_ip .. ":" .. server_port .. endpoint
    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/octet-stream" -- Indicate we expect raw binary data
    }
    local body = textutils.encodeJSON({ youtube_url = youtube_url })

    print("Connecting to: " .. url)

    -- Use http.post to send a POST request
    local ok, response = pcall(http.post, url, body, headers)

    if not ok then
        return nil, "HTTP request failed: " .. response
    end

    local statusCode = response.getStatusCode()
    print("Server response status code: " .. statusCode)

    if statusCode ~= 200 then
        -- Server returned an error
        local error_body = response.readAll()
        response.close()
        return nil, "Server returned error code " .. statusCode .. ": " .. error_body
    end

    -- Read the DFPWM data from the response
    local dfpwm_data = response.readAll()
    response.close()

    print("Successfully received DFPWM data (" .. #dfpwm_data .. " bytes) from server.")
    return dfpwm_data
end

-- Function to write DFPWM data to the tape drive
function writeToTape(dfpwm_data)
    print("Preparing to write to tape...")
    local tape_peripheral = peripheral.wrap(tape_drive_side)

    if tape_peripheral == nil then
        return false, "No tape drive found on the specified side: " .. tape_drive_side .. ". Ensure it's placed correctly and the side is correct."
    end

    if not tape_peripheral.isReady() then
         return false, "Tape drive is not ready. Ensure a tape is inserted and formatted."
    end

    -- Rewind and clear the tape before writing
    print("Rewinding tape...")
    tape_peripheral.rewind()
    -- Note: Some older tape drive APIs might require formatting
    -- print("Formatting tape...")
    -- tape_peripheral.format() -- Use if your tape drive requires explicit formatting before writing

    print("Writing DFPWM data to tape...")
    -- The tape peripheral's write function expects a string (binary data)
    local success, message = pcall(tape_peripheral.write, dfpwm_data)

    if not success then
        return false, "Failed to write to tape: " .. message
    end

    -- Optional: Label the tape
    if output_tape_label and tape_peripheral.setLabel then
        print("Labeling tape: " .. output_tape_label)
        pcall(tape_peripheral.setLabel, output_tape_label) -- pcall in case setLabel isn't supported
    end

    print("Finished writing to tape.")
    return true
end

-- Main program execution
print("YouTube to Tape Converter")
print("-------------------------")

-- Get YouTube URL from user input
write("Enter YouTube URL: ")
local youtube_url_input = read()

if youtube_url_input == "" then
    print("No URL entered. Exiting.")
    return
end

-- Get DFPWM data from the server
local dfpwm_data, err = getDFPWM(youtube_url_input)

if dfpwm_data == nil then
    print("Error getting DFPWM data: " .. err)
    return
end

-- Write data to the tape drive
local write_ok, write_err = writeToTape(dfpwm_data)

if not write_ok then
    print("Error writing to tape: " .. write_err)
    return
end

print("Successfully converted and written to tape!")
print("You can now play the tape in the Tape Drive.")
