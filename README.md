# Nginx Lua API Module

## Begin To Use

## Easy Start

If you only want to use HTTP API.
```conf
http{
    server {
        listen 10000;
        server_name _;
        location / {
            content_by_lua_file /usr/local/nginx/conf/lua_module/API/nginx_http_api.lua;
        }
    }
}
```

If you also want to use Stream API.
```conf
http{
    server {
        listen 10000;
        server_name _;
        location / {
            # !!! Important !!!
            set $stream_port 10001;
            content_by_lua_file /usr/local/nginx/conf/lua_module/API/nginx_http_api.lua;
        }
    }
}

stream{
    server {
        listen 10001;
        content_by_lua_file /usr/local/nginx/conf/lua_module/API/nginx_stream_api.lua;
    }
}
```

you also could add conf such as
```conf
allow 127.0.0.1;
deny all;
```
to improve your API security.


+ Standard Response Body

```shell
{
    "status"=200,
    "api"="",
    "data":{
    }
}
```


## Content <a id='content'></a>

+ Nginx
    + [Version](#version)
+ HTTP
    + [KeyVals](#httpkeyvals)
    + [Uptreams](#httpupstreams)
    + [Uptream](#httpupstream)
+ Stream
    + [KeyVals](#streamkeyvals)
    + [Uptreams](#streamupstreams)
    + [Uptream](#streamupstream)


### Version <a id='version'></a>

#### GET

```shell
GET api/http/version

# response
{
    "data": {
        "nginx_version": "1.19.3",
        "api_version": "1.1.1"
    },
    "status": 200,
    "api": "/api/nginx/version"
}
```

[BACK TO CONTENT](#content)


### Http KeyVals <a id='httpkeyvals'></a>

```
set_by_lua_file $[value] [function_path] $[key] [zone];
``
Depends on the input key to determine the output value by function. Input key usually is request arg, such as $remote_addr,$remote_port and so on.

KeyVals also support some normal function.

+ nginx_keyval.lua
+ nginx_white.lua
+ nginx_black.lua
+ nginx_split_client.lua

```conf
http{
    lua_shared_dict zone1 1m;
    # ...
    server{
        #...
        location / {
            set_by_lua_file $value1 /usr/local/nginx/conf/lua_module/nginx_white.lua $remote_addr zone1;
            # to use
            if ($value1 = 0) {
                return 405;
            }
        }
    }
}
```

[BACK TO CONTENT](#content)

#### GET

```shell
GET /api/http/keyvals/<zone>

# response
{
    "status"=200,
    "api"="/api/http/keyvals/<zone>",
    "data":{
        "key1":"value1",
        "key2":"value2"
    }
}
```

[BACK TO CONTENT](#content)

#### POST

```shell
POST api/http/keyvals/<zone>
# request
{
    "key1":"value1",
    "key2":{
        "value":"value2",
        "expire"=200,
    },
}

# response
{
    "status"=200,
    "api"="api/http/keyvals/<zone>",
    "data":{
    }
}
```

[BACK TO CONTENT](#content)

#### PATCH

Update keyvals.

```shell
PATCH api/http/keyvals/<zone>
# request
{
    "key1":"value1",
    "key2":{
        "value":"value2",
        "expire"=200,
    },
}

# response
{
    "status"=200,
    "api"="api/http/keyvals/<zone>",
    "data":{
    }
}
```

[BACK TO CONTENT](#content)

#### DELETE

Delete key in the zone.

```shell
DELETE api/http/keyvals/<zone>/<key>
# response
{
    "status"=200,
    "api"="api/http/keyvals/<zone>",
    "data":{
    }
}
```

Flush all data in the zone to expire.

```shell
DELETE api/http/keyvals/<zone>
# response
{
    "status"=200,
    "api"="api/http/keyvals/<zone>",
    "data":{
    }
}
```

[BACK TO CONTENT](#content)


### Http Uptream <a id='httpupstream'></a>

#### GET

```shell
GET /api/http/upstream/<upstream_name> 

# response
{
    "data": {
        "<upstream_name>": [
            {
                "weight": 1,
                "name": "127.0.0.2",
                "addr": "127.0.0.2:80",
                "fail_timeout": 10,
                "max_fails": 1
            },
            {
                "weight": 1,
                "name": "127.0.0.3",
                "addr": "127.0.0.3:80",
                "backup": true,
                "fail_timeout": 10,
                "max_fails": 1
            }
        ]
    },
    "api": "/api/http/upstream/<upstream_name>",
    "status": 200
}
```

[BACK TO CONTENT](#content)

#### POST

set server to down / up.

```shell
POST api/http/upstream/<upstream_name>

{
    "server_name":"127.0.0.1",
    "port":80,# 非必须,默认为80
    "status":true
}

# response
{
    "api": "/api/http/upstream/bar",
    "status": 200,
    "data": {}
}
```

[BACK TO CONTENT](#content)


### Http Upstreams <a id='httpupstreams'></a>


#### GET

get http all upstreams.

```shell
GET /api/http/upstreams

# response
{
    "data": {
        "upstream_a": [
            {
                "weight": 1,
                "name": "127.0.0.2",
                "addr": "127.0.0.2:80",
                "fail_timeout": 10,
                "max_fails": 1
            },
            {
                "weight": 1,
                "name": "127.0.0.3",
                "addr": "127.0.0.3:80",
                "backup": true,
                "fail_timeout": 10,
                "max_fails": 1
            }
        ],
        "upstream_b":[
            {
                "weight": 1,
                "name": "127.0.0.2",
                "addr": "127.0.0.2:80",
                "fail_timeout": 10,
                "max_fails": 1
            }
        ]
    },
    "api": "/api/http/upstreams",
    "status": 200
}
```

[BACK TO CONTENT](#content)


### Stream KeyVals <a id='streamkeyvals'></a>

The same as Http KeyVals. The difference is only the API URL.

```shell
<method> /api/stream/keyvals/<zone>
```

+ [To Http KeyVals](#httpkeyvals)

[BACK TO CONTENT](#content)


### Stream Upstream <a id='streamupstream'></a>

The same as Http Upstream. The difference is only the API URL.

```shell
<method> /api/stream/upstream/<upstream_name>
```

+ [To Http Upstream](#httpupstream)

[BACK TO CONTENT](#content)


### Stream Upstreams <a id='streamupstreams'></a>

The same as Http Upstreams. The difference is only the API URL.

```shell
<method> /api/stream/upstreams
```

+ [To Http Upstreams](#httpupstreams)

[BACK TO CONTENT](#content)


## For Dev

