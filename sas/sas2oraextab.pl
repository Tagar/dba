#!/usr/bin/perl

use strict;

use Getopt::Long qw(GetOptions);
use POSIX qw(ceil);

use constant {ORA_NAME_MAXLEN=>30, ORA_MAXCOLUMNS=>1000};

# ====================================================================================================================

my ($source,$id_column,$bigdata,$table,$underscores,$prefix_id,$fields,$debug, $sasname)
	= ('','',0,'',1,0,'',0,'');		#defaults
check_options();


# ====================================================================================================================

#following two hashes will contain content of the SAS description file
my %pos;	#key=name, value=[pos,len]
my %label;	#key=name, value=description

#== 1. Parse SAS fields description file
my ($lines,$prev_pos) = (0,1);
open(SAS, $sasname) || die "Can't open $sasname: $!";
foreach (<SAS>)
{	chomp;	$lines++;
	#1.1 parse INPUT section - fields names and positions
	#   @202 I00009 $char23.
	if (/^\s+\@(\d+)\s+(\S+)\s+\$char(\d+)\.$/)
	{	my ($pos,$name,$len) = ($1,$2,$3);
		debug("INPUT $name field, line $lines: unexpected start pos=$pos, expected $prev_pos, diff ".($pos-$prev_pos)) if $pos!=$prev_pos;
		$pos{$name} = [$pos,$len];
		$prev_pos = $pos+$len;
	}
	#1.2 parse LABEL section
	#   I00008 = "Filler [I00008]"
	elsif (/^\s+(\S+)\s+=\s+"(.*)"$/)
	{	my ($name,$label) = ($1,$2);
		die "Parse error: field '$name' found in LABEL section, but not in INPUT.\n" unless $pos{$name};
		$label{$name} = $label;
	}
	elsif (/^(;|INPUT|LABEL)$/)
	{	#well known syntax to ignore
	}
	else {
		die "Unrecognized syntax on $sasname line $lines:\n$_\n";
	}
}
close SAS;

#Sanity checks:
die "File $sasname does not contain fields definition.\n" if $lines<6;	#at least 6 lines for a 1-column file
die sprintf("File $sasname: $lines lines read: pos %d entries != label %d entries.", scalar(keys %pos), scalar(keys %label))
	if scalar(keys %pos) != scalar(keys %label);	#INPUT and LABEL must describe the same column set.
die "ID column '$id_column' not found in the $sasname" if $id_column && !$pos{$id_column};

#Remove columns that are not explicitly specified in --fields parameter
$fields =~ s/\s//g;
remove_columns_to_ignore()	if $fields;		#if fields parameter is set

# ====================================================================================================================


#== 2. Generate unique Oracle column names based on description, 30 chars length limit
my %oranames;		#key = SAS column id (like 'I00009'), value = Oracle column name (like 'User_ID')
my %colnames;		#key = upper cased Oracle name, value = SAS name, used for uniqueness check
my $us_ = $underscores ? '_':' ';

my ($orig_label,$label, $oraname);
foreach my $col (sort keys %label)
{	$orig_label = $label = $label{$col};
#sample of a string to parse:
#A04705 = "14-001 Birthdate Indicator 1st child "I" or "S" (Enhanced) [TSPDEOS_E11252_BRINKID1_ENH]"

	#1. cut digits and hyphens in the beginning
	$label =~ s/^[ 0-9-]+//;
	#2. cut and remember short name in the square brackets and the end
	my $short_sas_name;
	$short_sas_name=$1  if $label =~ s/ +\[(\S+)\]$//;
	#debug("step 2: $orig_label -> $label (short sas name=$short_sas_name)");

	#3. remove punctuation characters
	remove_punctuation();
	#4. shortcut ranges 
	shortcut_ranges();
	#5.1. change some words to well known abbreviations
	well_known_abbreviation();
	#5.2. cut words to ignore
	words_to_ignore();

	#6. now start cutting letters until we reach 30-char Oracle's limit
	$oraname = ($prefix_id ? "${col}_ ":'') . $label;
	while ( !good_name() )
	{	#6.1. try to remove vowels first
		cut_vowels() for 1,2;				#two times - as vowels have to be removed at a faster pace
		#6.1. try to remove consonants now
		cut_consonants();
#TODO: improvement: if $oraname is too short and not unique - try to add uniqueness by adding an id, not by cutting letters
	}
	die "Column name can't start from a digit ".oraname()  if oraname() =~ /^\d/;
	die "Empty column/field name"  if !$col || !oraname();
	$oranames{$col} = oraname();
	$colnames{uc oraname()} = $col;
	#debug("$orig_label -> ".oraname());
}#foreach $col

