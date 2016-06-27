#!c:\Perl\bin\perl.exe
# For Unix use /usr/local/bin/
# This will parse data from a Pebble SQLite database

use strict;
use IO::All;
use Getopt::Long;
use POSIX;
use DateTime;
use DBI;
use CGI;
use Data::Plist;
use Data::Plist::BinaryReader;
use Data::Plist::Foundation::NSArray;



# EASY TO EDIT SCRIPT INFORMATION
	my $scriptname='allyourpebblearebelongtous.pl';
	my $scriptversion= '1.0 (Build 20160623)';
	my $authorname='Brian Moran (\@brianjmoran)';
	my $emailaddress='(brian\@brimorlabs.com)';


#Declarations
my ($OUTFILE, $FILE, $database, $databasetype, $slashes);
my $pebblehtmlpage= CGI->new;
my @options=(
	'file=s'		=>	"will parse a file",
	'ofolder=s'		=>	"directory where output is saved",
	'changes'		=>	"	shows script changes",
	'info'			=>	"	shows script information"
);
die &usage if (@ARGV == 0); #A nice die at usage


# Getopt::Long stuff happens here
my @getopt_opts;
for(my $i =0;$i<@options;$i+=2){
	push @getopt_opts,$options[$i];
}
%Getopt::Long::options = ();
$Getopt::Long::autoabbrev=1;
&Getopt::Long::GetOptions( \%Getopt::Long::options,@getopt_opts) or &usage;




my $filename=$Getopt::Long::options{file} if (defined $Getopt::Long::options{file}); #Looks to see if filename is defined
my $output=$Getopt::Long::options{ofolder} if (defined $Getopt::Long::options{ofolder}); #Looks to see if output is defined
die &changes if (defined $Getopt::Long::options{changes}); #Dies at changes if changes is defined
die &info if (defined $Getopt::Long::options{info}); #Dies at info if info is defined
die "\nERROR!! Please define a file to parse with the -file flag.\n\n" if (not defined $Getopt::Long::options{file});
die "\nERROR!! Please define an output folder with the -output flag.\n\n" if (not defined $Getopt::Long::options{ofolder});
my $makedir=mkdir "$Getopt::Long::options{ofolder}" if (defined $Getopt::Long::options{ofolder});

my $content = io($filename); #A single file
my $filename = $content->filename; #IO All-filename
my $abspathname=io($content)->absolute->pathname; #IO All Pathname
print STDERR "\nProcessing $abspathname\n"; #Processing this
#Reading the entire file into a single variable
open($FILE, "$abspathname") || die "Cannot open $content $!\n";
my $data = do {local $/; binmode $FILE; <$FILE>};
my $sqlitedb = $data;
close($FILE);

my $outputcontent=io($output);
my $outputabspathname=io($outputcontent)->absolute->pathname;

#Small check for slash direction to handle multiple operating systems
if ($outputabspathname =~ /\\/)
{
	$slashes='\\';
} 
else
{
	$slashes='/';
}


#A small test to ensure it is a sqlite database
my $pebbleheader=substr($data,0,15); #Grabbing the first 15 bytes of data. Rather than use magic or something, gonna do this ourselves

if ($pebbleheader =~ /SQLite format 3/)
{
	#Defined values
	my ($manifesturl);
	open($OUTFILE, ">tempsqlfile");
	binmode $OUTFILE;
	print $OUTFILE $sqlitedb;
	close($OUTFILE);
	
	#Connecting to the SQLite database
	$database=DBI->connect('dbi:SQLite:tempsqlfile');

	
	#Subroutine to determine database type, either iOS or Android
	my $dbprocessingoption=&determinedbtype;
	#Now we are going to go through subroutines for each SQLite query

	#The best way to do this is through various subroutines. That way the code is easier to follow if you want to add something new
	#Android specific queries
	my $androidapps=&androidapps if $databasetype eq 'Android'; #Running android apps subroutine
	my $notifications=&notifications if $databasetype eq 'Android'; #Running notifications subroutine
	my $cannedresponses=&canned_responses if $databasetype eq 'Android'; #Running canned responses subroutine
	my $phonenumbers=&phone_numbers if $databasetype eq 'Android'; #Running phone numbers subroutine
	
	#iOS specific queries
	my $timelineattribute=&timelineattribute if $databasetype eq 'iOS'; #Running canned responses subroutine


	print STDERR "\n\nFinished pebble data parsing succesfully\n\nPlease review the output stored in the folder \"$output\" found under the path\n$outputabspathname\n\n";
	}
	else
	{
		die "\nUnfortunately the script cannot determine if this is a pebble database. The script will exit now\n";
	}

