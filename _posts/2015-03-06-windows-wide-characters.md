---
layout: post
title: Whats in a (Windows) name?
description: "in which we introduce an encoding scheme for Windows names"
modified: 2015-03-06
tags: []
image:
  feature: 3514279453_8372f71a19_o.jpg
  credit: buenosaurus
  creditlink: https://www.flickr.com/photos/buenosaurus
---

*in which we introduce a forensically sound encoding scheme for Windows names*

## So what is a Windows path?

Anyone who has done work on Windows has probably heard that file names are "unicode." But what does that mean exactly? For starters it means that you can name files things like `你好世界.txt` and `Здравствулте мир.txt`.

![]({{site.baseurl}}/images/unicode-names-shot.png)

This works because virtually every name in Windows is represented as a sequence of 16-bit characters which are encoded as UTF-16 (or maybe UCS-2 depending on the version of Windows and who you ask). So a filename is allowed to contain *any* 16-bit value? Not quite...

![]({{site.baseurl}}/images/unicode-names2-shot.png)

What is really going on here? Let's write a little test program to find out.

## Experimenting with Invalid Paths

The bubble says that `<` is not allowed in filenames so lets see what happens when we try to create a file with `<` in it.

{% highlight c++%}
// cl test.cc & test.exe
#include <windows.h>
#include <stdio.h>

int main() {
  wchar_t path[] = L"a<b";
  CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
  
  LPVOID lastErrorString;
  DWORD lastError = GetLastError();
  FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, lastError, 0, (LPTSTR) &lastErrorString, 0, NULL);
  printf("error: %d %s\n", lastError, lastErrorString);
}
{% endhighlight %}

This program produces:

	error: 123 The filename, directory name, or volume label syntax is incorrect.

