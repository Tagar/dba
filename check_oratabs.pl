#!/usr/bin/perl

=pod
	This script checks consistency of oratab entries across clusterware nodes.
	Assuming a database can run on any node of a cloud (RAC or RON).
	Adds missing dbname, dbanme_1 .. dbname_x entries into the /etc/oratab,
	where x=2 for RON, and maximum current number of instances for RAC database.
	Will report if entry is in /etc/oratab, but is pointing to a wrong OH
	(per srvctl condig database output).

	Usage: add GI bin home to PATH and launch this script without parameters first time.
	When you confirm all oratab-$node.good files are okay, run the script second time
	with --apply parameter - it just copies generated previously .good files to remote
	oratabs. Original /etc/oratab from all servers are saved locally as .saved files.
=cut

use strict;
use constant (DEBUG => 0);
use Getopt::Long;

my $quite_ssh = '-q -o PasswordAuthentication=no -o StrictHostKeyChecking=no';


my $apply;
GetOptions('apply'=>\$apply) || die "Usage: $0 [--apply]\n";
if ($apply) #Apply mode:
{	#applying previously generated oratab.good files to remote hosts
	foreach my $fname (<./oratab-*.good>)
	{	print "\n";
		$fname =~ /oratab-(.+?)\.good$/ || next;
		my $node = $1;
		my ($size,$mtime) = (stat($fname))[7,9];
		$mtime = scalar localtime $mtime;
		unless (prompt_yn("File $fname ($size bytes) modified $mtime will be copied to /etc/oratab at $node. \t"))
			{	print "Skipped\n"; next	}
		#1. Save original remote file locally
		my ($saved_fname, $i);
		do {	$saved_fname = "./oratab-$node.saved";
				$saved_fname .= "_$i" if $i++;			#don't overwrite .saved files - find a new filename
		} while -e $saved_fname;
		my $scp = `scp $quite_ssh $node:/etc/oratab $saved_fname`;
		$? == 0 || die "Could not save /etc/oratab from $node: $!";
		print "Original file saved as $saved_fname\n";
		#2. Overwrite remote oratab
		$scp = `scp $quite_ssh $fname $node:/etc/oratab`;
		$? == 0 || die "Could copy file to /etc/oratab from $node: $!";
		print "$fname overwritten /etc/oratab on $node\n";
	}
	exit 0;
}


#No options specified, complete the first run:

#1. Checking all cloud nodes.
my $crs_stat = `crsctl stat res -t -w "TYPE = ora.cluster_vip_net1.type"`	#or net2 too?
	|| die "Error running crsctl stat res for vip: $!";
my %oratab; #hash(by nodes) of hashes(by db/sid name), value is OH
my %asmtab;	#hash(by node), value is ASM sid colon(:) GI home
my $quite_ssh = '-q -o PasswordAuthentication=no -o StrictHostKeyChecking=no';
foreach my $line (split /\n/, $crs_stat)
{	next if $line !~ /^ora\.(.+?)\.vip$/;
	my $node = $1;
	my $oratab = `ssh $quite_ssh $node "cat /etc/oratab"`;
	$? == 0 || die "Could not fetch /etc/oratab from $node: $!";
	print "/etc/oratab is ".length($oratab)." bytes long on $node:\n";
	#parse the oratab file:
	foreach (split /\n/, $oratab)
	{	s/^\s*#.*$//;			#remove comments
		s/^\s*(.*?)\s*$/$1/;	#remove trailing and heading whitespaces
		next unless /^([^:]+):([^:]+):[YN]/i;
		if (substr($_,0,1) eq '+') 
		          {	$asmtab{$node}="$1:$2" }		#ASM entry (assuming just one)
			 else {	$oratab{$node}{$1}=$2  }		#db db/sid entry
	}
	print "  ".(scalar keys %{$oratab{$node}})." oratab entries found.\n";
	`cat /dev/null >oratab-$node.sdiff`;	#reset report files
}


print "\n";

#2. Checking all databases
my (%dbtype,%dbhome,%inst,%dbinst);
# %dbtype - RAC, RACOneNode (or SingleInstance - check if there are any);
# %dbinst - how many instances have a RAC database;
# %inst   - list of comma-separated instances from srvctl's "Database instances"
# %dbhome - db Oracle Home.

$crs_stat = `crsctl stat res -t -w "TYPE = ora.database.type"`	#|head -20  for debugging
	|| die "Error running crsctl stat res: $!";

my $db;
foreach my $line (split /\n/, $crs_stat)
{	if ($line =~ /^ora\.(.+?)\.db$/)
	{	$db = $1;
		print "Pulling srvctl config database -d $db ...\n";
		my $dbcfg = `srvctl config database -d $db`;
		if ($dbcfg =~ /. Instead run the program from (.+?)\.$/s)
		{	#sometimes srvctl has to be run from a specific OH:
			$dbcfg = `$1/bin/srvctl config database -d $db`;
			print "$db uses another OH $1\n"	if DEBUG;
		}
		for my $srvline (split /\n/, $dbcfg)
		{	next if $srvline !~ /^(.+?): (.+)$/;
			my ($name,$val) = ($1,$2);
			   if ($name =~ /^Type$/i ) 	   		{ $dbtype{$db}=$val }
			elsif ($name =~ /^Oracle home$/i ) 		{ $dbhome{$db}=$val }
			elsif ($name =~ /^Database instances/i ){ $inst{$db}=$val }
		}
		print "Type $dbtype{$db}; OH $dbhome{$db}; instances: $inst{$db}\n"  if DEBUG;
	}
	else
	{	#      1        ONLINE  ONLINE       v-craig                  Open
		next if $line !~ /^\s+(\d+)\s+(online|offline|intermediate)\s+/i;
		$dbinst{$db}=$1  if $dbinst{$db} < $1;
		print "Instance count set to $dbinst{$db}\n"  if DEBUG;
	}
}


