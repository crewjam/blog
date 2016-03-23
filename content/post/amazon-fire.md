+++
date = "2016-03-18T09:38:19-04:00"
title = "How to set up Amazon Fire Tablet"
slug = "amazon-fire"
layout = "post"
draft = true
+++

Source video https://www.youtube.com/watch?v=NaCBSuUuhRE

## Install SDK Tools

- Get the Android SDK tools from http://developer.android.com/sdk/index.html if you don't 
  already have them. I ended up downloading
  http://dl.google.com/android/android-sdk_r24.4.1-macosx.zip
  But you'll fetch whatever is current. You'll need to extract the zip file
  and run `./tools/android` which downloads additional compontents. The only
  extra component you'll need is `Android SDK Platform-tools`.

  img fire01

      $ export PATH=$PATH:$(pwd)/platform-tools
      $ adb version
      Android Debug Bridge version 1.0.32
      Revision 09a0d98bebce-android

- Turn on ADB debugging on the device. Go to settings, Device Options, and tap the serial number
  seven times. This enables a new menu called "Developer options". In "Developer Options", under 
  "Debugging" choose "Enable ADB".

- Check that ADB can see your device.

      $ adb devices
      List of devices attached
      G0K0H404551211FX	device

- Reboot the device into the bootloader:

      adb reboot bootloader

## Root on 5.0.1 (if your device has not been on WiFi)

If you haven't let the device talk to amazon yet, then it has Fire OS 5.0.1 on it, and you can use this method (tested):

- adb push ~/Downloads/Amazon-Fire-5th-Gen-SuperTool/SuperSU-v2.46.zip /sdcard/
- adb reboot bootloader
- fastboot boot ~/Downloads/AmazonFire5thGenSuperTool/apps/TWRP_Fire_2.8.7.0.img

echo.--------------------------------------------------------------------------------
echo [*] once TWRP recovery Boots up swipe to allow modifications
echo [*] then select install and navigate to SuperSU-v2.46.zip on the sdcard
echo [*] select it then swipe to flash once finished select reboot system
echo.--------------------------------------------------------------------------------
echo [*] When the device has fully booted up you will have root access. 
echo [*] check in the app drawer for supersu app. 
echo [*] NOTE now that you have root please block ota updates option 3 
echo [*] so that you can keep it safe. 
echo.--------------------------------------------------------------------------------

image

## Root on >= 5.1.x (if your device has been used a little already)

If you have, then you need to use the alternate method (based on my recollection):

  Once the screen is black and says "FASTBOOT mode..." then do:

      fastboot oem append-cmdline "androidboot.unlocked_kernel=true"
      fastboot continue

  Wait for the device to boot:

      adb wait-for-device && adb remount
      adb push files/libsupol.so /data/local/tmp/
      adb push files/root_fire.sh /data/local/tmp/
      adb push files/su /data/local/tmp/
      adb push files/Superuser.apk /data/local/tmp/
      adb push files/supolicy /data/local/tmp/
      adb shell chmod 777 /data/local/tmp/root_fire.sh
      adb shell /data/local/tmp/root_fire.sh


echo.--------------------------------------------------------------------------------
echo [*] Once the screen is black and says fastboot in the corner
echo [*] press and key to continue the script.
echo.--------------------------------------------------------------------------------
pause > nul
files\fastboot.exe oem append-cmdline "androidboot.unlocked_kernel=true"
timeout 8 > nul
files\fastboot.exe continue
echo.--------------------------------------------------------------------------------
echo [*] your device is rebooting and will finish the root process.
echo.--------------------------------------------------------------------------------
timeout 5 > nul
files\adb.exe wait-for-device && files\adb.exe remount
files\adb.exe shell /system/xbin/su --install
echo.--------------------------------------------------------------------------------
echo [*] one last reboot to finish process
echo.--------------------------------------------------------------------------------
files\adb.exe reboot
echo.--------------------------------------------------------------------------------
echo [*] process finished now just wait for your device to fully boot up
echo [*] this will take some time if you are on the Optimizing system screen.
echo [*] NOTE now that you have root please block ota updates option 3 
echo [*] so that you can keep it safe. 
echo.--------------------------------------------------------------------------------

## Fetch the SlimLP bits.

## SlimLP bits

http://forum.xda-developers.com/amazon-fire/orig-development/rom-slimlp-5-1-1-amazon-fire-2015-ford-t3256053

Unofficial SlimLP 0.14: https://www.androidfilehost.com/?fid=24352994023707680

Google Applications: http://goo.gl/4QNwn6 > Slim_mini_gapps.BETA.6.0.build.0.x-20160121-1447.zip

$ adb push Slim-ford-5.1.1.beta.0.14-UNOFFICIAL-20160107-1121.zip /sdcard/

## Install FlashFire

- http://rootjunkysdl.com/getdownload.php?file=Amazon%20Fire%205th%20gen/flashfire-0.24.apk
  adb install ~/Downloads/flashfire-0.24.apk
  adb push Slim_mini_gapps.BETA.6.0.build.0.x-20160121-1447.zip /sdcard/

Flashfire

Plus > wipes > "System Data", "3rd Party", "Dalvik cache", "Cache partition" (not "Internal Storage")

Plus -> "Flash zip or OTA" > "Slim-ford-....zip". Check "auto mount"

Plus -> "Flash zip or OTA" > "Slim_mini_gapps.BETA.6.0.build.0.x-20160121-1447.zip". Check "auto mount"

Cross your fingers and click "flash"

Rom (v2.3): https://www.androidfilehost.com/?fid=24269982087020873 (DISCONTINUED)
Recovery: https://www.androidfilehost.com/?fid=24269982087018181
Gapps: i recommend mini version 
You can find what every release includes at the xda thread: http://forum.xda-developers.com/slim...imkat-t2792842

