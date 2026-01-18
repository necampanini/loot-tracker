--[[
    LootTracker - Database Unit Tests
    Tests for Core/Database.lua functionality
]]

local _, LT = ...

-- Register test suite after a short delay to ensure modules are loaded
C_Timer.After(1, function()
    LT.Test:RegisterSuite("Database", {
        -- Setup: Reset database before each suite run
        setup = function()
            -- Store original data
            LT.Test._originalDB = LootTrackerDB
            -- Initialize fresh database
            LootTrackerDB = nil
            LT.DB:Initialize()
        end,

        -- Teardown: Restore original data
        teardown = function()
            LootTrackerDB = LT.Test._originalDB
            LT.DB.db = LootTrackerDB
        end,

        --[[
            INITIALIZATION TESTS
        ]]

        test_Initialize_CreatesDefaultStructure = function(ctx)
            ctx.assert.isNotNil(LT.DB.db, "Database should be initialized")
            ctx.assert.hasKey(LT.DB.db, "rolls", "Should have rolls table")
            ctx.assert.hasKey(LT.DB.db, "stats", "Should have stats table")
            ctx.assert.hasKey(LT.DB.db, "attendance", "Should have attendance table")
            ctx.assert.hasKey(LT.DB.db, "config", "Should have config table")
        end,

        test_Initialize_PreservesExistingData = function(ctx)
            -- Add some data
            table.insert(LT.DB.db.rolls, { item = "Test Item", winner = "TestPlayer" })

            -- Re-initialize
            LT.DB:Initialize()

            -- Data should still exist
            ctx.assert.equals(#LT.DB.db.rolls, 1, "Should preserve existing rolls")
        end,

        --[[
            ROLL SESSION TESTS
        ]]

        test_StartRollSession_Success = function(ctx)
            local success, err = LT.DB:StartRollSession("Test Sword", "Officer1")

            ctx.assert.isTrue(success, "Should start session successfully")
            ctx.assert.isNil(err, "Should have no error")

            local session = LT.DB:GetActiveSession()
            ctx.assert.isNotNil(session, "Session should exist")
            ctx.assert.equals(session.item, "Test Sword", "Item should match")
            ctx.assert.equals(session.startedBy, "Officer1", "StartedBy should match")
            ctx.assert.equals(session.state, "open", "State should be open")
        end,

        test_StartRollSession_FailsWhenActive = function(ctx)
            LT.DB:StartRollSession("Item1", "Officer1")
            local success, err = LT.DB:StartRollSession("Item2", "Officer2")

            ctx.assert.isFalse(success, "Should fail to start second session")
            ctx.assert.matches(err, "already active", "Error should mention active session")
        end,

        test_RecordRoll_Success = function(ctx)
            LT.DB:StartRollSession("Test Item", "Officer1")

            local success, err = LT.DB:RecordRoll("Player1", 85, 1, 100)

            ctx.assert.isTrue(success, "Should record roll successfully")

            local session = LT.DB:GetActiveSession()
            ctx.assert.equals(#session.rolls, 1, "Should have one roll")
            ctx.assert.equals(session.rolls[1].player, "Player1", "Player should match")
            ctx.assert.equals(session.rolls[1].value, 85, "Roll value should match")
        end,

        test_RecordRoll_RejectsNon100Roll = function(ctx)
            LT.DB:StartRollSession("Test Item", "Officer1")

            local success, err = LT.DB:RecordRoll("Player1", 50, 1, 50)

            ctx.assert.isFalse(success, "Should reject non-100 roll")
            ctx.assert.matches(err, "1-100", "Error should mention 1-100")
        end,

        test_RecordRoll_RejectsDuplicateRoll = function(ctx)
            LT.DB:StartRollSession("Test Item", "Officer1")
            LT.DB:RecordRoll("Player1", 85, 1, 100)

            local success, err = LT.DB:RecordRoll("Player1", 90, 1, 100)

            ctx.assert.isFalse(success, "Should reject duplicate roll")
            ctx.assert.matches(err, "already rolled", "Error should mention already rolled")
        end,

        test_RecordRoll_FailsWithNoSession = function(ctx)
            local success, err = LT.DB:RecordRoll("Player1", 85, 1, 100)

            ctx.assert.isFalse(success, "Should fail with no session")
        end,

        test_GetHighestRollers_SingleWinner = function(ctx)
            LT.DB:StartRollSession("Test Item", "Officer1")
            LT.DB:RecordRoll("Player1", 85, 1, 100)
            LT.DB:RecordRoll("Player2", 50, 1, 100)
            LT.DB:RecordRoll("Player3", 72, 1, 100)

            local winners, highValue = LT.DB:GetHighestRollers()

            ctx.assert.equals(#winners, 1, "Should have one winner")
            ctx.assert.equals(winners[1].player, "Player1", "Winner should be Player1")
            ctx.assert.equals(highValue, 85, "Highest value should be 85")
        end,

        test_GetHighestRollers_DetectsTie = function(ctx)
            LT.DB:StartRollSession("Test Item", "Officer1")
            LT.DB:RecordRoll("Player1", 85, 1, 100)
            LT.DB:RecordRoll("Player2", 85, 1, 100)
            LT.DB:RecordRoll("Player3", 50, 1, 100)

            local winners, highValue = LT.DB:GetHighestRollers()

            ctx.assert.equals(#winners, 2, "Should have two tied winners")
            ctx.assert.equals(highValue, 85, "Highest value should be 85")
        end,

        test_StartReroll_SetsUpNextRound = function(ctx)
            LT.DB:StartRollSession("Test Item", "Officer1")
            LT.DB:RecordRoll("Player1", 85, 1, 100)
            LT.DB:RecordRoll("Player2", 85, 1, 100)

            local tiedPlayers = LT.DB:GetHighestRollers()
            local success, round = LT.DB:StartReroll(tiedPlayers)

            ctx.assert.isTrue(success, "Should start reroll")
            ctx.assert.equals(round, 1, "Should be round 1")

            local session = LT.DB:GetActiveSession()
            ctx.assert.equals(session.state, "rerolling", "State should be rerolling")
            ctx.assert.equals(#session.eligiblePlayers, 2, "Should have 2 eligible players")
        end,

        test_EndRollSession_DeterminesWinner = function(ctx)
            LT.DB:StartRollSession("Test Sword", "Officer1")
            LT.DB:RecordRoll("Player1", 85, 1, 100)
            LT.DB:RecordRoll("Player2", 50, 1, 100)

            local success, winner, record = LT.DB:EndRollSession()

            ctx.assert.isTrue(success, "Should end successfully")
            ctx.assert.isNotNil(winner, "Should have a winner")
            ctx.assert.equals(winner.player, "Player1", "Winner should be Player1")
            ctx.assert.equals(winner.value, 85, "Winner roll should be 85")

            -- Check record was saved
            ctx.assert.equals(#LT.DB.db.rolls, 1, "Should have one roll record")
            ctx.assert.equals(LT.DB.db.rolls[1].winner, "Player1", "Record winner should match")
        end,

        test_EndRollSession_ReturnsTieIfNotResolved = function(ctx)
            LT.DB:StartRollSession("Test Item", "Officer1")
            LT.DB:RecordRoll("Player1", 85, 1, 100)
            LT.DB:RecordRoll("Player2", 85, 1, 100)

            local success, winners, msg = LT.DB:EndRollSession()

            ctx.assert.isFalse(success, "Should return false for tie")
            ctx.assert.isType(winners, "table", "Should return tied players")
            ctx.assert.equals(#winners, 2, "Should have 2 tied players")
            ctx.assert.matches(msg, "Tie", "Message should mention tie")
        end,

        test_CancelRollSession_ClearsSession = function(ctx)
            LT.DB:StartRollSession("Test Item", "Officer1")
            LT.DB:RecordRoll("Player1", 85, 1, 100)

            local success = LT.DB:CancelRollSession()

            ctx.assert.isTrue(success, "Should cancel successfully")
            ctx.assert.isNil(LT.DB:GetActiveSession(), "Session should be nil")
            ctx.assert.equals(#LT.DB.db.rolls, 0, "Should not save cancelled roll")
        end,

        --[[
            PLAYER STATISTICS TESTS
        ]]

        test_UpdatePlayerStats_TracksWins = function(ctx)
            LT.DB:UpdatePlayerStats("Player1", true, 85)
            LT.DB:UpdatePlayerStats("Player1", true, 90)
            LT.DB:UpdatePlayerStats("Player1", false, 30)

            local stats = LT.DB:GetPlayerStats("Player1")

            ctx.assert.equals(stats.wins, 2, "Should have 2 wins")
            ctx.assert.equals(stats.losses, 1, "Should have 1 loss")
            ctx.assert.equals(stats.totalRolls, 3, "Should have 3 total rolls")
        end,

        test_GetPlayerStats_CalculatesDerivedStats = function(ctx)
            LT.DB:UpdatePlayerStats("Player1", true, 80)
            LT.DB:UpdatePlayerStats("Player1", true, 90)
            LT.DB:UpdatePlayerStats("Player1", false, 30)
            LT.DB:UpdatePlayerStats("Player1", false, 40)

            local stats = LT.DB:GetPlayerStats("Player1")

            ctx.assert.equals(stats.winRate, 50, "Win rate should be 50%")
            ctx.assert.equals(stats.avgRoll, 60, "Average roll should be 60")
            ctx.assert.equals(stats.highestRoll, 90, "Highest roll should be 90")
            ctx.assert.equals(stats.lowestRoll, 30, "Lowest roll should be 30")
        end,

        test_GetAllPlayerStats_SortsByWins = function(ctx)
            LT.DB:UpdatePlayerStats("Player1", true, 80)
            LT.DB:UpdatePlayerStats("Player2", true, 70)
            LT.DB:UpdatePlayerStats("Player2", true, 85)
            LT.DB:UpdatePlayerStats("Player3", false, 50)

            local allStats = LT.DB:GetAllPlayerStats()

            ctx.assert.equals(allStats[1].name, "Player2", "Player2 should be first (2 wins)")
            ctx.assert.equals(allStats[2].name, "Player1", "Player1 should be second (1 win)")
        end,

        --[[
            ATTENDANCE TESTS
        ]]

        test_StartRaidSession_Success = function(ctx)
            local success, err = LT.DB:StartRaidSession("Molten Core", "RaidLeader")

            ctx.assert.isTrue(success, "Should start raid session")

            local raid = LT.DB:GetActiveRaid()
            ctx.assert.isNotNil(raid, "Raid should exist")
            ctx.assert.equals(raid.name, "Molten Core", "Raid name should match")
        end,

        test_AddAttendee_AddsPlayer = function(ctx)
            LT.DB:StartRaidSession("Test Raid", "Leader")

            local success = LT.DB:AddAttendee("Player1")
            ctx.assert.isTrue(success, "Should add attendee")

            local raid = LT.DB:GetActiveRaid()
            ctx.assert.equals(#raid.attendees, 1, "Should have 1 attendee")
            ctx.assert.equals(raid.attendees[1], "Player1", "Attendee should be Player1")
        end,

        test_AddAttendee_RejectsDuplicate = function(ctx)
            LT.DB:StartRaidSession("Test Raid", "Leader")
            LT.DB:AddAttendee("Player1")

            local success, err = LT.DB:AddAttendee("Player1")

            ctx.assert.isFalse(success, "Should reject duplicate")
            ctx.assert.matches(err, "already", "Error should mention already added")
        end,

        test_EndRaidSession_SavesRecord = function(ctx)
            LT.DB:StartRaidSession("Test Raid", "Leader")
            LT.DB:AddAttendee("Player1")
            LT.DB:AddAttendee("Player2")

            local success, record = LT.DB:EndRaidSession()

            ctx.assert.isTrue(success, "Should end successfully")
            ctx.assert.equals(#LT.DB.db.attendance.raids, 1, "Should have 1 raid record")
            ctx.assert.equals(#record.attendees, 2, "Record should have 2 attendees")
        end,

        test_GetAttendanceRate_CalculatesCorrectly = function(ctx)
            -- Create two raid records
            LT.DB:StartRaidSession("Raid1", "Leader")
            LT.DB:AddAttendee("Player1")
            LT.DB:AddAttendee("Player2")
            LT.DB:EndRaidSession()

            LT.DB:StartRaidSession("Raid2", "Leader")
            LT.DB:AddAttendee("Player1")
            -- Player2 absent
            LT.DB:EndRaidSession()

            local rate1 = LT.DB:GetAttendanceRate("Player1")
            local rate2 = LT.DB:GetAttendanceRate("Player2")

            ctx.assert.equals(rate1, 100, "Player1 should have 100% attendance")
            ctx.assert.equals(rate2, 50, "Player2 should have 50% attendance")
        end,

        --[[
            DATA QUERY TESTS
        ]]

        test_GetRollHistory_FiltersCorrectly = function(ctx)
            -- Add some test records directly
            table.insert(LT.DB.db.rolls, {
                item = "Sword of Testing",
                winner = "Player1",
                startTime = time() - 3600,
                endTime = time() - 3500,
            })
            table.insert(LT.DB.db.rolls, {
                item = "Shield of Testing",
                winner = "Player2",
                startTime = time() - 1800,
                endTime = time() - 1700,
            })

            local all = LT.DB:GetRollHistory()
            ctx.assert.equals(#all, 2, "Should have 2 records")

            local filtered = LT.DB:GetRollHistory({ player = "Player1" })
            ctx.assert.equals(#filtered, 1, "Should filter to 1 record")
            ctx.assert.equals(filtered[1].winner, "Player1", "Filtered record should be Player1's")
        end,

        --[[
            CONFIGURATION TESTS
        ]]

        test_SetConfig_UpdatesValue = function(ctx)
            local success = LT.DB:SetConfig("announceWinner", false)

            ctx.assert.isTrue(success, "Should update config")
            ctx.assert.isFalse(LT.DB:GetConfig().announceWinner, "Config should be updated")
        end,

        test_SetConfig_RejectsInvalidKey = function(ctx)
            local success = LT.DB:SetConfig("invalidKey", "value")

            ctx.assert.isFalse(success, "Should reject invalid key")
        end,

        --[[
            EDGE CASES
        ]]

        test_DeepCopy_CopiesTables = function(ctx)
            local original = { a = 1, b = { c = 2 } }
            local copy = LT.DB:DeepCopy(original)

            copy.a = 100
            copy.b.c = 200

            ctx.assert.equals(original.a, 1, "Original should be unchanged")
            ctx.assert.equals(original.b.c, 2, "Nested original should be unchanged")
        end,
    })
end)