#3. Compute how many instances (sids in /etc/oratab) each database
#   might have depending on type.
foreach my $db (sort keys %dbhome)
{	my $inst_cnt = $dbtype{$db} eq 'RACOneNode' ? 2				#RON has 2 additional entries
				 : $dbtype{$db} eq 'RAC' 		? $dbinst{$db}
				 : 0;	#for SI db only db/sid entry itself, no sid_x
	$dbinst{$db} = $inst_cnt;
}


#4. Now go through each database and node and decide what oratab entries to update

print "\n";

#4.1. Check entries that are missing in the oratabs:
my %missing_on;	#key is db or sid, value is list of nodes
my %allsid;		#all possible dbs and sids, used in later steps
foreach my $db (sort keys %dbhome)
{	foreach my $node (keys %oratab)
	{	push @{$missing_on{$db}}, $node  unless exists $oratab{$node}{$db};
		$allsid{$db} = $dbhome{$db};
		for (my $i=1;  $i<=$dbinst{$db};  $i++)
		{	my $sid = "${db}_$i";
			$allsid{$sid} = $dbhome{$db};	#all sids use the same dbhome
			push @{$missing_on{$sid}}, $node  unless exists $oratab{$node}{$sid};
		}
		foreach my $sid (split /,/, $inst{$db})
		{	$allsid{$sid} = $dbhome{$db};	#all sids use the same dbhome
			push @{$missing_on{$sid}}, $node  unless exists $oratab{$node}{$sid};
		}
	}
}
#report missing:
foreach my $sid (sort keys %missing_on)
{	my @nodes = sort @{$missing_on{$sid}};
	print "$sid missing on \t".join(',',@nodes)."\n";
	map {`echo "+ $sid:$allsid{$sid}:N" >> oratab-$_.sdiff`} @nodes;
}


print "\n";

#4.2. Check orphan entries in oratabs (there is no matching database in CRS):
foreach my $node (sort keys %oratab)
{	my @orphans;
	foreach my $sid (sort keys %{$oratab{$node}})
	{	push @orphans, $sid unless exists $allsid{$sid};
		`echo "- $sid:$oratab{$node}{$sid}:N" >> oratab-$node.sdiff`;
	}
	if (@orphans)
	{	print "Orphan /etc/oratab entries on $node:\n";
		print "  ".join(',',@orphans)."\n";
	}
}


print "\n";

#4.3. Check for wrong OH entries in oratabs (doesn't match srvctl config output):
foreach my $node (sort keys %oratab)
{	my @mismatches;
	foreach my $sid (sort keys %{$oratab{$node}})
	{	next unless exists $allsid{$sid};	#skip entries that were already reported above as orphan
		my ($oh1,$oh2) = ($oratab{$node}{$sid}, $allsid{$sid});
		if ($oh1 ne $oh2)
		{	push @mismatches, $sid;
			print "$sid\@$node:  \t$oh1, should be \t$oh2\n"  if DEBUG;
			my $sdiff = sprintf "! %s:%s:N \t\t ! %s", $sid,$oh1, $oh2;
			`echo "$sdiff" >> oratab-$node.sdiff`;
		}
	}
	if (@mismatches)
	{	print "Entries in /etc/oratab at $node with wrong OH:\n";
		print "  ".join(',',@mismatches)."\n";
	}
}


#5. Write "good" oratab file as well in the current directory.
#   All oratabs should be the same except ASM entry
foreach my $node (sort keys %oratab)
{	`echo "$asmtab{$node}:N" > oratab-$node.good`;
	foreach my $sid (sort keys %allsid)
	{	`echo "$sid:$allsid{$sid}:N" >> oratab-$node.good`;
	}
}


print "\n";

#6. Check if there are any databases or ASM instances running that were not added to clusterware
foreach my $node (sort keys %oratab)
{	my $pmons = `ssh $quite_ssh $node "ps -ef | grep pmon | grep -v grep | cut -d'_' -f 3,4"`;
	$? == 0 || die "Could not fetch list of processes from $node: $!";
	foreach my $sid (split /\n/, $pmons)
	{	
		if ( substr($sid,0,1) eq '+' ? $asmtab{$node} !~ /^\Q$sid\E:/ : !$allsid{$sid} )
		{ print "pmon for unknown sid $sid is running on $node. Will not be added to oratab.good files.\n" }
	}
}


exit;

sub prompt {
  my ($query) = @_; # take a prompt string as argument
  local $| = 1; # activate autoflush to immediately show the prompt
  print $query;
  chomp(my $answer = <STDIN>);
  return $answer;
}
sub prompt_yn {
  my ($query) = @_;
  my $answer = prompt("$query (Y/N): ");
  return lc($answer) eq 'y';
}


