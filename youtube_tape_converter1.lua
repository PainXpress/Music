-- --- Configuration ---
local server_hostname = "ec2-18-191-56-206.us-east-2.compute.amazonaws.com" -- ** HARDCODE YOUR EC2 PUBLIC DNS HERE **
local server_port = 5000 -- ** HARDCODE YOUR SERVER PORT HERE (usually 5000) **
local tape_label = "youtube_tape" -- The label for the tape
-- --- End Configuration ---


-- Function to send a request to the server with added debug, expecting multiple return values
local function sendRequest(method, endpoint, data)
    local url = "http://" .. server_hostname .. ":" .. server_port .. endpoint
    print("DEBUG CC: Sending " .. method .. " request to: " .. url) -- Debug print URL

    local headers = {
        ["Content-Type"] = "application/json"
    }
    print("DEBUG CC: Request Headers:", textutils.serialize(headers)) -- Debug print headers

    local json_data = nil
    if method == "POST" and data then
        -- Use the correct function based on help textutils: textutils.serializeJSON
        json_data = textutils.serializeJSON(data, false) -- Use serializeJSON instead of encodeJSON
        headers["Content-Length"] = string.len(json_data) -- Manually setting Content-Length
        print("DEBUG CC: Request Body:", json_data) -- Debug print body
    end

    local raw_response_body = nil
    local response_headers = nil
    local status_code = nil
    local status_text = nil
    local http_error = nil

    local function doHttpRequest()
        if method == "POST" then
            return http.post(url, json_data, headers)
        else -- Assuming GET
            return http.get(url, headers)
        end
    end

    -- MODIFIED PCALL ASSIGNMENT
    local success = pcall(doHttpRequest)
    if success then
        -- If pcall was successful, call doHttpRequest again to get its actual return values
        raw_response_body, response_headers, status_code, status_text = doHttpRequest()
    else
        -- If pcall failed, result1 is the error message
        http_error = raw_response_body -- pcall's second return value is the error message on failure
        printError("CC Error: HTTP request pcall failed: " .. tostring(http_error), file=io.stderr)
        -- Set other returns to nil explicitly for clarity
        raw_response_body = nil
        response_headers = nil
        status_code = nil
        status_text = nil
        return nil, nil -- Return nil for both body and status on pcall failure
    end


    if success then
        -- --- Debug prints using the directly captured values ---
        print("DEBUG CC: HTTP request call was successful in pcall.", file=io.stderr)
        print("DEBUG CC: Retrieved Status Code:", tostring(status_code or "N/A"))
        print("DEBUG CC: Retrieved Status Text:", tostring(status_text or "N/A"))
        if response_headers then print("DEBUG CC: Retrieved Response Headers:", textutils.serialize(response_headers)) else print("DEBUG CC: Failed to retrieve Response Headers.", file=io.stderr) end
        print("DEBUG CC: Retrieved Raw Response Body (start):", tostring(raw_response_body or ""):sub(1, 500)) -- Handle nil raw_response_body
        if raw_response_body and string.len(raw_response_body) > 500 then print("DEBUG CC: ... (response body truncated for print)") end
        -- --- End Debug prints ---


        -- Now proceed with JSON decoding if we got a status code and body
        if status_code and raw_response_body then
            -- Check for successful HTTP status codes (2xx) before processing body
            if status_code >= 200 and status_code < 300 then
                -- Try to decode JSON only if status is successful
                local json_decode_func = textutils.parseJSON or textutils.unserializeJSON -- Try parseJSON or unserializeJSON
                if json_decode_func then
                    local success_decode, json_response = pcall(json_decode_func, raw_response_body)
                     if success_decode and type(json_response) == "table" then
                            print("DEBUG CC: Decoded JSON response successfully.")
                            -- Return the decoded JSON table and status code
                            return json_response, status_code
                     else
                            printError("CC Error: Received 2xx status but failed to decode response body as JSON.")
                            printError("CC Error: Raw response body was: " .. tostring(raw_response_body))
                            return nil, status_code -- Indicate failure to decode JSON
                     end
                else
                    printError("CC Error: No suitable JSON decode function found (looked for parseJSON, unserializeJSON).")
                    printError("CC Error: Raw response body was: " .. tostring(raw_response_body))
                    return nil, status_code
                end

            else
                -- Error status code returned by server
                printError("CC Error: Server returned error status: " .. tostring(status_code) .. " " .. tostring(status_text or ""))
                printError("CC Error: Error details (raw body): " .. tostring(raw_response_body))
                return nil, status_code
            end
        elseif status_code then
            -- Got a status code but no body (maybe a 204 No Content, or readAll failed)
             printError("CC Error: Received status code " .. tostring(status_code) .. " but no response body was retrieved.", file=io.stderr)
             return nil, status_code
        elseif raw_response_body then
            -- Got a body but no status code (very unusual)
             printError("CC Error: Received response body but no status code was retrieved.", file=io.stderr)
             return nil, nil -- Cannot return meaningful status
        else
            -- Neither status code nor body received directly (might be timeout or connection error caught by pcall in sendRequest)
            -- sendRequest already printed error if pcall failed
             printError("CC Error: Failed to retrieve a response with a status code.")
        end

    else
        -- If pcall failed, the error message is already captured and printed above.
        -- This 'else' block here is redundant given the structure change, but kept for clarity.
        -- We've already returned nil, nil earlier in the 'else' of 'local success = pcall(doHttpRequest)'
        return nil, nil
    end