$database->disconnect or warn "Database disconnect error!\n";
my $tmpsqlfile = io("tempsqlfile"); # Using IO:All against tmpsqlfile
my $tmpabspathname=io($tmpsqlfile)->absolute->pathname; #Getting full path to temp file for clean deletion purposes
unlink "$tmpabspathname" or warn "Cound not unlink $tmpabspathname"; #Deleting the tempsqlfile
exit (-1); #A nice clean exit


#Determine database type
sub determinedbtype ()
{
	#Defined values go here
	my ($androidresults, $iosresults);
	#SQLite query to check if the table name exists, starting with Android
	my $androidcheck=$database->prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='android_apps'");
	$androidcheck->execute();
	while (my @androidquery=$androidcheck->fetchrow_array())
	{
		$androidresults=$androidquery[0];
	}

	if ($androidresults =~ /android_apps/) #The SQLite query above should return this value. If not, we exit nicely and move along
	{
		print STDERR "\nGood news everyone!!\nThis looks like a Pebble database from an Android device, so we will proceed\n";
		$databasetype='Android';
	}
	else
	{
		my $ioscheck=$database->prepare( "SELECT name FROM sqlite_master WHERE type='table' AND name='ZWATCHAPPHARDWAREPLATFORM'");
		$ioscheck->execute();
		while (my @iosquery=$ioscheck->fetchrow_array())
		{
			$iosresults=$iosquery[0];
		}

		if ($iosresults =~ /ZWATCHAPPHARDWAREPLATFORM/) #The SQLite query above should return this value. If not, we exit nicely and move along
		{
		print STDERR "\nGood news everyone!!\nThis looks like a Pebble database from an iOS device, so we will proceed\n";
			$databasetype='iOS';
		}
		else
		{
			print STDERR "This does not appear to be an Android or iOS database.\nPlease contact Brian Moran (\@brianjmoran) if you wish to add\nparsing capabilities for this database.\n";
			print STDERR "This script will now exit.\n";
			exit (-1);
		}
	}
}



#Android Apps Subroutine
sub androidapps ()
{
	#Defined values go here
	my ($androidapptableresults, $ANDROIDAPPSHTML);
	#SQLite query to check if the table name exists
	my $androidapptablecheck=$database->prepare( "SELECT name FROM sqlite_master WHERE type='table' AND name='android_apps'");
	$androidapptablecheck->execute();
	while (my @androidapptablequery=$androidapptablecheck->fetchrow_array())
	{
		$androidapptableresults=$androidapptablequery[0];
	}

	if ($androidapptableresults =~ /android_apps/) #The SQLite query above should return this value. If not, we exit nicely and move along
	{
		my @androidappfields=('Application Name', 'Application Package Name', 'Application Version', 'Application Creation Date', 'Application Updated Date', 'Last Notification Recorded by Pebble'); #This is the name of the fields we will be parsing
		my $androidappsfilecreation="$output$slashes". "AndroidApps.html"; #Building the name of the output file
		open($ANDROIDAPPSHTML, ">$androidappsfilecreation"); #Opening our output file
		binmode $ANDROIDAPPSHTML; #I am all about that binmode
		print $ANDROIDAPPSHTML $pebblehtmlpage->start_html(-title => 'Installed Android Applications', -encoding=>"utf-8"); #Formatting
		print $ANDROIDAPPSHTML $pebblehtmlpage->start_table({-border=>2, -cellspacing=>3, -cellpadding=>3}); #Formatting
		print $ANDROIDAPPSHTML $pebblehtmlpage->Tr({-align=>'center',-valign=>'middle',style=>'font-size: x-large; font-weight: bold; text-decoration: underline'},[$pebblehtmlpage->th(\@androidappfields)]); #Formatting
		print STDERR "\nGood news everyone!!\nThe table \"android_apps\" exists in this database.\nBeginning to parse data now.\n";
		my $android_apps_parsing=$database->prepare( "SELECT app_name, package_name, app_version, _date_created, _date_updated, case when last_notified_time > 0 then DATETIME((last_notified_time / 1000), 'unixepoch') else '' end as 'last_notified_time' FROM android_apps ORDER BY app_name ASC"); #Our SQLite query
		$android_apps_parsing->execute(); #Run query run!
		while (my @androidappsquery=$android_apps_parsing->fetchrow_array())
		{
			print $ANDROIDAPPSHTML $pebblehtmlpage->Tr({-align=>'left',-valign=>'middle',style=>'font-size: medium; font-weight: ligther'},[$pebblehtmlpage->th(\@androidappsquery)]); #This looks complex, but this is actually taking our output and printing it right to html
			
		}
		$android_apps_parsing->finish(); #Whew, I am tired
		print $ANDROIDAPPSHTML $pebblehtmlpage->end_table; #The end of the table
		print $ANDROIDAPPSHTML $pebblehtmlpage->end_html; #The end of the html
		close($ANDROIDAPPSHTML); #Closing time
		print STDERR "The parsing of the table \"android_apps\" has completed.\nMoving on to next table now.\n";

	}
	else
	{
		print "\nThe table \"android_apps\" does not exist.\nMoving on to next table now.\nExiting \"androidapps\" subroutine.\n";
	}
}

