#!/usr/bin/perl
use warnings; use strict;

use Carp;
use EBook::Tools;
use Getopt::Long;
use List::MoreUtils;


#####################################
########## OPTION HANDLING ##########
#####################################

my %opt = (
    'dir'     => '',
    'help'    => 0,
    'mobi'    => 0,
    'oeb12'   => 0,
    'opf20'   => 0,
    'tidy'    => '',
    'verbose' => 0,
    );

GetOptions(
    \%opt,
    "dir|d=s",
    "help|h|?",
    "mobi|m",
    "oeb12|oeb",
    "opf20|opf",
    "tidy",
    'verbose|v+',
    );

if($opt{oeb12} && $opt{opf20})
{
    print "Options --oeb12 and --opf20 are mutually exclusive.\n";
    exit(1);
}

# Default to OEB12 if neither format is specified
if(!$opt{oeb12} && !$opt{opf20}) { $opt{oeb12} = 1; }


my %dispatch = (
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

sub fix
{
    my ($opffile) = @_;
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
        die("No OPF file specified, and there are multiple files to choose from!")
            if(scalar(@candidates) > 1);
        die("No OPF file specified, and I couldn't find one nearby!\n")
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
}


sub metasplit
{
    print "STUB!\n";
    exit(255);
}

sub genepub
{
    print "STUB!\n";
    exit(255);
}

sub tidyxhtml
{
    print "STUB!\n";
    exit(255);
}

sub tidyxml
{
    print "STUB!\n";
    exit(255);
}