end
local function printError(message)
    io.stderr:write(message .. "\n")
end

local function printUsage()
    print("Usage: youtube_tape_converter <command>")
    print("Commands:")
    print("  get <youtube_url> - Download and convert a YouTube video to DFPWM and get tape data")
    print("  write <tape_side> <youtube_url> - Download, convert, and write DFPWM to a tape")
    print("  list - List available DFPWM files on the server")
    print("  status <process_id> - Check the status of a conversion process")
    print("  download <filename> - Download a specific DFPWM file from the server")
    print("  play <tape_side> - Play DFPWM data from a tape (requires Disk Drive and speaker)")
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

    print("Formatting tape ID: " .. tostring(tape_id))
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
        -- sendRequest now returns body, headers, status_code, status_text
        local raw_response_body, response_headers, status_code, status_text = sendRequest("POST", "/convert", { youtube_url = youtube_url })

        -- Process the response based on the returned values
        if status_code then
            -- Check for successful HTTP status codes (2xx) before processing body
            if status_code >= 200 and status_code < 300 then
                -- Try to decode JSON if we got a body
                if raw_response_body then
                    local json_decode_func = textutils.parseJSON or textutils.unserializeJSON -- Try parseJSON or unserializeJSON
                    if json_decode_func then
                        local success_decode, json_response = pcall(json_decode_func, raw_response_body)
                         if success_decode and type(json_response) == "table" then
                                print("DEBUG CC: Decoded JSON response successfully.")
                                -- We received and decoded a JSON response
                                print("\nConversion request sent. If successful, the server is processing.")
                                print("Use 'status <process_id>' to check progress, where process_id is typically the video ID.")

                                 if json_response.status then
                                        print("Server Response Status: " .. tostring(json_response.status))
                                        if json_response.message then print("Server Message: " .. tostring(json_response.message)) end
                                        if json_response.process_id then print("Server Process ID: " .. tostring(json_response.process_id)) end
                                else
                                        printError("Server returned JSON without a 'status' key.")
                                end
                                -- Now we can potentially return or do more with the json_response table
                                -- return json_response, status_code -- Decide if main execution needs to return these
                         else
                                printError("CC Error: Received 2xx status but failed to decode response body as JSON.")
                                printError("CC Error: Raw response body was: " .. tostring(raw_response_body))
                         end
                    else
                            printError("CC Error: No suitable JSON decode function found (looked for parseJSON, unserializeJSON).")
                            printError("CC Error: Raw response body was: " .. tostring(raw_response_body))
                    end
                else
                    -- Received a status code, but it was an error status (not 2xx)
                    printError("CC Error: Server returned error status: " .. tostring(status_code) .. " " .. tostring(status_text or ""))
                    printError("CC Error: Error details (raw body): " .. tostring(raw_response_body))
                end
            elseif raw_response_body then
                -- Received a body but no status code (very unusual)
                 printError("CC Error: Received response body but no status code was retrieved.", file=io.stderr)
            else
                -- Neither status code nor body received directly (might be timeout or connection error caught by pcall in sendRequest)
                -- sendRequest already printed error if pcall failed
                 printError("CC Error: Failed to retrieve a response with a status code.")
            end
        else
             -- pcall in sendRequest failed, error already printed by sendRequest
             printError("Failed to get a valid response from server.")
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
             -- Use convert_and_get endpoint which returns raw DFPWM data directly
             local dfpwm_data, response_headers, status_code, status_text = sendRequest("POST", "/convert_and_get", { youtube_url = youtube_url })
             if status_code then
                 if status_code >= 200 and status_code < 300 then
                     -- Assuming successful 2xx status means dfpwm_data is the body
                     if dfpwm_data then
                         print("Received raw DFPWM data.")
                         if writeDFPWMToTape(tape_side, dfpwm_data) then
                             print("DFPWM data successfully written to tape side '" .. tape_side .. "'.")
                         else
                             printError("Failed to write DFPWM data to tape.")
                         end
                     else
                          printError("Received 2xx status but no DFPWM data was received.")
                     end
                 else
                     -- Error status
                      printError("CC Error: Server returned error status: " .. tostring(status_code) .. " " .. tostring(status_text or ""))
                      printError("CC Error: Error details (raw body): " .. tostring(dfpwm_data))
                 end
             else
                 -- sendRequest pcall failed, error already printed
                 printError("Failed to get a valid response from server.")
             end
        end
    end

