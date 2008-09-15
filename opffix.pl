#!/usr/bin/perl
#
# opffix <filename>
#
# Standardize an OPF file
#
# Copyright 2008 Zed Pobre
# Licensed to the public under the terms of the GNU GPL, version 2.
#
# Version history:
# 0.1 - Prerelease - not ready for use
#

use warnings;
use strict;

use FindBin;
use lib $FindBin::RealBin;

use File::Basename 'fileparse';
use OEB::Tools qw(get_container_rootfile system_tidy_xml);

my $opffile = $ARGV[0];
my $oeb;
my $retval;
my ($filebase,$filedir,$fileext);
my $tidyfile;


# If no OPF file was specified, attempt to find one
if(! $opffile)
{
    if(-f 'META-INF/container.xml')
    {
	$opffile = get_container_rootfile();
	if(! -f $opffile) { undef $opffile; }
    }
}
if(! $opffile)
{
    # search for a single OPF file in the current directory.
    die("Could not find an OPF file.\n"); 
}

$oeb = OEB::Tools->new( opffile => $opffile );
$oeb->init;
$oeb->fixoeb12;
$oeb->fixmisc;
$oeb->save;

($filebase,$filedir,$fileext) = fileparse($opffile,'\.\w+$');
$tidyfile = $filebase . "-tidy" . $fileext;
$retval = system_tidy_xml($opffile,$tidyfile);
exit($retval);

##########

__DATA__
