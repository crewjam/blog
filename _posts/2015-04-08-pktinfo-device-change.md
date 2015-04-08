---
layout: post
title: IP_PKTINFO and removing network devices
description: If you use the IP_PKTINFO flag on your UDP listener, everything breaks when network devices change
modified: 2015-04-08
tags: []
image:
  feature: DSC_0591.JPG

---

You only care about this if Google brought you here and you have this problem.

The following sequence of events breaks:

1. You listen on a UDP socket
2. You specify the [IP_PKTINFO](http://stackoverflow.com/a/3929208) socket option
3. You enter a blocking `recv()`
4. A network device is removed
5. You close the listening socket.

If you skip step 2, everything works as expected. Scroll down for a test program to illustrate what I'm talking about. On my system, ``setPktInfoFlag = false`` produces:

{% highlight sh %}
creating ethernet device foo0 9.9.9.9
listening on 0.0.0.0:999
ReadMsgUDP()
deleting interface foo0
closing udpCon
waiting for ReadMsgUDP to return
ReadMsgUDP(): n=-1, oobn=0, flags=0, addr=(*net.UDPAddr)(nil), err="read udp [::]:999: use of closed network connection"
done
{% endhighlight %}

While if we set ``setPktInfoFlag = true``, the ReadMsgUDP() never returns:

{% highlight sh %}
creating ethernet device foo0 9.9.9.9
listening on 0.0.0.0:999
ReadMsgUDP()
deleting interface foo0
closing udpCon
waiting for ReadMsgUDP to return
(hangs here forever... why?)
panic: **boom**
{% endhighlight %}

What happens on your system? 

Anybody have any idea what is going on here? Hit me up on twitter, [@crewjam](http://twitter.com/crewjam).

{% gist a7c76f41ee35a82f668d baz.go %}

