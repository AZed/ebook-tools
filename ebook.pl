#!/usr/bin/perl
use warnings; use strict;

=head1 NAME

ebook - create and manipulate e-books from the command line

=head1 SYNOPSIS

 ebook COMMAND arg1 arg2 --opt1 --opt2

See also L</EXAMPLES>.

=cut


use EBook::Tools qw(split_metadata split_pre 
                    system_tidy_xhtml system_tidy_xml);
use EBook::Tools::Unpack qw(unpack_ebook);
use File::Basename 'fileparse';
use File::Path;    # Exports 'mkpath' and 'rmtree'
use Getopt::Long qw(:config bundling);


#####################################
########## OPTION HANDLING ##########
#####################################

my %opt = (
    'author'     => '',
    'dir'        => '',
    'filename'   => '',
    'help'       => 0,
    'id'         => '',
    'mimetype'   => '',
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
    'filename|file|f=s',
    'help|h|?',
    'id=s',
    'mimetype|mtype=s',
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
    'genepub'   => \&genepub,
    'setmeta'   => \&setmeta,
    'splitmeta' => \&splitmeta,
    'splitpre'  => \&splitpre,
    'tidyxhtml' => \&tidyxhtml,
    'tidyxml'   => \&tidyxml,
    'unpack'    => \&unpack,
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

Adds a documents to both the book manifest and spine.

=head3 Options

=over

=item C<--opffile>

=item C<--opf>

The OPF file to modify.  If not specified one will be searched for in
the current directory.

=item C<--id>

The ID attribute to use for the added manifest item.  This is
required, and ebook will abort if it is not specified.

=item C<--mimetype>

=item C<--mtype>

The mime type string to use for the added manifest item.  If not
specified, it will be autodetected via File::Mimeinfo::Magic.  This
may not result in an optimal string.

=back

=head3 Example

 ebook adddoc --opf mybook.opf --id 'text-ch1' chapter1.html

=cut

sub adddoc
{
    my ($newdoc) = @_;
    my $opffile = $opt{opffile};
    my $id = $opt{id};
    my $mtype = $opt{mimetype};

    if(!$id)
    {
        print {*STDERR} "You must specify an ID when adding a document!\n";
        exit(21);
    }

    my $ebook = EBook::Tools->new();
    $ebook->init($opffile);
    $ebook->add_document($newdoc,$id,$mtype);
    if($ebook->errors)
    {
        print {*STDERR} "Unrecoverable errors found.  Aborting.\n";
        $ebook->print_errors;
    }
    $ebook->save;
    $ebook->print_warnings;
    exit(0);
}


=head2 C<additem>

Add an item to the book manifest, but not the spine.

Note that the L</fix> command will automatically insert manifest items
for any local files referenced by existing manifest items.

=head3 Options

=over

=item C<--opffile>

=item C<--opf>

The OPF file to modify.  If not specified one will be searched for in
the current directory.

=item C<--id>

The ID attribute to use for the added manifest item.  This is
required, and ebook will abort if it is not specified.

=item C<--mimetype>

=item C<--mtype>

The mime type string to use for the added manifest item.  If not
specified, it will be autodetected via File::Mimeinfo::Magic.  This
may not result in an optimal string.

=back

=head3 Example

 ebook additem --opf mybook.opf --id 'illus-ch1' chapter1-illus.jpg

=cut

sub additem
{
    my ($newitem) = @_;
    my $opffile = $opt{opffile};
    my $id = $opt{id};
    my $mtype = $opt{mimetype};

    if(!$id)
    {
        print {*STDERR} "You must specify an ID when adding a document!\n";
        exit(21);
    }

    my $ebook = EBook::Tools->new();
    $ebook->init($opffile);
    $ebook->add_item($newitem,$id,$mtype);
    if($ebook->errors)
    {
        print {*STDERR} "Unrecoverable errors found.  Aborting.\n";
        $ebook->print_errors;
    }
    $ebook->save;
    $ebook->print_warnings;
    exit(0);
    
    print "STUB!\n";
    exit(255);
}


=head2 C<blank>

Create a blank e-book structure.

=head3 Options

=over

=item C<--opffile filename.opf>

=item C<--opf filename.opf>

Use the specified OPF file.  This can also be specified as the first
non-option argument, which will override this option if it exists.  If
no file is specified, the program will abort with an error.
=item C<--author> "Author Name"

The author of the book.  If not specified, defaults to "Unknown
Author".

=item C<--title> "Title Name"

The title of the book.  If not specified, defaults to "Unknown Title".

=item C<--dir directory>

=item C<-d directory>

Output the OPF file in this directory, creating it if necessary.

=back

=head3 Example

 ebook blank newfile.opf --author "Me Myself" --title "New File"
 ebook blank --opffile newfile.opf --author "Me Myself" --title "New File"

Both of those commands have the same effect.

=cut

sub blank
{
    my ($opffile) = @_;
    my %args;
    my $ebook;

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
    useoptdir();
    $ebook->save;
    exit(0);
}


=head2 C<fix>

Find and fix problems with an e-book, including enforcing a standard
specification and ensuring that all linked objects are present in the
manifest.

=head3 Options

=over

=item C<--opffile filename.opf>

=item C<--opf filename.opf>

Use the specified OPF file.  This can also be specified as the first
non-option argument, which will override this option if it exists.  If
no file is specified, one will be searched for.

=item C<--oeb12>

Force the OPF to conform to the OEB 1.2 standard.  This is the default.

=item C<--opf20>

Force the OPF to conform to the OPF 2.0 standard.  If both this and
C<--oeb12> are specified, the program will abort with an error.

=item C<--mobi>

Correct Mobipocket-specific elements, creating an output element to
force UTF-8 output if one does not yet exist.

=item C<--dir directory>

=item C<-d directory>

Save the fixed output into the specified directory.  The default is to
write all output in the current working directory.  Note that this
only affects the output, and not where the OPF file is found.

=back

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
    $ebook->init($opffile);
    $ebook->fix_oeb12 if($opt{oeb12});
    $ebook->fix_opf20 if($opt{opf20});
    $ebook->fix_misc;
    $ebook->fix_mobi if($opt{mobi});
    useoptdir();
    $ebook->save;
    
    if($ebook->errors)
    {
        $ebook->print_errors;
        print "Unrecoverable errors while fixing '",$opffile,"'!\n";
        exit(11);
    }
    
    $ebook->print_warnings if($ebook->warnings);
    exit(0);
}


