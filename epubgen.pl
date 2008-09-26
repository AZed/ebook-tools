#!/usr/bin/perl
#
# epubgen <filename>
#
# Take an OPF file and use the information in it to create an epub file.
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
use Cwd 'realpath';
use File::Basename qw(dirname fileparse);

use lib dirname(realpath($0));
use OEB::Tools qw(get_container_rootfile);

my $metastring = '';
my $metafile;
my $opffile = $ARGV[0];
my $oebpackage;
my $elem;
my $oeb;

my ($filebase,$filedir,$fileext);

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


#($filebase,$filedir,$fileext) = fileparse($metafile,'\.\w+$');

$oeb = OEB::Tools->new($opffile);
$oeb->init;
$oeb->fixopf20;
$oeb->fixmisc;
$oeb->save;

my @manifest = $oeb->manifest_hrefs;

$oeb->gen_epub();


##########

__DATA__
