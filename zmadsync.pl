#!/usr/bin/perl
#
# Active Directory and Zimbra Directory syncronisation
# (c) Pavel Lu, 2012-2014
# email: email@pavel.lu

# Tested with CentOS/RedHat only
#
# Dependencies:
# yum install perl-LDAP perl-Config-Simple
#
# Features:
# - imports accounts from Active Directory to Zimbra
# - creates mail aliases from Mail field in AD
# - supports cyrillic
#
use strict;
use Net::LDAP;
use Data::Dumper;
use Config::Simple ('-lc');

my %cfg;
Config::Simple->import_from('/home/zimbra/zmadsync.conf', \%cfg)  or die Config::Simple->error();

my $DEBUG 	= $cfg{'default.debug'};
my $ZIMBRA_HOME = $cfg{'zimbra.zmhome'};

my $LOGFILE	= $cfg{'default.log'};
# domain used for mail delivery
my $MAILDOMAIN	= $cfg{'zimbra.domain'};

# COS ID to assign all users by default
my $COSID 	= $cfg{'zimbra.cosid'};

# Active Directory domain
my $AD 		= $cfg{'ad.server'};
# Zimbra LDAP service
my $ZM		= $cfg{'zimbra.zmhost'};

my $ADBASEDN	= $cfg{'ad.adbasedn'};
my $ADBINDDN	= $cfg{'ad.adbinddn'};
my $ADBINDPW	= $cfg{'ad.adbindpw'};

my $ZMBASEDN	= $cfg{'zimbra.zmbasedn'};
my $ZMBINDDN	= $cfg{'zimbra.zmbinddn'};
my $ZMBINDPW	= $cfg{'zimbra.zmbindpw'};

my $ADFILTER	= $cfg{'ad.adfilter'};

######
# open LDAP connections to AD and Zimbra LDAP service
my $ad_ldap = Net::LDAP->new ( $AD );
my $zm_ldap = Net::LDAP->new ( $ZM );

my $res = $ad_ldap->bind ( "$ADBINDDN",           
                        password => "$ADBINDPW",
		 	version => 3 ) or die "$!";
$res->code && die $res->error;

my $res = $zm_ldap->bind ( "$ZMBINDDN",           
                        password => "$ZMBINDPW",
			version => 3 ) or die "$!";
$res->code && die $res->error;

# create temporary command file for batch provisioning
open(CMDFILE, ">/tmp/zmprov.data") or die "$0: can't create temporary file: $!\n";


my @ADATTRS = (
	"sn", 
	"givenName", 
	"mail", 
	"userPrincipalName", 
	"cn", 
	"sAMAccountName" 
	); # request all available attributes to be returned.

my @ZMATTRS = (
	"sn",
	"cn",
	"displayName",
	"uid",
	"mail"
	);

my $ad_result = LDAPsearch ( $ad_ldap, "$ADFILTER", \@ADATTRS, $ADBASEDN );

# Walking through AD results
foreach my $entry ( $ad_result->entries ) {

 my $zmuid = $entry->get_value("sAMAccountName");
 my $zm_result = LDAPsearch ( $zm_ldap, "(&(objectClass=zimbraAccount)(uid=$zmuid))", \@ZMATTRS, $ZMBASEDN ) or die "$!";

 # found the same id in Zimbra: running update
 if ( $zm_result->entries  ) {
	zmUpdate ($entry, $zm_result);
 } else {

	zmCreate ($entry);
 }
}

close (CMDFILE);


# Running Zimbra commands in batch
print `cat /tmp/zmprov.data` if ($DEBUG);
print `$ZIMBRA_HOME/bin/zmprov -f /tmp/zmprov.data >>$LOGFILE`;

exit;

#
## Zimbra accounts create
sub zmCreate
{
	my ($adobj) = @_;

	my $domainName = $adobj->get_value("sAMAccountName")."@".$MAILDOMAIN;
        my $adSN = $adobj->get_value("sn");
        my $adGivenName = $adobj->get_value("givenName");
        my $adName = "";

        if ($adSN || $adGivenName) {
                $adName = $adobj->get_value("sn")." ".$adobj->get_value("givenName");
        } else {
                $adName = $adobj->get_value("cn");
                $adSN = $adName;
        }

	# Updating name fields
	my $cmd = "ca $domainName 23f4f5102b70 sn '".$adSN."' displayName '".$adName."'";
	$cmd .= " zimbraCOSid $COSID" if ($COSID);

	print CMDFILE $cmd."\n";
	zmLog ($cmd, "create");

	# create email alias (if exists)
	my $adMail = $adobj->get_value("mail");

	if (($domainName ne $adMail) && $adMail ) {
		$cmd = "aaa $domainName $adMail";
		print CMDFILE $cmd."\n";
		zmLog($cmd, "create");
	}
}

# Zimbra accounts update
#
sub zmUpdate
{
	my ($adobj, $zmobj) = @_;
	my $cmd = "";
	
	foreach my $rec ($zmobj->entries) {

		my $domainName = $adobj->get_value("sAMAccountName")."@".$MAILDOMAIN;
		my $adSN = $adobj->get_value("sn");
		my $adGivenName = $adobj->get_value("givenName");
		my $adName = "";
		
		if ($adSN || $adGivenName) {
			$adName = $adobj->get_value("sn")." ".$adobj->get_value("givenName");
		} else {
			$adName = $adobj->get_value("cn");
			$adSN = $adName;
		}
		
		if ($adName ne $rec->get_value("displayName") && $adobj->get_value("sn")) {
			$cmd = "ma $domainName sn '".$adSN."' displayName '".$adName."'";
			print CMDFILE $cmd."\n";
			zmLog ($cmd, "update");
		}

		if (! $adobj->get_value("sn")){
			zmLog ("sn attribute is missing", $adName);
		}

		# Updating email alias
		my $mail = $rec->get_value("mail", asref => 1);
		my $zmMail = @{$mail}[1];
		my $adMail = $adobj->get_value("mail");

		if (($domainName ne $adMail) && ($adMail ne $zmMail) && $adMail){
			$cmd = "raa $domainName $zmMail";
			print CMDFILE $cmd."\n" if ($zmMail);
			zmLog($cmd, "delete") if ($zmMail);

			$cmd = "aaa $domainName $adMail";
			print CMDFILE $cmd."\n";
			zmLog($cmd, "create");
		}
	}
}
#
# search through ldap directory
sub LDAPsearch
{
   my ($ldap,$searchString,$attrs,$base) = @_;

   my $result = $ldap->search ( base    => "$base",
                                scope   => "sub",
                                filter  => "$searchString",
                                attrs   =>  $attrs
                              );
}

#
# printing logs
sub zmLog
{
	my ($msg, $comment) = @_;
	my $extra = "";
	my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	my @weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
	my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
	my $year = 1900 + $yearOffset;

	$extra = "[$comment]" if ($comment);
	my $theTime = "$months[$month] $dayOfMonth $hour:$minute:$second $extra: ";

	open (LOGFILE, ">>$LOGFILE") or die "$0: can't create log file: $!\n";
	print LOGFILE $theTime.$msg."\n";
	print $theTime.$msg."\n" if ($DEBUG);
	close (LOGFILE);
} 
