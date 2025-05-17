-- Configuration
local server_hostname = "ec2-3-147-78-217.us-east-2.compute.amazonaws.com" -- Use the hostname instead of IP
-- OR use the public IP directly if hostname resolution is a problem:
-- local server_ip = "YOUR_EC2_PUBLIC_IP" -- !!! Uncomment this and replace with your EC2 Public IP if using hostname fails !!!
local server_port = 5000             -- The port your Flask server is listening on
local convert_endpoint = "/convert"  -- The API endpoint for conversion request
local download_endpoint = "/download/latest.dfpwm" -- Fixed endpoint for the latest file

local output_tape_label = "youtube_music" -- Optional: Label for the tape

-- Function to find the connected tape drive peripheral automatically
function findTapeDrive()
    print("Searching for connected tape drive...")
    local sides = peripheral.getNames() -- Get a list of sides with connected peripherals
    for _, side in ipairs(sides) do
        local peripheral_type = peripheral.getType(side) -- Get the type of the peripheral on this side
        if peripheral_type and string.find(string.lower(peripheral_type), "tape") then
            print("Found tape drive on side: " .. side)
            return peripheral.wrap(side) -- Wrap the peripheral and return it
        end
    end
    return nil -- No tape drive found on any side
end


-- Function to send conversion request (plain text) and download latest DFPWM via GET
function triggerConversionAndDownload()
    print("Step 1: Triggering conversion on server (sending plain text URL)...")
    -- Construct the full URL for the conversion request
    local convert_url
    if server_ip then
        convert_url = "http://" .. server_ip .. ":" .. server_port .. convert_endpoint
    else
        convert_url = "http://" .. server_hostname .. ":" .. server_port .. convert_endpoint
    end

    -- Get YouTube URL from user input (moved here as it's part of the POST body)
    write("Enter YouTube URL: ")
    local youtube_url_input = read()
    if youtube_url_input == "" then
        return nil, "No URL entered."
    end

    -- Send the YouTube URL as a plain text request body
    local headers = {
        ["Content-Type"] = "text/plain" -- Indicate we are sending plain text
    }
    local body = youtube_url_input -- Just send the URL string as the body

    print("Connecting to conversion endpoint: " .. convert_url)

    -- Send the POST request
    local ok, response = pcall(http.post, convert_url, body, headers)

    -- *** Inspect Response from Conversion Request (expecting simple text confirmation) ***
    if not ok then
        return nil, "HTTP POST request failed: " .. tostring(response) .. ". Check network, firewall, and server status."
    end

    local response_type = type(response)
    print("Received response object type (conversion request): " .. response_type)

    -- Standard response object should be userdata with methods (getStatusCode, readAll, close)
    if response_type ~= "userdata" or type(response.getStatusCode) ~= "function" or type(response.readAll) ~= "function" or type(response.close) ~= "function" then
         local error_message = "Received invalid response object from conversion request."
         error_message = error_message .. " Type: " .. response_type .. "."

         local response_preview = "N/A"
         -- Attempt to get a preview based on its type
         if response_type == "string" then
             response_preview = response:sub(1, 200) .. (string.len(response) > 200 and "..." or "") # Use string.len()
         elseif response_type == "table" then
             response_preview = "Received a table structure." # Indicate it was a table
         elseif response_type == "userdata" and type(response.readAll) == "function" then
              local success, content = pcall(response.readAll)
              if success then response_preview = content:sub(1, 200) .. ( string.len(content) > 200 and "..." or "") end # Use string.len()
         end
         if response_type == "userdata" and type(response.close) == "function" then pcall(response.close) end # Attempt to close

         return nil, error_message .. " Preview: " .. response_preview .. ". Check server logs for actual response."
    end

    # If we are here, response is a userdata object, read status and body
    local statusCode = response.getStatusCode()
    local response_body = response.readAll() # Read the response body (should be plain text confirmation)
    response.close()

    print("Server response status code (conversion request): " .. statusCode)
    print("Received response body (conversion request): " .. response_body:sub(1, 200) .. (string.len(response_body) > 200 and "..." or "")) # Use string.len()


    if statusCode ~= 200 then
        return nil, "Server returned error code " .. statusCode .. " for conversion request. Response: " .. response_body
    end

    # We expect a plain text confirmation string here.
    # We don't need to parse a URL from this response anymore.

    print("Conversion triggered successfully. Waiting briefly before download.")
    sleep(5) # Wait a few seconds to ensure the server finishes processing and saving

    print("Step 2: Downloading latest DFPWM file via GET...")

    # Construct the full URL for the download (using the fixed endpoint)
    local download_url_full
    if server_ip then
        download_url_full = "http://" .. server_ip .. ":" .. server_port .. download_endpoint
    else
        download_url_full = "http://" .. server_hostname .. ":" .. server_port .. download_endpoint
    end

    print("Connecting to download endpoint: " .. download_url_full)

    # Use http.get to download the file
    local ok_get, response_get = pcall(http.get, download_url_full)

    if not ok_get then
         return nil, "HTTP GET request for download failed: " .. tostring(response_get) .. ". Check network or if the download URL is accessible."
    end

    # *** Inspect Response from Download Request (expecting binary data) ***
    local response_get_type = type(response_get)
    print("Received response object type (download request): " .. response_get_type)

    # Standard response object should be userdata with methods
    if response_get_type ~= "userdata" or type(response_get.getStatusCode) ~= "function" or type(response_get.readAll) ~= "function" or type(response_get.close) ~= "function" then
        local error_message = "Received invalid response object from download request."
        error_message = error_message .. " Type: " .. response_get_type .. "."
         local response_preview = "N/A"
         if response_get_type == "string" then
             response_preview = response_get:sub(1, 200) .. (string.len(response_get) > 200 and "..." or "") # Use string.len()
         elseif response_get_type == "table" then
              response_preview = "Received a table structure."
         elseif response_get_type == "userdata" and type(response_get.readAll) == "function" then
              local success, content = pcall(response_get.readAll)
              if success then response_preview = content:sub(1, 200) .. ( string.len(content) > 200 and "..." or "") end
         end
         if type(response_get) == "userdata" and type(response_get.close) == "function" then pcall(response_get.close) end # Attempt to close

         return nil, error_message .. " Preview: " .. response_preview
    end

    # If we are here, response_get is a userdata object, read status and body
    local statusCode_get = response_get.getStatusCode()
    print("Server response status code (download): " .. statusCode_get)

    if statusCode_get ~= 200 then
        local error_body_get = response_get.readAll()
        response_get.close()
        return nil, "Server returned error code " .. statusCode_get .. " for download request. Response: " .. error_body_get
    end

    # Read the DFPWM data from the download response body
    local dfpwm_data = response_get.readAll() # This should be the binary DFPWM data
    response_get.close() # Close the response object

    print("Successfully downloaded DFPWM data (" .. string.len(dfpwm_data) .. " bytes).") # Use string.len()

    return dfpwm_data # Return the DFPWM binary data
end

-- Function to write DFPWM data to the tape drive (same as before)
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
    -- tape_peripheral.format() # Use if your tape drive requires explicit formatting before writing

    print("Writing DFPWM data to tape (" .. string.len(dfpwm_data) .. " bytes)...") # Use string.len()
    # The tape peripheral's write function expects a string (binary data)
    local success, message = pcall(tape_peripheral.write, dfpwm_data)

    if not success then
        return false, "Failed to write to tape: " .. message .. ". Ensure the tape is writable and large enough."
    end

    -- Optional: Label the tape
    if output_tape_label and tape_peripheral.setLabel then
        print("Labeling tape: " .. output_tape_label)
        pcall(tape_peripheral.setLabel, output_tape_label) # pcall in case setLabel isn't supported or tape is read-only
    end

    print("Finished writing to tape.")
    return true
end

-- Main program execution
print("YouTube to Tape Converter")
print("-------------------------")

-- Find the tape drive automatically
local tape_peripheral = findTapeDrive()
if tape_peripheral == nil then
    print("Error: Could not find a connected Tape Drive peripheral. Ensure one is attached to the computer.")
    return
end

# Trigger conversion, get URL, and download data
local dfpwm_data, err = triggerConversionAndDownload()

if dfpwm_data == nil then
    print("Error during get/download process: " .. err)
    return
end

-- Write data to the tape drive
local write_ok, write_err = writeToTape(dfpwm_data, tape_peripheral) # Pass the found peripheral

if not write_ok then
    print("Error writing to tape: " .. write_err)
    return
end

print("Successfully converted and written to tape!")
print("You can now play the tape in the Tape Drive.")
