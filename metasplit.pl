#!/usr/bin/perl
#
# mobimeta <filename>
#
# Split the psuedo-HTML result of mobi2html into a metadata file and
# a proper HTML file.
#
# Requires that tidy be installed (needed to deal with elements
# outside the XML default).  No warning is given if the specified tidy
# config file isn't found.  If tidy isn't in the path, the full path
# will have to be specified in $tidycmd.
#
# The Mobi HTML file is currently slurped, which may consume huge
# amounts of memory with large files.  Be warned.
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
use EBook::Tools qw(split_metadata print_memory);

if(scalar(@ARGV) == 0) { die("You must specify a file to parse.\n"); }

my $metafile;
my $opffile;
my $ebook;

my ($filebase,$filedir,$fileext);
$metafile = split_metadata($ARGV[0]);

($filebase,$filedir,$fileext) = fileparse($metafile,'\.\w+$');
$opffile = $filebase . ".opf";
rename($metafile,$opffile);

$ebook = EBook::Tools->new($opffile);
$ebook->fix_oeb12;
$ebook->fix_misc;

# The split metadata never includes manifest/spine info, so add in the
# HTML file now
$ebook->add_document('item-text',$ARGV[0]);
$ebook->save;

##########

__DATA__
