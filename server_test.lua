-- server_test.lua
-- This script is for testing connectivity to your EC2 server.

-- --- Configuration ---
local server_hostname = "ec2-18-191-56-206.us-east-2.compute.amazonaws.com"  -- ** HARDCODE YOUR EC2 PUBLIC DNS HERE **
local server_port = 5000  -- ** HARDCODE YOUR SERVER PORT HERE (usually 5000) **
local test_youtube_url = "https://www.youtube.com/watch?v=Bf01riuiJWA" -- A fixed URL for testing
-- --- End Configuration ---

-- Helper function to print errors to stderr
local function printError(message)
    io.stderr:write("ERROR CC: " .. message .. "\n")
end

-- Function to send a request to the server and retrieve raw DFPWM data
local function testServerConnectivity()
    local url = "http://" .. server_hostname .. ":" .. server_port .. "/convert_and_get"
    print("DEBUG CC: Attempting to connect to: " .. url)
    print("DEBUG CC: Sending request for YouTube URL: " .. test_youtube_url)

    local headers = {
        ["Content-Type"] = "application/json"
    }
    local json_data = textutils.serializeJSON({youtube_url = test_youtube_url}, false)
    headers["Content-Length"] = string.len(json_data)

    local raw_response_body = nil
    local status_code = nil
    local status_text = nil
    local http_error = nil

    local function doHttpRequest()
        return http.post(url, json_data, headers)
    end

    local success, response = pcall(doHttpRequest)
    if not success then
        http_error = response -- pcall's second return value is the error message
        printError("HTTP request failed: " .. tostring(http_error))
        return nil, nil, nil, http_error -- Return error details
    end

    -- If pcall was successful, 'response' is the HTTP response object (handle)
    if response then
        status_code = response.getStatusCode()
        status_text = response.getStatusMessage()
        raw_response_body = response.readAll()
        response.close() -- Always close the response handle

        if status_code >= 200 and status_code < 300 then
            print("Server Test SUCCESS:")
            print("  Status Code: " .. tostring(status_code))
            print("  Status Text: " .. tostring(status_text or "N/A"))
            print("  Data Length: " .. #raw_response_body .. " bytes")
            -- Print first 100 bytes of data (or less if data is shorter)
            print("  First 100 bytes of DFPWM data (hex):")
            local hex_representation = ""
            for i = 1, math.min(100, #raw_response_body) do
                hex_representation = hex_representation .. string.format("%02X ", string.byte(raw_response_body, i))
            end
            print("    " .. hex_representation)
            return true -- Indicate success
        else
            printError("Server Test FAILED: Server returned error status.")
            printError("  Status Code: " .. tostring(status_code))
            printError("  Status Text: " .. tostring(status_text or ""))
            printError("  Server Error Details (if any): " .. tostring(raw_response_body))
            return false -- Indicate failure
        end
    else
        printError("Server Test FAILED: No HTTP response object received.")
        return false -- Indicate failure
    end
end

-- Run the test
testServerConnectivity()
