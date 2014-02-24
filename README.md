Forked from the following:

Created from Igor Pečovnik work at :

http://www.igorpecovnik.com/2013/12/24/cubietruck-debian-wheezy-sd-card-image/

---------------------------------------------------------
Installation steps Slackware for Cubietruck
---------------------------------------------------------

0. Use a debian based Linux Distribution! (sleazy, I know, we'll keep it that way until it can be hosted on a real distribution)

1. open your preferred shell

2. sudo apt-get -y install git

3. cd ~

4. git clone https://bitbucket.org/gwenhael/cubietruck-slackware

5. cd cubietruck-slackware

6. chmod +x build.sh

7. sudo ./build.sh

8-99. dd if=/where/is/it/ of=/dev/mmcblk0 bs=4096 (FIXME)

99. Enjoy Slackware :)