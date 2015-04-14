#!/usr/bin/perl -w

use strict;
use DBI;
use DBD::Oracle qw(:ora_session_modes);
use File::Spec;
use Sys::Hostname;
use POSIX qw(ceil);
use IO::Handle;

# Connections 
my $dbasm;
my $db;

# files
my $param = "connect.param";

# connect
my $host = hostname();
my $dbName = ""; 
my $dbPort = "1521";
my $dbUser = "";
my $dbPass = "";

# Global variables

# global Control
my $readConn = 0;


sub connASM {

$dbasm = DBI->connect( "dbi:Oracle:", "", "", { ora_session_mode => ORA_SYSDBA})
    || die( $DBI::errstr . "\n" );
$dbasm->{AutoCommit}    = 0;
$dbasm->{RaiseError}    = 1;
$dbasm->{ora_check_sql} = 0;
$dbasm->{RowCacheSize}  = 16;

}

sub connDB {

$db = DBI->connect("dbi:Oracle://$host:$dbPort/$dbName", "$dbUser", "$dbPass")
    || die( $DBI::errstr . "\n" );
$db->{AutoCommit}    = 0;
$db->{RaiseError}    = 0;
$db->{PrintError}    = 1;
$db->{ora_check_sql} = 0;
$db->{RowCacheSize}  = 16;

}

sub disconnASM {

    $dbasm->disconnect if defined($dbasm);
	
}

sub disconnDB {

    $db->disconnect if defined($db);
	
}


sub printStage {

	my $text = $_[0];
	print "\n";
	print '-' x length($text) . "\n";
	print "$text\n";
	print '-' x length($text) . "\n";
	
}

sub qSingle {


	my ($type,$SQL) = @_;
	my $sth;

	if ( $type eq "ASM") {
		$sth = $dbasm->prepare($SQL);
	}
	elsif ( $type eq "DB") {
		$sth = $db->prepare($SQL);
	}
	
	$sth->execute();
	
	my @row = $sth->fetchrow_array();
	return @row;

}

sub qMulti {

	my ($type,$SQL) = @_;
	my $sth;

	if ( $type eq "ASM") {
		$sth = $dbasm->prepare($SQL);
	}
	elsif ( $type eq "DB") {
		$sth = $db->prepare($SQL);
	}
	
	$sth->execute();
	my $nf = $sth->{NUM_OF_FIELDS};
	my @dim;
	while ( my @row = $sth->fetchrow_array() ) {
		push @{ $dim[$sth->rows - 1]}, @row;
	}
	
	return ($sth->rows, @dim);
}


sub readConn {

	$readConn=1;
	my $readinput;
	print "\n\nPlease provide DB connection:\n\n";
	
	print "HOSTNAME of DB ($host): ";
	$readinput = <STDIN> ;
	chomp($readinput);
	if ( $readinput ne "" ) {
		$host = $readinput;
	}
	
	print "Port of Listener ($dbPort): ";
	$readinput = <STDIN> ;
	chomp($readinput);
	if ( $readinput ne "" ) {
		$dbPort = $readinput;
	}
	
	print "Database Name ($dbName): ";
	$readinput = <STDIN> ;
	chomp($readinput);
	if ( $readinput ne "" ) {
		$dbName = $readinput;
	}
	
	print "Username of DB ($dbUser): ";
	$readinput = <STDIN> ;
	chomp($readinput);
	if ( $readinput ne "" ) {
		$dbUser = $readinput;
	}
	
	print "Password for $dbUser : ";
	system ("stty -echo");
	$readinput = <STDIN> ;
	system ("stty echo");
	chomp($readinput);
	if ( $readinput ne "" ) {
		$dbPass = $readinput;
	}
	
	print "\n\n";
	print "HOSTNAME: $host \n";
	print "    PORT: $dbPort \n";
	print "  DBNAME: $dbName \n";
	print "USERMAME: $dbUser \n";
	print "PASSWORD: $dbPass \n";

}

sub printRowid {
	my $rowid = $_[0];
	
	my ($dbFileId, $dbBlkId) = qSingle ("DB","select dbms_rowid.ROWID_RELATIVE_FNO('$rowid'),dbms_rowid.ROWID_BLOCK_NUMBER('$rowid') from dual");
	#print "file id: $dbFileId\nblcoknum: $dbBlkId\n";
	
	printBlock($dbFileId, $dbBlkId);
	
}