elseif command == "list" then
    print("Requesting list of DFPWM files from server...")
    local raw_response_body, response_headers, status_code, status_text = sendRequest("GET", "/list_files", nil)
    if status_code then
        if status_code >= 200 and status_code < 300 then
            if raw_response_body then
                 local json_decode_func = textutils.parseJSON or textutils.unserializeJSON -- Try parseJSON or unserializeJSON
                 if json_decode_func then
                     local success_decode, file_list = pcall(json_decode_func, raw_response_body)
                      if success_decode and type(file_list) == "table" then
                            print("\nAvailable DFPWM files on server:")
                            if #file_list > 0 then
                                for i, filename in ipairs(file_list) do
                                    print("- " .. filename)
                                end
                            else
                                print("No DFPWM files found on the server.")
                            end
                          else
                            printError("Failed to parse file list or list is not a table.")
                            printError("Raw response body was: " .. tostring(raw_response_body))
                          end
                      else
                          printError("CC Error: No suitable JSON decode function found (looked for parseJSON, unserializeJSON).")
                          printError("Raw response body was: " .. tostring(raw_response_body))
                      end
                  else
                      printError("Received 2xx status but no response body for file list.")
                  end
              else
                  printError("CC Error: Server returned error status: " .. tostring(status_code) .. " " .. tostring(status_text or ""))
                  printError("CC Error: Error details (raw body): " .. tostring(raw_response_body))
              end
          else
              printError("Failed to get a valid response from server.")
          end


elseif command == "status" then
      local process_id = args[2]
      if not process_id then
          printError("Error: Process ID is required for 'status' command.")
          printUsage()
      else
          print("Checking status for process ID: " .. process_id)
          local raw_response_body, response_headers, status_code, status_text = sendRequest("GET", "/status/" .. textutils.urlEncode(tostring(process_id)), nil) -- URL encode process_id
          if status_code then
              if status_code >= 200 and status_code < 300 then
                  if raw_response_body then
                      local json_decode_func = textutils.parseJSON or textutils.unserializeJSON -- Try parseJSON or unserializeJSON
                      if json_decode_func then
                          local success_decode, status_info = pcall(json_decode_func, raw_response_body)
                          if success_decode and type(status_info) == "table" then
                                print("\nProcess Status:")
                                print("  Status: " .. tostring(status_info.status))
                                if status_info.message then
                                    print("  Message: " .. tostring(status_info.message))
                                end
                                if status_info.progress then
                                     print("  Progress: " .. tostring(status_info.progress))
                                end
                                if status_info.filename then
                                     print("  Filename: " .. tostring(status_info.filename))
                                end
                              else
                                printError("Failed to parse status information or info is not a table.")
                                printError("Raw response body was: " .. tostring(raw_response_body))
                              end
                          else
                              printError("CC Error: No suitable JSON decode function found (looked for parseJSON, unserializeJSON).")
                              printError("Raw response body was: " .. tostring(raw_response_body))
                          end
                      else
                          printError("Received 2xx status but no response body for status check.")
                      end
                  else
                      printError("CC Error: Server returned error status: " .. tostring(status_code) .. " " .. tostring(status_text or ""))
                      printError("CC Error: Error details (raw body): " .. tostring(raw_response_body))
                  end
              else
                  printError("Failed to get a valid response from server.")
              end
          end

elseif command == "download" then
    local filename = args[2]
    if not filename then
        printError("Error: Filename is required for 'download' command.")
        printUsage()
    else
        print("Requesting download for file: " .. filename)
        -- This endpoint returns raw DFPWM data, not JSON status
        local dfpwm_data, response_headers, status_code, status_text = sendRequest("GET", "/download/" .. textutils.urlEncode(tostring(filename)), nil) -- URL encode filename
        if status_code then
            if status_code >= 200 and status_code < 300 then
                 -- Assuming successful 2xx status means dfpwm_data is the body
                 if dfpwm_data then
                    print("Received DFPWM data for download.")
                    -- You would need to implement saving dfpwm_data to a local CC file here if needed
                 else
                      printError("Received 2xx status but no data was received for download.")
                 end
            else
                 printError("CC Error: Server returned error error status: " .. tostring(status_code) .. " " .. tostring(status_text or ""))
                 printError("CC Error: Error details (raw body): " .. tostring(dfpwm_data))
            end
        else
            printError("Failed to get a valid response from server.")
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
