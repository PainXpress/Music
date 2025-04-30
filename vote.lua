-- disk_vote.lua

-- File names
local voteFile = "votes.dat"
local voterFile = "voters.dat"
local configFile = "config.dat"

-- Default configuration
local config = {
    question = "Vote for a community project:",
    choices = {"A - Build a park", "B - Build a library", "C - Build a statue"}
}

-- Load saved config
if fs.exists(configFile) then
    local f = fs.open(configFile, "r")
    config = textutils.unserialize(f.readAll())
    f.close()
end

-- Load vote data
local votes = {}
local voters = {}
for i, c in ipairs(config.choices) do
    local key = c:sub(1, 1):upper()
    votes[key] = 0
end

if fs.exists(voteFile) then
    local f = fs.open(voteFile, "r")
    votes = textutils.unserialize(f.readAll())
    f.close()
end

if fs.exists(voterFile) then
    local f = fs.open(voterFile, "r")
    voters = textutils.unserialize(f.readAll())
    f.close()
end

-- Save data
local function saveAll()
    local f1 = fs.open(voteFile, "w")
    f1.write(textutils.serialize(votes))
    f1.close()

    local f2 = fs.open(voterFile, "w")
    f2.write(textutils.serialize(voters))
    f2.close()

    local f3 = fs.open(configFile, "w")
    f3.write(textutils.serialize(config))
    f3.close()
end

-- Voting UI
local function voteMenu(name)
    term.clear()
    term.setCursorPos(1,1)
    print("Welcome, " .. name .. "!")
    print(config.question)
    for _, option in ipairs(config.choices) do
        print(option)
    end
    write("Enter your choice: ")
    local input = read():upper()

    if votes[input] and not voters[name] then
        votes[input] = votes[input] + 1
        voters[name] = true
        print("Thank you! Your vote has been recorded.")
        saveAll()
    elseif voters[name] then
        print("You have already voted.")
    else
        print("Invalid choice.")
    end
end

-- Admin menu
local function adminMenu()
    term.clear()
    term.setCursorPos(1,1)
    print("Admin Panel")
    print("1. View vote totals")
    print("2. Change question and choices")
    print("3. Reset all votes")
    write("Choose an option: ")
    local choice = read()

    if choice == "1" then
        print("\nVote Totals:")
        for k, v in pairs(votes) do
            print(k .. ": " .. v)
        end

    elseif choice == "2" then
        write("Enter new question: ")
        config.question = read()
        config.choices = {}
        votes = {}
        for i = 1, 5 do
            write("Enter choice " .. i .. " (or leave blank to stop): ")
            local opt = read()
            if opt == "" then break end
            local key = opt:sub(1,1):upper()
            table.insert(config.choices, opt)
            votes[key] = 0
        end
        voters = {}
        saveAll()
        print("Question and choices updated. Votes reset.")

    elseif choice == "3" then
        print("Are you sure? Type YES to confirm.")
        if read():upper() == "YES" then
            voters = {}
            for k in pairs(votes) do
                votes[k] = 0
            end
            saveAll()
            print("Votes reset.")
        else
            print("Reset cancelled.")
        end
    else
        print("Invalid option.")
    end
end

-- Main loop
while true do
    term.clear()
    term.setCursorPos(1,1)
    print("Insert your voting keycard (floppy disk)...")
    os.pullEvent("disk")

    -- Find inserted disk side
    local side
    for _, s in ipairs(peripheral.getNames()) do
        if peripheral.getType(s) == "drive" and disk.isPresent(s) then
            side = s
            break
        end
    end

    local label = disk.getLabel(side)
    if not label then
        print("Disk must be labeled with your name.")
    elseif label == "Admin" then
        adminMenu()
    else
        voteMenu(label)
    end

    print("\nRemove your disk...")
    while disk.isPresent(side) do sleep(0.1) end
    print("Disk removed. Returning to main screen...")
    sleep(1)
end
