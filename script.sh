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
hnamen=`echo $hname | sed -e 's/\./\\\\./g'`
domain=`echo $hname | sed "s/^[A-Za-z0-9\/]*[A-Za-z0-9\/]\.//" `

# Set the organization name to the domain name with out the tld
orgname=`echo $domain | sed 's/^\([A-Za-z0-9]*[A-Za-z0-9]\)\..*$/\U\1/'`

searchdc=`echo $domain | sed 's/\(^\)/dc\=\1/'`
searchdc=`echo $searchdc | sed 's/\./\,dc\=/g'`
admindc="cn=admin,${searchdc}"

. ./ssl/ssl.sh
ssl -p $password -h $hname
if [ ! -d "/etc/openldap/ssl/" ] ; then 
	mkdir -p /etc/openldap/ssl/
fi

cp ssl/certs/server_cacert.crt /etc/openldap/ssl/cacert.crt
cp ssl/certs/server_crt.pem /etc/openldap/ssl/ 
cp ssl/certs/server_key.pem /etc/openldap/ssl/ 
rm -rf ssl/certs/
chown ldap:ldap -R /etc/openldap/ssl 
chmod 700 -R /etc/openldap/ssl 

if [ ! -d "/var/lib/ldap" ] ; then 
	mkdir -p /var/lib/ldap
fi
chmod 700 -R /var/lib/ldap
chown ldap:ldap -R /var/lib/ldap

if [ ! -d "/etc/openldap/slapd.d" ] ; then 
	mkdir -p /etc/openldap/slapd.d
fi
chmod 700 -R /etc/openldap/slapd.d

. ./depends
check_dependencies

hashedpw=`slappasswd -s $password`

. ./slap_d
prep_slap_d $searchdc $admindc $hashedpw
chown ldap:ldap /etc/openldap/slapd.conf
chmod 700 /etc/openldap/slapd.conf
. ./slapd_config
slapd_config_init

chmod 700 /var/lib/ldap
chown ldap:ldap /var/lib/ldap

echo "Initializing database frontend"

/etc/init.d/slapd start
echo "database initialized"
/etc/init.d/slapd stop
sed -i "s/\(rootdn.*\)$/\#\1/" /etc/openldap/slapd.conf
hashedpw1=`echo $hashedpw | sed -e 's/\//\\\\\//g'`
sed -i "s/\(rootpw.*\)$/\#\1/" /etc/openldap/slapd.conf
sed -i "s/\#\ config\_be/database\ config\nrootdn\ \"cn\=admin\,cn\=config\"\nrootpw\ $hashedpw1/" /etc/openldap/slapd.conf

slaptest -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d 
chown ldap:ldap -R /etc/openldap/slapd.d

mv /etc/openldap/slapd.conf /etc/openldap/slapd.conf.save

# TODO add xinetd support for only listening and accepting connections over lan
#ints=`/sbin/ifconfig | grep eth | sed 's/^.*\(eth[0-9]\).*$/\1/'`
#interfaces=(${ints})
#for i in "${interfaces[@]}" ; do
#                  
#done


# mv /etc/conf.d/slapd /etc/conf.d/slapd.old

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
ldapmodify -f ssl.ldif -D cn=admin,cn=config -w $password -x -H ldap://localhost
rm ssl.ldif

slapd_config_post
echo "#
# LDAP Defaults
#

# See ldap.conf(5) for details
# This file should be world readable but not world writable.

BASE	$searchdc
URI	ldaps://$hname
#SIZELIMIT	12
#TIMELIMIT	15
#DEREF		never
TLS_REQCERT never
" > /etc/openldap/ldap.conf


/etc/init.d/slapd restart

. ./front
front $searchdc $admindc $hashedpw $orgname
ldapadd -f front.ldif -D cn=admin,cn=config -w $password -x -H ldaps://localhost

. ./kerberos
krb5conf $searchdc $admindc $password
/etc/init.d/mit-krb5kpropd start
/etc/init.d/mit-krb5kdc start
/etc/init.d/mit-krb5kadmind start

exit 0