sub printBlock {

	my ($dbFileId, $dbBlkId) = @_;
	my ($dbBlkSize,$dbTbsName, $dbFileName, $asmDgName,$asmFileName,$asmAuSize,@asmCopy) = getFromBlock($dbFileId, $dbBlkId);
	
	printStage "Printing Report";
	
	my @format = qw(2 20 57);
	printLine (@format);
	printHeader (@format, "Block information: FileID->$dbFileId,BlockID->$dbBlkId");
	printLine (@format);
	printField (@format, "DB Block Size", $dbBlkSize);
	printField (@format, "ASM AU Size",   $asmAuSize);
	printField (@format, "Tablespace Name", $dbTbsName);
	printField (@format, "DB File Name",  $dbFileName);
	printField (@format, "ASM Diskgroup", $asmDgName);
	printField (@format, "ASM File Name", $asmFileName);
	printLine (@format);
	

	my @copyName = qw(Primary Secondary Tertiary);
	
	foreach my $row (@asmCopy) {
		#printStage "$copyName[0] Copy";
		printLine (@format);
		printHeader (@format, "$copyName[0] Copy");
		printLine (@format);
	
		shift @copyName;
		
		printField (@format, "ASM Disk ID", $row->[0]);
		printField (@format, "ASM AU ID", $row->[1]);
		printField (@format, "ASM Mirror ID", $row->[2]);
		printField (@format, "ASM Failgroup", $row->[3]);
		printField (@format, "ASM File Path", $row->[4]);
		printField (@format, "ASM Extent ID", $row->[5]);

		printLine (@format);

	}


}

sub getFromBlock {

	my ($dbFileId, $dbBlkId) = @_;
	
	my ($dbBlkSize,$dbFileName, $asmDgName,$asmFileName,$asmAuSize,$asmDgId,$asmFileId,$asmMirror,$dbTbsName) = getDBFile($dbFileId, $dbBlkId);
	
	my @asmCopy = findBlock($dbBlkSize,$dbBlkId,$asmAuSize,$asmDgId,$asmFileId);
	return ($dbBlkSize,$dbTbsName, $dbFileName, $asmDgName,$asmFileName,$asmAuSize,@asmCopy);

}

sub getDBFile {

	my ($dbFileId, $dbBlkId) = @_;
	my $asmFileName;
	my $asmDgName;
	
	my $SQL = <<"EOF";
select dbf.tablespace_name,dbf.file_name,tbs.block_size
  from dba_data_files dbf, dba_tablespaces tbs
 where dbf.tablespace_name=tbs.tablespace_name
   and dbf.file_id=$dbFileId
EOF
	my ($dbTbsName,$dbFileName,$dbBlkSize) = qSingle ("DB", $SQL);
	#print "$dbTbsName,$dbFileName,$dbBlkSize\n";

	if ( $dbFileName =~ /^\+(\w+)\/\S+\/(.+)$/ ) {
		$asmDgName = $1;
		$asmFileName = $2;
		#print "Diskgroup: $asmDgName\n ASM file: $asmFileName\n";
	}
	else {
		print "Database file doesn't reside in ASM!\n";
		exit;
	}
	
	$SQL = "select GROUP_NUMBER,ALLOCATION_UNIT_SIZE,decode(TYPE,'NORMAL',2,'HIGH',3,1) FROM v\$asm_diskgroup where name='$asmDgName'";
	my ($asmDgId,$asmAuSize,$asmMirror) = qSingle("ASM",$SQL);
	#print " GroupNum: $asmDgId\n  AU Size: $asmAuSize\n";
	
	$SQL = "select file_number from v\$asm_alias where upper(name)=upper('$asmFileName')";
	my ($asmFileId) = qSingle("ASM",$SQL);
	#print "AsmFileID: $asmFileId\n";
	
	return ($dbBlkSize,$dbFileName, $asmDgName,$asmFileName,$asmAuSize,$asmDgId,$asmFileId,$asmMirror,$dbTbsName);

}

