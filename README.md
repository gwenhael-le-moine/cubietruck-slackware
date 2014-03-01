Preferred host is a x86_64 Slackware.

---------------------------------------------------------
Installation steps Slackware for Cubietruck
---------------------------------------------------------

1. open your preferred shell

2. su -

3. cd ~

4. git clone https://bitbucket.org/gwenhael/cubietruck-slackware

5. cd cubietruck-slackware

6. chmod +x build.sh

7. ./build.sh # see build.sh --help

8. cd dist/image/

9. dd if=<image>.raw of=/dev/mmcblk0 bs=1024

99. Enjoy Slackware :)



---------------------------------------------------------
FAQ
---------------------------------------------------------
* default root password is 'password'


---
Forked from the following:

Created from Igor Pečovnik work at :

http://www.igorpecovnik.com/2013/12/24/cubietruck-debian-wheezy-sd-card-image/
