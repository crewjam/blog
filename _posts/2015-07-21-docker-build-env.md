---
layout: post
title: Docker build environments
description: 
modified: 2015-07-21
tags: []
image:
  feature: BSBConstructionSite_500.jpg

---

Docker is a handy way to construct complex build environments.

Like a lot of folks, we've found that Docker is a handy way handy way to avoid having long complex build environment setup instructions. Instead, we define a docker container and assume that the build always runs there.

# Warmup: a simple tool

For simple tools this can be done in one line. For example, here is a simplified version of the Makefile from a simple tool one-file tools called [ephdisk](https://github.com/secureworks/ephdisk):

{% highlight make %}
.PHONY: _ephdisk

all: ephdisk

ephdisk: ephdisk.go
    docker run -v $(PWD):/go/src/github.com/secureworks/ephdisk golang \
        make -C /go/src/github.com/secureworks/ephdisk _ephdisk

_ephdisk:
    go get ./...
    go install ./...
    install /go/bin/ephdisk ephdisk
{% endhighlight %}

Our primary make target `ephdisk` is constructed by running a docker image `golang` and mapping the current directory into the container at a particular path. Once inside the container we invoke make again to build the `_ephdisk` target which does the actual work of building the tool. The output file is copied into the working directory.

The only dependencies we have on the host system are *make* and *docker*. The build instructions are "run `make`". Easy peasy.

<img src="http://stream1.gifsoup.com/view4/1896021/sasuke-s-easy-button-o.gif">

# A more complex example

The build environment for another internal tool is a bit more complex and quite a bit bigger. This environment requires tons of stuff: a bunch of standard Linux packages (nginx, GNU parallel, JDK), packaging tools (`fpm`, `rpm`, `dpkg`), Google Chrome (for running web tests), bower and NPM packages, the go compiler and lots of go libraries and tools.

*Yuck* you say. Why not just have fewer dependencies? In my view, dependencies are a pain in the ass, but for some things they are less of a pain in the ass than  writing the code yourself, or (in the case of packaging tools) having non-automated packaging procedures. It's a trade-off--and in a bunch of cases we've chosen to have a dependency. 

Bottom line, **in any project bigger than a toy you'll have dependencies to manage.**

To construct our build environment we start with a base `Dockerfile`:

{% highlight dockerfile %}
#
# This dockerfile is used to build and test the project.  You'll interact with
# this container using the main Makefile, which will in turn invoke the 
# container for various purposes.
FROM ubuntu:14.04

# Add apt repos
RUN apt-get install -y curl apt-transport-https
RUN curl -s https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -
RUN echo "deb http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google.list 
RUN curl -s https://get.docker.com/gpg | apt-key add -
RUN echo "deb http://get.docker.com/ubuntu docker main" > /etc/apt/sources.list.d/docker.list 

RUN apt-get update && apt-get install -y ca-certificates google-chrome-stable  lxc-docker make openjdk-7-jre-headless parallel unzip vim wget xvfb gcc dpkg-dev ruby-dev rpm dpkg-sig reprepro createrepo s3cmd
RUN gem install fpm

# Set up the go environment and dependencies
RUN curl -sSL http://golang.org/dl/go1.4.linux-amd64.tar.gz | tar -xz -C /usr/local
ENV PATH /go/bin:/usr/local/go/bin:$PATH
ENV GOPATH /go
RUN \
  go get github.com/kardianos/osext && \
  go get code.google.com/p/go.net/context && \
  go get code.google.com/p/go.tools/cmd/goimports && \
  go get golang.org/x/crypto/bcrypt && \
  go get golang.org/x/net/html && \
  go get golang.org/x/oauth2 && \
  go get golang.org/x/text/transform && \
  go get golang.org/x/tools/cmd/cover && \
  go get github.com/crowdmob/goamz/... && \
  go get github.com/dchest/uniuri && \
  go get github.com/drone/config && \
  go get github.com/elazarl/go-bindata-assetfs && \
  go get github.com/fsouza/go-dockerclient && \
  go get github.com/goamz/goamz/... && \
  go get github.com/goji/context && \
  go get github.com/golang/lint/golint && \
  go get github.com/gorilla/websocket && \
  go get github.com/jteeuwen/go-bindata/... && \
  go get github.com/miekg/dns && \
  go get github.com/rcrowley/go-metrics && \
  go get github.com/pelletier/go-toml && \
  go get github.com/peterbourgon/mergemap && \
  go get github.com/stretchr/testify/mock && \
  go get github.com/zenazn/goji/web && \
  go get golang.org/x/tools/cmd/cover && \
  go get golang.org/x/tools/cmd/vet && \
  go get gopkg.in/yaml.v2

# Build the web (node and bower) dependencies in /cache. The two directories,
# node_modules and bower_modules will be later symlinked from the code checkout
# directory
WORKDIR /cache
RUN \
  curl -sSL http://nodejs.org/dist/v0.10.33/node-v0.10.33-linux-x64.tar.gz |\
  tar -xzf - --strip-components=1 -C /usr/local
ADD package.json /cache/package.json
ADD bower.json /cache/bower.json
ADD .bowerrc /cache/.bowerrc
RUN npm install
RUN npm install -g karma-cli grunt-cli
RUN /cache/node_modules/bower/bin/bower --allow-root install
RUN /cache/node_modules/protractor/bin/webdriver-manager update

WORKDIR /go/src/github.com/secureworks/PROJECT
{% endhighlight %}

We now have a basic container with all our dependencies in it. Next we need to get it set up to run Docker inside.

## Docker-in-docker.

There is a script called [dind](https://github.com/docker/docker/blob/master/hack/dind) in the Docker source tree that demonstrates how to run Docker inside a Docker container. (See also [this blog](http://blog.docker.com/2013/09/docker-can-now-run-within-docker/).) The only change we made to `dind` is that we removed the final `exec "$@"`. We wrap `dind` with our own script called `run_inside.sh`. Here is a simplified version:

{% highlight sh %}
#!/bin/bash
#
# This program runs inside the environment container. It is invoked by run.sh
# using something like:
#
#   docker run --privileged -it securewoks/PROJECT-base ./build/run_inside.sh $@
#
# It sets up the container, launches the docker daemon, and invokes the
# specified command, or bash if none was specified.
#
set -e
source_root=/go/src/github.com/secureworks/PROJECT

. $source_root/build/dind

# launch the docker daemon
(setsid docker --debug --daemon --pidfile /tmp/docker.pid &> /tmp/docker.log) &

# bind-mount the cached directories
[ -d $source_root/frontend/node_modules ] || \
  mkdir -p $source_root/frontend/node_modules
mount --bind /cache/node_modules $source_root/frontend/node_modules
[ -d $source_root/frontend/bower_components ] || \
  mkdir -p $source_root/frontend/bower_components
mount --bind /cache/bower_components $source_root/frontend/bower_components

wait_for_docker() {
  tries=20
  while ! docker version &> /dev/null; do
    (( tries-- ))
    if [ $tries -le 0 ]; then
      docker version >&2 || true
      false
    fi
    sleep 1
  done
}
wait_for_docker

# run the wrapped program (or bash)
if [ $# -eq 0 ] ; then
  exec bash
else
  exec $@
fi
{% endhighlight %}

So at this point we can get a functional build environment by doing:

{% highlight sh %}
$ docker build -t secureworks/PROJECT-base ./build
$ docker run secureworks/PROJECT-base --privileged -it \
    -v $(pwd):/go/src/github.com/secureworks/PROJECT \
    ./build/run-inside.sh bash
{% endhighlight %}

We wrap that invocation up in another script that takes care of when to rebuild the build environment container. We compute a hash of the files that could affect the build environment and use that as the version of the container. This way we only need to rebuild the dev environment when one of those files changes. Here is (a truncated version of) that script, `./build/run.sh`:

{% highlight sh %}
#!/usr/bin/env bash
#
# This script runs commands inside the PROJECT development environment,
# which we construct as needed.
#
# We've tried to limit the external dependencies of this program to bash and
# docker. For example, this program does *not* require a working go compiler,
# or any dependencies of the project itself. Those dependencies are pulled in
# inside the container.
#
set -e
source_root=$(cd $(dirname "$BASH_SOURCE")/../; pwd)
docker_env="-e TERM -e UPSTREAM_USER=$USER -e UPSTREAM_HOST=$HOSTNAME -e BUILDFLAGS -e TESTDIRS -e TESTFLAGS -e TIMEOUT"
docker_ports=${docker_ports-"-p 80:80 -p 8000:8000 -p 443:443"}
docker_flags=${docker_flags-"-it"}

# Build the container (if needed)
#
# The version of the base image is determined by $base_image_version which is a
# (truncated) hash of all the files that could possibly affect the image. Thus
# we only need to rebuild the base image when a relevant change affects it.
# These files influence the construction of the container
base_container_dependencies="\
  $source_root/build/Dockerfile \
  $source_root/build/.bash_aliases \
  $source_root/frontend/package.json \
  $source_root/frontend/bower.json \
  $source_root/frontend/.bowerrc \
  "
# The version is a short tag that changes whenever any of the file above change
base_image_version=$(cat $base_container_dependencies | sha1sum | cut -c-10)

# build the base image but only if needed
if ! docker inspect secureworks/PROJECT-base:$base_image_version &>/dev/null ; then
  install -p frontend/package.json build/package.json
  install -p frontend/bower.json build/bower.json
  install -p frontend/.bowerrc build/.bowerrc

  TERM= docker build -t secureworks/PROJECT-base:$base_image_version $source_root/build
fi

docker run --privileged $docker_flags \
  -v $source_root:/go/src/github.com/secureworks/PROJECT \
  $dockercfg_volume \
  $docker_ports \
  $docker_env \
  -e ENV_NAME=PROJECT-live \
  secureworks/PROJECT-base:$base_image_version ./build/run_inside.sh $@
exit $?
{% endhighlight %}

## Make

Our top level `Makefile` wraps invocations to `run.sh` (again the actual Makefile is more complicated--this is a simplified version for clarity):

{% highlight make %}
TARGETS=all build check deploy run shell
.PHONY: $(TARGETS)

# If the ENV_NAME environment variable is not sent (meaning we are outside
# of the dev environment), reinvoke make wrapped by run.sh so we are 
# inside the dev environment.
ifeq ($(ENV_NAME),)
$(TARGETS):
    ./build/run.sh make $@
shell:
    ./build/run.sh bash
else

# If we are inside the build environment then do the actual work
all: build
build:
    go generate ./...
    go build ./...

check:
    ./tools/lint.sh
    go test ./...

run: build
    ./tools/run_integration_environment.sh

deploy:
    # ....
endif
{% endhighlight %}

## Putting it all together

In the end I get an environment where the build instructions are stupid simple. This is from our `README.md`: 

> ### Getting started 
>
> 1. Install docker (or boot2docker for mac & windows)
> 2. If you are using boot2docker make sure the environment is set up correctly,
>   perhaps by invoking ``boot2docker shellinit`` in a way appropriate for your
>   shell.
>   
>         $(boot2docker shellinit)
>   
>3. ``make run``

## Bonus: Warming the Docker image cache

Our integration tests (which run inside this environment) pull down a variety of docker images and whatnot. Because the inner docker's image cache is empty every time, we have to wait a few minutes for each download. This is annoying and was a big part of the time spent during build/test cycles. Slow builds suck so we have to fix this.

Annoyingly you cannot run docker-in-docker while constructing a container, so instead we do a two stage build. First we construct the image as before except this time it is tagged `secureworks/PROJECT-base-pre:$base_image_version` . Second, we run that image as a new container invoking `./build/warm_image.sh`. When that finishes, we capture the running container as a new image `secureworks/PROJECT-base:$base_image_version`.

In `run.sh` we add:

{% highlight sh %}
# run the warmup script inside the preliminary base image to generate the 
# actual base image.
echo "building image secureworks/PROJECT-base:$base_image_version..."
base_build_image_name="PROJECT-base-pre-$base_image_version-$$"
docker run --privileged $docker_flags \
  --name=$base_build_image_name \
  -v $source_root:/go/src/github.com/secureworks/PROJECT \
  $dockercfg_volume \
  $docker_ports \
  $docker_env \
  -e ENV_NAME=PROJECT-pre \
  secureworks/PROJECT-base-pre:$base_image_version ./build/run_inside.sh \
  ./build/warm_image.sh
docker commit $base_build_image_name crewjam/PROJECT-base:$base_image_version
docker rm -f $base_build_image_name
{% endhighlight %}

Here is `./build/warm_image.sh`:

{% highlight sh %}
#!/bin/sh
#
# This script runs inside a the preliminary base container to finish building 
# the base image. Commands here require docker (and hence privileged mode) which
# is not possible inside the `docker build` environment.
#
# Note: if you have a test that requires an image, you should still pull/build 
# it in your test setup. The purpose of this script is to prime the image cache,
# but you shouldn't rely on it when building tests.
#
set -ex
docker pull ubuntu:14.04
docker pull mysql:latest
docker pull training/webapp
docker build -t secureworks/HELPER-1 ./docker/HELPER-1
docker build -t crewjam/HELPER-2 ./docker/HELPER-1
docker build -t crewjam/HELPER-3 ./docker/HELPER-1
{% endhighlight %}

# Wrapup

We use docker to create a consistent development environment in a significant project. Although the initial construction of the environment is slow (it takes about 5 minutes), each developer only incurs that pain when the environment changes. Change are uncommon enough that this pain isn't too bad, but common enough that we don't want to manage it by hand.

The big bonus for us is that we have a consistent environment across all our developers. And because we use the same environment continuous integration, we don't get surprise test failures (much). We also use the same environment for releases to production (note the `deploy` target in the Makefile), so that is consistent too. 

Now all we have to do it not screw it up. 

<img src="../images/antisuccessoriesconsistencyfunnysalescartoon.jpg">

I hope you found this helpful. [I'd be grateful for feedback or suggestions](http://twitter.com/crewjam).