=head2 C<genepub>

Generate a .epub book from existing OPF data.

=head3 Options

=over

=item C<--opffile filename.opf>

=item C<--opf filename.opf>

Use the specified OPF file.  This can also be specified as the first
non-option argument, which will override this option if it exists.  If
no file is specified, one will be searched for.

=item C<--filename bookname.epub>

=item C<--file bookname.epub>

=item C<-f bookname.epub>

Use the specified name for the final output file.  If not specified,
the bok will have the same filename as the OPF file, with the
extension changed to C<.epub>.

=item C<--dir directory>

=item C<-d directory>

Output the final .epub book into the specified directory.  The default
is to use the current working directory.

=back

=head3 Example

 ebook genepub mybook.opf -f my_special_book.epub -d ../epubbooks

or in the simplest case:

 ebook genepub

=cut

sub genepub
{
    my ($opffile) = @_;
    my $ebook;
    
    $opffile = $opt{opffile} if(!$opffile);

    if($opffile) { $ebook = EBook::Tools->new($opffile); }
    else {$ebook = EBook::Tools->new(); $ebook->init(); }

    if(! $ebook->gen_epub(filename => $opt{filename},
                          dir => $opt{dir}) )
    {
        print {*STDERR} "Failed to generate .epub file!\n";
        $ebook->print_errors;
        $ebook->print_warnings;
        exit(12);
    }
    $ebook->print_warnings if($ebook->warnings);
    exit(0);
}


=head2 C<setmeta>

Set metadata values on existing OPF data.

