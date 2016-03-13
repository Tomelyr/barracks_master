-- Contains general mechanics used extensively thourought different scripts

function SendErrorMessage( pID, string )
	Notifications:ClearBottom(pID)
	Notifications:Bottom(pID, {text=string, style={color='#E62020'}, duration=2})
	EmitSoundOnClient("General.Cancel", PlayerResource:GetPlayer(pID))
end

-- Modifies the lumber of this player. Accepts negative values
function ModifyLumber( player, lumber_value )
	local hero = player:GetAssignedHero()
	if lumber_value == 0 then return end
	if lumber_value > 0 then
		hero.lumber = hero.lumber + lumber_value
	    CustomGameEventManager:Send_ServerToPlayer(player, "player_lumber_changed", { lumber = math.floor(hero.lumber) })
	else
		if PlayerHasEnoughLumber( player, math.abs(lumber_value) ) then
			hero.lumber = hero.lumber + lumber_value
		    CustomGameEventManager:Send_ServerToPlayer(player, "player_lumber_changed", { lumber = math.floor(hero.lumber) })
		end
	end
end

-- Returns Int
function GetGoldCost( unit )
	if unit and IsValidEntity(unit) then
		if unit.GoldCost then
			return unit.GoldCost
		end
	end
	return 0
end

-- Returns Int
function GetLumberCost( unit )
	if unit and IsValidEntity(unit) then
		if unit.LumberCost then
			return unit.LumberCost
		end
	end
	return 0
end

-- Returns float
function GetBuildTime( unit )
	if unit and IsValidEntity(unit) then
		if unit.BuildTime then
			return unit.BuildTime
		end
	end
	return 0
end

function GetCollisionSize( unit )
	if unit and IsValidEntity(unit) then
		if GameRules.UnitKV[unit:GetUnitName()]["CollisionSize"] and GameRules.UnitKV[unit:GetUnitName()]["CollisionSize"] then
			return GameRules.UnitKV[unit:GetUnitName()]["CollisionSize"]
		end
	end
	return 0
end



-- Returns bool
function PlayerHasEnoughGold( player, gold_cost )
	local hero = player:GetAssignedHero()
	local pID = hero:GetPlayerID()
	local gold = hero:GetGold()

	print(gold , gold_cost, gold < gold_cost ) 
	if gold < gold_cost then
		SendErrorMessage(pID, "#error_not_enough_gold")
		return false
	else
		return true
	end
end

-- Returns bool
function PlayerHasEnoughLumber( player, lumber_cost )
	local pID = player:GetPlayerID()
	local hero = player:GetAssignedHero()

	if hero.lumber < lumber_cost then
		SendErrorMessage(pID, "#error_not_enough_lumber")
		return false
	else
		return true
	end
end

function GetResearchLevel(player, research_name)
	local hero = player:GetAssignedHero()
	return hero.upgrades[research_name]
end

-- Returns bool
function PlayerHasResearch( player, research_name )
	local hero = player:GetAssignedHero()
	if hero.upgrades[research_name] then
		return true
	else
		return false
	end
end

-- Returns bool
function PlayerHasRequirementForAbility( player, ability_name )
	-- Unlock all abilities cheat
	if GameRules.Synergy then
		return true
	end

	local hero = player:GetAssignedHero()
	local requirements = GameRules.Requirements
	local buildings = hero.buildings
	local upgrades = hero.upgrades
	local requirement_failed = false

	if requirements[ability_name] then
		-- Go through each requirement line and check if the player has that building on its list
		for k,v in pairs(requirements[ability_name]) do

			-- If it's an ability tied to a research, check the upgrades table
			if requirements[ability_name].research then
				if k ~= "research" and (not upgrades[k] or upgrades[k] == 0) then
					--print("Failed the research requirements for "..ability_name..", no "..k.." found")
					return false
				end
			else
				--print("Building Name","Need","Have")
				--print(k,v,buildings[k])

				-- If its a building, check every building requirement
				if not buildings[k] or buildings[k] == 0 then
					--print("Failed one of the requirements for "..ability_name..", no "..k.." found")
					return false
				end
			end
		end
	end

	return true
