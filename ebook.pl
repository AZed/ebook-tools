#!/usr/bin/perl
use warnings; use strict;
use version; our $VERSION = qv("0.2.1");
# $Revision$ $Date$
# $Id$


=head1 NAME

ebook - create and manipulate e-books from the command line

=head1 SYNOPSIS

 ebook COMMAND arg1 arg2 --opt1 --opt2

See also L</EXAMPLES>.

=cut


use EBook::Tools qw(split_metadata split_pre strip_script
                    system_tidy_xhtml system_tidy_xml);
use EBook::Tools::Mobipocket qw(pid_is_valid);
use EBook::Tools::Unpack;
use File::Basename 'fileparse';
use File::Path;    # Exports 'mkpath' and 'rmtree'
use Getopt::Long qw(:config bundling);


#####################################
########## OPTION HANDLING ##########
#####################################

my %opt = (
    'author'      => '',
    'dir'         => '',
    'fileas'      => '',
    'filename'    => '',
    'help'        => 0,
    'htmlconvert' => 0,
    'id'          => '',
    'key'         => '',
    'mimetype'    => '',
    'mobi'        => 0,
    'nosave'      => 0,
    'noscript'    => 0,
    'oeb12'       => 0,
    'opf20'       => 0,
    'opffile'     => '',
    'raw'         => 0,
    'tidy'        => 0,
    'tidycmd'     => '',
    'tidysafety'  => 1,
    'title'       => '',
    'verbose'     => 0,
    );

