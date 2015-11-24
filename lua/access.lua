
local cache      = ngx.shared.lb
local math       = require "math"
local resolver   = require "resty.dns.resolver"
local resty_lock = require "resty.lock"

math.randomseed(os.time())

function abort(reason, code)
    ngx.status = code
    ngx.say(reason)
    return code
end

function random_upstream(num_upstreams)
    local upstream_idx  = math.random(1, num_upstreams)
    ngx.log(ngx.DEBUG, "Random(1," .. num_upstreams .. ") = " .. upstream_idx)
    local name          = ngx.var.name .. "#" .. upstream_idx
    local upstream      = cache:get(name)
    if upstream == nil then
        ngx.log(ngx.ERR, "Upstream " .. name .. " (of " .. num_upstreams .. ") not found")
        return abort("Internal routing error", 500)
    end
    return upstream
end

-- hackish solution for storing the 'name':IP1,IP2...IPn
-- in the shared memory area: we store
--    'name#records' = n
--    'name#1'       = IP1
--    'name#2'       = IP2
--    ...

local name_records_key = ngx.var.name .. "#records"

-- check the cache for a hit with the key
local num_records, err = cache:get(name_records_key)
if num_records then
    ngx.var.upstream = random_upstream(num_records)
    ngx.log(ngx.DEBUG, "Upstream is " .. ngx.var.upstream)
    return
end
if err then
    return fail("failed to get key from shm: ", err)
end

-- cache miss!
local lock = resty_lock:new("lb_locks")
local elapsed, err = lock:lock(name_records_key)
if not elapsed then
    return fail("failed to acquire the lock: ", err)
end

-- lock successfully acquired!
-- someone might have already put the value into the cache
-- so we check it here again:
num_records, err = cache:get(name_records_key)
if num_records then
    local ok, err = lock:unlock()
    if not ok then
        return fail("failed to unlock: ", err)
    end

    ngx.say("result: ", num_records)
    return
end

--- perform the DNS resolution
local dns, err  = resolver:new{
    nameservers = { ngx.var.nameserver },
    retrans     = 2,
    timeout     = 300,
    no_recurse  = true
}

if not dns then
    local ok, err = lock:unlock()
    if not ok then
        return fail("failed to unlock: ", err)
    end
    ngx.log(ngx.ERR, "failed to instantiate the resolver: " .. err)
    return abort("DNS error", 500)
end

ngx.log(ngx.DEBUG, "Refreshing query about " .. ngx.var.name .. " to " .. ngx.var.nameserver)
local records, err = dns:query(ngx.var.name)
if not records then
    local ok, err = lock:unlock()
    if not ok then
        return fail("failed to unlock: ", err)
    end
    ngx.log(ngx.ERR, msg, "failed to query the DNS server: " .. err)
    return abort("Internal routing error", 500)
end

if records.errcode then
    local ok, err = lock:unlock()
    if not ok then
        return fail("failed to unlock: ", err)
    end
    if records.errcode == 3 then
        return abort("Not found", 404)
    else
        ngx.log(ngx.ERR, msg, "DNS error #" .. records.errcode .. ": " .. records.errstr)
        return abort("DNS error", 500)
    end
end

-- save the records count
local ok, err = cache:set(name_records_key, table.getn(records), ngx.var.ttl)
if not ok then
    local ok, err = lock:unlock()
    if not ok then
        return fail("failed to unlock: ", err)
    end

    return fail("failed to update shm cache: ", err)
end

-- ... and then each record
num_records = 0
for i, ans in ipairs(records) do
    num_records = num_records  + 1

    local name     = ngx.var.name .. "#" .. num_records
    local upstream = "http://" .. ans.address .. ":" .. ngx.var.int_port .. "/"
    
    ngx.log(ngx.DEBUG, name, " :", ans.name, " ", ans.address or ans.cname,
            " type:", ans.type, " class:", ans.class,
            " ttl:", ans.ttl)

    local ok, err = cache:set(name, upstream, ngx.var.ttl)        
    if not ok then
        local ok, err = lock:unlock()
        if not ok then
            return fail("failed to unlock: ", err)
        end

        return fail("failed to update shm cache: ", err)
    end
end

local ok, err = lock:unlock()
if not ok then
    return fail("failed to unlock: ", err)
end

ngx.var.upstream = random_upstream(num_records)
ngx.log(ngx.DEBUG, "Upstream is " .. ngx.var.upstream)
