+++
date = "2015-08-26T17:59:12-07:00"
title = "Yubikey for Local Authentication on Mac"
description = "how I set up OS X to require a Yubikey for local login"
image = "/images/key.jpg"
+++

How I set up OS X to require a Yubikey for local login.

<!--more-->

A YubiKey is a small hardware device that offers two-factor authentication with a simple touch of a button. It appears like a USB human interface device (read: keyboard) and under normal conditions, when you press the button, it emits some random characters as if you typed them.

![](/images/yubikey-hid.gif)

The garbage printed is actually a proprietary one-time-pad which can be verified against a network service. 

## Challenge and Response

I wanted my mac to require my YubiKey in order to log in locally. Using a OTP that must be verified over the network isn't going to cut it. 

Fortunately yubikeys support a challenge & response mode. In this mode supported software issues a challenge to the Yubikey (some random bytes), and the Yubikey uses the secret key only it knows to sign those random bytes. The signature becomes the response.

The host system can verify that an authorized yubikey is present by validating the signature.

## Configuring your Yubikey

Configure your Yubikey for challenge-response. I used the Yubikey Personalization tool and slot #2 of my Yubikey.

![](/images/YubiKey_Personalization_Tool_and_MacOS_X_Challenge-Response.png)

## Configuring PAM on OSX

PAM is the software that manages the rules for authenticating users. Yubico provide a PAM module the supports Yubikey in Challenge-Response mode.

Install the yubikey PAM module:

    brew install yubico-pam

The challenge data are stored per user in `~/.yubico`.

    mkdir -m0700 -p ~/.yubico
    ykpamcfg -2

## Dipping a toe in

I was concerned about locking myself out, so to start I only worked on the lock screen. That way if I broke the configuration, a simple reboot would get me logged back in.

The file that controls the rules for unlocking the screen when it is locked is `/etc/pam.d/screensaver`. I added a line referencing the new PAM module:

        # screensaver: auth account
        auth required /usr/local/Cellar/pam_yubico/2.16/lib/security/pam_yubico.so mode=challenge-response
        auth       optional       pam_krb5.so use_first_pass use_kcminit
        auth       required       pam_opendirectory.so use_first_pass nullok
        account    required       pam_opendirectory.so
        account    sufficient     pam_self.so
        account    required       pam_group.so no_warn group=admin,wheel fail_safe
        account    required       pam_group.so no_warn deny group=admin,wheel ruser fail_safe

If your version of `pam_yubico` is different than `2.16` you'll want to specify a slightly different path here.

## Taking the plunge

The file that controls the rules for initial login is `/etc/pam.d/authorization`. I added the same line from the screensaver and all works as expected.

    # authorization: auth account
    auth required /usr/local/Cellar/pam_yubico/2.16/lib/security/pam_yubico.so mode=challenge-response
    auth       optional       pam_krb5.so use_first_pass use_kcminit
    auth       optional       pam_ntlm.so use_first_pass
    auth       required       pam_opendirectory.so use_first_pass nullok
    account    required       pam_opendirectory.so

## User Experience

There is no user interface to speak of. There is no little box that prompts you to insert your token. The light starts flashing and you push the button twice.

![](/images/yubikey-ux.gif)

## Caveats

If you use full disk encryption, the key is derived only from the password. This makes it inferior to the old eToken + PGP desktop thing we used to do on Windows.

## References

* https://developers.yubico.com/yubico-pam/MacOS_X_Challenge-Response.html
* http://linux.die.net/man/1/ykpamcfg





