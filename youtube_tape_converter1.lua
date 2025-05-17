-- Configuration
local server_hostname = "ec2-3-147-78-217.us-east-2.compute.amazonaws.com" -- Use the hostname instead of IP
-- OR use the public IP directly if hostname resolution is a problem:
-- local server_ip = "YOUR_EC2_PUBLIC_IP" -- !!! Uncomment this and replace with your EC2 Public IP if using hostname fails !!!
local server_port = 5000             -- The port your Flask server is listening on
local endpoint = "/convert"          -- The API endpoint on your Flask server
local output_tape_label = "youtube_music" -- Optional: Label for the tape

-- Function to find the connected tape drive peripheral automatically
function findTapeDrive()
    print("Searching for connected tape drive...")
    local sides = peripheral.getNames() -- Get a list of sides with connected peripherals
    for _, side in ipairs(sides) do
        local peripheral_type = peripheral.getType(side) -- Get the type of the peripheral on this side
        -- Check if the peripheral type string contains "tape" (case-insensitive)
        if peripheral_type and string.find(string.lower(peripheral_type), "tape") then
            print("Found tape drive on side: " .. side)
            return peripheral.wrap(side) -- Wrap the peripheral and return it
        end
    end
    return nil -- No tape drive found on any side
end


-- Function to send request to EC2 server and get DFPWM data
function getDFPWM(youtube_url)
    print("Sending request to server...")
    -- Construct the full URL using either hostname or IP
    local url
    if server_ip then -- Check if server_ip is defined and prefer it
        url = "http://" .. server_ip .. ":" .. server_port .. endpoint
    else -- Otherwise use hostname
        url = "http://" .. server_hostname .. ":" .. server_port .. endpoint
    end

    local headers = {
        ["Content-Type"] = "application/json", -- Still indicate the content type is JSON
        ["Accept"] = "application/octet-stream" -- Indicate we expect raw binary data (even though server sends text now, keep for later)
    }
    -- Manually create the JSON string for the request body
    local body = '{"youtube_url": "' .. youtube_url .. '"}' -- Manually construct JSON

    print("Connecting to: " .. url)
    -- print("Request body: " .. body) -- Optional: uncomment for debugging the request body

    -- Use http.post to send a POST request
    local ok, response = pcall(http.post, url, body, headers)

    -- *** MORE ROBUST ERROR HANDLING & INSPECTION START ***
    if not ok then
        -- pcall failed, the second return value is the error message string
        return nil, "HTTP request failed before getting response object: " .. tostring(response) .. ". Possible causes: Server not reachable, Security Group blocking, hostname resolution failure, or ComputerCraft network issue."
    end

    local response_type = type(response)
    print("Received response object type: " .. response_type)

    -- Check if response is a standard response object (userdata with necessary methods)
    if response_type ~= "userdata" or type(response.getStatusCode) ~= "function" or type(response.readAll) ~= "function" or type(response.close) ~= "function" then
         -- If it's not a standard response object, inspect what it is
         local error_message = "HTTP request returned an invalid response object after successful connection."
         error_message = error_message .. " Response type: " .. response_type .. "."

         local response_preview = "N/A"
         -- Try to get a preview of the response content based on its type
         if response_type == "table" then
             -- If it's a table, try to serialize it for inspection
             -- Need textutils.serialize for this, hope it exists if encodeJSON didn't
             if type(textutils.serialize) == "function" then
                 local success, serialized_table = pcall(textutils.serialize, response)
                 if success then response_preview = serialized_table:sub(1, 200) .. (#serialized_table > 200 and "..." or "") end
             else
                 response_preview = "Cannot serialize table: textutils.serialize not available."
             end
         elseif response_type == "string" then
             -- If it's a string, it might be an error message directly
             response_preview = response:sub(1, 200) .. (#response > 200 and "..." or "")
         elseif response_type == "userdata" then
              -- If it's userdata but doesn't have expected methods, try reading if possible
              if type(response.readAll) == "function" then
                  local success, content = pcall(response.readAll)
                  if success then response_preview = content:sub(1, 200) .. ( #content > 200 and "..." or "") end
                  pcall(response.close) -- Try to close if it's a userdata
              end
         end

         error_message = error_message .. " Response preview: " .. response_preview .. ". Check server logs for unexpected output or network interference."
         -- Close the response object if it's a userdata type that wasn't closed yet
         if response_type == "userdata" and type(response.close) == "function" and type(response.readAll) == "function" then
              pcall(response.close) -- Attempt to close
         end

         return nil, error_message
    end
    -- *** MORE ROBUST ERROR HANDLING & INSPECTION END ***


    local statusCode = response.getStatusCode()
    print("Server response status code: " .. statusCode)

    if statusCode ~= 200 then
        -- Server returned an error response (status code is not 200)
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
function writeToTape(dfpwm_data, tape_peripheral)
    print("Preparing to write to tape...")

    if tape_peripheral == nil then
        return false, "Internal error: Tape peripheral not provided to writeToTape function."
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

    print("Writing DFPWM data to tape (" .. #dfpwm_data .. " bytes)...")
    -- The tape peripheral's write function expects a string (binary data)
    local success, message = pcall(tape_peripheral.write, dfpwm_data)

    if not success then
        return false, "Failed to write to tape: " .. message .. ". Ensure the tape is writable and large enough."
    end

    -- Optional: Label the tape
    if output_tape_label and tape_peripheral.setLabel then
        print("Labeling tape: " .. output_tape_label)
        pcall(tape_peripheral.setLabel, output_tape_label) -- pcall in case setLabel isn't supported or tape is read-only
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

-- Find the tape drive automatically
local tape_peripheral = findTapeDrive()
if tape_peripheral == nil then
    print("Error: Could not find a connected Tape Drive peripheral. Ensure one is attached to the computer.")
    return
end

-- Get DFPWM data from the server
local dfpwm_data, err = getDFPWM(youtube_url_input)

if dfpwm_data == nil then
    print("Error getting DFPWM data: " .. err)
    -- The error message from getDFPWM will include details
    return
end

-- Write data to the tape drive
local write_ok, write_err = writeToTape(dfpwm_data, tape_peripheral) -- Pass the found peripheral

if not write_ok then
    print("Error writing to tape: " .. write_err)
    return
end

print("Successfully converted and written to tape!")
print("You can now play the tape in the Tape Drive.")
