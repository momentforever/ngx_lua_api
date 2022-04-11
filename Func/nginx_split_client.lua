if ngx.arg[1] == nil or ngx.arg[2] == nil then
    return "0"
end

local key = ngx.arg[1]
local zone = ngx.arg[2]

local keyval = ngx.shared[zone]

local val = ngx.crc32_short(key)

val = val % 100

local keyval_keys = keyval:get_keys()
local probability = 0
local intkey
for _, keyval_key in pairs(keyval_keys) do
    if probability > 100 then
       break
    end
    -- % == 37
    if string.byte(keyval_key,-1) == 37 then
        intkey = tonumber(string.sub(keyval_key,0,-2))
        if intkey ~= nil then
            probability = intkey + probability
        end
    
        if( val < probability)then
            return keyval:get(keyval_key)
        end
    end
    
end

if keyval:get("*") == nil then
    -- TODO 处理默认值
    return ""
else
    return keyval:get("*")
end