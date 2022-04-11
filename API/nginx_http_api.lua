-- Import Package
local cjson = require "cjson"

-- 主版本.http版本.stream版本
local api_version = '1.1.1'
local stream_server_name = '127.0.0.1'
local stream_port = ngx.var.stream_port

-- local resp_body = {}
local resp_body = {
    status=200,
    api="",
    data={
    }
}

-- url: GET api/nginx/version
local function GetNginxVersion()
    resp_body["data"]["nginx_version"] = ngx.var.nginx_version
    resp_body["data"]["api_version"] = api_version
    return
end

-- url: GET api/http/upstreams
local function GetHttpUpstreams()
    local concat = table.concat
    local upstream = require "ngx.upstream"
    local get_servers = upstream.get_servers
    local get_upstreams = upstream.get_upstreams

    local us = get_upstreams()
    
    for _, u in ipairs(us) do
        local srvs, err = get_servers(u)
        resp_body["data"][u] = srvs
    end
    return 
end

-- url: GET api/http/upstream/<upstream_name> 
local function GetHttpUpstream(upstream_name)
    local concat = table.concat
    local upstream = require "ngx.upstream"
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
    return
end

-- set server to down / up
-- url: POST api/http/upstream/<upstream_name> 
-- {
--     "server_name":"127.0.0.1"
--     "port":80,(非必须)
--     "status":true,
-- }
local function PostHttpUpstream(upstream_name)
    
    -- 参数处理
    local server_name = nil
    local port = nil
    local status = nil

    local post_args = cjson.decode(ngx.req.get_body_data())
    
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
    local upstream = require "ngx.upstream"
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

-- set keyvals
-- url: POST api/http/keyvals/<zone> 
-- {
--     "key1":"value1",
--     "key2":{
--         "value":"value2",
--         "expire"=200,
--     },
-- }
local function PostHttpKeyVals(zone)
    local shared = ngx.shared[zone]
    if shared == nil then
        resp_body["status"] = 406
        return
    end

    local post_args = cjson.decode(ngx.req.get_body_data())

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
    return
end

-- get keyvals
-- url: GET api/http/keyvals/<zone> 
-- {
--     "key1":"value1",
--     "key2":"value2",
-- }
local function GetHttpKeyVals(zone)
    local shared_zone = ngx.shared[zone]
    if shared_zone == nil then
        resp_body["status"] = 400
        return
    end
    
    local shared_zone_key = shared_zone:get_keys()
    
    for _, v in pairs(shared_zone_key) do
        resp_body["data"][v] = shared_zone:get(v)
    end
    return
end

-- flush expired keyvals zone
-- url: DELETE api/http/keyvals/<zone> 
-- delete keyval 
-- url: DELETE api/http/keyvals/<zone>/<key>
local function DeleteHttpKeyVals(zone,key)
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

local function PatchHttpKeyVals(zone)
    local shared = ngx.shared[zone]
    if shared == nil then
        resp_body["status"] = 400
        return
    end

    local post_args = cjson.decode(ngx.req.get_body_data())

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
    return
end

-- Stream
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

local function DealStream() 
    local request_to_stream_json = {
        method=ngx.var.request_method,
        api=ngx.var.uri,
        data= nil,
    }
    if stream_port == nil then
        resp_body["status"] = 404
        resp_body["data"]["errorMsg"] = "Unable to find stream port, please set stream_port arg"
        return 
    end

    if ngx.req.get_body_data() ~= nil then
        request_to_stream_json["data"] = cjson.decode(ngx.req.get_body_data())
    end

    local sock = ngx.req.socket()
    local sock = ngx.socket.tcp()

    local ok, err = sock:connect(stream_server_name,stream_port)    
    if not ok then
        -- TODO Error
        resp_body["status"] = 400
        return
    end
    sock:settimeout(1000)  -- one second timeout

    local request_to_stream = EncodeApiMsg(request_to_stream_json)
    local bytes, err = sock:send(request_to_stream)

    -- local response_form_stream = DecodeApiMsgSock(sock)
    local ok,response_form_stream = pcall(DecodeApiMsgSock,sock)

    sock:close()

    -- ngx.log(ngx.ERR, "message is: ", resp_body["api"])

    if ok then
        if response_form_stream == nil then
            -- TODO error    
            resp_body["status"] = 400
            return 
        end
    
        if response_form_stream["data"] ~= nil then
            resp_body["data"] = response_form_stream["data"]
        end
    end

    return
end

-- 添加API子路径
-- 存在了method就不允许再添加子路径
local api = {
    nginx = {
        version = {
            method = {
                GET = GetNginxVersion,
            }
        }
    },
    http = {
        keyvals = {
            method = {
                POST = PostHttpKeyVals,
                GET = GetHttpKeyVals,
                DELETE = DeleteHttpKeyVals,
                PATCH = PatchHttpKeyVals,
            }
        },
        upstreams = {
            method = {
                GET = GetHttpUpstreams,
            }
        },
        upstream = {
            method = {
                GET = GetHttpUpstream,
                POST = PostHttpUpstream,
            },
        },
    },
    stream = {
        method = {
            POST = DealStream,
            GET = DealStream,
            DELETE = DealStream,
            PUTCH = DealStream,
        }
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

-- MAIN
function ApiStateMachine()
    -- 设置api
    resp_body["api"] = ngx.var.uri

    local t_uri = Split( ngx.var.uri, "/" )
    local flag = FindRIndex(t_uri,"api")

    if flag == nil then
        resp_body["status"] = 404
        return
    end

    local now_api = api
    for key, value in Npairs(t_uri,flag)
    do
        -- ngx.say(value)
        if type(now_api[value]) == "nil" then
            resp_body["status"] = 404
            return
        elseif type(now_api[value]) == "table" then
            now_api = now_api[value]
        end

        if type(now_api["method"]) ~= "nil" and key < #t_uri then

            if now_api["method"][ngx.var.request_method] ~= nil then
                now_api["method"][ngx.var.request_method](t_uri[key + 1],t_uri[key + 2])
            end
            return
        elseif type(now_api["method"]) ~= "nil" then
            if now_api["method"][ngx.var.request_method] ~= nil then
                now_api["method"][ngx.var.request_method]()
            end
            return
        end
    end
    return
end

local function Main()
    -- 设置响应类型
    ngx.header.content_type = 'application/json';
    -- 获取json参数
    ngx.req.read_body()

    ApiStateMachine()
    
    -- 返回
    ngx.say(cjson.encode(resp_body))

    ngx.exit(200)

    return
end

-- Main
Main()