sub findBlock {

	my ($dbBlkSize,$dbBlkId,$asmAuSize,$asmDgId,$asmFileId) = @_;
	#print "\n";
	my $blkPerAU = $asmAuSize/$dbBlkSize;
	#print "Blocks per AU: $blkPerAU\n";
	my $extentNum = blk2Ext($dbBlkId, $blkPerAU);
	#print "ASM Extent: $extentNum\n";
	
	my $SQL = <<"EOF";
select  DISK_KFFXP asmDiskNum,
      AU_KFFXP AuNum,
	  LXN_KFFXP Mirror,
	  dsk.failgroup,
	  dsk.path,
	  XNUM_KFFXP
 from X\$KFFXP xp, v\$asm_disk dsk
where DISK_KFFXP=dsk.disk_number
  AND GROUP_KFFXP=dsk.group_number
  AND NUMBER_KFFXP=$asmFileId
  AND GROUP_KFFXP=$asmDgId
  AND XNUM_KFFXP=$extentNum
order by  LXN_KFFXP
EOF

	#my ($asmDiskID,$asmAuID,$asmMirror,$asmFailGroup,$asmFilePath) = qSingle("ASM",$SQL);
	#print "$asmDiskID,$asmAuID,$asmMirror,$asmFailGroup,$asmFilePath\n";
	
	my ($rcnt,@asmCopy) = qMulti("ASM",$SQL);
	
#foreach my $row (@asmCopy) {
#    foreach my $element (@$row) {
#        print $element, "\t";
#    }
#	print "\n";
#}


	return @asmCopy;
	
}

sub checkInput {

	my $input = $_[0];
	
	if ( validRowid($input) >=0 ) {
		print "$input is valid rowid!\n";
		return "rowid";
	}
	if ( validTable($input) >= 0 ) {
		$input = uc $input ;
		print "'$input' is valid table name!\n";
		return "table";
	}
	else {
		print "Invalid input! \n\n";
		return "invalid";
	}
}

sub validRowid {

	my $rowid = $_[0];
	if ( ! ($rowid =~ /^[1-9a-zA-Z]{18}$/) ) {
		#print "invalid rowid format\n";
		return -1;
	}
	my $SQL = <<"EOF";
select DBMS_ROWID.ROWID_OBJECT('$rowid'),
       DBMS_ROWID.ROWID_RELATIVE_FNO('$rowid'),
       DBMS_ROWID.ROWID_BLOCK_NUMBER('$rowid'),
       DBMS_ROWID.ROWID_ROW_NUMBER('$rowid')
from dual
EOF
	my @row = qSingle ("DB", $SQL);
	return $#row;
}

sub validTable {

	my $input = $_[0];
	my $schema = "";
	my $tableName;
	
	if ( $input =~ /^(\w[\w\d]*)\.(\w[\w\d]*)$/ ) {
		$schema = $1;
		$tableName = $2;
	}
	elsif ( $input =~ /^(\w[\w\d]*)$/ ) {
		$tableName = $input;	
	}
	else {
			return -1;
	}
	
	
	my $SQL ;
	if ( length($schema) == 0 ) {
		$SQL = "select tname from tab where tname=upper('$tableName') and TABTYPE='TABLE'";
	}
	else {
		$SQL = "select table_name from all_tables where table_name=upper('$tableName') and owner=upper('$schema')";
	}
	
	my @row = qSingle ("DB", $SQL);
	return $#row;
	
}



