Reverse-proxy/load-balancer for Docker networks
===============================================

Dynamic reverse proxy and load balancer for microservices running in a Docker network,
based on [nginx](http://nginx.org).

Scenario
--------

You have `n` webservers running in `host1`..`hostn` in containers.
You want to have a reverse proxy running in `gateway` that load balances requests
to all these `webserver` containers. 

Design
======

The load-balancer is based on a Lua script that runs in the _nginx_ process and
queries periodically (every second) the DNS server about the _service_ name.
As long as your DNS server has up-to-date information about your containers,
any container that appears with that name will be immediately available as an
upstream server in _nginx_, and containers being stopped or dying will be
immediately removed from this pool.

Usage
=====

With Weave
----------

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
gateway$ docker run -p 80:80 inercia/docker-nginx-dns 80:webserver:8080
```

You could expose and load-balance more services by adding them to the
command line. For example:

```
gateway$ docker run -p 80:80 inercia/docker-nginx-dns 80:webserver:8080 81:graphite:8081
```

- Open port 80 on the gateway and let you user request come in!

Limitations
-----------

When used with Weave,

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