GetOptions(
    \%opt,
    'author=s',
    'dir|d=s',
    'fileas=s',
    'filename|file|f=s',
    'help|h|?',
    'htmlconvert',
    'id=s',
    'key|pid=s',
    'mimetype|mtype=s',
    'mobi|m',
    'nosave',
    'noscript',
    'raw',
    'oeb12',
    'opf20',
    'opffile|opf=s',
    'tidy',
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
$EBook::Tools::tidycmd = $opt{tidycmd} if($opt{tidycmd});
$EBook::Tools::tidysafety = $opt{tidysafety};

my %dispatch = (
    'adddoc'      => \&adddoc,
    'additem'     => \&additem,
    'blank'       => \&blank,
    'fix'         => \&fix,
    'genepub'     => \&genepub,
    'setmeta'     => \&setmeta,
    'splitmeta'   => \&splitmeta,
    'splitpre'    => \&splitpre,
    'stripscript' => \&stripscript,
    'tidyxhtml'   => \&tidyxhtml,
    'tidyxml'     => \&tidyxml,
    'unpack'      => \&unpack,
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
    
    $args{opffile} = $opffile;
    $args{author} = $opt{author} if($opt{author});
    $args{title} = $opt{title} if($opt{title});

    $ebook = EBook::Tools->new();
    $ebook->init_blank(%args);
    unless($opt{nosave})
    {
        useoptdir();
        $ebook->save;
    }
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
    unless($opt{nosave})
    {
        useoptdir();
        $ebook->save;
    }
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

Set specific metadata values on existing OPF data, creating a new
element only if none exists.

Both the element to set and the value are specified as additional
arguments, not as options.

The elements that can be set are currently 'author', 'title',
'publisher', and 'rights'.

=head3 Options

=over

=item * C<--opffile>
=item * C<--opf>

Specifies the OPF file to modify.  If not specified, the script will
attempt to find one in the current directory.

=item * C<--fileas>

Specifies the 'file-as' attribute when setting an author.  Has no
effect on other elements.

=item * C<--id>

Specifies the ID to assign to the element



=back

=head3 Examples

 ebook setmeta title 'My Great Title'
 ebook --opf newfile.opf setmeta author 'John Smith' --fileas 'Smith, John' --id mainauthor 

=cut

sub setmeta
{
    my ($element,$value) = @_;
    my %valid_elements = (
        'title' => 1,
        'author' => 1,
        'publisher' => 1,
        'rights' => 1,
        );

    unless($element)
    {
        print "You must specify which element to set.\n";
        print "Example: ebook setmeta title 'My Great Title'\n";
        exit(21);
    }
    unless($value)
    {
        print "You muts specify the value to set.\n";
        print "Example: ebook setmeta title 'My Great Title'\n";
    }

    my $opffile = $opt{opffile};
    my $fileas = $opt{fileas};
    my $id = $opt{id};

    my $ebook = EBook::Tools->new();
    $ebook->init($opffile);

    if($element eq 'author')
    {
        $ebook->set_primary_author('text' => $value,
                                   'fileas' => $fileas,
                                   'id' => $id );
    }
    elsif($element eq 'publisher')
    {
        $ebook->set_publisher('text' => $value,
                              'id' => $id ); 
    }
    elsif($element eq 'rights')
    {
        $ebook->set_rights('text' => $value,
                           'id' => $id ); 
    }
    elsif($element eq 'title')
    {
        $ebook->set_title('text' => $value,
                          'id' => $id);
    }
    $ebook->save;
    $ebook->print_errors;
    $ebook->print_warnings;
    exit(0);
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

The first non-option argument is taken to be the input file.  The
second non-option argument is taken to be the basename of the output
files.

=cut

sub splitpre
{
    my ($infile,$outfilebase) = @_;
    if(!$infile) { die("You must specify a file to parse.\n"); }
    split_pre($infile,$outfilebase);
    exit(0);
}


=head2 C<stripscript>

Strips <script>...</script> blocks out of a HTML file.

The first non-option argument is taken to be the input file.  The
second non-option argument is taken to be the output file.  If the
latter is not specified, the input file will be overwritten.

=head3 Options

=over

=item * C<--noscript>

Strips <noscript>...</noscript> blocks as well.

=back

=cut

sub stripscript
{
    my ($infile,$outfile) = @_;

    if(!$infile)
    {
        print "You must specify an input file.\n";
        exit(10);
    }
    my %args;
    $args{infile} = $infile;
    $args{outfile} = $outfile;
    $args{noscript} = $opt{noscript};

    strip_script(%args);
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

=item C<--htmlconvert>

Attempt to convert the extracted text to HTML.  This is obviously only
of value if the format doesn't use HTML normally.

=item C<--raw>

This causes a lot of raw, unparsed, unmodified data to be dumped into
the directory along with everything else.  It's useful for debugging
exactly what was in the file being unpacked, but not for much else.

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

=item C<--tidy>

Run tidy on any HTML output files to convert them to valid XHTML.  Be
warned that this can occasionally change the formatting, as Tidy isn't
very forgiving on certain common tricks (such as empty <pre> elements
with style elements) that abuse the standard.

=back

=item C<--tidycmd>

The tidy executable name.  This has to be a fully qualified pathname
if tidy isn't on the path.  Defaults to 'tidy'.

=item C<--tidysafety>

The safety level to use when running tidy (default is 1).  Potential
values are:

=over

=item C<$tidysafety < 1>:

No checks performed, no error files kept, works like a clean tidy -m

This setting is DANGEROUS!

=item C<$tidysafety == 1>:

Overwrites original file if there were no errors, but even if there
were warnings.  Keeps a log of errors, but not warnings.

=item C<$tidysafety == 2>:

Overwrites original file if there were no errors, but even if there
were warnings.  Keeps a log of both errors and warnings.

=item C<$tidysafety == 3>:

Overwrites original file only if there were no errors or warnings.
Keeps a log of both errors and warnings.

=item C<$tidysafety >= 4>:

Never overwrites original file.  Keeps a log of both errors and
warnings.

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
    
    unless($filename)
    {
        print {*STDERR} "You must specify a file to unpack!\n";
        exit(20);
    }

    unless(-f $filename)
    {
        print {*STDERR} "Could not find '",$filename,"' to unpack!\n";
        exit(21);
    }

    if( $opt{key} && ! pid_is_valid($opt{key}) )
    {
        print {*STDERR} "Invalid PID '",$opt{key},"'\n";
        exit(22);
    }

    my $unpacker = EBook::Tools::Unpack->new(
        'file' => $filename,
        'dir' => $dir,
        'format' => $opt{format},
        'htmlconvert' => $opt{htmlconvert},
        'raw' => $opt{raw},
        'author' => $opt{author},
        'title' => $opt{title},
        'opffile' => $opt{opffile},
        'tidy' => $opt{tidy},
        'nosave' => $opt{nosave},
        );

    $unpacker->unpack;

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

=item * Need to implement a one-pass conversion from one format to
another.  This will wait until more formats are supported by the
underlying modules, however.

=item * documentation is incomplete

=back

=head1 COPYRIGHT

Copyright 2008 Zed Pobre

=head1 LICENSE

Licensed to the public under the terms of the GNU GPL, version 2.

=cut


########## DATA ##########

__DATA__
