------------------------------------------
--             Build Scripts
------------------------------------------

-- A build ability is used (not yet confirmed)
function Build( event )
    local caster = event.caster
    local ability = event.ability
    local ability_name = ability:GetAbilityName()
    local AbilityKV = BuildingHelper.AbilityKV
    local UnitKV = BuildingHelper.UnitKV

    -- Hold needs an Interrupt
    if caster.bHold then
        caster.bHold = false
        caster:Interrupt()
    end

    -- Handle the name for item-ability build
    local building_name = nil
    if event.ItemUnitName then
        building_name = event.ItemUnitName --Directly passed through the runscript
    else
        building_name = AbilityKV[ability_name].UnitName --Building Helper value
    end

    -- Checks if there is enough custom resources to start the building, else stop.
    local unit_table = UnitKV[building_name]
    local build_time = ability:GetSpecialValueFor("build_time")
    local gold_cost = ability:GetSpecialValueFor("gold_cost")
    print("Gold1")
    local lumber_cost = ability:GetSpecialValueFor("lumber_cost")

    local hero = caster:GetPlayerOwner():GetAssignedHero()
    local playerID = hero:GetPlayerID()
    local player = PlayerResource:GetPlayer(playerID)   

    -- If the ability has an AbilityGoldCost, it's impossible to not have enough gold the first time it's cast
    -- Always refund the gold here, as the building hasn't been placed yet
    --ability:GetGoldCost(1) 
    hero:ModifyGold(gold_cost, false, 0)
    print("Gold2")

    if not PlayerHasEnoughLumber( player, lumber_cost ) then
        -- include sound for insufficient lumber here -- cows
        SendErrorMessage(playerID, "#error_not_enough_lumber")      
        return
    end

    -- <<<VEGGIESAMA
    -- Ultimate towers possess the "UltimateTower" unit label in their unit KV
    -- Only one ultimate tower may be built per player.
    if IsUltimateTower(building_name) and HasBuiltUltimateTower(player) then
        SendErrorMessage(playerID, "#error_max_ultimate_towers")
        return
    end

    -- Set MaxBuildingCount in the ability KV to trigger this check.
    -- No one player can build more than X building units at a time.
    if HasReachedMaxBuildingLimit(player, ability_name, building_name) then
        SendErrorMessage(playerID, "#error_max_building_count")
        --print("MaxBuildingCount limit reached! Aborting build command.")
        return
    end
    -- VEGGIESAMA>>>

    -- Makes a building dummy and starts panorama ghosting
    BuildingHelper:AddBuilding(event)

    -- Additional checks to confirm a valid building position can be performed here
    event:OnPreConstruction(function(vPos)

        -- Blight check
        --[[if string.match(building_name, "undead") and building_name ~= "undead_necropolis" then
            local bHasBlight = HasBlight(vPos)
            DebugPrint("[BH] Blight check for "..building_name..":", bHasBlight)
            if not bHasBlight then
                SendErrorMessage(caster:GetPlayerOwnerID(), "#error_must_build_on_blight")
                return false
            end
        end]]--

        -- If attempting to build below a certain height, reject (to deny building in lane)
        if vPos.z < 250 then
            SendErrorMessage(caster:GetPlayerOwnerID(), "#error_cannot_build_in_lane")
            return false
        end

        -- If not enough resources to queue, stop
        if not PlayerHasEnoughGold(player, gold_cost) then
            print("Gold3")
            SendErrorMessage(caster:GetPlayerOwnerID(), "#error_not_enough_gold")
            return false
        end

        if not PlayerHasEnoughLumber(player, lumber_cost) then
            SendErrorMessage(caster:GetPlayerOwnerID(), "#error_not_enough_lumber")         
            return false
        end

        -- If max count reached, stop
        print("precheck")
        if HasReachedMaxBuildingLimit(player, ability_name, building_name) then
            SendErrorMessage(playerID, "#test")
            print("check complete")
            return false
        end
        
        return true
    end)

    -- Position for a building was confirmed and valid
    event:OnBuildingPosChosen(function(vPos)
        
        -- Spend resources
        hero:ModifyGold(-gold_cost, false, 0)
        print("Gold4 - Consumed when ghost is confirmed")
        ModifyLumber( player, -lumber_cost)

        -- Play a sound
        --EmitSoundOnClient("DOTA_Item.ObserverWard.Activate", player)

        -- Move the units away from the building place
    

    end)

    -- The construction failed and was never confirmed due to the gridnav being blocked in the attempted area
    event:OnConstructionFailed(function()
        local playerTable = BuildingHelper:GetPlayerTable(playerID) 
        local name = playerTable.activeBuilding 
        DebugPrint("[BH] Failed placement of " .. name)
        SendErrorMessage(caster:GetPlayerOwnerID(), "#error_invalid_build_position")
    end)

    -- Cancelled due to ClearQueue
    event:OnConstructionCancelled(function(work)
        local name = work.name
        DebugPrint("[BH] Cancelled construction of " .. name)

        -- Refund resources if work never begins and order is stopped
        if work.refund then
            hero:ModifyGold(gold_cost, false, 0)
            print("Gold5 - refund gold if building does not get built")
            ModifyLumber( player, lumber_cost)
        end
    end)

    -- A building unit was created
    event:OnConstructionStarted(function(unit)
        DebugPrint("[BH] Started construction of " .. unit:GetUnitName() .. " " .. unit:GetEntityIndex())

        -- Play construction sound -- cows
        --Sounds:EmitSoundOnClient(playerID, "BarracksMaster.Building") -- need to have 2 includes for this to work
        EmitSoundOn("BarracksMaster.Building", caster)
        print("Building Construction Start")

        -- Store the Build Time, Gold Cost and secondary resource the building 
        -- This is to refund the resources if the building is not completed
        unit.GoldCost = gold_cost
        print("Gold6 - Store Info")
        unit.LumberCost = lumber_cost
        unit.BuildTime = build_time

        -- Give item to cancel
        local item = CreateItem("item_building_cancel", playersHero, playersHero)
        unit:AddItem(item)

        -- FindClearSpace for the builder
        FindClearSpaceForUnit(caster, caster:GetAbsOrigin(), true)
        caster:AddNewModifier(caster, nil, "modifier_phased", {duration=0.03})

        -- Remove invulnerability on npc_dota_building baseclass
        unit:RemoveModifierByName("modifier_invulnerable")

        -- Particle effect
        ApplyModifier(unit, "modifier_construction")

        -- Check the abilities of this building, disabling those that don't meet the requirements
        CheckAbilityRequirements( unit, player )

        -- Add the building handle to the list of structures
        table.insert(hero.structures, unit)

        -- colorize the building when construction starts
        local playerColor = GetPlayerColor(player)
        ApplyColorToUnit(unit, playerColor)
    end)

    -- A building finished construction
    event:OnConstructionCompleted(function(unit)
        DebugPrint("[BH] Completed construction of " .. unit:GetUnitName() .. " " .. unit:GetEntityIndex())
        
        -- Play construction complete sound
        EmitSoundOn("BarracksMaster.ConstructionComplete", caster) -- cows
        print("Building Finished")

        -- Popup notification and sound for specific buildings
        local dur = 4.0
        if unit:GetUnitName() == "bm_library" then
            Notifications:BottomToAll({text="#warning_library", duration=dur, style={color="red", ["font-size"]="40px"}})
            EmitGlobalSound("General.PingWarning")
        end

        -- Remove Particle Effect
        unit:RemoveModifierByName("modifier_construction")

        -- Remove item_building_cancel
        for i=0,5 do
            local item = unit:GetItemInSlot(i)
            if item then
                if item:GetAbilityName() == "item_building_cancel" then
                    item:RemoveSelf()
                end
            end
        end

        local building_name = unit:GetUnitName()
        local builders = {}
        if unit.builder then
            table.insert(builders, unit.builder)
        elseif unit.units_repairing then
            builders = unit.units_repairing
        end

        -- Add 1 to the player building tracking table for that name
        if not hero.buildings[building_name] then
            hero.buildings[building_name] = 1
        else
            hero.buildings[building_name] = hero.buildings[building_name] + 1
        end

        -- Update the abilities of the builders and buildings
        for k,units in pairs(hero.units) do
            CheckAbilityRequirements( units, player )
        end

        for k,structure in pairs(hero.structures) do
            CheckAbilityRequirements( structure, player )
        end

    end)

    -- These callbacks will only fire when the state between below half health/above half health changes.
    -- i.e. it won't fire multiple times unnecessarily.
    event:OnBelowHalfHealth(function(unit)
        DebugPrint("[BH] " .. unit:GetUnitName() .. " is below half health.")
                
        local item = CreateItem("item_apply_modifiers", nil, nil)
        item:ApplyDataDrivenModifier(unit, unit, "modifier_onfire", {})
        item = nil

    end)

    event:OnAboveHalfHealth(function(unit)
        DebugPrint("[BH] " ..unit:GetUnitName().. " is above half health.")

        unit:RemoveModifierByName("modifier_onfire")
        
    end)
