#!/bin/bash

replication () 
{
echo "Hello" 
}

rentval=`id | sed 's/uid\=\([0-9]\).*$/\1/'`
if [ "$rentval" -ne "0" ] ; then 
	echo "I must be run as root or with sudo privledges"
	echo "Attempting to run as sudo."
	sudo $0
   echo "failed."
   echo "exiting."
	exit 0
fi

dialog --backtitle "KERBEROS/LDAP config script" \
	--inputbox \
	"Is this Server Name Correct? `hostname -f`" 0 60 2> name.txt.$$
	hname=`cat name.txt.$$`
	rm -f name.txt.$$
if [ -z "$input" ]; then 
	hname=`hostname -f`
else 
	hname=$input
fi
dialog --passwordbox \
	"Kerberos/LDAP Password:" 0 60 2> passwd.txt.$$
password=`cat passwd.txt.$$`
rm -f passwd.txt.$$
dialog --passwordbox \
	"Confirm Kerberos/LDAP Password:" 0 60 2> passwd.txt.$$
password1=`cat passwd.txt.$$`
rm -f passwd.txt.$$
if [[ "$password" != "$password1" ]] ;  then 
	echo "passwords did not match, exiting"
	exit 0
fi
searchdc=`hostname -d | sed 's/\(^\)/dc\=\1/'`
searchdc=`echo $searchdc | sed 's/\./\,dc\=/g'`
admindc="cn=admin,${searchdc}"

. ./ssl.sh
ssl -p $password
mkdir -p /etc/openldap/ssl/
cp ssl/cacert.crt /etc/openldap/ssl/ 
cp ssl/server_crt.pem /etc/openldap/ssl/ 
cp ssl/server_key.pem /etc/openldap/ssl/ 
rm -rf ssl/
chown ldap:ldap -R /etc/openldap/ssl 
chmod 700 -R /etc/openldap/ssl 

. ./depends
check_dependencies

hashedpw=`slappasswd -s $password`

. ./slap_d
prep_slap $searchdc $admindc $hashedpw

if [ ! -d "/var/lib/ldap" ] ; then 
	mkdir -p /var/lib/ldap
fi
chmod 700 /var/lib/ldap
chown ldap:ldap /var/lib/ldap

if [ ! -d "/etc/openldap/slapd.d" ] ; then 
	mkdir -p /etc/openldap/slapd.d
fi
chmod 700 /etc/openldap/slapd.d
chown ldap:ldap /etc/openldap/slapd.d
slaptest -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d 

mv /etc/openldap/slapd.conf /etc/openldap/slapd.conf.save

# TODO add xinetd support for only listening and accepting connections over lan
#ints=`/sbin/ifconfig | grep eth | sed 's/^.*\(eth[0-9]\).*$/\1/'`
#interfaces=(${ints})
#for i in "${interfaces[@]}" ; do
#                  
#done


mv /etc/conf.d/slapd /etc/conf.d/slapd.old
. ./slapd_config
slapd_config_pre

/etc/init.d/slapd restart

echo "dn: cn=config
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/openldap/ssl/cacert.crt
-
add: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/ssl/server_crt.pem
-
add: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/ssl/server_key.pem" > ssl.ldif
ldapadd -f ssl.ldif -D $admindc -w $password -x -H ldap://localhost
rm ssl.ldif

slapd_config_post

/etc/init.d/slapd restart

. ./kerberos
krb5conf $searchdc $admindc $password


exit 0
