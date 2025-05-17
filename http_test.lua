-- Configuration
local server_hostname = "ec2-3-147-78-217.us-east-2.compute.amazonaws.com" -- Use the hostname instead of IP
-- OR use the public IP directly if hostname resolution is a problem:
-- local server_ip = "YOUR_EC2_PUBLIC_IP" -- !!! Uncomment this and replace with your EC2 Public IP if using hostname fails !!!
local server_port = 5000             -- The port your Flask server is listening on
local endpoint = "/convert"          -- The API endpoint on your Flask server

-- Function to send a test request and inspect the response
function testHttpResponse(youtube_url)
    print("Sending test request to server...")
    -- Construct the full URL using either hostname or IP
    local url
    if server_ip then -- Check if server_ip is defined and prefer it
        url = "http://" .. server_ip .. ":" .. server_port .. endpoint
    else -- Otherwise use hostname
        url = "http://" .. server_hostname .. ":" .. server_port .. endpoint
    end

    local headers = {
        ["Content-Type"] = "application/json"
    }
    -- Manually create the JSON string for the request body
    local body = '{"youtube_url": "' .. youtube_url .. '"}'

    print("Connecting to: " .. url)

    -- Use http.post to send a POST request
    local ok, response = pcall(http.post, url, body, headers)

    -- *** SIMPLIFIED ERROR HANDLING & INSPECTION START ***
    if not ok then
        -- pcall failed, the second return value is the error message string
        print("HTTP request failed before getting response object.")
        print("Error message from pcall: " .. tostring(response))
        print("Possible causes: Server not reachable, Security Group blocking, hostname resolution failure, or ComputerCraft network issue.")
        return nil, "HTTP request failed"
    end

    local response_type = type(response)
    print("Received response object type: " .. response_type)

    -- If it's not the expected userdata, try to print a simple representation
    if response_type ~= "userdata" then
        print("Attempting to print received response (non-userdata):")
        -- Try to get a string representation of the received data
        local simple_representation = tostring(response)
        print("tostring() output: " .. simple_representation)

        -- If textutils.serialize exists, try to serialize it for more detail if it's a table
        if response_type == "table" and type(textutils.serialize) == "function" then
             print("Attempting to serialize received table:")
             local success, serialized = pcall(textutils.serialize, response)
             if success then
                 print("Serialized table output:")
                 print(serialized)
             else
                 print("Could not serialize table.")
             end
        end

        return nil, "Received unexpected response type: " .. response_type
    end
    -- *** SIMPLIFIED ERROR HANDLING & INSPECTION END ***


    -- If we reached here, response is likely userdata, try to read its status and body
    print("Received userdata response object.")
    local statusCode = response.getStatusCode()
    print("Server response status code: " .. statusCode)

    -- Try to read the response body
    local response_body_content = "Could not read response body."
    local success_read, body_data = pcall(response.readAll)
    if success_read then
         response_body_content = body_data
    end

    -- Try to close the response
    local success_close = pcall(response.close)
    if not success_close then
         print("Warning: Could not close response object.")
    end


    print("Received response body preview (first 200 chars):")
    print(response_body_content:sub(1, 200) .. (#response_body_content > 200 and "..." or ""))


    if statusCode ~= 200 then
        return nil, "Server returned error code " .. statusCode .. ": " .. response_body_content
    end

    print("HTTP request successful. Received 200 OK.")
    return response_body_content -- Return the response body on success
end

-- Main program execution (test only)
print("YouTube HTTP Response Tester")
print("-------------------------")

-- Get YouTube URL from user input (for the request body)
write("Enter YouTube URL (for test request): ")
local youtube_url_input = read()

if youtube_url_input == "" then
    print("No URL entered. Exiting.")
    return
end

-- Run the test function
local received_data, err = testHttpResponse(youtube_url_input)

if received_data == nil then
    print("Test failed: " .. err)
    return
end

print("Test completed successfully (received a 200 OK).")
-- The actual response body content is in 'received_data'