#try to rename ID column to just "ID", if doesn't exist already 
if ($id_column  &&  !$colnames{ID})
{	delete $colnames{$oranames{$id_column}};
	$colnames{ID} = $id_column;
	$oranames{$id_column} = 'ID';
}

#Sanity checks:
die sprintf("oranames %d entries != label %d entries.", scalar(keys %oranames), scalar(keys %label))
	if scalar(keys %oranames) != scalar(keys %label);	#oranames and LABEL must describe the same column set.

my $num_cols = scalar keys %oranames;
debug("$num_cols column names generated");


# ====================================================================================================================
	
#3. Now we can generate DDLs.

my $num_tables = $num_cols==ORA_MAXCOLUMNS ? 1: ceil($num_cols / (ORA_MAXCOLUMNS- ($id_column?1:0)));
debug("DDLs for $num_tables Oracle external tables will be generated");

my $prev_idx = 0;
for (my $tab_i=1;  $tab_i<=$num_tables;  $tab_i++)
{	my $idx = $num_cols*$tab_i/$num_tables;
	my @cols = (sort {$pos{$a}[0]<=>$pos{$b}[0]} keys %pos) [$prev_idx .. $idx -1];		#columns in the same order as in the SAS file
	$prev_idx = $idx;

	print "\n";
	my $tab_name = $table . ($num_tables>1? $tab_i:'');
	printf "CREATE TABLE $tab_name\n";
	if ($id_column)
	{	#if there is a ID column parameter - make it always first in the list (for all tables)
		@cols = ($id_column, (grep { $_ ne $id_column } @cols));
	}
	printf "( -- %d columns follow:\n", (scalar @cols);
	#Generate list of columns
	foreach my $col (@cols)
	{	my ($pos,$len) = @{$pos{$col}};
		my $oraname = $oranames{$col};
		printf "\t$oraname%sVARCHAR2(%3d BYTE)%s  -- $col\n"
				, ' ' x (4+ ORA_NAME_MAXLEN-length($oraname))
				, $len
				, $col eq $cols[-1]  ? '':','
				;
	}
	#
	my $dir = 'DIR1';
	$dir=$1  if $source =~ /^(.+?):/;
	print <<ORGANIZATION_EXTERNAL;
)
ORGANIZATION EXTERNAL
  (  TYPE ORACLE_LOADER
	 DEFAULT DIRECTORY $dir
     ACCESS PARAMETERS 
       ( RECORDS  DELIMITED BY NEWLINE
		 NOBADFILE
		 NODISCARDFILE
		 NOLOGFILE
		 FIELDS LDRTRIM
		 MISSING FIELD VALUES ARE NULL
		 REJECT ROWS WITH ALL NULL FIELDS
(
ORGANIZATION_EXTERNAL
	#Generate columns positions paragraph:
	foreach my $col (@cols)
	{	my ($pos,$len) = @{$pos{$col}};
		my $oraname = $oranames{$col};
		printf "\t$oraname%s(%5d :%5d )%s\n"	#-- $col
				, ' ' x (4+ ORA_NAME_MAXLEN-length($oraname))
				, $pos, $pos+$len-1
				, $col eq $cols[-1]  ? '':','
				;
	}
	#
	print <<CLOSING_DDL;
)
        )
     LOCATION ($source)
  )
REJECT LIMIT 0
NOPARALLEL
NOMONITORING;
CLOSING_DDL
	#Generate comments:
	my $comments_tab = $tab_name;
	$comments_tab =~ s/_?EXT(ERNAL)?$//i;
	print "\n";
	printf "-- Full description for %d columns follow:\n", (scalar @cols);
	print "-- COMMENTs are not possible on EXTERNAL tables - but you could use below statements\n";
	print "--  if you'll create a permanent table out of this EXTERNAL one.\n";
	print "/*\n";
	foreach my $col (@cols)
	{	my $label = $label{$col};
		$label =~ s/['\\]//ig;	#remove punctuation not allowed in comments
		$label =~ s/&/ /g;
		$label =~ s/\*\// /g;	#end of comment sequence
		$label =~ s/\s+/ /g;	#2+ spaces -> one
		my $oraname = $oranames{$col};
		print "COMMENT ON COLUMN $comments_tab.$oraname IS '$col: $label';\n";
	}
	print "*/\n\n";
}#for each table

printf "\n-- Above DDLs generated at %s\n", scalar(localtime());

