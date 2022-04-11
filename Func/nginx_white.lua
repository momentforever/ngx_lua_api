if ngx.arg[1] == nil or ngx.arg[2] == nil then
    return "0"
end

local key = ngx.arg[1]
local zone = ngx.arg[2]

-- return key

local white = ngx.shared[zone]
if white:get(key) == nil then
    return "0"
end

return white:get(key)