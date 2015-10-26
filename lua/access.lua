
local shlb     = ngx.shared.lb
local math     = require "math"
local resolver = require "resty.dns.resolver"

math.randomseed(os.time())

function abort(reason, code)
    ngx.status = code
    ngx.say(reason)
    return code
end
                        
-- TODO: maybe we could connect to weaveDNS and wait for updates on the name...

-- hackish solution for storing the 'name':IP1,IP2...IPn
-- in the shared memory area: we store
--    'name#records' = n
--    'name#1'       = IP1
--    'name#2'       = IP2
--    ...

local name_records_key = ngx.var.name .. "#records"

local num_records = shlb:get(name_records_key)
if num_records == nil then
    local dns, err  = resolver:new{
        nameservers = { ngx.var.nameserver },
        retrans     = 2,
        timeout     = 300,
        no_recurse  = true
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

    -- save the records count
    shlb:set(name_records_key, table.getn(records), ngx.var.ttl)

    -- ... and then each record
    local count = 0
    for i, ans in ipairs(records) do
        count = count  + 1

        local name     = ngx.var.name .. "#" .. count
        local upstream = "http://" .. ans.address .. ":" .. ngx.var.int_port .. "/"
        
        ngx.log(ngx.DEBUG, name, " :", ans.name, " ", ans.address or ans.cname,
                " type:", ans.type, " class:", ans.class,
                " ttl:", ans.ttl)

        shlb:set(name, upstream, ngx.var.ttl)        
    end
end

-- get a random upstream from the cached upstreams list
local num_upstreams  = shlb:get(name_records_key)
if num_upstreams == nil then
    return abort("Not found", 404)    
end
local upstream_idx  = math.random(1, num_upstreams)
local name          = ngx.var.name .. "#" .. upstream_idx
local upstream      = shlb:get(name)
if upstream == nil then
    ngx.log(ngx.ERR, "Upstream " .. name .. " (of " .. num_upstreams .. ") not found")
    return abort("Internal routing error", 500)
end

ngx.log(ngx.DEBUG, "Upstream is " .. upstream)
ngx.var.upstream = upstream

