if ngx.arg[1] == nil or ngx.arg[2] == nil then
    return "0"
end

local key = ngx.arg[1]
local zone = ngx.arg[2]

local keyval = ngx.shared[zone]

return keyval:get(key)