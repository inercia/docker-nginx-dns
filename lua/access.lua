
local shlb     = ngx.shared.lb
local resolver = require "resty.dns.resolver"

function abort(reason, code)
    ngx.status = code
    ngx.say(reason)
    return code
end
                        
-- TODO: use this caching mechanism:
-- http://sosedoff.com/2012/06/11/dynamic-nginx-upstreams-with-lua-and-redis.html
-- TODO: maybe we could connect to weaveDNS and wait for updates on the name...

local insync = shlb:get("insync")
if insync ~= true then
    shlb:set("insync", true, ngx.var.ttl)

    local dns, err  = resolver:new{
        nameservers = { ngx.var.nameserver },
        retrans     = 2,
        timeout     = 300
    }

    if not dns then
        ngx.log(ngx.ERR, "failed to instantiate the resolver: " .. err)
        return abort("DNS error", 500)
    end

    ngx.log(ngx.DEBUG, "Querying about " .. ngx.var.name .. " to " .. ngx.var.nameserver)
    local records, err = dns:query(ngx.var.name)
    if not records then
        ngx.log(ngx.ERR, msg, "failed to query the DNS server: " .. err)
        return abort("Internal routing error", 500)
    end

    if records.errcode then
        if records.errcode == 3 then
            return abort("Not found", 404)
        else
            ngx.log(ngx.ERR, msg, "DNS error #" .. records.errcode .. ": " .. records.errstr)
            return abort("DNS error", 500)
        end
    end

    for i, ans in ipairs(records) do
        ngx.log(ngx.DEBUG, "record:", ans.name, " ", ans.address or ans.cname,
                " type:", ans.type, " class:", ans.class,
                " ttl:", ans.ttl)
    end
                
    -- use the first IP
    local upstream = "http://" .. records[1].address .. ":" .. ngx.var.int_port .. "/"
    shlb:set("upstream", upstream)
    print("Setting upstream to " .. upstream)
end

ngx.var.upstream = shlb:get("upstream")
if ngx.var.upstream ~= nil then
    ngx.log(ngx.INFO, "Upstream is " .. ngx.var.upstream)
end