Not yet implemented.

=cut

sub setmeta
{
    print "STUB!\n";
    exit(255);
}


=head2 C<splitmeta>

Split the <metadata>...</metadata> block out of a pseudo-HTML file
that contains one.

=cut

sub splitmeta
{
    my ($infile,$opffile) = @_;
    if(!$infile) { die("You must specify a file to parse.\n"); }
    $opffile = $opt{opffile} if(!$opffile);

    my $ebook;

    $opffile = split_metadata($infile,$opffile);

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


=head2 C<splitpre>

Split <pre>...</pre> blocks out of an existing HTML file, wrapping
each one found into a separate HTML file.

=cut

sub splitpre
{
    my ($infile,$outfilebase) = @_;
    if(!$infile) { die("You must specify a file to parse.\n"); }
    split_pre($infile,$outfilebase);
    exit(0);
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


=head2 C<tidyxml>

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


=head2 C<unpack>

Unpacks an ebook into its component parts, creating an OPF for them if
necessary.

=head3 Arguments

=over

=item C<--filename>
=item C<--file>
=item C<-f>

The filename of the ebook to unpack.  This can also be specified as
the first non-option argument, in which case it will override the
option if it exists.

=item C<--dir>
=item C<-d>

The directory to unpack into, which will be created if it does not
exist, defaulting to the filename with the extension removed.  This
can also be specified as the second non-option argument, in which case
it will override the option if it exists.

=item C<--format>

The unpacking routines should autodetect the type of book under normal
conditions.  If autodetection fails, a format can be forced here.  See
L<EBook::Tools::Unpack> for a list of available formats.

=item C<--author>

Set the primary author of the unpacked e-book, overriding what is
detected.  Not all e-book formats contain author metadata, and if none
is found and this is not specified the primary author will be set to
'Unknown Author'.

=item C<--title>

Set the title of the unpacked e-book, overriding what is detected.  A
title will always be detected in some form from the e-book, but the
exact text can be overridden here.

=item C<--opffile>

=item C<--opf>

The filename of the OPF metadata file that will be generated.  If not
specified, defaults to the title with a .opf extension.

=back

=head3 Examples

 ebook unpack mybook.pdb My_Book --author "By Me"
 ebook unpack -f mybook.pdb -d My_Book --author "By Me"

Both of the above commands do the same thing

=cut

sub unpack
{
    my ($filename,$dir) = @_;
    $filename = $filename || $opt{filename};
    $dir = $dir || $opt{dir};

    unpack_ebook(
        'file' => $filename,
        'dir' => $dir,
        'format' => $opt{format},
        'author' => $opt{author},
        'title' => $opt{title},
        'opffile' => $opt{opffile},
        );

     exit(0);
}

########## PRIVATE PROCEDURES ##########

sub useoptdir ()
{
    if($opt{dir})
    {
        if(! -d $opt{dir})
        { 
            mkpath($opt{dir})
                or die("Unable to create working directory '",$opt{dir},"'!");
        }
        chdir($opt{dir})
            or die("Unable to chdir to working directory '",$opt{dir},"'!");
    }        
    return 1;
}

########## END CODE ##########

=head1 EXAMPLES

 ebook splitmeta book.html mybook.opf
 ebook tidyxhtml book.html
 ebook tidyxml mybook.opf
 ebook fix mybook.opf --oeb12 --mobi
 ebook genepub 

 ebook blank newbook.opf --title "My Title" --author "My Name"
 ebook adddoc myfile.html
 ebook fix newbook.opf --opf20 -v
 ebook genepub

 ebook unpack mybook.pdb my_book
 cd my_book
 ebook addoc new_document.html
 ebook fix
 ebook genepub

=head1 BUGS/TODO

=over

=item * setmeta command not yet implemented

=item * documentation is incomplete

=back

=head1 COPYRIGHT

Copyright 2008 Zed Pobre

=head1 LICENSE

Licensed to the public under the terms of the GNU GPL, version 2.

=cut


########## DATA ##########

__DATA__