sub printTable_3 {

	my $input = $_[0];
		
	my $SQL = <<"EOF";
select dbms_rowid.ROWID_RELATIVE_FNO(rowid),
       dbms_rowid.ROWID_BLOCK_NUMBER(rowid),
	   count(*) 
  from $input 
 group by dbms_rowid.ROWID_RELATIVE_FNO(rowid),
          dbms_rowid.ROWID_BLOCK_NUMBER(rowid)
 order by dbms_rowid.ROWID_RELATIVE_FNO(rowid)
EOF

	printStage "Getting data and calculate";
	STDOUT->autoflush(1);
	print "Retrieving table data...";
	my ($rcnt,@tableMap) = qMulti("DB",$SQL);
	print " $rcnt blocks found.\n";
	
	my %dbFileNameB; # Blocks Per File
	my %dbFileNameR; # Rows Per File
	my %FailGroup1B; # Blocks Per FailGroup in Primary Copy;
	my %FailGroup2B; # Blocks Per FailGroup in Secondary Copy;
	my %FailGroup3B; # Blocks Per FailGroup in Territry Copy;
	my %FailGroup1R; # Rows Per FailGroup in Primary Copy;
	my %FailGroup2R; # Rows Per FailGroup in Secondary Copy;
	my %FailGroup3R; # Rows Per FailGroup in Territry Copy;
	my %asmDisk1B;   # Blocks Per ASM Disk in Primary Copy;
	my %asmDisk2B;   # Blocks Per ASM Disk in Secondary Copy;
	my %asmDisk3B;   # Blocks Per ASM Disk in Territry Copy;
	my %asmDisk1R;   # Rows Per ASM Disk in Primary Copy;
	my %asmDisk2R;   # Rows Per ASM Disk in Secondary Copy;
	my %asmDisk3R;   # Rows Per ASM Disk in Territry Copy;
	my $totalB;
	my $totalR;
	
	my $topCopy;
	my $i = 0;
	my $curDBF = -1;
	
	#my ($dbBlkSize,$dbTbsName, $dbFileName, $asmDgName,$asmFileName,$asmAuSize,@asmCopy);
	#my ($asmDiskID,$asmAuID,$asmMirror,$asmFailGroup,$asmFilePath);
	
	my ($dbBlkSize,$dbFileName, $asmDgName,$asmFileName,$asmAuSize,$asmDgId,$asmFileId,$asmMirror,$dbTbsName);
	


	#my $sthasm = $dbasm->prepare($SQL_asmMeta);
	my @asmMeta;
	my $asmMetaCnt;
	
	my $blkPerAU;
	my $extentNum;

	my $sth;
	

	foreach my $row (@tableMap) {
		
		# $row->[0] fileID, $row->[1] BlockID, $row->[2] Row count
		if ( $curDBF != $row->[0] ) {
		
			($dbBlkSize,$dbFileName, $asmDgName,$asmFileName,$asmAuSize,$asmDgId,$asmFileId,$asmMirror,$dbTbsName) = getDBFile($row->[0],$row->[1]);
			#print "$dbBlkSize, $dbFileName, $asmDgName,$asmFileName,$asmAuSize,$asmDgId,$asmFileId\n";
			

			print "\n";
			my @format = qw(2 20 57);
			printLine (@format);
			printHeader (@format, "Data File Information");
			printLine (@format);
			printField (@format, "DB Block Size", $dbBlkSize);
			printField (@format, "DB File Name", $dbFileName);
			printField (@format, "ASM AU Size", $asmAuSize);
			printField (@format, "ASM DiskGroup ID", $asmDgId);
			printField (@format, "ASM DiskGroup", $asmDgName);
			printField (@format, "ASM File Name", $asmFileName);
			printField (@format, "ASM File ID", $asmFileId);
			printField (@format, "ASM Copy", $asmMirror);
			printLine (@format);

			
			$SQL = <<"EOF";
select  DISK_KFFXP asmDiskNum,
	  LXN_KFFXP Mirror,
	  dsk.failgroup,
	  dsk.path,
	  XNUM_KFFXP
 from X\$KFFXP xp, v\$asm_disk dsk
where DISK_KFFXP=dsk.disk_number
  AND GROUP_KFFXP=dsk.group_number
  AND NUMBER_KFFXP=$asmFileId
  AND GROUP_KFFXP=$asmDgId
order by  LXN_KFFXP
EOF

			print "Getting ASM matedata for ASM file $dbFileName ...";
			
			($asmMetaCnt,@asmMeta) = qMulti("ASM",$SQL);
			
			print "$asmMetaCnt rows loaded. \n";
			
			$blkPerAU = $asmAuSize/$dbBlkSize;
			
			$curDBF = $row->[0];
				
		}
		
		$totalB++;
		$totalR += $row->[2];
		$dbFileNameB{$asmFileName}++;
		$dbFileNameR{$asmFileName} += $row->[2];
		$topCopy = 0;
		
		foreach my $asm (@asmMeta) {
		
			$extentNum = blk2Ext($row->[1], $blkPerAU);
			#$extentNum = int($row->[1]/$blkPerAU);
			#print $asm->[4]."\n";
			# 0:asmDiskNum 1: Mirror 2: FailGroup 3: path 4: ExtendNum
			if ( $asm->[4] == $extentNum) {
			
				if ( $asm->[1] == 0 ) {
					$FailGroup1B{$asm->[2]}++;
					$FailGroup1R{$asm->[2]} += $row->[2];
					$asmDisk1B{$asm->[3]}++;
					$asmDisk1R{$asm->[3]} += $row->[2];
				}
				elsif ( $asm->[1] == 1 ) {
					$FailGroup2B{$asm->[2]}++;
					$FailGroup2R{$asm->[2]} += $row->[2];
					$asmDisk2B{$asm->[3]}++;
					$asmDisk2R{$asm->[3]} += $row->[2];
				}
				elsif ( $asm->[1] == 2 ) {
					$FailGroup3B{$asm->[2]}++;
					$FailGroup3R{$asm->[2]} += $row->[2];
					$asmDisk3B{$asm->[3]}++;
					$asmDisk3R{$asm->[3]} += $row->[2];
				}
				#last;
				$topCopy++;
				if ($topCopy == $asmMirror) {
					last;
				}
				
			}
		} 
		$i++;
		
		#STDOUT->autoflush(0);
		#print "Processing file->$row->[0], block->$row->[1] ($i\/$rcnt) [ ". int($i*100/$rcnt) . "%\r"; 
		printf ("Processing %3s%% [%-50s] [%6s/%-6s]\r",int($i*100/$rcnt),"#" x ceil($i*100/($rcnt*2)),$i,$rcnt);
	}
	
	print "\n";
	printStage "Printing Reports";
	
	my @format = qw(3 50 13 13);
	
	printLine (@format);
	printHeader (@format,"Group by Data Files");
	printLine (@format);
	
	if (%dbFileNameB) {

		printField (@format,"Data File Name","Blocks","Rows");
		printLine (@format);
		
		foreach my $key (sort keys %dbFileNameB) {
			printField (@format,$key,$dbFileNameB{$key},$dbFileNameR{$key});
			#print "$key : $dbFileNameB{$key} : $dbFileNameR{$key} \n";
			}
	
		printLine (@format);
	}
	
	printLine (@format);
	printHeader (@format,"Group By ASM FailGroup");
	printLine (@format);
	
	if (%FailGroup1B) {
		printHeader (@format,"Primary Copy");
		printLine (@format);
		printField (@format,"ASM FailGroup","Blocks","Rows");
		printLine (@format);
	
		foreach my $key (sort keys %FailGroup1B) {
			printField (@format,$key,$FailGroup1B{$key},$FailGroup1R{$key});
			#print "$key : $FailGroup1B{$key} : $FailGroup1R{$key} \n";
		}
		printLine (@format);
	}
	
	if (%FailGroup2B) {
	
		printHeader (@format,"Secondary Copy");
		printLine (@format);
		foreach my $key (sort keys %FailGroup2B) {
			printField (@format,$key,$FailGroup2B{$key},$FailGroup2R{$key});
			#print "$key : $FailGroup2B{$key} : $FailGroup2R{$key} \n";
		}
		printLine (@format);
	}
	
	if (%FailGroup3B) {
	
		printHeader (@format,"Tertiary Copy");
		printLine (@format);
		foreach my $key (sort keys %FailGroup3B) {
			printField (@format,$key,$FailGroup3B{$key},$FailGroup3R{$key});
		}
		printLine (@format);
	}

	printLine (@format);
	printHeader (@format,"Group By ASM Files");
	printLine (@format);
	
	if (%asmDisk1B) {
		printHeader (@format,"Primary Copy");
		printLine (@format);
		printField (@format,"ASM File Name","Blocks","Rows");
		printLine (@format);
	
		foreach my $key (sort keys %asmDisk1B) {
			printField (@format,$key,$asmDisk1B{$key},$asmDisk1R{$key});
		}
		printLine (@format);
	}
	
	if (%asmDisk2B) {
	
		printHeader (@format,"Secondary Copy");
		printLine (@format);
		foreach my $key (sort keys %asmDisk2B) {
			printField (@format,$key,$asmDisk2B{$key},$asmDisk2R{$key});
		}
		printLine (@format);
	}
	
	if (%asmDisk3B) {
	
		printHeader (@format,"Tertiary Copy");
		printLine (@format);
		foreach my $key (sort keys %asmDisk3B) {
			printField (@format,$key,$asmDisk3B{$key},$asmDisk3R{$key});
		}
		printLine (@format);
	}
	


}

