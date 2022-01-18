local util = require("util")
local NetworkComponent = require("network_component_class")

local em = {
    nuid_counter = 0,
    cache = {
        all_entity_ids = {},
        nc_entity_ids = {}
    }
}

--- Simply generates a new NUID by increasing by 1
--- @return integer nuid
function em.GetNextNuid()
    em.nuid_counter = em.nuid_counter + 1
    return em.nuid_counter
end

--- Checks for entities (only for his own - locally) in a specific range/radius to the player_units.
--- If there are entities in this radius, a NetworkComponent will be added as a VariableStorageComponent.
--- If entities does not have VelocityComponents, those will be ignored.
--- Every checked entity will be put into a cache list, to stop iterating over the same entities again and again.
function em.AddNetworkComponent()
    local player_unit_ids = EntityGetWithTag("player_unit")
    for i_p = 1, #player_unit_ids do
        -- get all player units
        local x, y, rot, scale_x, scale_y = EntityGetTransform(player_unit_ids[i_p])

        -- find all entities in a specific radius based on the player units position
        local entity_ids = EntityGetInRadius(x, y, 1000)

        for i_e = 1, #entity_ids do
            local entity_id = entity_ids[i_e]
            local filename = EntityGetFilename(entity_id)

            if not em.cache.all_entity_ids[entity_id] then -- if entity was already checked, skip it
                -- loop all components of the entity
                local component_ids = EntityGetAllComponents(entity_id)

                local has_velocity_component = false
                for i_c = 1, #component_ids do
                    local component_id = component_ids[i_c]

                    -- search for VelocityComponent
                    local component_name = ComponentGetTypeName(component_id)
                    if component_name == "VelocityComponent" then
                        has_velocity_component = true
                        local velo_x, velo_y = ComponentGetValue2(component_id, "mVelocity")
                        local velocity = {velo_x, velo_y}

                        local variable_storage_component_ids =
                            EntityGetComponentIncludingDisabled(entity_id, "VariableStorageComponent") or {}

                        local has_network_component = false
                        for i_v = 1, #variable_storage_component_ids do
                            local variable_storage_component_id = variable_storage_component_ids[i_v]
                            -- check if the entity already has a VariableStorageComponent
                            local variable_storage_component_name =
                                ComponentGetValue2(variable_storage_component_id, "name") or nil
                            if variable_storage_component_name == "network_component_class" then
                                -- if entity already has a VariableStorageComponent with the name of 'network_component_class', skip it
                                has_network_component = true
                            end
                        end

                        if has_network_component == false then
                            local nuid = nil
                            local x_e, y_e, rot_e = EntityGetTransform(entity_id)

                            if _G.Server:amIServer() then
                                nuid = em.GetNextNuid()

                                _G.Server:sendNewNuid(
                                    util.getLocalOwner(),
                                    entity_id,
                                    nuid,
                                    x_e,
                                    y_e,
                                    rot_e,
                                    velocity,
                                    filename
                                )
                            else
                                _G.Client:sendNeedNuid(entity_id, velocity)
                            end
                            -- if the VariableStorageComponent is not a 'network_component_class', then add one
                            em.AddNetworkComponentToEntity(entity_id, util.getLocalOwner(), nuid)
                        end
                    end
                end

                if has_velocity_component == false then
                    -- if the entity does not have a VelocityComponent, skip it always
                    -- logger:debug("Entity %s does not have a VelocityComponent. Ignore it.", entity_id)
                    em.cache.all_entity_ids[entity_id] = true
                end
            end
        end
    end
end

