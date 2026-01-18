--[[
    LootTracker - Test Harness
    Simple unit testing framework for WoW addons

    Usage:
        /lt test           - Run all tests
        /lt test [suite]   - Run specific test suite
        /lt test list      - List available test suites

    Test suites register themselves via LT.Test:RegisterSuite(name, tests)
]]

local _, LT = ...
LT.Test = {}

local Test = LT.Test

-- Test state
local testSuites = {}
local testResults = {
    passed = 0,
    failed = 0,
    skipped = 0,
    errors = {},
}

-- Colors for output
local COLORS = {
    pass = "|cff00ff00",
    fail = "|cffff0000",
    skip = "|cffff9900",
    info = "|cff00ffff",
    reset = "|r",
}

--[[
    ASSERTION FUNCTIONS
]]

local Assertions = {}

function Assertions.equals(actual, expected, message)
    if actual == expected then
        return true
    end
    return false, string.format("%s: expected %s, got %s",
        message or "equals", tostring(expected), tostring(actual))
end

function Assertions.notEquals(actual, notExpected, message)
    if actual ~= notExpected then
        return true
    end
    return false, string.format("%s: expected not %s",
        message or "notEquals", tostring(notExpected))
end

function Assertions.isTrue(value, message)
    if value == true then
        return true
    end
    return false, string.format("%s: expected true, got %s",
        message or "isTrue", tostring(value))
end

function Assertions.isFalse(value, message)
    if value == false then
        return true
    end
    return false, string.format("%s: expected false, got %s",
        message or "isFalse", tostring(value))
end

function Assertions.isNil(value, message)
    if value == nil then
        return true
    end
    return false, string.format("%s: expected nil, got %s",
        message or "isNil", tostring(value))
end

function Assertions.isNotNil(value, message)
    if value ~= nil then
        return true
    end
    return false, (message or "isNotNil") .. ": expected non-nil value"
end

function Assertions.isType(value, expectedType, message)
    if type(value) == expectedType then
        return true
    end
    return false, string.format("%s: expected type %s, got %s",
        message or "isType", expectedType, type(value))
end

function Assertions.contains(tbl, value, message)
    if type(tbl) ~= "table" then
        return false, (message or "contains") .. ": first argument must be a table"
    end
    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    return false, string.format("%s: table does not contain %s",
        message or "contains", tostring(value))
end

function Assertions.hasKey(tbl, key, message)
    if type(tbl) ~= "table" then
        return false, (message or "hasKey") .. ": first argument must be a table"
    end
    if tbl[key] ~= nil then
        return true
    end
    return false, string.format("%s: table does not have key '%s'",
        message or "hasKey", tostring(key))
end

function Assertions.tableEquals(actual, expected, message)
    if type(actual) ~= "table" or type(expected) ~= "table" then
        return false, (message or "tableEquals") .. ": both arguments must be tables"
    end

    -- Check all keys in expected exist in actual with same values
    for k, v in pairs(expected) do
        if type(v) == "table" then
            local success, err = Assertions.tableEquals(actual[k], v, message)
            if not success then
                return false, err
            end
        elseif actual[k] ~= v then
            return false, string.format("%s: key '%s' differs (expected %s, got %s)",
                message or "tableEquals", tostring(k), tostring(v), tostring(actual[k]))
        end
    end

    -- Check no extra keys in actual
    for k, _ in pairs(actual) do
        if expected[k] == nil then
            return false, string.format("%s: unexpected key '%s' in actual",
                message or "tableEquals", tostring(k))
        end
    end

    return true
end

function Assertions.greaterThan(actual, threshold, message)
    if actual > threshold then
        return true
    end
    return false, string.format("%s: expected > %s, got %s",
        message or "greaterThan", tostring(threshold), tostring(actual))
end

function Assertions.lessThan(actual, threshold, message)
    if actual < threshold then
        return true
    end
    return false, string.format("%s: expected < %s, got %s",
        message or "lessThan", tostring(threshold), tostring(actual))
end

function Assertions.matches(str, pattern, message)
    if type(str) == "string" and str:match(pattern) then
        return true
    end
    return false, string.format("%s: '%s' does not match pattern '%s'",
        message or "matches", tostring(str), pattern)
end

function Assertions.throws(func, message)
    local success, err = pcall(func)
    if not success then
        return true
    end
    return false, (message or "throws") .. ": expected function to throw an error"
end

--[[
    TEST EXECUTION
]]

-- Register a test suite
function Test:RegisterSuite(name, tests)
    testSuites[name] = tests
end

-- Run a single test
function Test:RunTest(suiteName, testName, testFunc)
    -- Create test context with assertions
    local ctx = {
        assert = Assertions,
        data = {},  -- For test data sharing
    }

    -- Run the test
    local success, err = pcall(testFunc, ctx)

    if not success then
        return false, "Error: " .. tostring(err)
    end

    return true
end

