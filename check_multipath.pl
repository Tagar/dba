#!/usr/bin/perl

use strict;
use constant MPATH  => '/sbin/multipath';
use constant IOSTAT => '/usr/bin/iostat';

die "Please run as root for multipath -l to work\n" if $>;
die "No paramers expected for this script.\n" if @ARGV;


open (my $mpath, '-|', MPATH, '-l') or die $!;
my @disknames;
my $largest_disbalance = -1;
while (my $line = <$mpath>)
{       print "\n"  if $line =~ / dm-\d+ /;
	print $line if $line =~ /^(size=|[0-9a-f]{10,}|\`-\+-)/;

	#  |- 1:0:0:19 sdu  65:64  active undef running
	#  `- 2:0:0:19 sdbm 68:0   active undef running

	next unless $line =~ / (.-) ([0-9:]+) (\w+)\s+(\d+:\d+) /;
	my ($node, $id, $name, $devnum) = ($1,$2,$3,$4);
	#print "       ($node, $id, $name, $devnum)\n";

	push @disknames, $name;
	if ($node eq '`-')  #if last disk for this multipath
	{	open(my $iostat, '-|', IOSTAT, @disknames) or die $!;
		my @reads;
		while (my $stat = <$iostat>)
		{	my @cols = split /\s+/, $stat;
			next unless $stat =~ /^(sd\w+|Device:)\s/ && $#cols == 5;
			printf "\t\t%-10s %-15s %-15s\n", @cols[0,4,5];
			push @reads, $cols[4];
		}
		undef @disknames;
		close $iostat;

		my ($min,$max) = (sort {$a<=>$b} @reads)[1,-1];  #index=0 containes column header
		if ($min>100_000)
		{	my $disbalance = sprintf "%.05f", ($max/$min -1.0);
			print "\tDisbalance=$disbalance\%\n";
			$largest_disbalance = $disbalance  if $disbalance>$largest_disbalance;
		}
	}
}

close $mpath;

print "\n\nLargest disbalance found $largest_disbalance\% across all multipath devices\n";
print "Only devices with more than 100k reads are accounted for.\n";


exit 0;


=pod
	Usage:
		$ sudo ./check_multipath.pl

	Sample output:
		. . . 
	
		360060e80160367000001036700007220 dm-4 HITACHI,OPEN-V
		size=1.0T features='1 queue_if_no_path' hwhandler='0' wp=rw
		`-+- policy='round-robin 0' prio=0 status=active
						Device:    Blk_read        Blk_wrtn
						sdco       31222062        360549
						sdcx       31223806        360744
				Disbalance=0.00006%

		360060e80160367000001036700007248 dm-19 HITACHI,OPEN-V
		size=1.0T features='1 queue_if_no_path' hwhandler='0' wp=rw
		`-+- policy='round-robin 0' prio=0 status=active
						Device:    Blk_read        Blk_wrtn
						sdu        3524257571      501740790
						sdbm       3526271302      500408445
				Disbalance=0.00057%


	Largest disbalance found 0.01511% across all multipath devices.
	Only devices with more than 100k reads are accounted for.

=cut