exit 0;


# ====================================================================================================================

sub check_options {
	GetOptions('s|src=s'		=>\$source		, 't|table=s'	=>\$table
			 , 'i|idcol=s'		=>\$id_column	, 'b|bigdata'	=>\$bigdata
			 , 'u|underscore!'	=>\$underscores	, 'p|prefixid!'	=>\$prefix_id
			 , 'f|fields=s'		=>\$fields		, 'd|debug'		=>\$debug)
	&& scalar(@ARGV)==1		#filename.sas (exactly one filename), required
	&& $source && $table	#source and table name are mandatory arguments
	&& $fields =~ /^(\w+(-\w+)?(,\w+(-\w+)?)*)?$/i	#fields contains ,-separated list of fields or ranges
	|| die "Usage: $0 --src=dir:filename --table=tabname [--idcol=unqiue_id_column] \\\n"
	 . "		[--fields=f2-f10,f15-f29,..] [--bigdata] filename.SAS\n\n"
	 . "where dir:filepath - Oracle Directory name, (:)colon, and source data file name, required\n"
	 . "      tabname - Oracle external table name, required\n"
	 . "      unqiue_id_column - unqiue column name (will be copied in all external tables if >1, optional\n"
	 . "      fields - list of field ranges to create external tables for, optional\n"
	 . "      \n"
	 . "      filename.SAS - SAS file with file format and columns descritpion, required.\n\n"
	 . "Example: $0 -s \"DIRA:'sasdata.txt'\" -i A03937 -t SCHEMA.ORAEXTTAB SampleDE.SAS >SampleDE.sql\n";
	;

	#Other options not documented above:
	#	--no-u 		- don't use underscores in oracle column names;
	#	--p 		- to prefix oracle column names with original SAS field ids;
	#	--bigdata	- use Oracle Big Data Connector, not yet implemented.

	$sasname = shift @ARGV;
	debug("Cmd options: s=$source, i=$id_column, b=$bigdata, t=$table, u=$underscores, p=$prefix_id, sasname=$sasname");
}


# ====================================================================================================================

sub debug {	print STDERR "DEBUG: $_[0]\n" if $debug }

sub oraname { return join(($underscores ? '_':''), split(/ +/, $oraname))  }

sub good_name {
	return !$colnames{uc oraname()}			#column name is unique (case-insensitive)
	    && ( length(oraname()) <= ORA_NAME_MAXLEN )		#and identifier is not too long
	;
}

