Reverse-proxy/load-balancer for Weave
=====================================

A reverse proxy and load balancer based on [nginx](http://nginx.org)
to be used in conjunction with [Weave](http://weave.works/).

Design
======

The load-balancer is based on a Lua script (runing in nginx) that connects to
[weaveDNS](http://docs.weave.works/weave/latest_release/weavedns.html) through a
websocket. This connection is used for _watching_ a DNS name (in our example,
`webserver`) and receive updates about the IPs registered in the
Weave network for that name. Any container that appears with that name will be
immediately available as an upstream server in nginx, and containers being stopped
or dying will be immediately removed from this pool.

This provides a major advantage in comparison with DNS-based load balancers (like
[NGINX Plus](https://www.nginx.com/products/on-the-fly-reconfiguration/) or
[haproxy](https://cbonte.github.io/haproxy-dconv/configuration-1.6.html#5.3)) as
they must keep resolving the name in order to have an up-to-date list of IPs
available. These solutions can either resolve the DNS name for each incomming HTTP
request (putting a lot of pressure in the DNS server) or they can respect the
TTL specified in the DNS response and keep the list of IPs for some time (this can
lead to stale IPs, as the minimum TTL is one second and it gets worse for larger TTLs).

Usage
=====

_Scenario_: you have `n` webservers running in `host1`..`hostn`
in containers. You want to have a reverse proxy running in `gateway`
that load balances requests to all these `webserver` containers. 

- Launch Weave in your `host*` machines as you usually do
([docs](http://docs.weave.works/weave/latest_release/))
(we will use the [proxy](http://docs.weave.works/weave/latest_release/proxy.html) 
in this example):

```
host1$ weave launch --init-peer-count n
host1$ eval $(weave env)
```

- Connect all these these peers in some way (with `weave connect`,
with [Weave Discovery](https://github.com/weaveworks/discovery), etc)
- Launch your `webserver`s. In this example, we use a minimal `webserver`
that listens on port 8080:

```
host1$ docker run -p 8080:8080 --rm  -ti --name webserver  adejonge/helloworld
```

Launch as many webservers as you want, but all registered with the
*same hostname* (`webserver`) and listening on the *same port*.

- On the gateway host, also launch Weave and the reverse proxy.

```
gateway$ weave launch
gateway$ eval $(weave env)
gateway$ docker run -p 80:80 inercia/weave-nginx 80:webserver:8080
```

You could expose and load-balance more services by adding them to the
command line. For example:

```
gateway$ docker run -p 80:80 inercia/weave-nginx 80:webserver:8080 81:graphite:8081
```

- Open port 80 on the gateway and let you user request come in!

Notes and Limitations
=====================

* the _service_ will be resolved in the DNS domain (by default, `weave.local`)
and you must not include it (eg, `webserver` is ok, `webserver.weave.local`
is not)
* all the services must be running on the same internal port

TODO
====

* Support different internal port numbers
* Use the advanced features nginx provides for upstream pools (ie, health check,
retries, timeouts, policies, etc)
* TCP support