If you try to create a file with an invalid name Windows returns `ERROR_INVALID_NAME`.  So far so good. Lets see what happens if we monitor our test program with [procmon](https://technet.microsoft.com/en-us/library/bb896645.aspx)? Naturally, it records our attempt to open a file with an invalid path and the resulting error.

![]({{site.baseurl}}/images/procmon.png)

Even though it is invalid, procmon is telling us the path we *attempted* to open. Lets try creating a file named 你好世界.

{% highlight c++%}
wchar_t path[5] = {0x4F60, 0x597D, 0x4E16, 0x754C, 0x0};
CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
{% endhighlight %}

![]({{site.baseurl}}/images/procmon3.png)

This time the path is valid, and procmon draws the path correctly in the user interface.  Everything as expected so far.

What happens if we try to create a file called `foo\nbar`? [^newline]

[^newline]: To be clear, I'm talking about a 7-character string here: "foo", the newline character, and "bar"

{% highlight c++%}
wchar_t path[] = L"foo\nbar";
CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
{% endhighlight %}

This program produces

	error: 123 The filename, directory name, or volume label syntax is incorrect.

What does procmon say?

![]({{site.baseurl}}/images/procmon2.png)

Oops! Procmon didn't render the newline at all.

## Invalid Unicode

UTF-16 code points [between 0xd800 and 0xdfff are invalid](http://en.wikipedia.org/wiki/UTF-16#U.2BD800_to_U.2BDFFF). Let's see what happens if we try to create a file with invalid UTF-16.

{% highlight c++%}
wchar_t path[2] = {0xd801, 0x0000};
CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
{% endhighlight %}

This program produces
  
	error: 0 The operation completed successfully.

So Windows 	doesn't validate the the argument passed to CreateFile() is a valid UTF-16 string. What does procmon do with this?

![]({{site.baseurl}}/images/procmon4.png)

Although procmon makes an attempt to describe the filename, I had a hard time making sense of what was actually happening. I copied and pasted the path into an editor and switched to a hex view and the path seems hopelessly mangled.

![]({{site.baseurl}}/images/procmon5.png)

(I suppose that this could have happened any number of places, in Procmon, in the copy & paste buffer, or in UltraEdit. The point is I have no idea which path the process was trying to open and have no real way to figure it out. Sadness.)

## Describing file activity

So if you are building a tool like Procmon and you want to be able to talk about Windows paths accurately, how can you do it? The standard formats (XML, JSON, etc.) all more or less require you to use Unicode.

- XML allows you to specify whichever character encoding you want as long as it is unicode. 
- JSON requires UTF-8, -16, or -32 (c.f. [RFC-7159](https://tools.ietf.org/html/rfc7159) section 8.1). 
- Strings in protocol buffers must be UTF-8 (c.f. [this](https://developers.google.com/protocol-buffers/docs/proto) section *Scalar Value Types*).

**We can't encode Windows paths using Unicode because the paths might not have valid encodings. We need a format that lets us reason about strings that are *mostly* ASCII but occasionally contain arbitrary characters.** [^mitre] [^base64]

[^mitre]: It seems like maybe the MITRE folks might have made some progress in this space, the [cyboxCommon:StringObjectPropertyType](http://cybox.mitre.org/language/version2.0/xsddocs/extensions/platform/cpe2.3/1.0/cybox_common_xsd.html#StringObjectPropertyType) which is used by a bunch of their XML-based standards seems to support pluggable string encodings. I looks around a little but couldn't find any example of it in use other than a [thread asking what these properties are for](http://making-security-measurable.1364806.n2.nabble.com/Defanging-Regular-Expression-and-base-property-examples-td7582915.html).

[^base64]: I suppose you could use base64 or hex encoding, but most of the strings we encounter are probably *not* going to be invalid and humans are pretty bad at decoding hex in their heads.

## Enter Quoted-wide

So we had these problems at work. 

To try and address them, I made up a format which we not-so-creatively called quoted-wide (because it is based on [quoted-printable](http://en.wikipedia.org/wiki/Quoted-printable)).The input is a sequence of 16-bit characters. The characters don't need to be valid UTF-16 or valid anything for that matter. 

Here are some example encodings:
	
- *truth=beauty* becomes `truth=003Dbeauty`.
- *Jean Réno* becomes `Jean R=00E9no`.
- *中国 / 章子怡* becomes `=4E2D=56FD / =7AE0=5B50=6021`.
- *ኃይሌ ገብረሥላሴ* becomes `=1283=12ED=120C =1308=1265=1228=1225=120B=1234`.
- The sequence {0x0041, 0x0000, 0x0042, 0x0000, 0x004C, 0x0000} becomes `A=0000B=0000C=0000`.

For values <= 0xff, quoted-wide escapes exactly the same values as quoted-printable.  All values > 0xff are encoded.  Encoded values are represented as an equal sign followed by the four digit value in hex.  [We discard the 76-character line length restriction and the special handling of soft line endings (lines ending in `=`) from quoted-printable.]

Here is an encoder in Python:

{% highlight python %}
import re

def QuotedWideEncode(input_):
  rv = []
  for char in input_:
    byte = ord(char)
    if byte >= 0x20 and byte <= 0x7e and char != '=':
      rv.append(str(char))
    else:
      rv.append("=%04X" % (byte,))
  return "".join(rv)
	
def QuotedWideDecode(input_):
  rv = []
  for i, part in enumerate(re.split("(=[0-9A-F]{4})", input_)):
    if i % 2 == 0:
      rv.append(unicode(part))
    else:
      rv.append(unichr(int(part[1:], 16)))
  return u"".join(rv) 
{% endhighlight %}

## So what?

So we can see that the encoding works well for strings that are mostly printable Latin characters, but which are not guaranteed to be encodable with Unicode.

At work we encode our Windows paths with quoted-wide as soon as we get them from the OS. They traverse various systems encoded, through protocols, databases, search indices and all the way to the user interface. When its time to show the path to a human, we just show 'em the quoted-wide encoded version of the path. We've found it to be quite intuitive. [^foo]

[^foo]: By the way this means that the QuotedWideDecode() function above has never really been used in real life. We simply do not decode our strings once we encode them.

So if you are encoding Windows paths (or registry keys, or mutex names) I'd encourage you to consider quoted-wide.

## Bonus: Homographs

The problem gets worse if you consider homograph attacks. A homograph is a character that is visually similar to another character but has a different encoding.[^2] For example, consider the Cyrillic letter а (U+0430) which in most fonts is indistinguishable from the Latin letter a (U+0061). Quoted-wide allows us to distinguish these characters in a meaningful way that would be otherwise difficult.

[^2]: Homograph attacks came to prominence with respect to international domain names as described [here](http://www.securityninja.co.uk/hacking/what-are-homograph-attacks/).
 