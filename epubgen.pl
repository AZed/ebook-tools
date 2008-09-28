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
use EBook::Tools qw(get_container_rootfile);

my $metastring = '';
my $metafile;
my $opffile = $ARGV[0];
my $ebookpackage;
my $elem;
my $ebook;

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

$ebook = EBook::Tools->new($opffile);
$ebook->init;
$ebook->fixopf20;
$ebook->fixmisc;
$ebook->save;

my @manifest = $ebook->manifest_hrefs;

$ebook->gen_epub();


##########

__DATA__