end

-- Builders require the "builder" label in its unit definition
function IsBuilder( unit )
	if not IsValidEntity(unit) then
		return
	end
	return (unit:GetUnitLabel() == "builder")
end

-- A BuildingHelper ability is identified by the "Building" key.
function IsBuildingAbility( ability )
	if not IsValidEntity(ability) then
		return
	end

	local ability_name = ability:GetAbilityName()
	local ability_table = GameRules.AbilityKV[ability_name]
	if ability_table and ability_table["Building"] then
		return true
	else
		ability_table = GameRules.ItemKV[ability_name]
		if ability_table and ability_table["Building"] then
			return true
		end
	end

	return false
end

function IsCustomBuilding( unit )
    local ability_building = unit:FindAbilityByName("ability_building")
    local ability_tower = unit:FindAbilityByName("ability_tower")
    if ability_building or ability_tower then
        return true
    else
        return false
    end
end

-- Shortcut for a very common check
function IsValidAlive( unit )
	return (IsValidEntity(unit) and unit:IsAlive())
end

-- ToggleAbility On only if its turned Off
function ToggleOn( ability )
	if ability:GetToggleState() == false then
		ability:ToggleAbility()
	end
end

-- ToggleAbility Off only if its turned On
function ToggleOff( ability )
	if ability:GetToggleState() == true then
		ability:ToggleAbility()
	end
end

function IsMultiOrderAbility( ability )
	if IsValidEntity(ability) then
		local ability_name = ability:GetAbilityName()
		local ability_table = GameRules.AbilityKV[ability_name]

		if not ability_table then
			ability_table = GameRules.ItemKV[ability_name]
		end

		if ability_table then
			local AbilityMultiOrder = ability_table["AbilityMultiOrder"]
			if AbilityMultiOrder and AbilityMultiOrder == 1 then
				return true
			end
		else
			print("Cant find ability table for "..ability_name)
		end
	end
	return false
end

-- Goes through every ability and item, checking for any ability being channelled
function IsChanneling ( hero )
	
	for abilitySlot=0,15 do
		local ability = hero:GetAbilityByIndex(abilitySlot)
		if ability ~= nil and ability:IsChanneling() then 
			return true
		end
	end

	for itemSlot=0,5 do
		local item = hero:GetItemInSlot(itemSlot)
		if item ~= nil and item:IsChanneling() then
			return true
		end
	end

	return false
end

-- Global item applier
function ApplyModifier( unit, modifier_name )
	local item = CreateItem("item_apply_modifiers", nil, nil)
	item:ApplyDataDrivenModifier(unit, unit, modifier_name, {})
	item:RemoveSelf()
end

-- Removes the first item by name if found on the unit. Returns true if removed
function RemoveItemByName( unit, item_name )
	for i=0,15 do
		local item = unit:GetItemInSlot(i)
		if item and item:GetAbilityName() == item_name then
			item:RemoveSelf()
			return true
		end
	end
	return false
end

-- Takes all items and puts them 1 slot back
function ReorderItems( caster )
	local slots = {}
	for itemSlot = 0, 5, 1 do

		-- Handle the case in which the caster is removed
		local item
		if IsValidEntity(caster) then
			item = caster:GetItemInSlot( itemSlot )
		end

       	if item ~= nil then
			table.insert(slots, itemSlot)
       	end
    end

    for k,itemSlot in pairs(slots) do
    	caster:SwapItems(itemSlot,k-1)
    end
end

-- Make all the gold unreliable for all players
function ConvertReliableGold()
    for playerID=0,DOTA_MAX_TEAM_PLAYERS do
        if PlayerResource:IsValidPlayer(playerID) then
            local gold = PlayerResource:GetGold(playerID)
            PlayerResource:SetGold(playerID, 0, true) --0 reliable
            PlayerResource:SetGold(playerID, gold, false) --all unreliable
        end
    end
end