--- Adds a NetworkComponent to an entity, if it doesn't exist already.
--- @param entity_id number The entity id where to add the NetworkComponent.
--- @param owner table { username, guid }
--- @param nuid number nuid to know the entity wiht network component
--- @return number component_id Returns the component_id. The already existed one or the newly created id.
function em.AddNetworkComponentToEntity(entity_id, owner, nuid)
    local variable_storage_component_ids =
        EntityGetComponentIncludingDisabled(entity_id, "VariableStorageComponent") or {}

    -- check if the entity already has a NetworkComponent. If so skip this function by returning the component_id
    for i_v = 1, #variable_storage_component_ids do
        local variable_storage_component_id = variable_storage_component_ids[i_v]
        local variable_storage_component_name = ComponentGetValue2(variable_storage_component_id, "name") or nil
        local nc_serialised = ComponentGetValue2(variable_storage_component_id, "value_string") or nil
        local nc = nil

        if not util.IsEmpty(nc_serialised) then
            nc = util.deserialise(nc_serialised)
        end

        if variable_storage_component_name == "network_component_class" and nc.nuid == nuid then
            -- if entity already has a VariableStorageComponent with the name of 'network_component_class', skip it
            em.cache.all_entity_ids[entity_id] = true
            return variable_storage_component_id
        end
    end

    local component_id =
        EntityAddComponent2(
        entity_id,
        "VariableStorageComponent",
        {
            name = "network_component_class",
            value_string = nil -- will be set after creation, because NetworkComponent has to be serialised
        }
    )
    logger:debug(
        "VariableStorageComponent (nuid=%s) added with noita component_id = %s to entity_id = %s!",
        nuid,
        component_id,
        entity_id
    )

    local nc = NetworkComponent:new(owner, nuid, entity_id, component_id)
    local nc_serialised = util.serialise(nc:toSerialisableTable())

    ComponentSetValue2(component_id, "value_string", nc_serialised)
    logger:debug(
        "Added network component (nuid=%s) to the VariableStorageComponent as a serialised string: component_id=%s to entity_id=%s!",
        nuid,
        component_id,
        entity_id
    )

    em.cache.nc_entity_ids[entity_id] = component_id
    em.cache.all_entity_ids[entity_id] = true

    util.debug_entity(entity_id)

    return component_id
end

function em.setNuid(owner, local_entity_id, nuid)
    local nc = em.GetNetworkComponent(owner, local_entity_id, nuid)
    if nc.nuid ~= nil then
        logger:warning("Nuid %s of entity %s was already set, although it's a local new one? It will be skipped!", nuid, local_entity_id)
        return
    end

    local owner_guid = owner.guid or owner[2]
    local nc_guid = nc.owner.guid or nc.owner[2]

    if nc_guid ~= owner_guid then
        error(
            ("%s (%s) tries to set nuid %s of different nc.owners %s (%s) entity %s."):format(
                owner.username or owner[1],
                owner.guid or owner[2],
                nuid,
                nc.owner.username or nc.owner[1],
                nc.owner.guid or nc.owner[2],
                local_entity_id
            ),
            2
        )
    end
    nc.nuid = nuid
    ComponentSetValue2(nc.noita_component_id, "value_string", util.serialise(nc))
    logger:debug(
        "Got new nuid (%s) from %s (%s) and set it to entity %s",
        nuid,
        owner.username or owner[1],
        owner_guid,
        local_entity_id
    )
end

--- Spwans an entity and applies the transform and velocity to it. Also adds the network_component.
---@param owner table { username, guid }
---@param nuid any
---@param x any
---@param y any
---@param rot any
---@param velocity table {x, y} - can be nil
---@param filename any
---@param local_entity_id number this is the initial entity_id created by server OR client. It's owner specific! Every owner has its own entity ids.
---@return number
function em.SpawnEntity(owner, nuid, x, y, rot, velocity, filename, local_entity_id)
    local local_guid = util.getLocalOwner().guid or util.getLocalOwner()[2]
    local owner_guid = owner.guid or owner[2]

    if local_guid == owner_guid then
        -- if the owner sent by network is the local owner, don't spawn an additional entity, but update the nuid
        em.setNuid(owner, local_entity_id, nuid)
        return
    end

    local entity_id = EntityLoad(filename, x, y)
    em.AddNetworkComponentToEntity(entity_id, owner, nuid)
    EntityApplyTransform(entity_id, x, y, rot)

    local velo_comp_id = EntityGetFirstComponent(entity_id, "VelocityComponent")
    if velocity and velo_comp_id then
        ComponentSetValue2(velo_comp_id, "mVelocity", velocity[1], velocity[2])
    end

    -- local velo_comp_ids = EntityGetComponent(entity_id, "VelocityComponent")
    -- if velocity and velo_comp_ids then
    --     for i = 1, #velo_comp_ids do
    --         ComponentSetValue2(velo_comp_ids[i], "mVelocity", velocity[1], velocity[2])
    --     end
    -- end

    return entity_id