#Android Notifications Subroutine
sub notifications ()
{
	#Defined values go here
	my ($notificationstableresults, $NOTIFICATIONSHTML);
	#SQLite query to check if the table name exists
	my $notificationstablecheck=$database->prepare( "SELECT name FROM sqlite_master WHERE type='table' AND name='notifications'");
	$notificationstablecheck->execute();
	while (my @notificationstablequery=$notificationstablecheck->fetchrow_array())
	{
		$notificationstableresults=$notificationstablequery[0];
	}

	if ($notificationstableresults =~ /notifications/) #The SQLite query above should return this value. If not, we exit nicely and move along
	{
		my @notificationsfields=('Date Created', 'Title', 'Body', 'Package Name', 'Source', 'Date Notification Cleared'); #This is the name of the fields we will be parsing
		my $notificationsfilecreation="$output$slashes". "Notifications.html"; #Building the name of the output file
		open($NOTIFICATIONSHTML, ">$notificationsfilecreation"); #Opening our output file
		binmode $NOTIFICATIONSHTML; #I am all about that binmode
		print $NOTIFICATIONSHTML $pebblehtmlpage->start_html(-title => 'Notifications', -encoding=>"utf-8"); #Formatting
		print $NOTIFICATIONSHTML $pebblehtmlpage->start_table({-border=>2, -cellspacing=>3, -cellpadding=>3}); #Formatting
		print $NOTIFICATIONSHTML $pebblehtmlpage->Tr({-align=>'center',-valign=>'middle',style=>'font-size: x-large; font-weight: bold; text-decoration: underline'},[$pebblehtmlpage->th(\@notificationsfields)]); #Formatting
		print STDERR "\nGood news everyone!!\nThe table \"notifications\" exists in this database.\nBeginning to parse data now.\n";
		my $notifications_parsing=$database->prepare( "SELECT _date_created, title, body, package_name, source, case when removed_timestamp_millis > 0 then DATETIME((removed_timestamp_millis / 1000), 'unixepoch') else '' end as removed_timestamp_millis FROM notifications ORDER BY _date_created ASC"); #Our SQLite query
		$notifications_parsing->execute(); #Run query run!
		while (my @notificationssquery=$notifications_parsing->fetchrow_array())
		{
			print $NOTIFICATIONSHTML $pebblehtmlpage->Tr({-align=>'left',-valign=>'middle',style=>'font-size: medium; font-weight: ligther'},[$pebblehtmlpage->th(\@notificationssquery)]); #This looks complex, but this is actually taking our output and printing it right to html
			
		}
		$notifications_parsing->finish(); #Whew, I am tired
		print $NOTIFICATIONSHTML $pebblehtmlpage->end_table; #The end of the table
		print $NOTIFICATIONSHTML $pebblehtmlpage->end_html; #The end of the html
		close($NOTIFICATIONSHTML); #Closing time
		print STDERR "The parsing of the table \"notifications\" has completed.\nMoving on to next table now.\n";
	}
	else
	{
		print "\nThe table \"notifications\" does not exist.\nMoving on to next table now.\nExiting \"notifications\" subroutine.\n";
	}
}


