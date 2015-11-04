local math          = require "math"
local cjson         = require "cjson"
local ws_client = require "resty.websocket.client"

local cache         = ngx.shared.lb

local _M = {
    _VERSION = '0.1'
}

local RETRY_INTERVAL = 5

if not ngx.config
   or not ngx.config.ngx_lua_version
   or ngx.config.ngx_lua_version < 9005
then
    error("ngx_lua 0.9.5+ required")
end

local abort
abort = function (reason, code)
    ngx.status = code
    ngx.log(ngx.ERR, reason)
    return code
end

--
-- Establish a WebSocket connection to a weave router and watch a name
--
-- Request format (JSON):   { "Name":      <NAME>            }
-- Updates format (JSON):   { "Addresses": [<IP>, <IP>, ...] }
--
local do_watch
do_watch = function (premature, name, ws_uri)
    if premature then
        return
    end

    local wb, err = ws_client:new()    
    ngx.log(ngx.DEBUG, "connecting to '",  ws_uri, "' for watching '", name, "'")
    local ok, err = wb:connect(ws_uri)
    if not ok then
        ngx.log(ngx.ERR, "failed to connect: " .. err)
    else
        ngx.log(ngx.DEBUG, "connected to '", ws_uri, "'")

        -- encode the request in JSON and send
        local value      = { Name = name }
        local json_data  = cjson.encode(value)
        ngx.log(ngx.DEBUG, "sending request: ", json_data)
        local len, err = wb:send_text(json_data)
        ngx.log(ngx.DEBUG, len, " bytes sent")
        
        -- loop forever, receiving updates
        while true do
            local data, typ, err = wb:recv_frame()
            if ws_client.fatal then
                ngx.log(ngx.ERR, "fatal error: " .. err)
                break
            elseif not data then
                ngx.log(ngx.DEBUG, "sending PING")
                local len, err = ws_client:send_ping()
                if not len then
                    ngx.log(ngx.ERR, "failed to send PING: ", err)
                    break
                end
            elseif typ == "close" then
                ngx.log(ngx.DEBUG, "connection closed by server")
                break
            elseif typ == "text"  then
                ngx.log(ngx.DEBUG, "update received: ", data)
                -- save the data exactly as we receive it in the cache
                local ok, err = cache:set(name, data)
                if not ok then
                    ngx.log(ngx.ERR, "failed to update the cache: ", err)
                    break
                end
            end
        end
        
        local bytes, err = wb:send_close()
        if not bytes then
            ngx.log(ngx.ERR, "failed to close: ", err)
            return
        end
    end
    
    local ok, err = ngx.timer.at(RETRY_INTERVAL, do_watch, name, ws_uri)
    if not ok then
        ngx.log(ngx.ERR, "failed to reschedule watcher", err)
        return
    end
end

--
-- start watching a name
--
function _M.watch_name(self, name, ws_uri)
    local ok, err = ngx.timer.at(0, do_watch, name, ws_uri)
    if not ok then
        return nil, "failed to create timer: " .. err
    end
    
    return true
end

--
-- return a random upstream from the cache
--
function _M.random_upstream(self, name)
    math.randomseed(os.time())

    ngx.log(ngx.DEBUG, "getting random upstream for '", name, "'")
    data, err = cache:get(name)
    if data then
        -- decode the message
        ngx.log(ngx.DEBUG, "received: ", data)
        local message = cjson.new().decode(data)

        local upstreams     = message.Addresses        
        local upstreams_num = table.getn(upstreams)
        local upstream_idx  = math.random(1, upstreams_num)
        local upstream      = upstreams[upstream_idx]
        ngx.log(ngx.DEBUG, "Random(1,", upstreams_num, ") = ", upstream_idx, " = ", upstream)
        return upstream
    else
        ngx.log(ngx.ERR, "no upstream servers in cache")
        return nil, abort("Internal routing error", 500)
    end
end

return _M