end

function em.DespawnEntity(owner, local_entity_id, nuid, is_alive)
    local nc = em.GetNetworkComponent(owner, local_entity_id, nuid)
    local entity_id = local_entity_id

    if nc.local_entity_id ~= local_entity_id then
        -- update entity_id, because the owner of the entity is not the local owner and the local_entity_id is not the correct one
        entity_id = nc.local_entity_id
    end

    if not is_alive then
        -- might be that the entity already was killed locally
        local alive = EntityGetIsAlive(entity_id)
        if alive then
            EntityKill(entity_id)
            logger:debug("Killed entity %s!", entity_id)
        else
            logger:debug("Entity %s was already killed locally!", entity_id)
        end
    end
end

function em.UpdateEntities()
    for e = 1, #em.cache.nc_entity_ids do
        local entity_id = em.cache.nc_entity_ids[e]
        local nc = em.GetNetworkComponent(entity_id, nil)
        local owner = util.getLocalOwner()
        local nuid = nc.nuid

        if EntityGetIsAlive(entity_id) == false then
            if _G.Server:amIServer() then
                _G.Server.super:sendToAll2("entityAlive", {owner, entity_id, nuid, false})
            else
                _G.Client.super:send("entityAlive", {owner, entity_id, nuid, false})
            end
        else
            local x, y, rot = EntityGetTransform(entity_id)
            local velo_comp_id = EntityGetFirstComponent(entity_id, "VelocityComponent")
            local velo_x, velo_y = ComponentGetValue2(velo_comp_id, "mVelocity")
            local velocity = {velo_x, velo_y}

            if _G.Server:amIServer() then
                _G.Server.super:sendToAll2("entityState", {owner, entity_id, nuid, x, y, rot, velocity, health})
            else
                _G.Client.super:send("entityState", {owner, entity_id, nuid, x, y, rot, velocity, health})
            end
        end
    end
end

--- Get a network component by its entity id
--- @param owner table { username, guid }
--- @param entity_id number Id of the entity, but related to the owner.
--- @param nuid number Network-Id of the component.
--- @return table nc Returns the network component.
function em.GetNetworkComponent(owner, entity_id, nuid)
    local nc = nil
    local nc_id = nil
    local guid = owner.guid or owner[2]

    if util.getLocalOwner().guid == guid then
        -- this local owner created the entity and its cached
        nc_id = em.cache.nc_entity_ids[entity_id]
    end

    -- may happen that the nc_id is still nil, because entity might not exist anymore
    -- or in addition the owner of the entity is not the local one
    -- therefore find network component by NUID
    if not nc_id or nc_id == nil then
        local index = table.indexOf(em.cache.nc_entity_ids, nuid)
        nc_id = em.cache.nc_entity_ids[index]
    end

    local nc_serialised = ComponentGetValue(nc_id, "value_string")
    nc = util.deserialise(nc_serialised)
    return nc
end

function em.getLocalPlayerId()
    local player_unit_ids = EntityGetWithTag("player_unit")
    for i_p = 1, #player_unit_ids do
        local nc = em.GetNetworkComponent(player_unit_ids[i_p])
        if nc and nc.owner.guid == ModSettingGet("noita-mp.guid") then
            return player_unit_ids[i_p]
        end
    end
    return player_unit_ids[1]
end

return em