end

-- Called when the move_to_point ability starts
function StartBuilding( keys )
    BuildingHelper:StartBuilding(keys)
end

-- Called when the Cancel ability-item is used
function CancelBuilding( keys )
    BuildingHelper:CancelBuilding(keys)
end

-- Called when a unit with UltimateTower label is built -- cows
function IsUltimateTower(building_name)
    local unitTable = GameRules.UnitKV[building_name]
    return (unitTable.UnitLabel == "UltimateTower")
end

function HasBuiltUltimateTower(player)
    local hero = player:GetAssignedHero()
    for _,building in pairs(hero.structures) do
        if building and IsValidEntity(building) and building:GetUnitLabel() == "UltimateTower" then
            return true
        end
    end

    return false
end

-- Called when a unit has a MaxBuildingCount attribute 
function HasReachedMaxBuildingLimit(player, ability_name, building_name)
    local hero = player:GetAssignedHero()
    local buildingCounter = 0
    for _,building in pairs(hero.structures) do
        if building and IsValidEntity(building) and building:GetUnitName() == building_name then
            buildingCounter = buildingCounter + 1
        end
    end

    local maxBuildingCount = GameRules.AbilityKV[ability_name].MaxBuildingCount
    if maxBuildingCount ~= nil and buildingCounter >= maxBuildingCount then
        return true
    end

    return false
end