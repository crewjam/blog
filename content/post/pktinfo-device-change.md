+++
layout = "post"
title = "IP_PKTINFO and removing network devices (Updated)"
description = "If you use the IP_PKTINFO flag on your UDP listener, everything breaks when network devices change"
date = "2015-04-08"
image = "images/DSC_0591.JPG"
+++

If you use the IP_PKTINFO flag on your UDP listener, everything breaks when network devices change

<!--more-->

You only care about this if Google brought you here and you have this problem.

**Update:** Nick B. sent me an some interesting insights into this problem. Scroll to the end for more

The following sequence of events breaks:

1. You listen on a UDP socket
2. You specify the [IP_PKTINFO](http://stackoverflow.com/a/3929208) socket option
3. You enter a blocking `recv()`
4. A network device is removed
5. You close the listening socket.

If you skip step 2, everything works as expected. Scroll down for a test program to illustrate what I'm talking about. On my system, ``setPktInfoFlag = false`` produces:

``` sh
creating ethernet device foo0 9.9.9.9
listening on 0.0.0.0:999
ReadMsgUDP()
deleting interface foo0
closing udpCon
waiting for ReadMsgUDP to return
ReadMsgUDP(): n=-1, oobn=0, flags=0, addr=(*net.UDPAddr)(nil), err="read udp [::]:999: use of closed network connection"
done
```

While if we set ``setPktInfoFlag = true``, the ReadMsgUDP() never returns:

``` sh
creating ethernet device foo0 9.9.9.9
listening on 0.0.0.0:999
ReadMsgUDP()
deleting interface foo0
closing udpCon
waiting for ReadMsgUDP to return
(hangs here forever... why?)
panic: **boom**
```

What happens on your system? 

Anybody have any idea what is going on here? Hit me up on twitter, [@crewjam](http://twitter.com/crewjam).

```go
// go run baz.go
package main

import (
    "fmt"
    "net"
    "os/exec"
    "syscall"
    "time"
)

func main() {
    setPktInfoFlag := true
    listenString := "0.0.0.0:999"

    fmt.Printf("creating ethernet device foo0 9.9.9.9\n")
    err := exec.Command("ip", "link", "add", "foo0", "type", "veth", "peer", "name", "foo1").Run()
    if err != nil {
        panic(err)
    }
    defer exec.Command("ip", "link", "del", "foo0").Run()
    err = exec.Command("ip", "addr", "add", "9.9.9.9/32", "dev", "foo0").Run()
    if err != nil {
        panic(err)
    }
    err = exec.Command("ip", "link", "set", "foo0", "up").Run()
    if err != nil {
        panic(err)
    }

    localAddr, _ := net.ResolveUDPAddr("udp", listenString)
    if err != nil {
        panic(err)
    }
    udpCon, err := net.ListenUDP("udp", localAddr)
    if err != nil {
        panic(err)
    }
    fmt.Printf("listening on %s\n", listenString)

    if setPktInfoFlag {
        udpConFile, err := udpCon.File()
        if err != nil {
            panic(err)
        }
        err = syscall.SetsockoptInt(int(udpConFile.Fd()), syscall.IPPROTO_IP, syscall.IP_PKTINFO, 1)
        if err != nil {
            panic(err)
        }
    }

    readDone := make(chan struct{})
    go func() {
        fmt.Printf("ReadMsgUDP()\n")
        b, oob := make([]byte, 40), make([]byte, 40)
        n, oobn, flags, addr, err := udpCon.ReadMsgUDP(b, oob)
        fmt.Printf("ReadMsgUDP(): n=%#v, oobn=%#v, flags=%#v, addr=%#v, err=%#v\n",
            n, oobn, flags, addr, err.Error())
        close(readDone)
    }()

    time.Sleep(time.Second)

    fmt.Printf("deleting interface foo0\n")
    err = exec.Command("ip", "link", "del", "foo0").Run()
    if err != nil {
        panic(err)
    }

    time.Sleep(time.Second)

    fmt.Printf("closing udpCon\n")
    udpCon.Close()

    fmt.Printf("waiting for ReadMsgUDP to return\n")
    if setPktInfoFlag {
        fmt.Printf("(hangs here forever... why?)\n")
        go func() {
            time.Sleep(2 * time.Second)
            panic("**boom**")
        }()
    }

    _, _ = <-readDone
    fmt.Printf("done\n")
}
```

# Update

Here is a note I got from Nick B. about this post:

> As an aside, I stumbled upon a post you made regarding IP_PKTINFO with an 
> example Go program. The blocking operation you encountered is due to a
> change in the way the Linux kernel processes that flag. With IP_PKTINFO, the
> kernel wil block in skb_recv_datagram. Without the flag, the kernel will
> enter futex_wait_queue_me which I *think* gets interrupted (i.e., returns
> EINTR) once the socket is closed. To troubleshoot it further and reproduce
> the behavior, check the WCHAN status of each task in the Go process once you
> encounter a point where your program appears hung.
> 
> For example, if your program is the process ip-link-test:
> 
>     cd /proc/$(pidof ip-link-test)
>     find task -name wchan -exec cat {} \; -exec echo “ {}” \;
> 
> You’ll see which syscall each task is in (if any) and the task making it.
> 
> I think some user-space programs - top and htop maybe - can show the wchan
> of a process as well.

We've worked around this problem other ways, so I haven't tried this, but I'm sharing in case this is helpful to someone else encountering it. Thanks Nick!


