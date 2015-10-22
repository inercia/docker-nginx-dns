Reverse-proxy/load-balancer for Weave
=====================================

A reverse proxy and load balancer based on [nginx](http://nginx.org)
to be used in conjunction with Weave.

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
host1$ eval "$(weave env)"
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
gateway$ eval "$(weave env)"
gateway$ docker run -p 80:80 inercia/weave-nginx 80:webserver:8080
```

- Open port 80 on the gateway and let you user request come in!

TODO
====

- Replace the DNS queries by some call to the weaveDNS API
- Support SRV records so we can use different port numbers

