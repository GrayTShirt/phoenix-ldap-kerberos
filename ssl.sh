#!/bin/bash

ssl () 
{
   while [ "$1" != "" ]; do
       case $1 in
           -p | --password )       shift
                                   password=$1
                                   ;;
       esac
       shift
   done

   # set up the configuration files
   . ./config
   config

   # Set the static file path in the script
   sdir=`pwd -P`/ssl
   sdir=`echo $sdir | sed -e 's/\//\\\\\//g'`
   sed -i "s/ssldir/$sdir/g" ssl/caconfig.cnf 

   # Set the common name of the cert to the fully qualifed domain name
   hname=`hostname -f`
   hname=`echo $hname | sed -e 's/\./\\\\./g'`
   sed -i "s/hhname/$hname/g" ssl/*

   # Set the organization name to the domain name with out the tld
   orgname=`hostname -d | sed 's/\(^.*\)\..*$/\U\1/'`
   sed -i "s/\(^organizationName.*\=\)$/\1\ $orgname/" ssl/*

   # Set the email to admin plus the domian name
   email=admin\@`hostname -d`
   email=`echo $email | sed -e 's/\./\\\\./g'`
   sed -i "s/\(^emailAddress.*\=\)$/\1\ $email/" ssl/*

   # Callout to get the country and parse
   . ./country
   getcountry
   sed -i "s/\(countryName.*\=\)$/\1\ $country/" ssl/*

   # Callout to get the state and parse
   . ./state
   getstate
   sed -i "s/\(stateOrProvinceName.*\=\)$/\1\ $state/" ssl/*

   # Callout to get the city, don't bother parsing
   city=`wget -qO-  http://www.liveipmap.com/ | grep -i city -C 1 | tail -1 | sed 's/^.*[\<]td[\>]\(.*\)[\<]\/td[\>].*$/\U\1/g'`
   sed -i "s/\(localityName.*\=\)$/\1\ $city/" ssl/*

   mkdir ssl/signedcerts
   mkdir ssl/private
   touch ssl/index.txt
   echo "01" > ssl/serial
   cd ssl

   # Generate the certificates
   export OPENSSL_CONF=./caconfig.cnf
   echo "Generating cacert.pem"
   openssl req -x509 -newkey rsa:4096 -out cacert.pem -outform PEM -days 9000 -passout pass:$password
   echo "Generating cacert.crt"
   openssl x509 -in cacert.pem -out cacert.crt  
   export OPENSSL_CONF=./`hostname`.cnf
   echo "Generating server_key.pem"
   openssl req -newkey rsa:4096 -keyout tempkey.pem -keyform PEM -out tempreq.pem -outform PEM -passout pass:$password
   openssl rsa < tempkey.pem > server_key.pem -passin pass:$password
   export OPENSSL_CONF=./caconfig.cnf
   echo "Generating server_crt.pem"
   openssl ca -in tempreq.pem -out server_crt.pem -passin pass:$password 
   rm -f tempkey.pem && rm -f tempreq.pem
   cd ../
}
