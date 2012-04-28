#!/bin/bash

ssl () 
{
   hname="0"
   filename="0"
   time="9000"
   while [ "$1" != "" ]; do
       case $1 in
           -p | --password )       shift
                                   password=$1
                                   ;;
           -h | --hostname )       shift
                                   hname=$1
                                   ;;
           -f | --file )           shift
                                   filename=$1
                                   ;;
           -t | --time )           shift
                                   time=$1
                                   ;;
       esac
       shift
   done

   if [[ "$hname" == "0" ]] ; then 
      hname=`hostname -f`
   fi
   if [[ "$filename" == "0" ]] ; then 
      filename="server"
   fi
   cd ssl/
   mkdir certs
   # set up the configuration files
   . ./config
   config $hname

   # Set the static file path in the script
   sdir=`pwd -P`/certs
   sdir=`echo $sdir | sed -e 's/\//\\\\\//g'`
   sed -i "s/ssldir/$sdir/g" certs/* 


   sed -i "s/default\_days\ \=/default\_days\ \=\ $time/" certs/*
   # Set the common name of the cert to the fully qualifed domain name
  
   
   hnamen=`echo $hname | sed -e 's/\./\\\\./g'`
   domain=`echo $hnamen | sed "s/^[A-Za-z0-1\/]*[A-Za-z0-1\/]\.//" `
   echo $hnamen   
   echo $domain
   sed -i "s/hhname/$hnamen/g" certs/*

   # Set the organization name to the domain name with out the tld
   orgname=`echo $domain | sed 's/\(^.*\)\\\.*$/\U\1/'`
   echo $orgname
   sed -i "s/\(^organizationName.*\=\)$/\1\ $orgname/" certs/*

   # Set the email to admin plus the domian name
   email=admin\@$domain
   
   email=`echo $email | sed -e 's/\@/\\\\@/g'`
   echo $email
   sed -i "s/\(^emailAddress.*\=\)$/\1\ $email/" certs/*
   if [ ! -f ip_info ] ; then 
      wget -qO-  http://www.liveipmap.com/ > ip_info
   fi
   # Callout to get the country and parse
   . ./country
   getcountry
   sed -i "s/\(countryName.*\=\)$/\1\ $country/" certs/*

   # Callout to get the state and parse
   . ./state
   getstate
   sed -i "s/\(stateOrProvinceName.*\=\)$/\1\ $state/" certs/*

   # Callout to get the city, don't bother parsing
   city=`cat ip_info | grep -i city -C 1 | tail -1 | sed 's/^.*[\<]td[\>]\(.*\)[\<]\/td[\>].*$/\U\1/g'`
   sed -i "s/\(localityName.*\=\)$/\1\ $city/" certs/*

   mkdir certs/signedcerts
   mkdir certs/private
   touch certs/index.txt
   echo "01" > certs/serial
   cd certs

   # Generate the certificates
   export OPENSSL_CONF=./caconfig.cnf
   echo "Generating cacert.pem"
   openssl req -x509 -newkey rsa:4096 -out cacert.pem -outform PEM -days 9000 -passout pass:$password
   echo "Generating cacert.crt"
   openssl x509 -in cacert.pem -out $filename\_cacert.crt  
   export OPENSSL_CONF=./$hname.cnf
   echo "Generating server_key.pem"
   openssl req -newkey rsa:4096 -keyout tempkey.pem -keyform PEM -out tempreq.pem -outform PEM -passout pass:$password
   openssl rsa < tempkey.pem > $filename\_key.pem -passin pass:$password
   export OPENSSL_CONF=./caconfig.cnf
   echo "Generating server_crt.pem"
   openssl ca -in tempreq.pem -out $filename\_crt.pem -passin pass:$password 
   rm -f tempkey.pem && rm -f tempreq.pem
   cd ../
}
