+++
layout = "post"
title = "Tiny Docker + Go Pattern"
date = "2015-07-22"
image = "/images/IMG_3480-1.jpg"
+++

Docker is a handy way to deploy applications, and [Go](http://golang.org) is handy way to build them. Here is how we build Docker containers for small apps.

<!--more-->

Here's how we build (nearly) single file docker containers for Go programs.

# Building static go programs

As of Go 1.4, and after much futzing, here's how I figured out to build programs statically:

```make
frobnicator: frobnicator.go
    CGO_ENABLED=0 go build -a -installsuffix cgo -ldflags '-s' -o frobnicator frobnicator.go
    ldd frobnicator | grep "not a dynamic executable"
```

Here's a Dockerfile:

```docker
FROM scratch
ADD frobnicator /
CMD ["/frobnicator"]
```

`scratch` is special docker magic that means start with a blank slate.

If your application needs to make outbound SSL connections you might need to add SSL certificates

```docker
ADD ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
```

Image: [Sean Kenney](http://seankenney.com/portfolio.php/docker-logo/)




