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

use Cwd 'realpath';
use File::Basename qw(dirname fileparse);

use lib dirname(realpath($0));
use EBook::Tools qw(get_container_rootfile system_tidy_xml);

my $opffile = $ARGV[0];
my $ebook;
my $retval;
my ($filebase,$filedir,$fileext);
my $tidyfile;
my $warncount;


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
    my @candidates = glob("*.opf");
    die("No OPF file specified, and there are multiple files to choose from")
	if(scalar(@candidates) > 1);
    die("No OPF file specified, and I couldn't find one nearby")
	if(scalar(@candidates) < 1);
    $opffile = $candidates[0];
}

die("The specified file '",$opffile,"' does not exist or is not a regular file!\n")
    if(! -f $opffile);

($filebase,$filedir,$fileext) = fileparse($opffile,'\.\w+$');
$tidyfile = $filebase . "-tidy" . $fileext;

# An initial cleanup is required to deal with any entities
$retval = system_tidy_xml($opffile,$tidyfile);
die ("Errors found while cleaning up '",$opffile,"' for parsing",
     " -- look in '",$tidyfile,"' for details") if($retval > 1);

$ebook = EBook::Tools->new($opffile);
$ebook->fix_oeb12;
$ebook->fix_manifest;
$ebook->fix_spine;
$ebook->fix_misc;
$ebook->save;

if($ebook->errors)
{
    $ebook->print_errors;
    die("Unrecoverable errors while fixing '",$opffile,"'!");
}

$ebook->print_warnings;
$warncount = scalar(@{$ebook->warnings});

$retval = system_tidy_xml($opffile,$tidyfile);
die ("Errors found during final cleanup of '",$opffile,"'",
     " -- look in '",$tidyfile,"' for details") if($retval > 1);

exit($warncount);

##########

__DATA__
