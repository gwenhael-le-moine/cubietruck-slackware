Forked from the following:

Created from Igor Pečovnik work at :

http://www.igorpecovnik.com/2013/12/24/cubietruck-debian-wheezy-sd-card-image/

---------------------------------------------------------
Installation steps Slackware for Cubietruck
---------------------------------------------------------

1. open your preferred shell

2. su -

3. cd ~

4. git clone https://bitbucket.org/gwenhael/cubietruck-slackware

5. cd cubietruck-slackware

6. chmod +x build.sh

7. ./build.sh

8. cd ~/cubieslack/output

9. gunzip <image>.raw.gz

10. dd if=<image>.raw of=/dev/mmcblk0 bs=1024

99. Enjoy Slackware :)