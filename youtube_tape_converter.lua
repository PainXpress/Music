-- Configuration
local server_hostname = "ec2-3-147-78-188.us-east-2.compute.amazonaws.com" -- Replace with your EC2 instance's public DNS or IP
local server_port = 5000 -- The port the Flask server is running on
local tape_label = "youtube_tape" -- The label for the tape

-- Function to send a request to the server
local function sendRequest(method, endpoint, data)
    local url = "http://" .. server_hostname .. ":" .. server_port .. endpoint
    print("Sending " .. method .. " request to: " .. url)

    local headers = {
        ["Content-Type"] = "application/json"
    }

    local response, response_headers, status_code, status_text
    if method == "POST" then
        -- Ensure data is encoded as JSON string
        local json_data = textutils.encodeJSON(data)
        -- Use string.len() to get the byte length for Content-Length header
        headers["Content-Length"] = string.len(json_data)
        response, response_headers, status_code, status_text = http.post(url, json_data, headers)
    else
        -- Assuming GET for simplicity if not POST
        response, response_headers, status_code, status_text = http.get(url, headers)
    end

    if not response then
        printError("Error connecting to server: " .. (status_text or "Unknown error"))
        return nil, status_code
    end

    local response_body = response.readAll()
    response.close()

    print("Status Code: " .. status_code)
    -- Print the first 200 characters of the response body
    print("Response Body (partial): " .. response_body:sub(1, 200) .. (string.len(response_body) > 200 and "..." or ""))
    -- Print some response headers
    if response_headers then
        print("Content-Type Header: " .. (response_headers["Content-Type"] or "N/A"))
        print("Server Header: " .. (response_headers["Server"] or "N/A"))
    end


    -- Check for successful HTTP status codes (e.g., 200 OK, 201 Created, 204 No Content)
    -- Be a bit lenient with Content-Type for success check, as some servers might respond with just plain text on error
    if status_code >= 200 and status_code < 300 then
        return response_body, status_code
    else
        printError("Server returned error status: " .. status_code .. " " .. status_text)
        printError("Error details: " .. response_body)
        return nil, status_code
    end
end

local function printError(message)
    io.stderr:write(message .. "\n")
end

local function printUsage()
    print("Usage: youtube_tape_converter <command>")
    print("Commands:")
    print("  get <youtube_url> - Download and convert a YouTube video to DFPWM and get tape data")
    print("  write <tape_side> <youtube_url> - Download, convert, and write DFPWM to a tape")
    print("  list - List available DFPWM files on the server")
    print("  status <process_id> - Check the status of a conversion process")
    print("  download <filename> - Download a specific DFPWM file from the server")
    print("  play <tape_side> - Play DFPWM data from a tape (requires Disk Drive and speaker)")
end

local function getTapeSide(side_arg)
    if side_arg == "left" then
        return "left"
    elseif side_arg == "right" then
        return "right"
    else
        printError("Invalid tape side: " .. tostring(side_arg) .. ". Must be 'left' or 'right'.")
        return nil
    end
end

local function getDiskDrive(side)
    local modem = peripheral.find("modem")
    if not modem then
        printError("No modem found. Please ensure a wired modem is attached.")
        return nil
    end

    local peripheral_names = peripheral.getNames()
    local disk_drive_name = nil

    for _, name in ipairs(peripheral_names) do
        local peri = peripheral.wrap(name)
        if peri and peri.isDiskPresent and peri.isDiskPresent(side) then
            -- Check if it's a disk drive specifically, not just any peripheral with a disk
            if peri.setLabel then -- setLabel is a common method for disk drives
                 disk_drive_name = name
                 break
            end
        end
    end

    if not disk_drive_name then
        printError("No disk drive found with a disk in the '" .. side .. "' slot.")
        return nil
    end

    return peripheral.wrap(disk_drive_name)
end


local function writeDFPWMToTape(tape_side, dfpwm_data)
    local disk_drive = getDiskDrive(tape_side)
    if not disk_drive then
        return false
    end

    local tape_id = disk_drive.getDiskID(tape_side)
    if not tape_id then
        printError("Could not get tape ID.")
        return false
    end

    print("Formatting tape ID: " .. tape_id)
    disk_drive.format(tape_side) -- Format the tape
    disk_drive.setLabel(tape_side, tape_label) -- Set the label

    print("Writing DFPWM data to tape...")
    local file = fs.open(disk_drive.getMount(tape_side) .. "/dfpwm_data", "w")
    if not file then
        printError("Could not open file on tape for writing.")
        return false
    end

    -- Write the DFPWM data in chunks if necessary, or just write all
    file.write(dfpwm_data)
    file.close()

    print("DFPWM data written to tape.")
    return true
end

local function readDFPWMFromTape(tape_side)
     local disk_drive = getDiskDrive(tape_side)
    if not disk_drive then
        return nil
    end

    if disk_drive.getLabel(tape_side) ~= tape_label then
         printError("Tape does not have the expected label: '" .. tape_label .. "'")
         return nil
    end

    local file_path = disk_drive.getMount(tape_side) .. "/dfpwm_data"
    if not fs.exists(file_path) then
        printError("DFPWM data file not found on tape.")
        return nil
    end

    print("Reading DFPWM data from tape...")
    local file = fs.open(file_path, "r")
    if not file then
        printError("Could not open file on tape for reading.")
        return nil
    end

    local dfpwm_data = file.readAll()
    file.close()

    print("DFPWM data read from tape.")
    return dfpwm_data
