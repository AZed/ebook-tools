#!/usr/bin/perl
#
# tidyxml <filename>
#
# A simple helper script to run tidy on a single utf8 XML file
#

#

use warnings;
use strict;

use File::Basename;

my $datapath;
OS:
{
    $_ = $^O;
    /MSWin32/	&& do { $datapath = 'W:\books\software\OEB'; last OS; };
    /dos/	&& do { $datapath = 'W:\books\software\OEB'; last OS; };
    $datapath = '/www/books/software/OEB';
}

my $tidyconfig = "$datapath/tidy-oeb.conf";
my $tidyerrors = 'tidyxml-errors.txt';

if(scalar(@ARGV) == 0) { die("You must specify an XML file to parse.\n"); }

my $inputfile = $ARGV[0];
my $tidyfile;
my $retval;
my $filebase;
my $filedir;
my $fileext;

($filebase,$filedir,$fileext) = fileparse($inputfile,'\.\w+$');
$tidyfile = $filebase . "-tidy" . $fileext;

$retval = system('tidy',
		 '-config',$tidyconfig,
		 '-q','-xml','-utf8',
		 '-f',$tidyerrors,
		 '-o',$tidyfile,
		 $inputfile);


# Possible return codes from tidy:
# 0 - no errors (move the out over the original, delete errorfile)
# 1 - warnings only (move the out over the original, leave errorfile)
# 2 - errors (delete outfile, leave errorfile)

# Some systems may return a two-byte code, so deal with that first
if($retval >= 256) { $retval = $retval >> 8 };
if($retval == 0)
{
    rename($tidyfile,$inputfile);
    unlink($tidyerrors);
}
elsif($retval == 1)
{
    rename($tidyfile,$inputfile);
}
elsif($retval == 2)
{
    unlink($tidyfile);
}
else
{
    # Something unexpected happened (program crash, sigint, other)
    die("Tidy did something unexpected.  Check all output.");
}
