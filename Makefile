PUBLISH=publish_weave_nginx

.DEFAULT: all
.PHONY: all update tests publish $(PUBLISH) clean prerequisites build

# If you can use docker without being root, you can do "make SUDO="
SUDO=sudo

DOCKERHUB_USER=inercia
WEAVE_NGINX_VERSION=git-$(shell git rev-parse --short=12 HEAD)

WEAVE_NGINX_UPTODATE=.weave_nginx.uptodate
IMAGES_UPTODATE=$(WEAVE_NGINX_UPTODATE)
WEAVE_NGINX_IMAGE=$(DOCKERHUB_USER)/weave-nginx
IMAGES=$(WEAVE_NGINX_IMAGE)
WEAVE_NGINX_EXPORT=weave_nginx.tar

all:    $(WEAVE_NGINX_EXPORT)

$(WEAVE_NGINX_UPTODATE): Dockerfile nginx.conf service.template wrapper.sh lua/weave.lua
	$(SUDO) docker build -t $(WEAVE_NGINX_IMAGE) .
	touch $@

$(WEAVE_NGINX_EXPORT): $(IMAGES_UPTODATE)
	$(SUDO) docker save $(addsuffix :latest,$(IMAGES)) > $@

$(DOCKER_DISTRIB):
	curl -o $(DOCKER_DISTRIB) $(DOCKER_DISTRIB_URL)

$(PUBLISH): publish_%:
	$(SUDO) docker tag -f $(DOCKERHUB_USER)/$* $(DOCKERHUB_USER)/$*:$(WEAVE_NGINX_VERSION)
	$(SUDO) docker push   $(DOCKERHUB_USER)/$*:$(WEAVE_NGINX_VERSION)
	$(SUDO) docker push   $(DOCKERHUB_USER)/$*:latest

publish: $(PUBLISH)

clean:
	-$(SUDO) docker rmi $(IMAGES) 2>/dev/null
	rm -f $(EXES) $(IMAGES_UPTODATE) $(WEAVE_NGINX_EXPORT) test/tls/*.pem coverage.html profile.cov

dist: $(WEAVE_NGINX_EXPORT)
