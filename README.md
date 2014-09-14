ZMADSYNC
--------
This script does copy the user data from Active Directory to Zimbra every time it runs. 

How it works
------------
It takes a user from Active Directory (AD) and creates it in Zimbra directory in one way.
No data changed/sent back to Active Directory.
If the user has been deleted in AD it still remains in Zimbra and able to receive emails. However, as the user no longer exists in AD there is no way to access its inbox if Zimbra users have been configured for LDAP authentication against AD.

The fields copied over are:
- sAMAccountName
- sn
- givenName
- cn

By default, it creates a user account in Zimbra using the 'sAMAccountName' value as a user name.
If the 'mail' field exists in AD it will be created as an alias in Zimbra.

Example
-------

Active Directory user:
- sAMAccountName: test1
- sn: Doe
- givenName: John
- cn: John Doe
- mail: johndoe@mydomain.com

Zimbra user created:
"John Doe" test1@mydomain.com + mail alias: johndoe@mydomain.com

Limitations
-----------
- If the user account has been deleted from AD it has to be deleted manually from Zimbra. It's assumed that all Zimbra mail user accounts are authenticated against AD.

Installation
------------

1. `git clone https://github.com/auspaul/zmadsync.git zmadsync`
2. The script requires the following Perl packages installed `yum install perl-LDAP perl-Config-Simple`
3. Edit config file
4. Create a cron job as a zimbra user
