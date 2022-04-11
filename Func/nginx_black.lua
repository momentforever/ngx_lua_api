if ngx.arg[1] == nil or ngx.arg[2] == nil then
    return "0"
end

local key = ngx.arg[1]
local zone = ngx.arg[2]

local black = ngx.shared[zone]

if black:get(key) == nil then
    return "1"
end

return black:get(key)