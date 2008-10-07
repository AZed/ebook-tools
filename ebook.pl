#!/usr/bin/perl
use warnings; use strict;

use File::Basename 'fileparse';
use EBook::Tools qw(split_metadata system_tidy_xhtml system_tidy_xml);
use Getopt::Long;


#####################################
########## OPTION HANDLING ##########
#####################################

my %opt = (
    'dir'        => '',
    'help'       => 0,
    'mobi'       => 0,
    'oeb12'      => 0,
    'opf20'      => 0,
    'opffile'    => '',
    'tidycmd'    => '',
    'tidysafety' => 1,
    'verbose'    => 0,
    );

GetOptions(
    \%opt,
    "dir|d=s",
    "help|h|?",
    "mobi|m",
    "oeb12",
    "opf20",
    "opffile|opf=s",
    "tidycmd",
    'tidysafety|ts=i',
    'verbose|v+',
    );

if($opt{oeb12} && $opt{opf20})
{
    print "Options --oeb12 and --opf20 are mutually exclusive.\n";
    exit(1);
}

# Default to OEB12 if neither format is specified
if(!$opt{oeb12} && !$opt{opf20}) { $opt{oeb12} = 1; }

$EBook::Tools::debug = $opt{verbose};
$EBook::Tools::tidysafety = $opt{tidysafety};

my %dispatch = (
    'adddoc'    => \&adddoc,
    'additem'   => \&additem,
    'blank'     => \&blank,
    'fix'       => \&fix,
    'metasplit' => \&metasplit,
    'genepub'   => \&genepub,
    'tidyxhtml' => \&tidyxhtml,
    'tidyxml'   => \&tidyxml,
    );

my $cmd = shift;

if(!$cmd)
{
    print "No command specified.\n";
    print "Valid commands are: ",join(" ",sort keys %dispatch),"\n";
    exit(1);
}    
if(!$dispatch{$cmd})
{
    print "Invalid command '",$cmd,"'\n";
    print "Valid commands are: ",join(" ",sort keys %dispatch),"\n";
    exit(1);
}

$dispatch{$cmd}(@ARGV);


#########################################
########## COMMAND SUBROUTINES ##########
#########################################

sub blank
{
    my ($opffile) = @_;
    my $ebook;

    $opffile = $opt{opffile} if(!$opffile);
    if(!$opffile)
    {
        print "You must specify an OPF filename to start with.\n";
        exit(10);
    }

    $ebook = EBook::Tools->new();
    $ebook->init_blank($opffile);
    $ebook->save;
    exit(0);
}

sub fix
{
    my ($opffile) = @_;
    my $ebook;
    my $retval;
    my ($filebase,$filedir,$fileext);
    my $tidyfile;
    my $warncount;

    $opffile = $opt{opffile} if(!$opffile);
    $ebook = EBook::Tools->new();
    if($opffile) { $ebook->init($opffile); }
    else { $ebook->init(); }
    $ebook->fix_oeb12 if($opt{oeb12});
    $ebook->fix_opf20 if($opt{opf20});
    $ebook->fix_misc;
    $ebook->fix_mobi if($opt{mobi});
    $ebook->save;
    
    if($ebook->errors)
    {
        $ebook->print_errors;
        print "Unrecoverable errors while fixing '",$opffile,"'!\n";
        exit(scalar(11));
    }
    
    $ebook->print_warnings if($ebook->warnings);
    exit(0);
}


sub metasplit
{
    my ($infile,$opffile) = @_;
    if(!$infile) { die("You must specify a file to parse.\n"); }

    my ($filebase,$filedir,$fileext) = fileparse($infile,'\.\w+$');
    
    $opffile = $opt{opffile} if(!$opffile);
    $opffile = $filebase . ".opf" if(!$opffile);

    my $ebook;

    split_metadata($infile,$opffile);

    if(!$opffile)
    {
        print {*STDERR} "No metadata block was found in '",$infile,"'\n";
        exit(20);
    }

    $ebook = EBook::Tools->new($opffile);
    $ebook->fix_oeb12 if($opt{oeb12});
    $ebook->fix_opf20 if($opt{opf20});
    $ebook->fix_mobi if($opt{mobi});
    
    # The split metadata never includes manifest/spine info, so add in the
    # HTML file now
    $ebook->add_document($infile,'item-maintext');
    $ebook->fix_misc;
    $ebook->save;

    if($ebook->errors)
    {
        $ebook->print_errors;
        $ebook->print_warnings if($ebook->warnings);
        exit(21);
    }
    $ebook->print_warnings if($ebook->warnings);
    exit(0);
}


sub genepub
{
    my ($opffile) = @_;
    my $metastring = '';
    my $metafile;
    my $ebookpackage;
    my $elem;
    my $ebook;
    
    my ($filebase,$filedir,$fileext);
    
    if($opffile) { $ebook = EBook::Tools->new($opffile); }
    else {$ebook = EBook::Tools->new(); $ebook->init(); }
    $ebook->fixoeb12 if($opt{oeb12});
    $ebook->fixopf20 if($opt{opf20});
    $ebook->fixmisc;
    $ebook->save;

    my @manifest = $ebook->manifest_hrefs;

    $ebook->gen_epub();

    exit(0);
}

sub tidyxhtml
{
    my ($inputfile,$tidyfile) = @_;
    my $retval;

    if(!$inputfile)
    {
        print "You must specify an input file to tidy.\n";
        exit(10);
    }

    if($tidyfile) { $retval = system_tidy_xhtml($inputfile,$tidyfile); }
    else { $retval = system_tidy_xhtml($inputfile); }
    exit($retval);
}


sub tidyxml
{
    my ($inputfile,$tidyfile) = @_;
    my $retval;

    if(!$inputfile)
    {
        print "You must specify an input file to tidy.\n";
        exit(10);
    }

    if($tidyfile) { $retval = system_tidy_xml($inputfile,$tidyfile); }
    else { $retval = system_tidy_xml($inputfile); }
    exit($retval);
}

##########

__DATA__
