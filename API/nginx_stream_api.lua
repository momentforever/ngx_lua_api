-- Import Package
local cjson = require "cjson"

-- 变量
local request_json = nil
local resp_body = {
    status=200,
    api="",
    data={
    }
}

-- 添加API方法
local function GetStreamKeyVals(zone)
    local shared_zone = ngx.shared[zone]
    if shared_zone == nil then
        resp_body["status"] = 406
        return 
    end
    
    local shared_zone_key = shared_zone:get_keys()
    
    for _, v in pairs(shared_zone_key) do
        resp_body["data"][v] = shared_zone:get(v)
    end
    resp_body["status"] = 200
    return
end

local function PostStreamKeyVals(zone)
    local shared = ngx.shared[zone]
    if shared == nil then
        resp_body["status"] = 406
        return
    end
    local post_args = request_json["data"]

    for k, v in pairs(post_args) do
        if type(v) == "table" then
            --TODO 过期时间
            if v["value"] == nil or v["expire"] == nil then
                shared:add(k,v["value"],v["expire"])
            end
        else
            shared:add(k, v)
        end
    end
    resp_body["status"] = 200
    return 
end

-- flush expired keyvals zone
-- url: DELETE api/http/keyvals/<zone> 
-- delete keyval 
-- url: DELETE api/http/keyvals/<zone>/<key>
local function DeleteStreamKeyVals(zone,key)
    local shared_zone = ngx.shared[zone]
    if shared_zone == nil then
        resp_body["status"] = 400
        return
    end

    if key == nil then
        -- TODO flush or delete
        shared_zone:flush_all()
    else
        shared_zone:delete(key)
    end

    return
end

local function PutchStreamKeyVals(zone)
    local shared = ngx.shared[zone]
    if shared == nil then
        resp_body["status"] = 406
        return
    end

    local post_args = request_json["data"]

    for k, v in pairs(post_args) do
        if type(v) == "table" then
            --TODO 过期时间
            if v["value"] == nil or v["expire"] == nil then
                shared:set(k,v["value"],v["expire"])
            end
        else
            shared:set(k, v)
        end
    end
    resp_body["status"] = 406
    return
end


local function GetStreamUpstreams()
    -- 依赖导入
    local ok,upstream = pcall(function ()
        require "ngx.streamupstream"
    end)
    if not ok then
        resp_body["status"] = 500
        resp_body["data"]["error"] = "unable find ngx.streamupstream package"
        return
    end

    local concat = table.concat
    local get_servers = upstream.get_servers
    local get_upstreams = upstream.get_upstreams

    local us = get_upstreams()
    
    for _, u in ipairs(us) do
        local srvs, err = get_servers(u)
        resp_body["data"][u] = srvs
    end
    resp_body["status"] = 200
    return
end


local function GetStreamUpstream(upstream_name)
    -- 依赖导入
    local ok,upstream = pcall(function ()
        require "ngx.streamupstream"
    end)
    if not ok then
        resp_body["status"] = 500
        resp_body["data"]["error"] = "unable find ngx.streamupstream package"
        return
    end
    local concat = table.concat
    local get_servers = upstream.get_servers
    local get_upstreams = upstream.get_upstreams

    local us = get_upstreams()
    
    for _, u in ipairs(us) do
        if upstream_name == u then
            local srvs, err = get_servers(u)
            resp_body["data"][u] = srvs
            break 
        end
    end
    resp_body["status"] = 200
    return
end

local function PostStreamUpstream(upstream_name)
    -- 依赖导入
    local ok,upstream = pcall(function ()
        require "ngx.streamupstream"
    end)
    if not ok then
        resp_body["status"] = 500
        resp_body["data"]["error"] = "unable find ngx.streamupstream package"
        return
    end

    -- 参数处理
    local server_name = nil
    local port = nil
    local status = nil

    local post_args = request_json["data"]
    
    if post_args["server_name"] == nil then
        resp_body["status"] = 415
        return
    end

    server_name = post_args["server_name"]

    if post_args["port"] == nil then
        port = 80
    else
        port = post_args["port"]
    end
    -- 判断unix
    if string.find(server_name,"unix:/") == nil then
        server_name = server_name..":"..tostring(port)
    end

    if post_args["status"] == nil then
        resp_body["status"] = 415
        return
    end
    server_name = post_args["status"]

    -- 数据处理
    local concat = table.concat
    local get_servers = upstream.get_servers
    local get_upstreams = upstream.get_upstreams

    local us = get_upstreams()

    local backup_count = 0
    local primary_count = 0

    for _, u in ipairs(us) do
        if u == upstream_name then
            local srvs, err = get_servers(u)
            if not srvs then
                resp_body["status"] = 400
                -- ngx.say("failed to get servers in upstream ", u)
                resp_body["data"]["error"] = u
                return
            else
                for _, srv in ipairs(srvs) do
                    if srv["addr"] == server_name then
                        if srv["backup"] == nil then
                            upstream.set_peer_down(upstream_name,false,backup_count,status)
                        else
                            upstream.set_peer_down(upstream_name,true,primary_count,status)
                        end
                        return
                    end
                    if srv["backup"] == nil then
                        primary_count = primary_count + 1
                    else
                        backup_count = backup_count + 1
                    end            
                end
            end 
        end
    end
    return