sub blk2Ext {
	my ($blkID,$blkPerAU) = @_;
	# Till 12.1 Ext size: 1~20000au->1au  20000~40000au->4au  40000+au->16au
	if ($blkID < $blkPerAU*20000) {
		return int($blkID/$blkPerAU);
	}
	elsif ($blkID < ($blkPerAU*20000+$blkPerAU*20000*4) ) {
		return int((($blkID-$blkPerAU*20000)/(4*$blkPerAU))+20000);
	}
	else	{
		return  int((($blkID-$blkPerAU*20000-$blkPerAU*20000*4)/(16*$blkPerAU))+40000);
	}
	
}



sub printLine {
	my ($fCnt,@header) = @_;
	my @fSize;
	for (my $i = 0; $i<$fCnt ; $i++) {
		push (@fSize, shift @header);
	}
	foreach my $row (@fSize) {
		print "-" x ($row + 1);
	}
	print "-\n";
}

sub printHeader {
	my ($fCnt,@header) = @_;
	#printLine ($fCnt,@header);
	
	my $fSize=0;
	for (my $i = 0; $i<$fCnt ; $i++) {
		$fSize = $fSize + $header[$i];
	}
	
	#printf ("| %-".($fSize+$fCnt-1-1)."s|\n", "$header[$#header]");
	printf ("|%-".($fSize+$fCnt-1)."s|\n", " " x int(($fSize+$fCnt-1-length($header[$#header]))/2) ."$header[$#header]");
	
}


sub printField {
	my ($fCnt,@header) = @_;
	#printLine ($fCnt,@header);
	
	my @fSize;
	for (my $i = 0; $i<$fCnt ; $i++) {
		push (@fSize, shift @header);
	}
	
	
	for (my $i = 0; $i<$fCnt ; $i++) {
		printf("| %-".($fSize[$i]-1)."s", "$header[$i]");
	}
	print "|\n";
	

	
}


#############################
########## MAIN #############
#############################

# catch Ctrl+C
$SIG{INT} = sub { die "Caught a sigint!" };


# Get abs path of this script
my ($vol,$dir,$filename) = File::Spec->splitpath( File::Spec->rel2abs( __FILE__ ) );

printStage "Checking for existing connect string";

if (open(my $fh, '<:encoding(UTF-8)', $dir.$param)) {
	print "param file found: $dir$param\n\n";
	while (my $row = <$fh>) {
		chomp $row;
		print "$row\n";
		# read parameter file to glboal varibales. 
		if ( $row =~ /\s*HOSTNAME: (.*)$/) { $host = $1; }
		elsif ( $row =~ /\s*PORT: (.*)$/)  { $dbPort = $1; }
		elsif ( $row =~ /\s*DBNAME: (.*)$/)  { $dbName = $1; }
		elsif ( $row =~ /\s*USERMAME: (.*)$/)  { $dbUser = $1; }
		elsif ( $row =~ /\s*PASSWORD: (.*)$/)  { $dbPass = $1; }
	}

	print "Do you want to use above connection? (y/n) [y]:";
	my $readinput = <STDIN> ;
	chomp($readinput);
	if ( $readinput eq "" || $readinput eq "y" ) {
		;
	}
	elsif ( $readinput eq "n" ) {
		readConn;
	}
	else {
		print "invalid input! \n";
		exit;
	}	
} 
else {
	print "Could not open file '$dir$param': $! \n";
	readConn;
}

printStage "Checking RDBMS/ASM Connection";

print "Connecting to ASM instance...";
connASM;
print "Succeed!\n";

print "Connecting to $dbName instance...";
connDB;
print "Succeed!\n";

if ( $readConn == 1 ) {
	print "Do you want to save the setting? (y/n) [y]:";
	my $readinput = <STDIN> ;
	chomp($readinput);
	if ( $readinput eq "" || $readinput eq "y" ) {
		print "Saving file...";
		my $filename= $dir.$param;
		open(my $fh, '>', $filename) or die "Could not open file '$filename' $!";
		print $fh "My first report generated by perl\n";
		print $fh "HOSTNAME: $host\n";
		print $fh "    PORT: $dbPort\n";
		print $fh "  DBNAME: $dbName\n";
		print $fh "USERMAME: $dbUser\n";
		print $fh "PASSWORD: $dbPass\n";
		close $fh;
		print "Done!\n";
	}
}

#printLine (3, 20, 15, 10);
#printField (3, 20, 15, 10, "Tablesapace","Size","Values");
#printLine (3, 20, 15, 10);

printStage "Getting input and check";

my $input;
my $type="invalid";



while ( $type eq "invalid" ) {

	print "'rowid', or 'fileID,blockID', or 'schema.tableName', or 'tableName'\n: ";
	$input = <STDIN> ;
	chomp($input);
	if ( $input ne "" ) {
		$type = checkInput($input);
	}
	else {
		print "exit!\n";
		exit;
	}
}

#my $rowid="AAAF3BAAFAAAACfAAD";

# printStage "Start calculations.";

if ( $type eq "rowid" ) {
	printRowid $input;
}
elsif ( $type eq "table") {
	printTable_3 $input;
}



END {
    disconnASM;
	disconnDB;
}