sub cut_vowels 		{ cut_letters('[AEIOUY]') }
sub cut_consonants 	{ cut_letters('[BCDFGHJKLMNPQRSTVWXZ]')  }
sub cut_letters {
	my $re = shift;
	if ( good_name() ) { return }
#rule 1: try to remove latest letters in a word first
#rule 2: never remove 1st letter of any word
#rule 3: remove from longest words first
	#my $oraname_before = $oraname;
	my ($letters_removed,$max_length) = (0,0);
	#1. sort words into buckets by length
	my %buckets;	#key - word length, value - array of word indexes
	my @words = split(/\s+/, $oraname);
	for (my $i=($prefix_id? 1:0);  	#skip 1st word if it is the prefix_id
			$i<=$#words;  $i++)
	{	my $word = $words[$i];
		next if $word !~ /^\S$re/i;		#ignore words that do no have letters to cut (starting from 2nd letter)
		push @{$buckets{length($word)}}, $i;
		$max_length = length($word)  if length($word)>$max_length;
	}
	#2. the loop itself
	foreach my $i (@{$buckets{$max_length}})
	{	my $skip_words_re = $i ? '(?:\S+\s+)'."{$i}" :'';
		if ($oraname =~ s/(${skip_words_re}\S+)$re(\S*?)\b/$1$2/i)		#try to remove latest possible letter in current word
		{	$letters_removed++;
			#debug("i=$i: ".substr($re,2,1).": len=".length(oraname()).": $oraname_before -> $oraname");
		}
		if ( good_name() ) { return }
	}
}#sub cut_letters

# ====================================================================================================================

sub remove_punctuation {
	$label =~ s/[+-]/$us_/g;				# just remove plus and minus signs
	$label =~ s/(\d)[,.](\d)/$1$2/g;		# remove dot or comma immediately between digits
	$label =~ s/\./$us_/g;					# remove or change to underscores all of the dots
	$label =~ s/(\s|\Z)\$+(\D|\Z)/$1Dlr$2/g;# standalone $ sign(s) -> word Dlr
	$label =~ s/(\d)'s/$1/g;				# 1000's -> 1000
	$label =~ s/[()"\/\$<:&,']/ /g;			# remove a lot of other punctuation to spaces
	#$label =~ tr/é/e/;						# é->e like in Décor
	$label =~ s/[^a-zA-Z0-9_ ]//g;			# remove any other special characters
	$label =~ s/ +/ /g;						# remove multiple space to just one
	$label =~ s/^\s*(.+?)\s*$/$1/;			# trim spaces at ^ & $
	#debug("step 3: $col: $label");
}
sub shortcut_ranges {
#Owner Occupied Housing Units Percent Value 150000 199999  -> should be 150k_200k
#Owner Occupied Housing Units Percent Value 200000000 299999999  -> should be 200M_300M
	$label =~ s/(\d+)\s*(to)?\s+(\d+)/$1_$3/ig;
	$label =~ s/(\d)000000(\D|\Z)/$1M$2/g;
	$label =~ s/(\d)000(\D|\Z)/$1k$2/g;
	$label =~ s/(\d+)999999(\D|\Z)/($1 +1) ."M$2"/xeg;
	$label =~ s/(\d+)999(\D|\Z)/($1 +1) ."k$2"/xeg;
#Owner Occupied Housing Units Percent Value 150000 199999  -> should be 150k_200k
#Owner Occupied Housing Units Percent Value 200000000 299999999  -> should be 200M_300M
	#debug("step 4: $col: $orig_label -> $label") if $orig_label =~ /\D\d{4}\D/;	#$orig_label =~ /[09]{3}/;
}
sub	well_known_abbreviation {
	$label =~ s/Households?/HH/ig;		$label =~ s/Population/Ppln/ig;
	$label =~ s/Percents?/Pcnt/ig;		$label =~ s/Enhanced/Enhnc/ig;
	$label =~ s/Count(r)y/Cnt$1y/ig;	$label =~ s/Occupation/Occpn/ig;
	$label =~ s/Effective/Effcv/ig;		$label =~ s/Retired/Rtrd/ig;
	$label =~ s/Occupied/Occpd/ig;		$label =~ s/(Average|Mean)/Avg/ig;
	$label =~ s/Years/Yrs/ig;			$label =~ s/Reserved/Rsrvd/ig;
	$label =~ s/Advantage/Advtg/ig;		$label =~ s/Transport(ation)?/Trnsprt/ig;
	$label =~ s/Administrat(ive|or)/Admin/ig;		$label =~ s/Employe([der])/Empl$1/ig;
	$label =~ s/Income/Incm/ig;			$label =~ s/Purchases?/Purchs/ig;
	$label =~ s/Channel/Chnl/ig;		$label =~ s/Birth ?date( *YYYYMM)?/BD/ig;
	$label =~ s/Residence/Rsdnc/ig;		$label =~ s/Language/Lang/ig;
	$label =~ s/Insurance/Insr/ig;		$label =~ s/Civilian/Cvln/ig;
	$label =~ s/Hispanic/Hisp/ig;		$label =~ s/Date +YYYYMM/Date/ig;
	$label =~ s/Child(ren)?/Chld/ig;	$label =~ s/Quintile/Qntl/ig;
}
sub words_to_ignore {
	$label =~ s/\b\s*or (later|older|more)$/_/i;
	$label =~ s/(\d)\s*or +(later|older|more)/$1_/ig;
	$label =~ s/\b(of|with|or|by|in|and|the|on)\b//ig;		#remove some prepositions
	$label =~ s/(\b\S+\b)(?:\s+\1\b)+/$1/g;					#remove repetitive words
	$label =~ s/ +/ /g;						# remove multiple space to just one
	$label =~ s/^\s*(.+?)\s*$/$1/;			# trim spaces at ^ & $
	#debug("step 5: $col: $orig_label -> $label") if $orig_label ne $label;
}

#
sub remove_columns_to_ignore 
{   column:
	foreach my $col (keys %pos)
	{	my ($pos,$len) = @{$pos{$col}};
		foreach my $f (split /,/, uc $fields)
		{	if ($f =~ /(\w+)-(\w+)/)
			{#field range:
				next column  if $pos >= $pos{$1}[0] && $pos <= $pos{$2}[0];
			}
			else {	#one field:
				next column  if $pos == $pos{$f}[0];
			}
		}
		#$col wasn't found in any of the field ranges, don't process it
		delete $pos{$col};
		delete $label{$col};
	}
}

# ====================================================================================================================
