Forked from the following:

Cubietruck-Debian
=================

Scripts to create an Image of Debian for cubietruck

Created from Igor Pečovnik work at :

http://www.igorpecovnik.com/2013/12/24/cubietruck-debian-wheezy-sd-card-image/


Installation steps
------------------

use a debian based Linux Distribution!

open your preferred shell
sudo apt-get -y install git
cd ~
git clone https://bitbucket.org/mziegler08/cubietruck-arch
cd cubietruck-arch
chmod +x build.sh
sudo ./build.sh