end

-- 添加API子路径
-- 存在了method就不允许再添加子路径
local api = {
    stream = {
        keyvals = {
            method = {
                POST = PostStreamKeyVals,
                GET = GetStreamKeyVals,
                DELETE = DeleteStreamKeyVals,
                PUTCH = PutchStreamKeyVals,
            }
        },
        upstreams = {
            method = {
                GET = GetStreamUpstreams,
            }
        },
        upstream = {
            method = {
                GET = GetStreamUpstream,
                POST = PostStreamUpstream,
            },
        },
    }
}

-- TOOL FUNC
local function Split(str,reps)
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function (w)
        table.insert(resultStrList,w)
    end)
    return resultStrList
end

local function RIter(t,i)
    i = i - 1
    local v = t[i]
    if v then
        return i , v
    end 
end
local function Rpairs(t)
    return RIter , t , #t
end

local function Iter(t,i)
    i = i + 1
    local v = t[i]
    if v then
        return i , v
    end 
end
local function Npairs(t,n)
    return Iter , t , n
end

local function FindRIndex(t,index)
    for key,value in Rpairs(t)
    do
        if value == index then
            return key
        end
    end
end

local function DecodeApiMsgSock(sock)
    local request_len = assert(sock:receive(8))
    request_len = tonumber(request_len)
    -- ngx.log(ngx.ERR, "len is: ", request_len)
    -- local request_msg = assert(sock:receive(request_len + 8))
    -- request_msg = string.sub(request_msg,9)
    local request_msg = assert(sock:receive(request_len))
    -- ngx.log(ngx.ERR, "message is: ", request_msg)
    return cjson.decode(request_msg)
end

local function EncodeApiMsg(msg)
    msg = cjson.encode(msg)
    if msg == nil then
        return nil
    end
    local msg_json_len = string.format("0x%06X",#msg)
    return msg_json_len..msg
end

-- Main Func
function ApiStateMachine()

    resp_body["api"] = request_json["api"]
    -- ngx.log(ngx.ERR, "api is: ", request_json["api"])
    local t_uri = Split( request_json["api"], "/" )
    local flag = FindRIndex(t_uri,"api")

    -- ngx.log(ngx.ERR, "api is: ", request_json["api"])
    if flag == nil then
        return
    end

    local now_api = api
    for key, value in Npairs(t_uri,flag)
    do
        -- ngx.say(value)
        if type(now_api[value]) == "nil" then
            return
        elseif type(now_api[value]) == "table" then
            now_api = now_api[value]
        end

        if type(now_api["method"]) ~= "nil" and key < #t_uri then

            if now_api["method"][request_json["method"]] ~= nil then
                now_api["method"][request_json["method"]](t_uri[key + 1],t_uri[key + 2])
            end
            return
        elseif type(now_api["method"]) ~= "nil" then

            if now_api["method"][request_json["method"]] ~= nil then
                now_api["method"][request_json["method"]]()
            end
            return
        end
    end
    
    return
end

function Main()
    -- Request 处理
    local sock = assert(ngx.req.socket())

    local ok,res = pcall(DecodeApiMsgSock,sock)
    request_json = res
    
    -- ngx.log(ngx.ERR, "message is: ", request_json["api"])

    if ok then
        ApiStateMachine()
    end
    
    local response_str = EncodeApiMsg(resp_body)
    
    -- ngx.log(ngx.ERR, "response_str is: ", response_str)

    local bytes, err = sock:send(response_str)
    if bytes == nil then
        ngx.log(ngx.ERR, "send error: ", err)
    end
    
end

-- 执行
Main()

