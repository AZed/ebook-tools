#!/usr/bin/perl

use EBook::Tools::LZSS;

my $infile = shift;
my $outfile = shift;
my $fh_in;
my $fh_out;

my $lzss = EBook::Tools::LZSS->new(verbose => 2,
                                   windowstart => 0,
                                   screwybits => 1);
my $compressed;
my $textref;

open($fh_in,'<:raw',$infile);
sysread($fh_in,$compressed,-s $infile);
close($fh_in);

$textref = $lzss->uncompress(\$compressed);

open($fh_out,">:raw",$outfile);
print {*$fh_out} $$textref;
close($fh_out);
