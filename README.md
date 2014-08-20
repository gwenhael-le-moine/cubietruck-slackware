Preferred host is a x86_64 Slackware.

---------------------------------------------------------
Installation steps Slackware for Cubietruck
---------------------------------------------------------

1. open your preferred shell

2. su -

3. cd ~

4. git clone https://bitbucket.org/gwenhael/cubietruck-slackware

5. cd cubietruck-slackware

6. ./build.sh # see build.sh --help

7. cd dist/image/

8. cat <image>.raw /dev/mmcblk0

99. Enjoy Slackware :)

---------------------------------------------------------
FAQ
---------------------------------------------------------
* default root password is 'password'
* you have to manually install l/mpfr

---------------------------------------------------------
Bugs
---------------------------------------------------------
* Wifi is not working

---
Forked from the following:

Created from Igor Pečovnik work at :

http://www.igorpecovnik.com/2013/12/24/cubietruck-debian-wheezy-sd-card-image/
