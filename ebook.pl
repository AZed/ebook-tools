#!/usr/bin/perl
use warnings; use strict;

=head1 NAME

ebook - create and manipulate e-books from the command line

=head1 SYNOPSIS

 ebook COMMAND arg1 arg2 --opt1 --opt2

See also L</EXAMPLES>.

=cut


use File::Basename 'fileparse';
use EBook::Tools qw(split_metadata system_tidy_xhtml system_tidy_xml);
use Getopt::Long;


#####################################
########## OPTION HANDLING ##########
#####################################

my %opt = (
    'author'     => '',
    'dir'        => '',
    'help'       => 0,
    'mobi'       => 0,
    'oeb12'      => 0,
    'opf20'      => 0,
    'opffile'    => '',
    'tidycmd'    => '',
    'tidysafety' => 1,
    'title'      => '',
    'verbose'    => 0,
    );

GetOptions(
    \%opt,
    'author=s',
    'dir|d=s',
    'help|h|?',
    'mobi|m',
    'oeb12',
    'opf20',
    'opffile|opf=s',
    'tidycmd',
    'tidysafety|ts=i',
    'title=s',
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
    'setmeta'   => \&setmeta,
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

=head1 COMMANDS

=head2 C<adddoc>

Add a document to both the book manifest and spine

=cut

sub addoc
{
    print "STUB!\n";
    exit(255);
}


=head2 C<additem>

Add an item to the book manifest, but not the spine

=cut

sub additem
{
    print "STUB!\n";
    exit(255);
}

=head2 C<blank>

Create a blank e-book structure.

=head3 Options

=over

=item C<--opffile> <filename.opf>

The filename of the OPF file to use to store the metadata structure.
Specifying this is mandatory, though it can also be specified as the
first non-option argument.  If both C<--opffile> and the argument are
passed, the argument value is used.

=item C<--author> "Author Name"

The author of the book.  If not specified, defaults to "Unknown
Author".

=item C<--title> "Title Name"

The title of the book.  If not specified, defaults to "Unknown Title".

=back

=head3 Example

 ebook blank newfile.opf --author "Me Myself" --title "New File"
 ebook blank --opffile newfile.opf --author "Me Myself" --title "New File"

Both of those links have the same effect.

=cut

sub blank
{
    my ($opffile) = @_;
    my $ebook;
    my %args;

    $opffile = $opt{opffile} if(!$opffile);
    
    if(!$opffile)
    {
        print "You must specify an OPF filename to start with.\n";
        exit(10);
    }
    $args{opffile} = $opffile;
    $args{author} = $opt{author} if($opt{author});
    $args{title} = $opt{title} if($opt{title});

    $ebook = EBook::Tools->new();
    $ebook->init_blank(%args);
    $ebook->save;
    exit(0);
}


=head2 C<fix>

Find and fix problems with an e-book, including enforcing a standard
specification and ensuring that all linked objects are present in the
manifest.

=cut

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


=head2 C<metasplit>

Split the <metadata>...</metadata> block out of pseudo-HTML files that
contain them.

=cut

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


=head2 C<genepub>

Generate a .epub book from existing OPF data.

=cut

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


=head2 C<setmeta>

Set metadata values on existing OPF data.

=cut

sub setmeta
{
    print "STUB!\n";
    exit(255);
}

=head2 C<tidyxhtml>

Run tidy on a HTML file to enforce valid XHTML output (required by the
OPF 2.0 specification).

=cut

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


=head2 tidyxml

Run tidy an a XML file (for neatness).

=cut

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

########## END CODE ##########

=head1 EXAMPLES

 ebook metasplit book.html mybook.opf
 ebook tidyxhtml book.html
 ebook tidyxml mybook.opf
 ebook fix mybook.opf --oeb12 --mobi
 ebook genepub 

 ebook blank newbook.opf --title "My Title" --author "My Name"
 ebook adddoc myfile.html
 ebook fix newbook.opf --opf20 -v
 ebook genepub


=head1 BUGS/TODO

=over

=item * adddoc and additem commands not yet implemented

=item * blank command doesn't use options yet

=item * documentation is very minimal

=item * output will overwrite files without warning or backup

=back

=head1 COPYRIGHT

Copyright 2008 Zed Pobre

=head1 LICENSE

Licensed to the public under the terms of the GNU GPL, version 2.

=cut


########## DATA ##########

__DATA__
