--[[
    LootTracker - Events Unit Tests
    Tests for Core/Events.lua functionality, especially roll parsing
]]

local _, LT = ...

-- Register test suite after modules are loaded
C_Timer.After(1, function()
    LT.Test:RegisterSuite("Events", {
        --[[
            ROLL PARSING TESTS
            These are critical - test all edge cases since we can't fake system messages
        ]]

        test_ParseRoll_StandardFormat = function(ctx)
            local player, roll, min, max = LT.Events:ParseRoll("Playername rolls 85 (1-100)")

            ctx.assert.equals(player, "Playername", "Should parse player name")
            ctx.assert.equals(roll, 85, "Should parse roll value")
            ctx.assert.equals(min, 1, "Should parse min value")
            ctx.assert.equals(max, 100, "Should parse max value")
        end,

        test_ParseRoll_HighRoll = function(ctx)
            local player, roll, min, max = LT.Events:ParseRoll("Luckyone rolls 100 (1-100)")

            ctx.assert.equals(player, "Luckyone", "Should parse player name")
            ctx.assert.equals(roll, 100, "Should parse perfect roll")
        end,

        test_ParseRoll_LowRoll = function(ctx)
            local player, roll, min, max = LT.Events:ParseRoll("Unlucky rolls 1 (1-100)")

            ctx.assert.equals(player, "Unlucky", "Should parse player name")
            ctx.assert.equals(roll, 1, "Should parse lowest roll")
        end,

        test_ParseRoll_NameWithSpecialChars = function(ctx)
            -- WoW allows accented characters in some regions
            local player, roll = LT.Events:ParseRoll("Tëstçhar rolls 50 (1-100)")

            ctx.assert.equals(player, "Tëstçhar", "Should parse special characters")
            ctx.assert.equals(roll, 50, "Should parse roll value")
        end,

        test_ParseRoll_NameWithNumbers = function(ctx)
            local player, roll = LT.Events:ParseRoll("Player123 rolls 75 (1-100)")

            ctx.assert.equals(player, "Player123", "Should parse name with numbers")
            ctx.assert.equals(roll, 75, "Should parse roll value")
        end,

        test_ParseRoll_RealmName = function(ctx)
            -- Cross-realm players show as "Name-Realm"
            local player, roll = LT.Events:ParseRoll("Crossrealm-Stormrage rolls 42 (1-100)")

            ctx.assert.equals(player, "Crossrealm-Stormrage", "Should parse realm name")
            ctx.assert.equals(roll, 42, "Should parse roll value")
        end,

        test_ParseRoll_Non100Roll = function(ctx)
            -- /roll 50 produces "Player rolls X (1-50)"
            local player, roll, min, max = LT.Events:ParseRoll("Weirdroll rolls 25 (1-50)")

            ctx.assert.equals(player, "Weirdroll", "Should parse player")
            ctx.assert.equals(roll, 25, "Should parse roll")
            ctx.assert.equals(max, 50, "Should parse non-100 max")
        end,

        test_ParseRoll_CustomRange = function(ctx)
            -- /roll 50-100 produces different range
            local player, roll, min, max = LT.Events:ParseRoll("Custom rolls 75 (50-100)")

            ctx.assert.equals(player, "Custom", "Should parse player")
            ctx.assert.equals(min, 50, "Should parse custom min")
            ctx.assert.equals(max, 100, "Should parse custom max")
        end,

        test_ParseRoll_InvalidMessage = function(ctx)
            local player = LT.Events:ParseRoll("This is not a roll message")

            ctx.assert.isNil(player, "Should return nil for non-roll message")
        end,

        test_ParseRoll_EmptyMessage = function(ctx)
            local player = LT.Events:ParseRoll("")

            ctx.assert.isNil(player, "Should return nil for empty message")
        end,

        test_ParseRoll_PartialMatch = function(ctx)
            local player = LT.Events:ParseRoll("Player rolls")

            ctx.assert.isNil(player, "Should return nil for partial match")
        end,

        --[[
            ITEM LINK TESTS
        ]]

        test_GetItemName_FromLink = function(ctx)
            local itemLink = "|cff0070dd|Hitem:12345:0:0:0|h[Test Sword of Testing]|h|r"
            local name = LT.Events:GetItemName(itemLink)

            ctx.assert.equals(name, "Test Sword of Testing", "Should extract item name from link")
        end,

        test_GetItemName_PlainText = function(ctx)
            local name = LT.Events:GetItemName("Plain Text Item")

            ctx.assert.equals(name, "Plain Text Item", "Should return plain text as-is")
        end,

        test_GetItemName_Nil = function(ctx)
            local name = LT.Events:GetItemName(nil)

            ctx.assert.isNil(name, "Should return nil for nil input")
        end,

        --[[
            PERMISSION CHECKS (mock-aware tests)
        ]]

        test_IsRaidLeadership_FalseWhenNotInRaid = function(ctx)
            -- When not in raid, should return false
            -- This tests the early return
            if not IsInRaid() then
                local result = LT.Events:IsRaidLeadership("TestPlayer")
                ctx.assert.isFalse(result, "Should be false when not in raid")
            else
                -- Skip if actually in a raid
                ctx.assert.isTrue(true, "Skipped - in raid")
            end
        end,

        --[[
            ANNOUNCE TESTS
        ]]

        test_Announce_FallsBackToLocal = function(ctx)
            -- When not in raid/party, should print locally
            -- We can't easily test this without mocking, but we can verify it doesn't error
            local success = pcall(function()
                LT.Events:Announce("Test message", "RAID")
            end)

            ctx.assert.isTrue(success, "Announce should not error when not in group")
        end,

        --[[
            ROLL PARSING STRESS TESTS
        ]]

        test_ParseRoll_ManyDifferentNames = function(ctx)
            local testCases = {
                { msg = "Abc rolls 1 (1-100)", player = "Abc", roll = 1 },
                { msg = "Abcdefghijkl rolls 50 (1-100)", player = "Abcdefghijkl", roll = 50 },
                { msg = "X rolls 99 (1-100)", player = "X", roll = 99 },
                { msg = "Aa rolls 100 (1-100)", player = "Aa", roll = 100 },
            }

            for _, tc in ipairs(testCases) do
                local player, roll = LT.Events:ParseRoll(tc.msg)
                ctx.assert.equals(player, tc.player, "Failed for: " .. tc.msg)
                ctx.assert.equals(roll, tc.roll, "Roll failed for: " .. tc.msg)
            end
        end,

        test_ParseRoll_AllPossibleRolls = function(ctx)
            -- Test boundary values
            for _, rollValue in ipairs({ 1, 2, 50, 99, 100 }) do
                local msg = string.format("TestPlayer rolls %d (1-100)", rollValue)
                local player, roll = LT.Events:ParseRoll(msg)

                ctx.assert.equals(roll, rollValue, "Should parse roll value " .. rollValue)
            end
        end,
    })
end)
