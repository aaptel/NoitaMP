local util = {}

function util.Sleep(seconds)
    -- https://stackoverflow.com/a/40524323/3493998
    local sec = tonumber(os.clock() + seconds)
    while (os.clock() < sec) do
        -- do a buys wait. Consuming processor time, but I dont care :)
    end
end

function util.IsEmpty(var)
    if var == nil then
        return true
    end
    if var == "" then
        return true
    end
    if type(var) == "table" and not next(var) then
        return true
    end
    return false
end

--- Extends @var to the @length with @char. Example 1: "test", 6, " " = "test  " | Example 2: "verylongstring", 5, " " = "veryl"
---@param var string any string you want to extend or cut
---@param length number
---@param char any
---@return string
function util.ExtendAndCutStringToLength(var, length, char)
    if type(var) ~= "string" then
        error("var is not a string.", 2)
    end
    if type(length) ~= "number" then
        error("length is not a number.", 2)
    end
    if type(char) ~= "string" or string.len(char) > 1 then
        error("length is not a character.", 2)
    end

    local new_var = ""
    local len = string.len(var)
    for i = 1, length, 1 do
        local char_of_var = var:sub(i, i)
        if char_of_var ~= "" then
            new_var = new_var .. char_of_var
        else
            new_var = new_var .. char
        end
    end
    return new_var
end

return util