#Android Canned Responses Subroutine
sub canned_responses ()
{
	#Defined values go here
	my ($cannedresponsestableresults, $CANNEDRESPONSESHTML);
	#SQLite query to check if the table name exists
	my $cannedresponsestablecheck=$database->prepare( "SELECT name FROM sqlite_master WHERE type='table' AND name='canned_responses'");
	$cannedresponsestablecheck->execute();
	while (my @cannedresponsestablequery=$cannedresponsestablecheck->fetchrow_array())
	{
		$cannedresponsestableresults=$cannedresponsestablequery[0];
	}

	if ($cannedresponsestableresults =~ /canned_responses/) #The SQLite query above should return this value. If not, we exit nicely and move along
	{
		my @cannedresponsesfields=('Date Created', 'Date Updated', 'Responses'); #This is the name of the fields we will be parsing
		my $cannedresponsesfilecreation="$output$slashes". "CannedResponses.html"; #Building the name of the output file
		open($CANNEDRESPONSESHTML, ">$cannedresponsesfilecreation"); #Opening our output file
		binmode $CANNEDRESPONSESHTML; #I am all about that binmode
		print $CANNEDRESPONSESHTML $pebblehtmlpage->start_html(-title => 'Canned Responses', -encoding=>"utf-8"); #Formatting
		print $CANNEDRESPONSESHTML $pebblehtmlpage->start_table({-border=>2, -cellspacing=>3, -cellpadding=>3}); #Formatting
		print $CANNEDRESPONSESHTML $pebblehtmlpage->Tr({-align=>'center',-valign=>'middle',style=>'font-size: x-large; font-weight: bold; text-decoration: underline'},[$pebblehtmlpage->th(\@cannedresponsesfields)]); #Formatting
		print STDERR "\nGood news everyone!!\nThe table \"canned_responses\" exists in this database.\nBeginning to parse data now.\n";
		my $cannedresponses_parsing=$database->prepare( "SELECT _date_created, _date_updated, responses_map FROM canned_responses ORDER BY _date_created ASC"); #Our SQLite query
		$cannedresponses_parsing->execute(); #Run query run!
		while (my @cannedresponsesquery=$cannedresponses_parsing->fetchrow_array())
		{
			#Some important cleanup, needed for parsing out this particular data field
			if ($cannedresponsesquery[2] =~ /{/)
			{
				$cannedresponsesquery[2]=~s/,/<br>/g;
				$cannedresponsesquery[2]=~s/{//g;
				$cannedresponsesquery[2]=~s/}/\n/g;
			}
			print $CANNEDRESPONSESHTML $pebblehtmlpage->Tr({-align=>'left',-valign=>'middle',style=>'font-size: medium; font-weight: ligther'},[$pebblehtmlpage->th(\@cannedresponsesquery)]); #This looks complex, but this is actually taking our output and printing it right to html
			
		}
		$cannedresponses_parsing->finish(); #Whew, I am tired
		print $CANNEDRESPONSESHTML $pebblehtmlpage->end_table; #The end of the table
		print $CANNEDRESPONSESHTML $pebblehtmlpage->end_html; #The end of the html
		close($CANNEDRESPONSESHTML); #Closing time
		print STDERR "The parsing of the table \"cannedresponses\" has completed.\nMoving on to next table now.\n";
	}
	else
	{
		print STDERR "\nThe table \"cannedresponses\" does not exist.\nMoving on to next table now.\nExiting \"cannedresponses\" subroutine.\n";
	}
}

# Android phone_numbers subroutine
sub phone_numbers ()
{
	#Defined values go here
	my ($phonenumberstableresults, $PHONENUMBERSHTML);
	#SQLite query to check if the table name exists
	my $phonenumberstablecheck=$database->prepare( "SELECT name FROM sqlite_master WHERE type='table' AND name='phone_numbers'");
	$phonenumberstablecheck->execute();
	while (my @phonenumberstablequery=$phonenumberstablecheck->fetchrow_array())
	{
		$phonenumberstableresults=$phonenumberstablequery[0];
	}

	if ($phonenumberstableresults =~ /phone_numbers/) #The SQLite query above should return this value. If not, we exit nicely and move along
	{
		my @phonenumbersfields=('Telephone Number', 'Date Number Was Last Messaged', 'Date Number Was Created', 'Date Number Was Last Updated'); #This is the name of the fields we will be parsing
		my $phonenumbersfilecreation="$output$slashes". "PhoneNumbers.html"; #Building the name of the output file
		open($PHONENUMBERSHTML, ">$phonenumbersfilecreation"); #Opening our output file
		binmode $PHONENUMBERSHTML; #I am all about that binmode
		print $PHONENUMBERSHTML $pebblehtmlpage->start_html(-title => 'Phone Numbers', -encoding=>"utf-8"); #Formatting
		print $PHONENUMBERSHTML $pebblehtmlpage->start_table({-border=>2, -cellspacing=>3, -cellpadding=>3}); #Formatting
		print $PHONENUMBERSHTML $pebblehtmlpage->Tr({-align=>'center',-valign=>'middle',style=>'font-size: x-large; font-weight: bold; text-decoration: underline'},[$pebblehtmlpage->th(\@phonenumbersfields)]); #Formatting
		print STDERR "\nGood news everyone!!\nThe table \"phone_numbers\" exists in this database.\nBeginning to parse data now.\n";
		my $phonenumbers_parsing=$database->prepare( "SELECT number, case when last_messaged_timestamp > 0 then DATETIME((last_messaged_timestamp / 1000), 'unixepoch') else '' end as last_messaged_timestamp, _date_created, _date_updated FROM phone_numbers ORDER BY _date_created ASC"); #Our SQLite query
		$phonenumbers_parsing->execute(); #Run query run!
		while (my @phonenumbersquery=$phonenumbers_parsing->fetchrow_array())
		{
			print $PHONENUMBERSHTML $pebblehtmlpage->Tr({-align=>'left',-valign=>'middle',style=>'font-size: medium; font-weight: ligther'},[$pebblehtmlpage->th(\@phonenumbersquery)]); #This looks complex, but this is actually taking our output and printing it right to html
			
		}
		$phonenumbers_parsing->finish(); #Whew, I am tired
		print $PHONENUMBERSHTML $pebblehtmlpage->end_table; #The end of the table
		print $PHONENUMBERSHTML $pebblehtmlpage->end_html; #The end of the html
		close($PHONENUMBERSHTML); #Closing time
		print STDERR "The parsing of the table \"phone_numbers\" has completed.\nMoving on to next table now.\n";
	}
	else
	{
		print STDERR "\nThe table \"phone_numbers\" does not exist.\nMoving on to next table now.\nExiting \"phone_numbers\" subroutine.\n";
	}
}


# iOS timelineattribute subroutine
sub timelineattribute ()
{
	#Defined values go here
	my ($timelineattributetableresults, $TIMELINEATTRIBUTEHTML);
	#SQLite query to check if the table name exists
	my $timelineattributetablecheck=$database->prepare( "SELECT name FROM sqlite_master WHERE type='table' AND name='ZTIMELINEITEMATTRIBUTE'");
	$timelineattributetablecheck->execute();
	while (my @timelineattributetablequery=$timelineattributetablecheck->fetchrow_array())
	{
		$timelineattributetableresults=$timelineattributetablequery[0];
	}

	if ($timelineattributetableresults =~ /ZTIMELINEITEMATTRIBUTE/) #The SQLite query above should return this value. If not, we exit nicely and move along
	{
		my @timelineattributefields=('Start Date', 'Updated At', 'Updated At 2', 'Application', 'Layout', 'Attribute Type', 'Parsed Data'); #This is the name of the fields we will be parsing
		my $timelineattributesfilecreation="$output$slashes". "TimelineAttributes.html"; #Building the name of the output file
		open($TIMELINEATTRIBUTEHTML, ">$timelineattributesfilecreation"); #Opening our output file
		binmode $TIMELINEATTRIBUTEHTML, ":utf8"; #I am all about that binmode
		print $TIMELINEATTRIBUTEHTML $pebblehtmlpage->start_html(-title => 'Timeline Attributes', -encoding=>"utf-8"); #Formatting
		print $TIMELINEATTRIBUTEHTML $pebblehtmlpage->start_table({-border=>2, -cellspacing=>3, -cellpadding=>3}); #Formatting
		print $TIMELINEATTRIBUTEHTML $pebblehtmlpage->Tr({-align=>'center',-valign=>'middle',style=>'font-size: x-large; font-weight: bold; text-decoration: underline'},[$pebblehtmlpage->th(\@timelineattributefields)]); #Formatting
		print STDERR "\nGood news everyone!!\nThe table \"ZTIMELINEATTRIBUTES\" exists in this database.\nBeginning to parse data now.\n";
		my $timelineattribute_parsing=$database->prepare( "SELECT datetime(ZSTARTDATE + 978307200, 'unixepoch') as ZSTARTDATE, datetime(ZUPDATEDAT1 + 978307200, 'unixepoch') as ZUPDATEDAT1, datetime(ZUPDATEDAT2 + 978307200, 'unixepoch') as ZUPDATEDAT2, ZAPPIDENTIFIER, ZLAYOUT, ZATTRIBUTETYPE, ZCONTENT FROM ZTIMELINEITEMATTRIBUTABLE, ZTIMELINEITEMATTRIBUTE WHERE ZTIMELINEITEMATTRIBUTABLE.Z_PK = ZATTRIBUTABLE "); #Our SQLite query
		$timelineattribute_parsing->execute(); #Run query run!
		my @cleaneduptimelineattributequery;
		while (my @timelineattributequery=$timelineattribute_parsing->fetchrow_array())
		{
			my $rawplistdata=$timelineattributequery[6];
			my $read = Data::Plist::BinaryReader->new;
			# Reading from a string <$str>
			my $plist = $read->open_string($rawplistdata);
			my $plistobject = $plist->object;
			
			# if ($plistobject =~ /Data\:\:Plist\:\:Foundation\:\:NSMutableArray/)
			# {
				# Eventually do something here, if I can figure out a good way to do it
			# }

			
			@cleaneduptimelineattributequery=($timelineattributequery[0], $timelineattributequery[1], $timelineattributequery[2], $timelineattributequery[3], $timelineattributequery[4], $timelineattributequery[5], $plistobject);
			print $TIMELINEATTRIBUTEHTML $pebblehtmlpage->Tr({-align=>'left',-valign=>'middle',style=>'font-size: medium; font-weight: ligther'},[$pebblehtmlpage->th(\@cleaneduptimelineattributequery)]) if $plistobject !~ /Data\:\:Plist\:\:Foundation\:\:NSMutableArray=HASH/; #This looks complex, but this is actually taking our output and printing it right to html			
		}
		$timelineattribute_parsing->finish(); #Whew, I am tired
		print $TIMELINEATTRIBUTEHTML $pebblehtmlpage->end_table; #The end of the table
		print $TIMELINEATTRIBUTEHTML $pebblehtmlpage->end_html; #The end of the html
		close($TIMELINEATTRIBUTEHTML); #Closing time
		print STDERR "The parsing of the table \"ZTIMELINEITEMATTRIBUTE\" has completed.\nMoving on to next table now.\n";
	}
	else
	{
		print STDERR "\nThe table \"ZTIMELINEITEMATTRIBUTE\" does not exist.\nMoving on to next table now.\nExiting \"timelineattribute\" subroutine.\n";
	}
}


sub usage() #This is where the usage statement goes. Hooray usage!
{
	my %defs=(
		s => "string",
	);
	print "\n";
	print "This script will parse data from the database associated with a\nPebble Time smart watch.\n";
	print "As of June 23, 2016, only iOS and Android databases are supported.\n";
	print "\nUsage example:\n\n";
	print "allyourpebblearebelongtous.pl -file \"pebble\" -ofolder \"ParsedResults\"\n\n";	
	print "\nOptions\n";
	for(my $c=0;$c<@options;$c+=2){
		my $arg="";
		my $exp=$options[$c+1];
		if($options[$c]=~s/([=:])([siof])$//){
			$arg="<".$defs{$2}.">" if $1 eq "=";
			$arg="[".$defs{$2}."]" if $1 eq ":";
			}
		$arg="(flag)" unless $arg;
		printf "	-%-15s $arg",$options[$c];
		print "\t",$exp if defined $exp;
		print "\n";
		}
		print "\n";
		print &changes;
		print &info;
		exit (-1);
}

sub changes ()
{
	print "\n\n";
	printf "%-15s==========CHANGES/REVISIONS==========\n";
	printf "%-17sVersion $scriptversion\n";
	printf "%-17sScript creation and subsequent revisions\n";
	printf "%-17sTested & written for Perl 5.22\n";
	
	print &info;
}
	



sub info ()
{
	print "\n\n";
	printf "%-15s==========SCRIPT INFORMATION==========\n";
	printf "%-17sScript Information: $scriptname\n";
	printf "%-17sVersion: $scriptversion\n";
	printf "%-17sAuthor: $authorname\n";
	printf "%-17sEmail: $emailaddress\n";
	printf "\n----------------- END OF LINE -----------------\n\n";
	exit (-1);
}
