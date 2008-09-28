#!/usr/bin/perl
#
# tidyxhtml <filename>
#
# A simple helper script to run tidy on an HTML file destined to be
# UTF-8 XHTML
#

use warnings;
use strict;

use Cwd 'realpath';
use File::Basename qw(dirname fileparse);

use lib dirname(realpath($0));
use EBook::Tools qw(system_tidy_xml system_tidy_xhtml);
#$EBook::Tools::datapath = $FindBin::RealBin . "/OEB";
#$EBook::Tools::tidysafety = 1;
# Possible $tidysafety values:
# <1: no checks performed, no error files kept, works like a clean tidy -m
#     This setting is DANGEROUS
#  1: Overwrites original file if there were no errors, but even if
#     there were warnings.  Keeps a log of errors, but not warnings.
#  2: Overwrites original file if there were no errors, but even if
#     there were warnings.  Keeps a log of both errors and warnings.
#  3: Overwrites original file only if there were no errors or
#     warnings.  Keeps a log of both errors and warnings.
# 4+: Never overwrites original file.  Keeps a log of both errors and
#     warnings.
# Default is 1


if(scalar(@ARGV) == 0) { die("You must specify an XML file to parse.\n"); }

my $inputfile = $ARGV[0];
my ($filebase,$filedir,$fileext) = fileparse($inputfile,'\.\w+$');
my $tidyfile = $filebase . "-tidy" . $fileext;
my $retval;

$retval = system_tidy_xhtml($inputfile,$tidyfile);

exit($retval);