end


-- Main execution
local args = { ... }
local command = args[1]

if command == "get" then
    local youtube_url = args[2]
    if not youtube_url then
        printError("Error: YouTube URL is required for 'get' command.")
        printUsage()
    else
        print("Requesting conversion for: " .. youtube_url)
        local response_body, status_code = sendRequest("POST", "/convert", { youtube_url = youtube_url })
        if response_body then
            print("\nConversion request sent. If successful, the server is processing.")
            print("Use 'status <process_id>' to check progress, where process_id is typically the video ID.")
            -- The server should ideally return the process ID (video ID) in the response body
            -- For now, we'll just indicate the request was sent.
        end
    end

elseif command == "write" then
    local tape_side_arg = args[2]
    local youtube_url = args[3]
    if not tape_side_arg or not youtube_url then
        printError("Error: Both tape side (left/right) and YouTube URL are required for 'write' command.")
        printUsage()
    else
        local tape_side = getTapeSide(tape_side_arg)
        if tape_side then
            print("Requesting conversion and writing for: " .. youtube_url)
             local response_body, status_code = sendRequest("POST", "/convert_and_get", { youtube_url = youtube_url })
             if response_body then
                print("Conversion and data retrieval request sent.")
                -- Assume response_body is the DFPWM data if successful
                -- Need to be careful here - the server might return JSON status first
                -- Let's check the Content-Type header for JSON
                 if status_code >= 200 and status_code < 300 and response_headers and response_headers["Content-Type"] and response_headers["Content-Type"]:lower():find("application/json") then
                     -- If it's JSON, it's probably a status update or error from the server logic
                     local json_response = textutils.decodeJSON(response_body)
                     if json_response and json_response.status == "success" and json_response.dfpwm_data then
                         -- This case is unlikely with the current server /convert_and_get returning raw data
                         print("Received DFPWM data within JSON response (unexpected).")
                         if writeDFPWMToTape(tape_side, json_response.dfpwm_data) then
                              print("DFPWM data successfully written to tape side '" .. tape_side .. "'.")
                         end
                     else
                          printError("Received JSON response that was not expected DFPWM data.")
                          printError("Server message: " .. tostring(json_response and json_response.message or response_body))
                     end
                 elseif status_code == 200 then -- If status is 200 but not JSON, assume it's the raw DFPWM data
                     print("Received raw DFPWM data.")
                     if writeDFPWMToTape(tape_side, response_body) then
                         print("DFPWM data successfully written to tape side '" .. tape_side .. "'.")
                     else
                         printError("Failed to write DFPWM data to tape.")
                     end
                 else
                      -- Error already printed by sendRequest
                      printError("Failed to retrieve DFPWM data.")
                 end
             else
                  printError("Failed to get response from server.")
             end
        end
    end

elseif command == "list" then
    print("Requesting list of DFPWM files from server...")
    local response_body, status_code = sendRequest("GET", "/list_files", nil)
    if response_body then
        local file_list = textutils.decodeJSON(response_body)
        if file_list and type(file_list) == "table" then
            print("\nAvailable DFPWM files on server:")
            for i, filename in ipairs(file_list) do
                print("- " .. filename)
            end
        else
            printError("Failed to parse file list or list is empty.")
        end
    end

elseif command == "status" then
     local process_id = args[2]
     if not process_id then
         printError("Error: Process ID is required for 'status' command.")
         printUsage()
     else
         print("Checking status for process ID: " .. process_id)
         local response_body, status_code = sendRequest("GET", "/status/" .. process_id, nil)
         if response_body then
              local status_info = textutils.decodeJSON(response_body)
              if status_info and type(status_info) == "table" then
                  print("\nProcess Status:")
                  print("  Status: " .. tostring(status_info.status))
                  if status_info.message then
                      print("  Message: " .. tostring(status_info.message))
                  end
                  if status_info.progress then
                       print("  Progress: " .. tostring(status_info.progress))
                  end
                  if status_info.filename then
                       print("  Filename: " .. tostring(status_info.filename))
                  end
              else
                  printError("Failed to parse status information.")
              end
         end
     end

elseif command == "download" then
    local filename = args[2]
    if not filename then
        printError("Error: Filename is required for 'download' command.")
        printUsage()
    else
        print("Requesting download for file: " .. filename)
        local response_body, status_code = sendRequest("GET", "/download/" .. filename, nil)
        if response_body then
             -- Assume successful response is the raw DFPWM data
             print("Received data for download. (Not writing to local file in this script)")
             -- You would need to implement saving response_body to a local CC file here if needed
        end
    end

elseif command == "play" then
    local tape_side_arg = args[2]
    if not tape_side_arg then
        printError("Error: Tape side (left/right) is required for 'play' command.")
        printUsage()
    else
        local tape_side = getTapeSide(tape_side_arg)
        if tape_side then
            local dfpwm_data = readDFPWMFromTape(tape_side)
            if dfpwm_data then
                 print("Playing DFPWM data from tape side '" .. tape_side .. "'...")
                 local speaker = peripheral.find("speaker")
                 if not speaker then
                      printError("No speaker found. Please ensure a speaker peripheral is attached.")
                 else
                      speaker.playDFPWM(dfpwm_data)
                      print("Playback finished.")
                 end
            else
                printError("Failed to read DFPWM data from tape.")
            end
        end
    end

else
    printError("Error: Unknown command '" .. tostring(command) .. "'")
    printUsage()
end
