-- OOP class definition is found here: Closure approach
-- http://lua-users.org/wiki/ObjectOrientationClosureApproach
-- Naming convention is found here:
-- http://lua-users.org/wiki/LuaStyleGuide#:~:text=Lua%20internal%20variable%20naming%20%2D%20The,but%20not%20necessarily%2C%20e.g.%20_G%20.

local util = require("util")
local fu = require("file_util")
local nxml = require("nxml")
local GlobalsUtils = require("GlobalsUtils")

-----------------
-- NuidUtils:
-----------------
--- class for getting the current network unique identifier
NuidUtils = {}

--#region Global private variables

local counter = -1

--#endregion

--#region Global private functions

local function getNextNuid()
    local whoAmI = _G.whoAmI()
    if whoAmI == "CLIENT" or util.IsEmpty(whoAmI) then
        error(("Unable to get next nuid, because looks like you aren't a server?! - whoAmI = %s"):format(whoAmI), 2)
    end

    -- Are there any nuids saved in globals, if so get the highest nuid?
    local worldStateXmlAbsPath = fu.GetAbsDirPathOfWorldStateXml("save01") -- TODO in https://github.com/Ismoh/NoitaMP/issues/39
    if fu.Exists(worldStateXmlAbsPath) then
        local f = io.open(worldStateXmlAbsPath, "r")
        local xml = nxml.parse(f:read("*a"))
        f:close()

        for v in xml:first_of("WorldStateComponent"):first_of("lua_globals"):each_of("E") do
            local nuid = GlobalsUtils.getNuidNumberOfKeyString(v.attr.key)
            if nuid ~= nil then
                nuid = tonumber(nuid)
                if nuid > counter then
                    counter = nuid
                end
            end
        end
    end
    counter = counter + 1
    return counter
end

--#endregion

--#region Global public functions

function NuidUtils.getNextNuid()
    return getNextNuid()
end

--#endregion

return NuidUtils