-- Run a test suite
function Test:RunSuite(suiteName)
    local suite = testSuites[suiteName]
    if not suite then
        print(COLORS.fail .. "Test suite not found: " .. suiteName .. COLORS.reset)
        return
    end

    print(COLORS.info .. "=== Running Test Suite: " .. suiteName .. " ===" .. COLORS.reset)

    local suitePassed = 0
    local suiteFailed = 0

    -- Run setup if exists
    if suite.setup then
        local success, err = pcall(suite.setup)
        if not success then
            print(COLORS.fail .. "  Suite setup failed: " .. tostring(err) .. COLORS.reset)
            return
        end
    end

    -- Run each test
    for testName, testFunc in pairs(suite) do
        if testName ~= "setup" and testName ~= "teardown" and type(testFunc) == "function" then
            local success, err = self:RunTest(suiteName, testName, testFunc)

            if success then
                print(COLORS.pass .. "  ✓ " .. testName .. COLORS.reset)
                suitePassed = suitePassed + 1
                testResults.passed = testResults.passed + 1
            else
                print(COLORS.fail .. "  ✗ " .. testName .. COLORS.reset)
                print(COLORS.fail .. "    " .. tostring(err) .. COLORS.reset)
                suiteFailed = suiteFailed + 1
                testResults.failed = testResults.failed + 1
                table.insert(testResults.errors, {
                    suite = suiteName,
                    test = testName,
                    error = err,
                })
            end
        end
    end

    -- Run teardown if exists
    if suite.teardown then
        pcall(suite.teardown)
    end

    print(string.format("  %s%d passed%s, %s%d failed%s",
        COLORS.pass, suitePassed, COLORS.reset,
        suiteFailed > 0 and COLORS.fail or COLORS.pass, suiteFailed, COLORS.reset))

    return suiteFailed == 0
end

-- Run all test suites
function Test:RunAll()
    print(COLORS.info .. "=====================================" .. COLORS.reset)
    print(COLORS.info .. "    LootTracker Test Runner" .. COLORS.reset)
    print(COLORS.info .. "=====================================" .. COLORS.reset)

    -- Reset results
    testResults = {
        passed = 0,
        failed = 0,
        skipped = 0,
        errors = {},
    }

    local startTime = GetTime()

    -- Run each suite
    for suiteName, _ in pairs(testSuites) do
        self:RunSuite(suiteName)
        print("")
    end

    local endTime = GetTime()

    -- Print summary
    print(COLORS.info .. "=====================================" .. COLORS.reset)
    print(string.format("  Total: %s%d passed%s, %s%d failed%s",
        COLORS.pass, testResults.passed, COLORS.reset,
        testResults.failed > 0 and COLORS.fail or COLORS.pass, testResults.failed, COLORS.reset))
    print(string.format("  Time: %.2f seconds", endTime - startTime))
    print(COLORS.info .. "=====================================" .. COLORS.reset)

    -- Return success status
    return testResults.failed == 0
end

-- List available test suites
function Test:ListSuites()
    print(COLORS.info .. "=== Available Test Suites ===" .. COLORS.reset)
    for suiteName, suite in pairs(testSuites) do
        local testCount = 0
        for name, func in pairs(suite) do
            if name ~= "setup" and name ~= "teardown" and type(func) == "function" then
                testCount = testCount + 1
            end
        end
        print(string.format("  %s (%d tests)", suiteName, testCount))
    end
end

-- Get last test results
function Test:GetResults()
    return testResults
end

--[[
    SLASH COMMAND HANDLER
]]

function Test:HandleCommand(args)
    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "" or cmd == "all" then
        self:RunAll()
    elseif cmd == "list" then
        self:ListSuites()
    elseif testSuites[cmd] then
        testResults = { passed = 0, failed = 0, skipped = 0, errors = {} }
        self:RunSuite(cmd)
    else
        print(COLORS.fail .. "Unknown test suite: " .. cmd .. COLORS.reset)
        print("Use '/lt test list' to see available suites")
    end
end

--[[
    MOCKING UTILITIES
]]

Test.Mock = {}

-- Create a mock function that records calls
function Test.Mock.func(returnValue)
    local mock = {
        calls = {},
        returnValue = returnValue,
    }

    setmetatable(mock, {
        __call = function(self, ...)
            table.insert(self.calls, { ... })
            return self.returnValue
        end
    })

    return mock
end

-- Create a mock WoW API
function Test.Mock.wowAPI()
    return {
        UnitName = function(unit)
            if unit == "player" then return "TestPlayer" end
            return "MockUnit"
        end,
        GetTime = function() return os.time() end,
        time = function() return os.time() end,
        IsInRaid = function() return false end,
        IsInGroup = function() return false end,
        GetNumGroupMembers = function() return 1 end,
        IsInGuild = function() return true end,
        GetGuildInfo = function() return "TestGuild", "Officer", 1 end,
        GetRaidRosterInfo = function(i)
            if i == 1 then return "TestPlayer", 2 end
            return nil
        end,
        SendChatMessage = Test.Mock.func(),
        C_ChatInfo = {
            SendAddonMessage = Test.Mock.func(true),
            RegisterAddonMessagePrefix = Test.Mock.func(true),
        },
    }
end
