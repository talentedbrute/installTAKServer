# install TAKServer

Obtain the TAK Server RPM from tak.gov

Setup the `setup.sh` script for your environment 

The installTAKServer script will do the actual install, needs to be run as root.

The setupTAKServer.sh will be run as the tak user and does the actual setup of certs and stuff.  This is called by the install script.  

This does need internet access to install the java (sdkman).  You can remove that if you already have Java 17 installed.

Its expecting the database to be on a different host, but you can still specify the database credentials.
