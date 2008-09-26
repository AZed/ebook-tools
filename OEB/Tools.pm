package OEB::Tools;
use version; our $VERSION = qv("0.1.0");

our $debug = 0;
use warnings;
use strict;

=head1 NAME

EBook::Tools -- A collection of tools to manipulate documents in Open
E-book formats.

=head1 DESCRIPTION

This module provides an object interface and a number of related
procedures intended to create or modify documents centered around the
International Digital Publishing Forum (IDPF) standards, currently
both OEBPS v1.2 and OPS/OPF v2.0.

=cut

require Exporter;
use base qw(Class::Accessor Exporter);


=head1 DEPENDENCIES

=head2 Perl Modules

=over

=item Archive::Zip

=item Date::Manip

Note that Date::Manip will die on MS Windows system unless the
TZ environment variable is set in a specific manner. See: 

http://search.cpan.org/perldoc?Date::Manip#TIME_ZONES

=item File::Basename

=item File::MimeInfo::Magic

=item XML::Twig::XPath

=back

=head2 Other Programs

=over

=item Tidy

=back

=cut

# OSSP::UUID will provide Data::UUID on systems such as Debian that do
# not distribute the original Data::UUID.
use Data::UUID;

use Archive::Zip qw( :CONSTANTS :ERROR_CODES );
use Cwd 'realpath';
use Date::Manip;
use File::Basename qw(dirname fileparse);
# File::MimeInfo::Magic gets *.css right, but detects all html as
# text/html, even if it has an XML header.
use File::MimeInfo::Magic;
# File::MMagic gets text/xml right (though it still doesn't properly
# detect XHTML), but detects CSS as x-system, and has a number of
# other weird bugs.
#use File::MMagic;
#use HTML::Tidy;
use XML::Twig::XPath;

our @EXPORT_OK;
@EXPORT_OK = qw (
    &create_epub_container
    &create_epub_mimetype
    &fix_date
    &get_container_rootfile
    &print_memory
    &split_metadata
    &system_tidy_xml
    &system_tidy_xhtml
    );

my @rwfields = qw(
    opffile
    spec
    twigroot
    );
my @rofields = qw(
    twig
    error
    );
my @privatefields = ();
    
# A simple 'use fields' will not work here: use takes place inside
# BEGIN {}, so the @...fields variables won't exist.
require fields;
fields->import(@rwfields,@rofields,@privatefields);
OEB::Tools->mk_accessors(@rwfields);
OEB::Tools->mk_ro_accessors(@rofields);

my $book = OEB::Tools->new();

print $book->{'opffile'};

=head1 CONFIGURABLE GLOBAL VARIABLES

=over

=item $datapath

The location where various external files (such as tidy configuration
files) can be found.

Defaults to the subdirectory 'data' in whatever directory the calling
script is actually in.  (See BUGS/TODO)

=item $tidycmd

The tidy executable name.  This has to be a fully qualified pathname
if tidy isn't on the path.  Defaults to 'tidy'.

=item $tidyconfig

The name of the tidy configuration file.  It will be looked for as
"$datapath/$tidyconfig".  Defaults to 'tidy-oeb.conf', but nothing bad
will happen if it can't be found.

=item $tidyxhtmlerrors

The name of the error output file from system_tidy_xhtml().  Defaults
to 'tidyxhtml-errors.txt'

=item $tidyxmlerrors

The name of the error output file from system_tidy_xml().  Defaults to
'tidyxml-errors.txt'

=item $tidysafety

The safety level to use when running tidy.  Potential values are:

=over

=item <1:

No checks performed, no error files kept, works like a clean tidy -m

This setting is DANGEROUS!

=item 1:

Overwrites original file if there were no errors, but even if there
were warnings.  Keeps a log of errors, but not warnings.

=item 2:

Overwrites original file if there were no errors, but even if there
were warnings.  Keeps a log of both errors and warnings.

=item 3:

Overwrites original file only if there were no errors or warnings.
Keeps a log of both errors and warnings.

=item 4+:

Never overwrites original file.  Keeps a log of both errors and
warnings.

=back

=back

=cut

our $datapath = dirname(realpath($0)) . "/data";

our $mobi2htmlcmd = 'mobi2html';
our $tidycmd = 'tidy'; # Specify full pathname if not on path
our $tidyconfig = 'tidy-oeb.conf';
our $tidyxhtmlerrors = 'tidyxhtml-errors.txt';
our $tidyxmlerrors = 'tidyxml-errors.txt';
our $tidysafety = 1;


my $utf8xmldec = '<?xml version="1.0" encoding="UTF-8" ?>' . "\n";
my $oeb12doctype = 
    '<!DOCTYPE package' . "\n" .
    '  PUBLIC "+//ISBN 0-9673008-1-9//DTD OEB 1.2 Package//EN"' . "\n" .
    '  "http://openebook.org/dtds/oeb-1.2/oebpkg12.dtd">' . "\n";
my $opf20package =
    '<package version="2.0" xmlns="http://www.idpf.org/2007/opf">' . "\n";

my %dcelements20 = (
    "dc:title"	     => "dc:title",
    "dc:creator"     => "dc:creator",
    "dc:subject"     => "dc:subject",
    "dc:description" => "dc:description",
    "dc:publisher"   => "dc:publisher",
    "dc:contributor" => "dc:contributor",
    "dc:date"        => "dc:date",
    "dc:type"        => "dc:type",
    "dc:format"      => "dc:format",
    "dc:identifier"  => "dc:identifier",
    "dc:source"      => "dc:source",
    "dc:language"    => "dc:language",
    "dc:relation"    => "dc:relation",
    "dc:coverage"    => "dc:coverage",
    "dc:rights"      => "dc:rights",
    "dc:Title"       => "dc:title",
    "dc:Creator"     => "dc:creator",
    "dc:Subject"     => "dc:subject",
    "dc:Description" => "dc:description",
    "dc:Publisher"   => "dc:publisher",
    "dc:Contributor" => "dc:contributor",
    "dc:Date"        => "dc:date",
    "dc:Type"        => "dc:type",
    "dc:Format"      => "dc:format",
    "dc:Identifier"  => "dc:identifier",
    "dc:Source"      => "dc:source",
    "dc:Language"    => "dc:language",
    "dc:Relation"    => "dc:relation",
    "dc:Coverage"    => "dc:coverage",
    "dc:Rights"      => "dc:rights",
    "dc:Copyrights"  => "dc:rights"
    );

my %dcelements12to20 = (
    "dc:Title"       => "dc:title",
    "dc:Creator"     => "dc:creator",
    "dc:Subject"     => "dc:subject",
    "dc:Description" => "dc:description",
    "dc:Publisher"   => "dc:publisher",
    "dc:Contributor" => "dc:contributor",
    "dc:Date"        => "dc:date",
    "dc:Type"        => "dc:type",
    "dc:Format"      => "dc:format",
    "dc:Identifier"  => "dc:identifier",
    "dc:Source"      => "dc:source",
    "dc:Language"    => "dc:language",
    "dc:Relation"    => "dc:relation",
    "dc:Coverage"    => "dc:coverage",
    "dc:Rights"      => "dc:rights",
    "dc:Copyrights"  => "dc:rights"
    );

my %dcelements12 = (
    "dc:title"	     => "dc:Title",
    "dc:creator"     => "dc:Creator",
    "dc:subject"     => "dc:Subject",
    "dc:description" => "dc:Description",
    "dc:publisher"   => "dc:Publisher",
    "dc:contributor" => "dc:Contributor",
    "dc:date"        => "dc:Date",
    "dc:type"        => "dc:Type",
    "dc:format"      => "dc:Format",
    "dc:identifier"  => "dc:Identifier",
    "dc:source"      => "dc:Source",
    "dc:language"    => "dc:Language",
    "dc:relation"    => "dc:Relation",
    "dc:coverage"    => "dc:Coverage",
    "dc:rights"      => "dc:Rights",
    "dc:copyrights"  => "dc:Rights",
    "dc:Title"       => "dc:Title",
    "dc:Creator"     => "dc:Creator",
    "dc:Subject"     => "dc:Subject",
    "dc:Description" => "dc:Description",
    "dc:Publisher"   => "dc:Publisher",
    "dc:Contributor" => "dc:Contributor",
    "dc:Date"        => "dc:Date",
    "dc:Type"        => "dc:Type",
    "dc:Format"      => "dc:Format",
    "dc:Identifier"  => "dc:Identifier",
    "dc:Source"      => "dc:Source",
    "dc:Language"    => "dc:Language",
    "dc:Relation"    => "dc:Relation",
    "dc:Coverage"    => "dc:Coverage",
    "dc:Rights"      => "dc:Rights",
    "dc:Copyrights"  => "dc:Rights"
    );

my %dcelements20to12 = (
    "dc:title"	     => "dc:Title",
    "dc:creator"     => "dc:Creator",
    "dc:subject"     => "dc:Subject",
    "dc:description" => "dc:Description",
    "dc:publisher"   => "dc:Publisher",
    "dc:contributor" => "dc:Contributor",
    "dc:date"        => "dc:Date",
    "dc:type"        => "dc:Type",
    "dc:format"      => "dc:Format",
    "dc:identifier"  => "dc:Identifier",
    "dc:source"      => "dc:Source",
    "dc:language"    => "dc:Language",
    "dc:relation"    => "dc:Relation",
    "dc:coverage"    => "dc:Coverage",
    "dc:rights"      => "dc:Rights",
    "dc:copyrights"  => "dc:Rights"
    );

my %opfatts_ns = (
    "role" => "opf:role",
    "file-as" => "opf:file-as",
    "scheme" => "opf:scheme",
    "event" => "opf:event"
    );

my %mobibooktypes = (
    'Default' => undef,
    'eBook' => 'text/x-oeb1-document',
    'eNews' => 'application/x-mobipocket-subscription',
    'News feed' => 'application/x-mobipocket-subscription-feed',
    'News magazine' => 'application/x-mobipocket-subscription-magazine',
    'Images' => 'image/gif',
    'Microsoft Word document' => 'application/msword',
    'Microsoft Excel sheet' => 'application/vnd.ms-excel',
    'Microsoft Powerpoint presentation' => 'application/vnd.ms-powerpoint',
    'Plain text' => 'text/plain',
    'HTML' => 'text/html',
    'Mobipocket game' => 'application/vnd.mobipocket-game',
    'Franklin game' => 'application/vnd.mobipocket-franklin-ua-game'
    );

my %mobicontenttypes = (
    'text/x-oeb1-document' => 'text/x-oeb1-document',
    'application/x-mobipocket-subscription' => 'application/x-mobipocket-subscription',
    'application/x-mobipocket-subscription-feed' => 'application/x-mobipocket-subscription-feed',
    'application/x-mobipocket-subscription-magazine' => 'application/x-mobipocket-subscription-magazine',
    'image/gif' => 'image/gif',
    'application/msword' => 'application/msword',
    'application/vnd.ms-excel' => 'application/vnd.ms-excel',
    'application/vnd.ms-powerpoint' => 'application/vnd.ms-powerpoint',
    'text/plain' => 'text/plain',
    'text/html' => 'text/html',
    'application/vnd.mobipocket-game' => 'application/vnd.mobipocket-game',
    'application/vnd.mobipocket-franklin-ua-game' => 'application/vnd.mobipocket-franklin-ua-game'
    );
    
my %mobiencodings = (
    'Windows-1252' => 'Windows-1252',
    'utf-8' => 'utf-8'
    );

my %oebspecs = (
    'OEB12' => 'OEB12',
    'OPF20' => 'OPF20'
    );


########## METHODS ##########

=head1 ACCESSORS

=head2 opffile

Reads and writes the name of the OPF filename the
object will use for the C<init> and C<save> methods.

=head2 spec

The version of the OEB specification currently in use.  Valid values
are C<OEB12> and C<OPF20>.  This value will default to undef until
C<fixoeb12> or C<fixopf20> is called, as there is no way for the
object to know what the format is until it attempts to enforce it.

=head2 twig

The main twig object used to store the OPF XML tree.

=head2 twigroot

The twig object corresponding to the root tag, which should always be
<package>.  Modifying this will modify the twig.

=head2 error

Reads the last generated error message, if any.

=head1 METHODS

=head2 new($filename)

Instantiates a new OEB::Tools object.  If C<$filename> is specified,
it will also immediately initialize itself via the C<init> method.

=cut

sub new
{
    my $self = shift;
    my $class = ref($self) || $self;

    print "DEBUG[new]\n" if($debug);

    $self = fields::new($class);
    my ($filename) = @_;
    $self->init($filename) if($filename);
    return $self;
}

=head2 init($filename)

Initializes the data from an existing OPF file.  If C<$filename> is
specified and exists, the OEB object will be set to read and write to
that file before attempting to initialize.  Otherwise, if the object
currently points to an OPF file it will use that name.  If there is no
OPF filename data, and C<$filename> was not specified, it will make a
last-ditch attempt to find an OPF file first by looking in
META-INF/container.xml, and if nothing is found there, by looking in
the current directory for a single OPF file.

If no such files or found (or more than one is found), the method will
die horribly.

=cut

sub init
{
    my $self = shift;
    my ($filename) = @_;

    print "DEBUG[init]\n" if($debug);

    if($filename) { $self->opffile($filename); }

    if(!$self->opffile) { $self->opffile( get_container_rootfile() ); }
    
    if(!$self->opffile)
    {
	my @candidates = glob("*.opf");
	die("No OPF file specified, and there are multiple files to choose from")
	    if(scalar(@candidates) > 1);
	die("No OPF file specified, and I couldn't find one nearby")
	    if(scalar(@candidates) < 1);
	$self->opffile($candidates[0]);
    }
    
    if(-z $self->opffile)
    {
	die("OPF file '",$self->opffile,"' has zero size!");
    }

    if(! -f $self->opffile)
    {
	die("Could not initialize OEB object from '",$$self{opffile},"'!")
    }

    # Initialize the twig before use
    $$self{twig} = XML::Twig->new(
	keep_atts_order => 1,
	output_encoding => 'utf-8',
	pretty_print => 'record'
	),

    $$self{twig}->parsefile($$self{opffile});
    $$self{twigroot} = $$self{twig}->root
	or die("[OEB::init] '",$$self{opffile},"' has no root!");
    die("[OEB::init] '",$$self{opffile},"' root must be <package> (found '",
	$$self{twigroot}->gi,"')!")
	if($$self{twigroot}->gi ne 'package');

    return $self;
}

=head2 add_document($id,$href,$mediatype)

Adds a document to the OPF manifest and spine.

=head3 Arguments

=over 

=item $id

The XML ID to use.  This must be unique not only to the manifest list,
but to every element in the file.

=item $href

The href to the document in question.  Usually, this is just a
filename (or relative path and filename) of a file in the current
working directory.  If you are planning to eventually generate a .epub
book, all hrefs MUST be in or below the current working directory.

=item $mediatype (optional)

The mime type of the document.  If not specified, will default to
'application/xhtml+xml'.

=back

=cut
sub add_document
{
    my $self = shift;
    my ($id,$href,$mediatype) = @_;
    twig_add_document(\$$self{twig},$id,$href,$mediatype);
    return $self;
}

=head2 epubinit ()

Generates the C<mimetype> and C<META-INF/container.xml> files expected
by a .epub container, but does not actually generate the .epub file
itself.  This will be called automatically by C<gen_epub>.

=cut

sub epubinit ()
{
    my $self = shift;
    create_epub_mimetype();
    create_epub_container($$self{opffile});
    return;
}

=head2 fixmisc ()

Fixes miscellaneous potential problems in OPF data.  Specifically:

=over

=item * Standardizes the date format in <dc:date> elements

=item * Deletes any secondary <metadata> elements containing the
"filepos" attribute (potentially left over from Mobipocket
conversions)

=item * Verifies that the package ID corresponds to a proper
dc:identifier, and if not, creates a dc:identifier and assigns it.

=item * Inserts an <output> metadata element if it is missing (to
support Mobipocket Creator)

=back

=cut
sub fixmisc ()
{
    my $self = shift;

    print "DEBUG[fixmisc]\n" if($debug);

    my @dates;

    @dates = $$self{twigroot}->descendants('dc:date');
    push(@dates,$$self{twigroot}->descendants('dc:Date'));

    # Fix date formating
    foreach my $dcdate (@dates)
    {
	if(!$dcdate->text)
	{
	    print "WARNING: found dc:date with no value -- skipping\n";
	}
	else
	{
	    my $newdate = fix_date($dcdate->text);
	    if(!$newdate)
	    {
		print "WARNING: the date '",$dcdate->text,
		"' is so badly formatted I can't deal with it -- skipping.\n";
	    }
	    else
	    {
		print "DEBUG: setting date from '",$dcdate->text,
		"' to '",$newdate,"'\n" if($debug);
		$dcdate->set_text($newdate);
	    }
	}
    }
	
    # Delete extra metadata
    twig_delete_meta_filepos(\$$self{twig});

    # Make sure the package ID is valid, and assign it if not
    twig_fix_packageid(\$$self{twig});

    # Fix miscellaneous Mobipocket-related issues
    twig_fix_mobi(\$$self{twig});

    print "DEBUG: returning from fixmisc\n" if($debug);
    return $self;
}

=head2 fixopf20 ()

Modifies the OPF data to conform to the OPF 2.0 standard

=cut
sub fixopf20 ()
{
    my $self = shift;

    twig_fix_opf20(\$$self{twig});
    $$self{spec} = $oebspecs{'OPF20'};
    return $self;
}

=head2 fixoeb12 ()

Modifies the OPF data to conform to the OEB 1.2 standard

=cut

sub fixoeb12 ()
{
    my $self = shift;

    # Make the twig conform to the OEB 1.2 standard
    twig_fix_oeb12(\$$self{twig});
    $$self{spec} = $oebspecs{'OEB12'};
    return $self;
}

=head2 gen_epub($filename)

Creates a .epub format e-book.  This will create (or overwrite) the
files 'mimetype' and 'META-INF/container.xml' in the current
directory, creating the subdirectory META-INF as needed.

=head3 Arguments

=over

=item $filename

The filename of the .epub output file.  If not specifies, takes the
base name of the opf file and adds a .epub extension.

=back

=cut

sub gen_epub
{
    my $self = shift;
    my ($filename) = @_;

    my $zip = Archive::Zip->new();
    my $member;

    $self->epubinit();

    if(! $$self{opffile} )
    {
	die("Cannot create epub without an OPF (did you forget to init?)");
    }
    if(! -f $$self{opffile} )
    {
	die("OPF '",$$self{opffile},"' does not exist (did you forget to save?)");
    }

    $member = $zip->addFile('mimetype');
    $member->desiredCompressionMethod(COMPRESSION_STORED);

    $member = $zip->addFile('META-INF/container.xml');
    $member->desiredCompressionLevel(9);

    $member = $zip->addFile($$self{opffile});
    $member->desiredCompressionLevel(9);

    foreach my $file ($self->manifest_hrefs())
    {
	if(! $file)
	{
	    die("No items found in manifest!");
	}
	if(-f $file)
	{
	    $member = $zip->addFile($file);
	    $member->desiredCompressionLevel(9);
	}
	else { print STDERR "WARNING: ",$file," not found, skipping.\n"; }
    }

    if(! $filename)
    {
	($filename) = fileparse($$self{opffile},'\.\w+$');
	$filename .= ".epub";
    }

    unless ( $zip->writeToFileNamed($filename) == AZ_OK )
    {
	die("Failed to create epub as '",$filename,"'");
    }
    return;
}


=head2 manifest_hrefs ()

Returns a list of all of the hrefs in the current OPF manifest

=cut

sub manifest_hrefs ()
{
    my $self = shift;

    print "DEBUG[manifest_hrefs]\n" if($debug);

    my @items;
    my $href;
    my $manifest;
    my @retval;

    my $type;

    $manifest = $$self{twigroot}->first_child('manifest');
    if(! $manifest) { return @retval; }

    @items = $manifest->descendants('item');
    foreach my $item (@items)
    {
	if($debug)
	{
	    if(-f $item->att('href'))
	    {
		undef $type;
		$type = mimetype($item->att('href'));
		print "DEBUG: '",$item->att('href'),"' has mime-type '",$type,"'\n";
	    }
	}
	$href = $item->att('href');
	push(@retval,$href);
    }
    return @retval;
}

=head2 printopf ()

Prints the OPF file to the default filehandle

=cut

sub printopf ()
{
    my $self = shift;
    my $filehandle = shift;

    if(defined $filehandle) { $$self{twig}->print($filehandle); }
    else { $$self{twig}->print; }
    return;
}

=head2 save ()

Saves the OPF file to disk

=cut

sub save ()
{
    my $self = shift;
    
    open(OPFFILE,">",$$self{opffile})
	or die("Could not open ",$$self{opffile}," to save to!");
    $$self{twig}->print(\*OPFFILE);
    close(OPFFILE) or die ("Failure while closing ",$$self{opffile},"!");
    return $self;
}


########## PROCEDURES ##########

=head1 PROCEDURES

=head2 create_epub_container($opffile)

Creates the XML file META-INF/container.xml pointing to the
specified OPF file.

Creates the META-INF directory if necessary.  Will destroy any
non-directory file named 'META-INF' in the current directory.

=head3 Arguments

=over

=item $opffile

The OPF filename (and path, if necessary) to use in the container.  If
not specified, looks for a sole OPF file in the current working
directory.  Fails if more than one is found.

=back

=head3 Return values

=over

=item Returns a twig representing the container data if successful, undef
otherwise

=back

=cut

sub create_epub_container
{
    my ($opffile) = @_;
    my $twig;
    my $twigroot;
    my $rootfiles;
    my $element;

    if($opffile eq '') { return undef; }

    if(-e 'META-INF')
    {
	if(! -d 'META-INF')
	{
	    unlink('META-INF') or return undef;
	    mkdir('META-INF') or return undef;
	}
    }
    else { mkdir('META-INF') or return undef; }

    $twig = XML::Twig->new(
	output_encoding => 'utf-8',
	pretty_print => 'record'
	);

    $element = XML::Twig::Elt->new('container');
    $element->set_att('version' => '1.0',
		      'xmlns' => 'urn:oasis:names:tc:opendocument:xmlns:container');
    $twig->set_root($element);
    $twigroot = $twig->root;

    $rootfiles = $twigroot->insert_new_elt('first_child','rootfiles');
    $element = $rootfiles->insert_new_elt('first_child','rootfile');
    $element->set_att('full-path',$opffile);
    $element->set_att('media-type','application/oebps-package+xml');

    open(CONTAINER,'>','META-INF/container.xml') or die;
    $twig->print(\*CONTAINER);
    close(CONTAINER);
    return $twig;
}


=head2 create_epub_mimetype ()

Creates a file named 'mimetype' in the current working directory
containing 'application/epub+zip' (no trailing newline)

Destroys and overwrites that file if it exists.

Returns the mimetype string if successful, undef otherwise.

=cut

sub create_epub_mimetype ()
{
    my $mimetype = "application/epub+zip";
    
    open(EPUBMIMETYPE,">",'mimetype') or return undef;
    print EPUBMIMETYPE $mimetype;
    close(EPUBMIMETYPE);

    return $mimetype;
}

# Make sure month and day are in a plausible range.  Return the passed
# values if they are, return 3 undefs if not.  Testing of month or day
# can be skipped by passing undef in that spot.
#
sub ymd_sanitycheck
{
    my ($year,$month,$day) = @_;

    return (undef,undef,undef) unless($year);
    
    if($month)
    {
	return (undef,undef,undef) if($month > 12);
	if($day)
	{
	    return (undef,undef,undef) if($day > 31);
	}
	return ($year,$month,$day);
    }

    # We don't have a month.  If we *do* have a day, the result is
    # broken, so send back the undefs.
    return (undef,undef,undef) if($day);
    return ($year,undef,undef);
}

=head2 fix_date($datestring)

Takes a date string and attempts to convert it to the limited subset
of ISO8601 allowed by the OPF standard (YYYY, YYYY-MM, or YYYY-MM-DD).

In the special case of finding MM/DD/YYYY, it assumes that it was a
Mobipocket-mangled date, and not only converts it, but will strip the
day information if the day is '01', and both the month and day
information if both month and day are '01'.  This is because
Mobipocket Creator enforces a complete MM/DD/YYYY even if the month
and day aren't known, and it is common practice to use 01 for an
unknown value.

=head3 Arguments

=over

=item $datestring

A date string in a format recognizable by Date::Manip

=back

=head3 Return values

=over

=item Returns the corrected string, or undef on failure

=back

=cut

sub fix_date
{
    my ($datestring) = @_;
    return unless($datestring);

    my $date;
    my ($year,$month,$day);
    my $retval;

    print "DEBUG[fix_date]: '",$datestring,"'\n" if($debug);

    $_ = $datestring;

    print "DEBUG: checking M(M)/D(D)/YYYY\n" if($debug);
    if(( ($month,$day,$year) = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/ ) == 3)
    {
	# We have a XX/XX/XXXX datestring
	print "DEBUG: found '",$month,"/",$day,"/",$year,"'\n" if($debug);
	if( ($month <= 12) && ($day <= 31) )
	{
	    # We probably have a Mobipocket MM/DD/YYYY
	    if($day <= 1)
	    {
		undef($day);
		undef($month) if($month <= 1);
	    }

	    $retval = $year;
	    $retval .= sprintf("-%02u",$month) if($month);
	    $retval .= sprintf("-%02u",$day) if($day);
	    return $retval;
	}
    }

    print "DEBUG: checking M(M)/YYYY\n" if($debug);
    if(( ($month,$year) = /^(\d{1,2})\/(\d{4})$/ ) == 2)
    {
	# We have a XX/XXXX datestring
	print "DEBUG: found '",$month,"/",$year,"'\n" if($debug);
	if($month <= 12)
	{
	    # We probably have MM/YYYY
	    $retval = sprintf("%04u-%02u",$year,$month);
	    print "DEBUG: returning '",$retval,"'\n" if($debug);
	    return $retval;
	}
    }

    # This regexp will reduce '2009-xx-01' to just 2009
    # This may not be desirable
#    ($year,$month,$day) = /(\d{4})-?(\d{2})?-?(\d{2})?/;
#    ($year,$month,$day) = /(\d{4})(?:-?(\d{2})-?(\d{2}))?/;

    # Force exact match)
    print "DEBUG: checking YYYY-MM-DD\n" if($debug);
    ($year,$month,$day) = /^(\d{4})-(\d{2})-(\d{2})$/;
    ($year,$month,$day) = ymd_sanitycheck($year,$month,$day);

    if(!$year)
    {
	print "DEBUG: checking YYYYMMDD\n" if($debug);
	($year,$month,$day) = /^(\d{4})(\d{2})(\d{2})$/;
	($year,$month,$day) = ymd_sanitycheck($year,$month,$day);
    }

    if(!$year)
    {
	print "DEBUG: checking YYYY-MM\n" if($debug);
	($year,$month) = /^(\d{4})-(\d{2})$/;
	($year,$month) = ymd_sanitycheck($year,$month,undef);
    }

    if(!$year)
    {
	print "DEBUG: checking YYYY\n" if($debug);
	($year) = /^(\d{4})$/;
    }

    # At this point, we've exhausted all of the common cases.  We use
    # Date::Manip to hit all of the unlikely ones as well.  This comes
    # with a drawback: Date::Manip doesn't distinguish between 2008
    # and 2008-01-01, but we should have covered that above.
    #
    # Note that Date::Manip will die on MS Windows system unless the
    # TZ environment variable is set in a specific manner.
    # See: 
    # http://search.cpan.org/perldoc?Date::Manip#TIME_ZONES

    if(!$year)
    {
	$date = ParseDate($datestring);
	print "DEBUG: Date::Manip found '",UnixDate($date,"%Y-%m-%d"),"'\n" if($debug);
	$year = UnixDate($date,"%Y");
	$month = UnixDate($date,"%m");
	$day = UnixDate($date,"%d");
    }

    if($year)
    {
	# If we still have a $year, $month and $day either don't exist
	# or are plausibly valid.
	print "DEBUG: found year=",$year," " if($debug);
	$retval = sprintf("%04u",$year);
	if($month)
	{
	    print "month=",$month," " if($debug);
	    $retval .= sprintf("-%02u",$month);
	    if($day)
	    {
		print "day=",$day if($debug);
		$retval .= sprintf("-%02u",$day);
	    }
	}
	print "\n" if($debug);
	print "DEBUG: returning '",$retval,"'\n" if($debug);
	return $retval if($retval);
    }

    if(!$year)
    {
	print "DEBUG: didn't find a year in '",$datestring,"'!\n" if($debug);
	return undef;
    }
    elsif($debug)
    {
	print "DEBUG: found ",sprintf("04u",$year);
	print sprintf("-02u",$month) if($month);
	print sprintf("-02u",$day),"\n" if($day);
    }

    $retval = sprintf("%04u",$year);
    $retval .= sprintf("-%02u-%02u",$month,$day);
    return $retval;
}

=head2 get_container_rootfile($container)

Opens and parses an OPS/epub container, extracting the 'full-path'
attribute of element 'rootfile'

=head3 Arguments

=over

=item $container

The OPS container to parse.  Defaults to 'META-INF/container.xml'

=back

=head3 Return values

=over

=item Returns a string containing the rootfile on success, undef on failure.

=back

=cut

sub get_container_rootfile
{
    my ($container) = @_;
    my $twig = XML::Twig->new();
    my $rootfile;
    my $retval = undef;

    $container = 'META-INF/container.xml' if(! $container);

    if(-f $container)
    {
	$twig->parsefile($container) or return undef;
	$rootfile = $twig->root->first_descendant('rootfile');
	return undef if(!defined $rootfile);
	$retval = $rootfile->att('full-path');
    }
    return $retval;
}


=head2 print_memory($label)

Checks /proc/$PID/statm and prints out a line to STDERR showing the
current memory usage.  This is a debugging tool that will likely fail
to do anything useful on a system without a /proc system compatible
with Linux.

=head3 Arguments

=over

=item $label

If defined, will be output along with the memory usage.

=back

Returns nothing

=cut

sub print_memory
{
    my ($label) = @_;
    my @mem;
      
    if(!open(PROCSTATM,"<","/proc/$$/statm"))
    {
	print "[",$label,"]: " if(defined $label);
	print "Couldn't open /proc/$$/statm [$!]\n";
    }

    @mem = split(/\s+/,<PROCSTATM>);
    close(PROCSTATM);

    # @mem[0]*4 = size (kb)
    # @mem[1]*4 = resident (kb)
    # @mem[2]*4 = shared (kb)
    # @mem[3] = trs
    # @mem[4] = lrs
    # @mem[5] = drs
    # @mem[6] = dt

    print "Current memory usage";
    print " [".$label."]" if(defined $label);
    print ":  size=",$mem[0]*4,"k";
    print "  resident=",$mem[1]*4,"k";
    print "  shared=",$mem[2]*4,"k\n";
    return;
}



=head2 split_metadata($metahtmlfile)

Takes a psuedo-HTML containing one or more <metadata> segments (such
as in many files output by mobi2html) and splits out the metadata
values into an XML file in preparation for conversion to OPF.
Rewrites the html file without the metadata.

If tidy cannot be run, split_metadata MUST output the OEB 1.2
doctype (and thus not conform to OPF 2.0, which doesn't use a dtd at
all), as the the metadata values may contain HTML entities and Tidy
is needed to convert them to UTF-8 characters

=head3 Arguments

=over

=item $metahtmlfile

The filename of the pseudo-HTML file

=back


=head3 Returns ($xmlstring,$basename)

=over

=item $xmlstring: a string containing the XML

=item $basename: the base filename with the final extension stripped

=back

Dies horribly on failure

=cut

sub split_metadata ( $ )
{
    my ($metahtmlfile) = @_;

    my $delim = $/;

    my $metafile;
    my $metastring;
    my $htmlfile;

    my $filebase;
    my $filedir;
    my $fileext;

    my $tidy; # boolean to check if tidy is available

    my $retval;

    
    ($filebase,$filedir,$fileext) = fileparse($metahtmlfile,'\.\w+$');
    $metafile = $filebase . ".opf";
    $htmlfile = $filebase . "-html.html";

    open(METAHTML,"<",$metahtmlfile)
	or die("Failed to open ",$metahtmlfile," for reading!\n");

    open(META,">",$metafile)
	or die("Failed to open ",$metafile," for writing!\n");

    open(HTML,">",$htmlfile)
	or die("Failed to open ",$htmlfile," for writing!\n");


    # Preload the return value with the OPF headers
    #print META $utf8xmldec,$oeb12doctype,"<package>\n";
    print META $utf8xmldec,$opf20package;

    # Finding and removing all of the metadata requires that the
    # entire thing be handled as one slurped string, so temporarily
    # undefine the perl delimiter
    #
    # Since multiple <metadata> sections may be present, cannot use
    # </metadata> as a delimiter.
    undef $/;
    while(<METAHTML>)
    {
	($metastring) = /(<metadata>.*<\/metadata>)/;
	if(!defined $metastring) { last; }
	print META $metastring,"\n";
	s/(<metadata>.*<\/metadata>)//;
	print HTML $_,"\n";
    }
    $/ = $delim;
    print META "</package>\n";

    close(HTML);
    close(META);
    close(METAHTML);

    # It is very unlikely that split_metadata will be called twice
    # from the same program, so undef $metastring to reclaim the
    # memory.  Just going out of scope will not necessarily do this.
    undef($metastring);

    system_tidy_xml($metafile,"$filebase-tidy.opf");
#    system_tidy_xhtml($htmlfile,$metahtmlfile);
    rename($htmlfile,$metahtmlfile)
	or die("Failed to rename ",$htmlfile," to ",$metahtmlfile,"!\n");

    return $metafile;
}


#
# sub twig_add_document(\$twigref,$id,$href,$mediatype)
#
# Adds a document with the given id, href, and mediatype to both
# manifest and spine.
#
# An attempt was made to determine the mimetype automatically, but as
# of 2008.09, all of the available modules are too buggy to be usable.
#
# Arguments:
#   $twigref : Reference to the twig to modify
#   $id : The document item id
#   $href : The document href
#   $mediatype: The document mime-type.  If not set, defaults to 
#               'application/xhtml+xml'
#
# Returns nothing (modifies $twigref by reference)
#
sub twig_add_document
{
    my $twigref = shift;
    my ($id,$href,$mediatype) = @_;
    my $topelement = $$twigref->root;

    my $mimetype;

    if(!defined $mediatype)
    {
	$mediatype = 'application/xhtml+xml';

#	$mimetype = mimetype($href);
#	print "DEBUG: found mimetype = '",$mimetype,"'\n";
#	if(defined $mimetype) { $mediatype = $mimetype; }
#	else { $mediatype = "application/xhtml+xml"; }

#    my @dcformat = $topelement->descendants('dc:Format');
#    if(defined $dcformat)
#    {
#	$mediatype = $dcformat[0]->text;
#    }
    }
    my $manifest = $topelement->first_child('manifest');
    my $spine = $topelement->first_child('spine');
    my $item = XML::Twig::Elt->new('item');
    my $itemref = XML::Twig::Elt->new('itemref');

    if(!defined $manifest)
    {
	$manifest = XML::Twig::Elt->new('manifest');
	$manifest->paste('last_child',$topelement);
    }
    if(!defined $spine)
    {
	$spine = XML::Twig::Elt->new('spine');
	$spine->paste('last_child',$topelement);
    }
    
    $item->set_id($id);
    $item->set_att(
	'href' => $href,
	'media-type' => $mediatype
	);
    $item->paste('last_child',$manifest);

    $itemref->set_att('idref' => $id);
    $itemref->paste('last_child',$spine);

    return;
}
    

#
# sub twig_assign_uid($topelement,$condition)
#
# Finds the first child of $topelement meeting the twig condition in
# $condition containing any text.  If it has no uid, assigns it the ID
# 'UID';
#
# This was originally planned as a fallback to assign a UID to
# whatever identifier was available if no recognized UIDs were found,
# but was reconsidered as a very bad idea, as there is no real way to
# guess at the uniqueness of a completely unknown identifier.  The
# code was kept in case it is useful in some other context.
#
# Warning: this does not check for the existence of the id 'UID'
# elsewhere in the tree.  You are responsible for making sure you
# aren't creating a duplicate before calling this subroutine.
#
# Arguments:
#   $topelement : Top twig element to look under
#   $condition : Twig search condition
#                Default value: 'dc:identifier'
#
# Returns the element designated to be the package UID, or undef if nothing
# matching the condition was found.
# 
sub twig_assign_uid
{
    my $topelement;
    my $condition;

    my @identifiers;
    my $ident;
    my $retval = undef;

    ($topelement,$condition) = @_;
    if(!defined $condition) { $condition = 'dc:identifier'; }

    @identifiers = $topelement->descendants($condition);
    foreach my $element (@identifiers)
    {
	if($element->text ne '')
	{
	    if(!defined $element->id)
	    {
		$element->set_id('UID');
	    }
	    $retval = $element;
	    last;
	}
    }
    return $retval;
}

#
# sub twig_create_uuid($gi)
#
# Creates an unlinked element with the specified gi (tag), and then
# assigns it the id and scheme attributes 'UUID'.
#
# Arguments:
#   $gi : The gi (tag) to use for the element
#         Default: 'dc:identifier'
#
# Returns the element.
#
sub twig_create_uuid
{
    my ($gi) = @_;
    my $element;

    if(!defined $gi) { $gi = 'dc:identifier'; }
    
    $element = XML::Twig::Elt->new($gi);
    $element->set_id('UUID');
    $element->set_att('scheme' => 'UUID');
    $element->set_text(Data::UUID->create_str());
    return $element;
}


#
# sub twig_delete_meta_filepos(\$twigref)
#
# Deletes metadata elements with the attribute 'filepos' underneath
# the given parent element
#
# These are secondary metadata elements included in the output from
# mobi2html may that are not used.
#
# Arguments:
#   $twigref: the reference to the twig to modify
#
# Returns nothing (modifies $twig by reference)
#
sub twig_delete_meta_filepos ( $ )
{
    my $twigref = shift;
    my $topelement = $$twigref->root;
    my @elements;

    @elements = $topelement->descendants('metadata[@filepos]');
    foreach my $el (@elements)
    {
	$el->delete;
    }
    return;
}


#
# sub twig_fix_lowercase_dcmeta(\$twigref)
#
# Searches through the descendants of a twig for tags matching
# a known list of all-lowercase DC metadata elements and corrects the
# capitalization to the OEB 1.2 standard.
#
# Note that OPF 2.0 (for epub books) requires that these all be
# lowercase, but Mobipocket and several other tools are still on the
# OEB 1.2 standard.
#
# Passing this sub a twig with a root other than <package> may result
# in undefined behavior.
#
# Arguments:
#   $twigref : Reference to twig to modify
#
# Returns nothing (modifies $twigref by reference)
#
sub twig_fix_lowercase_dcmeta ( $ )
{
    my $twigref = shift;
    my $topelement = $$twigref->root;

    my $meta;
    my $dcmeta;
    my @elements;

    $meta = $topelement->first_child('metadata');
    $dcmeta = $meta->first_child('dc-metadata');

    foreach my $dcmetatag (keys %dcelements20to12)
    {
	@elements = $dcmeta->descendants($dcmetatag);
	foreach my $el (@elements)
	{
	    $el->set_tag($dcelements20to12{$el->tag})
		if defined($dcelements20to12{$el->tag});
	}
    }
    return;
}


#
# sub twig_fix_mobi(\$twigref)
#
# Manipulates the twig to fix Mobipocket-specific issues
# * If no <output> element exists, creates one for a utf-8 ebook
#
# Arguments:
#   $twigref : reference to the OPF twig
#
# Global variables:
#   %mobiencodings : valid Mobipocket output encoding attribute strings
#   %mobicontenttypes : valid Mobipocket output content-type attribute strings
#
# Returns nothing (modifies the twig by reference)
#
sub twig_fix_mobi ( $ )
{
    my $twigref = shift;

    print "DEBUG[twig_fix_mobi]\n" if($debug);

    # Sanity checks
    die("Tried to fix mobipocket issues on undefined twig!")
	if(!$$twigref);
    my $twigroot = $$twigref->root
	or die("Tried to fix mobipocket issues on twig with no root!");
    die("Tried to fix mobipocket issues, but twigroot isn't <package>!")
	if($twigroot->gi ne 'package');
    my $metadata = $twigroot->first_descendant('metadata')
	or die("Tried to fix mobipocket issues on twig with no metadata!");

    # If <output> already exists, and it has a valid content-type,
    # validate the encoding and return.  Otherwise, continue.
    my $output = $twigroot->first_descendant('output');
    if($output)
    {
	my $encoding = $mobiencodings{$output->att('encoding')};
	my $contenttype = $mobicontenttypes{$output->att('content-type')};

	if($contenttype)
	{
	    $encoding = 'utf-8' if(!$encoding);
	    return;
	}
    }

    my $dcmeta = $twigroot->first_descendant('dc-metadata');
    my $xmeta = $twigroot->first_descendant('x-metadata');
    my $parent;
    
    # If we have <dc-metadata>, <output> has to go under <x-metadata>
    # If we don't, it goes under <metadata> directly.
    if($dcmeta)
    {
	# If <x-metadata> doesn't exist, create it
	if(!$xmeta)
	{
	    print "DEBUG: creating <x-metadata>\n" if($debug);
	    $xmeta = $dcmeta->insert_new_elt('after','x-metadata')
	}
	if($output)
	{
	    $parent = $output->parent;
	    if($parent != $xmeta)
	    {
		print "DEBUG: moving <output> under <x-metadata>\n"
		    if($debug);
		$output->move('last_child',$xmeta);
	    }
	}
	else
	{
	    print "DEBUG: creating <output> under <x-metadata>\n" if($debug);
	    $output = $xmeta->insert_new_elt('last_child','output');
	}
    }
    else
    {
	if($output)
	{
	    $parent = $output->parent;
	    if($parent != $metadata)
	    {
		print "DEBUG: moving <output> under <metadata>\n" if($debug);
		$output->move('last_child',$metadata)
	    }
	}
	else
	{
	    print "DEBUG: creating <output> under <metadata>\n" if($debug);
	    $output = $metadata->insert_new_elt('last_child','output');
	}
    }
    
    # At this stage, we definitely have <output> in the right place.
    # Set the attributes and return.
    $output->set_att('encoding' => 'utf-8',
		     'content-type' => 'text/x-oeb1-document');
    print "DEBUG: returning from twig_fix_mobi" if($debug);
    return;
}


#
# sub twig_fix_oeb12(\$twigref)
#
# Manipulates the twig such that it conforms to OEB v1.2
# 
# Specifically, this involves moving all of the dc-metadata elements
# underneath an element with tag 'dc-metadata', moving any remaining
# tags underneath 'x-metadata', and making the dc-metadata tags
# conform to the OEB v1.2 capitalization
#
# Arguments:
#   \$twigref : the reference to the twig to modify
#
# Returns the modified twig (but also modifies $twig by reference)
#
sub twig_fix_oeb12 ( $ )
{
    my $twigref = shift;

    print "DEBUG[twig_fix_oeb12]\n" if($debug);

    # Sanity checks
    die("Tried to fix undefined twig to OEB1.2!")
	if(!$$twigref);
    my $twigroot = $$twigref->root
	or die("Tried to fix twig with no root to OEB1.2!");
    die("Can't fix OEB1.2 if twigroot isn't <package>!")
	if($twigroot->gi ne 'package');

    my $metadata = $twigroot->first_descendant('metadata');
    my $parent;
    my $dcmeta;
    my $xmeta;
    my $regexp;
    my @elements;

    # Start by setting the OEB 1.2 doctype
    $$twigref->set_doctype('package',
			   "http://openebook.org/dtds/oeb-1.2/oebpkg12.dtd",
			   "+//ISBN 0-9673008-1-9//DTD OEB 1.2 Package//EN");
    
    # Remove <package> version attribute used in OPF 2.0
    $twigroot->del_att('version');

    # Set OEB 1.2 namespace attribute on <package>
    $twigroot->set_att('xmlns' => 'http://openebook.org/namespaces/oeb-package/1.0/');

    # If <metadata> doesn't exist, we're in a real mess, but go ahead
    # and try to create it anyway
    if(! $metadata)
    {
	print "DEBUG: creating <metadata>\n" if($debug);
	$metadata = $twigroot->insert_new_elt('first_child','metadata');
    }

    # Make sure that metadata is the first child of the twigroot,
    # which should be <package>
    $parent = $metadata->parent;
    if($parent != $twigroot)
    {
	print "DEBUG: moving <metadata>\n" if($debug);
	$metadata->move('first_child',$twigroot);
    }

    # Clobber metadata attributes 'xmlns:dc' and 'xmlns:opf'
    # attributes used in OPF2.0
    $metadata->del_atts('xmlns:dc','xmlns:opf');

    $dcmeta = $twigroot->first_descendant('dc-metadata');
    $xmeta = $metadata->first_descendant('x-metadata');

    # If <dc-metadata> doesn't exist, we'll have to create it.
    if(! $dcmeta)
    {
	print "DEBUG: creating <dc-metadata>\n" if($debug);
	$dcmeta = $metadata->insert_new_elt('first_child','dc-metadata');
    }

    # Make sure that $dcmeta is a child of $metadata
    $parent = $dcmeta->parent;
    if($parent != $metadata)
    {
	print "DEBUG: moving <dc-metadata>\n" if($debug);
	$dcmeta->move('first_child',$metadata);
    }
    
    # Assign the correct namespace attribute for OEB 1.2
    $dcmeta->set_att('xmlns:dc',"http://purl.org/dc/elements/1.1/");

    # Set the correct tag name and move it into <dc-metadata>
    $regexp = "(" . join('|',keys(%dcelements12)) .")";
    @elements = $twigroot->descendants(qr/$regexp/);
    foreach my $el (@elements)
    {
	print "DEBUG: processing '",$el->gi,"'\n" if($debug);
	die("Found invalid DC element '",$el->gi,"'!") if(!$dcelements12{$el->gi});
	$el->set_gi($dcelements12{$el->gi});
	$el->move('last_child',$dcmeta);
    }

    # Deal with any remaining elements under <metadata> that don't
    # match *-metadata
    @elements = $metadata->children(qr/^(?!(?s:.*)-metadata)/);
    if(@elements)
    {
	if($debug)
	{
	    print "DEBUG: extra metadata elements found: ";
	    foreach my $el (@elements) { print $el->gi," "; }
	    print "\n";
	}
	# Create x-metadata if necessary
	if(! $xmeta)
	{
	    print "DEBUG: creating <x-metadata>\n" if($debug);
	    $xmeta = $dcmeta->insert_new_elt('after','x-metadata')
	}
	# Make sure x-metadata belongs to metadata
	$parent = $xmeta->parent;
	if($parent != $metadata)
	{
	    print "DEBUG: moving <x-metadata>\n" if($debug);
	    $xmeta->move('after',$dcmeta);
	}
	
	foreach my $el (@elements)
	{
	    $el->move('last_child',$xmeta);
	}
    }

    print "DEBUG: returning from twig_fix_oeb12\n" if($debug);
    return;
}


#
# sub twig_fix_opf20(\$twigref)
#
# Manipulates the twig such that it conforms to OPF v2.0
# 
# Specifically, this involves:
#   * moving all of the dc-metadata and x-metadata elements directly
#     underneath <metadata>
#   * removing the <dc-metadata> and <x-metadata> elements themselves
#   * lowercasing the dc-metadata tags
#   * setting namespaces on dc-metata OPF attributes
#   * setting version and xmlns attributes on <package>
#   * setting xmlns:dc and xmlns:opf on <metadata>
#
# Arguments:
#   \$twigref : the reference to the twig to modify
#
# Returns the modified twig (but also modifies $twig by reference)
#
sub twig_fix_opf20 ( $ )
{
    my $twigref = shift;

    print "DEBUG[twig_fix_opf20]\n" if($debug);

    # Sanity checks
    die("Tried to fix undefined OPF2.0 twig!")
	if(!$$twigref);
    my $twigroot = $$twigref->root
	or die("Tried to fix OPF2.0 twig with no root!");
    die("Can't fix OPF2.0 twig if twigroot isn't <package>!")
	if($twigroot->gi ne 'package');

    my $metadata = $twigroot->first_descendant('metadata');
    my $parent;
    my $dcmeta;
    my $xmeta;
    my @elements;
    my @children;
    my $temp;

    # If <metadata> doesn't exist, we're in a real mess, but go ahead
    # and try to create it anyway
    if(! $metadata)
    {
	print "DEBUG: creating <metadata>\n" if($debug);
	$metadata = $twigroot->insert_new_elt('first_child','metadata');
    }

    # Make sure that metadata is the first child of the twigroot
    $parent = $metadata->parent;
    if($parent != $twigroot)
    {
	print "DEBUG: moving <metadata>\n" if($debug);
	$metadata->move('first_child',$twigroot);
    }


    # If <dc-metadata> exists, make sure that it is directly
    # underneath <metadata> so that its children will collapse to the
    # correct position, then erase it.
    @elements = $twigroot->descendants('dc-metadata');
    if(@elements)
    {
	foreach my $dcmeta (@elements)
	{
	    print "DEBUG: moving <dc-metadata>\n" if($debug);
	    $dcmeta->move('first_child',$metadata);
	    $dcmeta->erase;
	}
    }

    # If <x-metadata> exists, make sure that it is directly underneath
    # <metadata> so that its children will collapse to the correct
    # position, then erase it.
    @elements = $twigroot->descendants('x-metadata');
    if(@elements)
    {
	foreach my $xmeta (@elements)
	{
	    print "DEBUG: moving <x-metadata>\n" if($debug);
	    $xmeta->move('last_child',$metadata);
	    $xmeta->erase;
	}
    }

    # For all DC elements at any location, set the correct tag name
    # and attribute namespace and move it directly under <metadata>
    foreach my $dcmetatag (keys %dcelements20)
    {
	@elements = $twigroot->descendants($dcmetatag);
	foreach my $el (@elements)
	{
	    print "DEBUG: checking element '",$el->gi,"'\n" if($debug);
	    $el->set_gi($dcelements20{$dcmetatag});
	    foreach my $att ($el->att_names)
	    {
		print "DEBUG:   checking attribute '",$att,"'\n" if($debug);
		if($opfatts_ns{$att})
		{
		    # If the opf:att attribute properly exists already, do nothing.
		    if($el->att($opfatts_ns{att}))
		    {
			print "DEBUG:   found both '",$att,"' and '",$opfatts_ns{$att},"' -- skipping.\n"
			    if($debug);
			next;
		    }
		    print "DEBUG:   changing attribute '",$att,"' => '",$opfatts_ns{$att},"'\n"
			if($debug);
		    $el->change_att_name($att,$opfatts_ns{$att});
		}
	    }
	    $el->move('first_child',$metadata);
	}
    }
    
    # Fix the <package> attributes
    $twigroot->set_atts('version' => '2.0',
			'xmlns' => 'http://www.idpf.org/2007/opf');

    # Fix the <metadata> attributes
    $metadata->set_atts('xmlns:dc' => "http://purl.org/dc/elements/1.1/",
			'xmlns:opf' => "http://www.idpf.org/2007/opf");

    # Clobber the doctype, if present
    $$twigref->set_doctype(0,0,0,0);
    print "DEBUG: returning from twig_fix_opf20\n" if($debug);
    return;
}


#
# sub twig_fix_packageid(\$twigref)
#
# Checks the <package> element for the attribute 'unique-identifier',
# makes sure that it is mapped to a valid dc:identifier subelement,
# and if not, searches those subelements for an identifier to assign,
# or creates one if nothing can be found.
#
# Arguments:
#   \$twig : The twig reference containing the <package> element as a root.
#
# Returns nothing (modifies the reference).
#
sub twig_fix_packageid ( $ )
{
    my $twigref = shift;

    print "DEBUG[twig_fix_packageid]\n" if($debug);

    # Sanity checks
    die("Tried to fix packageid of undefined twig")
	if(!$$twigref);
    my $twigroot = $$twigref->root
	or die("Tried to fix packageid of twig with no root");
    die("Can't fix packageid if twigroot isn't <package>!")
	if($twigroot->gi ne 'package');

    my $packageid;
    my $meta = $twigroot->first_child('metadata');
    my $element;

    $element = $$twigref->elt_id($packageid);

    $packageid = $twigroot->att('unique-identifier');
    if(defined $packageid) 
    {
        # Check that the ID maps to a valid identifier
	# If not, undefine it
	print "DEBUG: checking existing packageid '",$packageid,"'\n"
	    if($debug);
	$element = $$twigref->elt_id($packageid);
	if(defined $element)
	{
	    if(lc($element->tag) ne 'dc:identifier')
	    {
		print "DEBUG: packageid '",$packageid,
		"' points to a non-identifier element ('",$element->tag,"')\n"
		    if($debug);
		print "DEBUG: undefining existing packageid '",$packageid,"'\n"
		    if($debug);
		undef($packageid);
	    }
	    elsif(!$element->text)
	    {
		print "DEBUG: packageid '",$packageid,
		"' points to an empty identifier.\n"
		    if($debug);
		print "DEBUG: undefining existing packageid '",$packageid,"'\n"
		    if($debug);
		undef($packageid);
	    }
	}
	else { undef($packageid); };
    }

    if(!defined $packageid)
    {
	# Search known IDs for a unique Package ID
	$packageid = twig_search_knownuids($$twigref);
    }

    # If no unique ID found so far, start searching known schemes
    if(!defined $packageid)
    {
	$packageid = twig_search_knownuidschemes($meta);
    }

    # And if we still don't have anything, we have to make one from
    # scratch using Data::UUID
    if(!defined $packageid)
    {
	print "DEBUG: creating new UUID\n" if($debug);
	$element = twig_create_uuid();
	$element->paste('first_child',$meta);
	$packageid = 'UUID';
    }

    # At this point, we have a unique ID.  Assign it to package
    $twigroot->set_att('unique-identifier',$packageid);
    print "DEBUG: returning from twig_fix_packageid\n" if($debug);
    return $$twigref;
}


#
# sub twig_search_knownuids($twig,$gi)
#
# Searches an XML twig for the first element with an ID matching known
# UID IDs
#
# If set, $gi must match the generic identifier (tag) of the element
# for it to be returned, otherwise 'dc:identifier'
#
# Arguments:
#   $twig: XML::Twig to search
#   $gi: generic identifier (tag) to check against
#        Default value: 'dc:identifier' (case-insensitive match)
#
# Returns the ID if a match is found, undef otherwise
#
sub twig_search_knownuids
{
    my ($twig, $gi) = @_;
    if(!defined $gi) { $gi = 'dc:identifier'; }

    my @knownuids = qw (
	OverDriveGUID
	GUID
	guid
	UUID
	uuid
	UID
	uid
	calibre_id
	FWID
	fwid
	);

    my $id;
    my $element;

    my $retval = undef;

    foreach $id (@knownuids)
    {
	$element = $twig->elt_id($id);
	if(defined $element)
	{
	    if(lc($element->gi) eq $gi)
	    {
		$retval = $element->id;
	    }
	    last;
	}
    }
    return $retval;
}


#
# sub twig_search_knownuidschemes($topelement)
#
# Searches descendants of an XML twig element for the first
# <dc:identifier> subelement with the attribute 'scheme' matching a
# known list of schemes for unique IDs
#
# Will search for both:
#   * opf:scheme in dc:identifier elements (OPF 2.0)
#   * scheme in dc:Identifier elements (OEB 1.2)
#
# Arguments:
#   $topelement : twig element to start descendant search
#
# Returns the ID if a match is found, undef otherwise
#
sub twig_search_knownuidschemes
{
    my ($topelement,$gi) = @_;
    if(!defined $gi) { $gi = 'dc:identifier'; }

    my @knownuidschemes = qw (
	GUID
	UUID
	ISBN
	FWID
	);
    # Creating a regexp to search on works, but doesn't let you
    # specify priority.  For that, you really do have to loop.
    my $schemeregexp = "(" . join('|',@knownuidschemes) . ")";
    my $scheme;

    my @elems;
    my $elem;
    my $id;

    my $retval = undef;

    print "DEBUG[twig_search_knownuidschemes]\n" if($debug);

    foreach $scheme (@knownuidschemes)
    {
	print "DEBUG: searching for scheme='",$scheme,"'\n" if($debug);
	@elems = $topelement->descendants("dc:identifier[\@opf:scheme='$scheme']");
	push(@elems,$topelement->descendants("dc:Identifier[\@scheme='$scheme']"));
	foreach $elem (@elems)
	{
	    print "DEBUG: working on scheme '",$scheme,"'\n" if($debug);
	    if(defined $elem)
	    {
		if($scheme eq 'FWID')
		{
		    # Fictionwise has a screwy output that sets the ID
		    # equal to the text.  Fix the ID to just be 'FWID'
		    print "DEBUG: fixing FWID\n" if($debug);
		    $elem->set_id('FWID');
		}

		$id = $elem->id;
		if(defined $id)
		{
		    $retval = $id;
		}
		else
		{
		    print "DEBUG: assigning ID from scheme '",$scheme,"'\n" if($debug);
		    $id = uc($scheme);
		    $elem->set_id($id);
		    $retval = $id;
		}
		print "DEBUG: found Package ID: ",$id,"\n" if($debug);
		last;
	    } # if(defined $elem)
	} # foreach $elem (@elems)
	last if(defined $retval);
    }
    print "DEBUG: returning from twig_search_knownuidschemes\n" if($debug);
    return $retval;
}


#
# sub tidy_xml($xmlstring, $inputenc)
# 
# An attempt to replace sub system_tidy_xml with a pure perl version.
#
# DO NOT USE
#
# HTML::Tidy appears to be incredibly buggy as of v1.08.  I got
# coredumps just trying to create a new tidy object.
#
sub tidy_xml
{
    my ($xmlstring,$inputenc) = @_;

    my %encodings = qw(
	raw raw
	ascii ascii
	latin0 latin0
	latin1 latin1
	utf8 utf8
	iso2022 iso2022
	mac mac
	win1252 win1252
	ibm858 ibm858
	utf16le utf16le
	utf16be utf16be
	utf16 utf16
	big5 big5
	shiftjis shiftjis
        );

    $inputenc = $encodings{$inputenc} if(defined $inputenc);
    $inputenc = "win1252" if(!defined $inputenc);
    print "DEBUG: tidy_xml input encoding: '",$inputenc,"'\n";
    print "DEBUG: tidy_xml config: '$datapath/$tidyconfig'\n";
#    my %tidyopts = (
#	config_file => "$datapath/$tidyconfig",
#	quiet => "yes",
#	input_xml => "yes",
#	input_encoding => $inputenc,
#	output_encoding => 'utf8'
#    );
	
    my $tidy = HTML::Tidy->new(
	{
#	    config_file => "$datapath/$tidyconfig",
#	    quiet => "yes",
#	    input_xml => "yes",
#	    input_encoding => $inputenc,
#	    output_encoding => 'utf8'
	}
	);
    
    return $tidy->clean($xmlstring);
}



=head2 system_tidy_xhtml($infile,$outfile)

Runs tidy on a XHTML file semi-safely (using a secondary file)

Converts HTML to XHTML if necessary

=head3 Arguments

=over

=item $infile

The filename to tidy

=item $outfile

The filename to use for tidy output if the safety condition to
overwrite the input file isn't met.

=back

=head3 Global variables used

=over

=item $tidycmd

the location of the tidy executable

=item $tidyconfig

the location of the config file to use

=item $tidyxhtmlerrors

the filename to use to output errors

=item $tidysafety

the safety factor to use (see CONFIGURABLE GLOBAL VARIABLES, above)

=back

=head3 Return Values

Returns the return value from tidy

=over

=item 0 - no errors

=item 1 - warnings only

=item 2 - errors

=item Dies horribly if the return value is unexpected

=back

=cut

sub system_tidy_xhtml
{
    my $infile;
    my $outfile;
    my @configopt = ();
    my $retval;

    ($infile,$outfile) = @_;
    die("system_tidy_xhtml called with no input file") if(!$infile);
    die("system_tidy_xhtml called with no output file") if(!$outfile);
    
    @configopt = ('-config',"$datapath/$tidyconfig")
	if(-f "$datapath/$tidyconfig");

    $retval = system($tidycmd,@configopt,
		     '-q','-utf8',
		     '-asxhtml',
		     '--doctype','transitional',
		     '-f',$tidyxhtmlerrors,
		     '-o',$outfile,
		     $infile);

    # Some systems may return a two-byte code, so deal with that first
    if($retval >= 256) { $retval = $retval >> 8 };
    if($retval == 0)
    {
	rename($outfile,$infile) if($tidysafety < 4);
	unlink($tidyxhtmlerrors);
    }
    elsif($retval == 1)
    {
	rename($outfile,$infile) if($tidysafety < 3);
	unlink($tidyxhtmlerrors) if($tidysafety < 2);
    }
    elsif($retval == 2)
    {
	print STDERR "WARNING: Tidy errors encountered.  Check ",$tidyxhtmlerrors,"\n"
	    if($tidysafety > 0);
	unlink($tidyxhtmlerrors) if($tidysafety < 1);
    }
    return $retval;
}


=head2 system_tidy_xml($infile,$outfile)

Runs tidy on an XML file semi-safely (using a secondary file)

=head3 Arguments

=over

=item $infile

The filename to tidy

=item $outfile

The filename to use for tidy output if the safety condition to
overwrite the input file isn't met.

=back

=head3 Global variables used

=over

=item $datapath

the location of the config file

=item $tidycmd

the name of the tidy executable

=item $tidyconfig

the name of the tidy config file to use

=item $tidyxmlerrors

the filename to use to output errors

=item $tidysafety

the safety factor to use (see CONFIGURABLE GLOBAL VARIABLES, above)

=back

=head3 Return values

Returns the return value from tidy

=over

=item 0 - no errors

=item 1 - warnings only

=item 2 - errors

=item Dies horribly if the return value is unexpected

=back

=cut

sub system_tidy_xml
{
    my ($infile,$outfile) = @_;
    my @configopt = ();
    my $retval;
    
    die("system_tidy_xml called with no input file") if(!$infile);
    die("system_tidy_xml called with no output file") if(!$outfile);

    @configopt = ('-config',"$datapath/$tidyconfig")
	if(-f "$datapath/$tidyconfig");

    $retval = system($tidycmd,@configopt,
		     '-q','-utf8',
		     '-xml',
		     '-f',$tidyxmlerrors,
		     '-o',$outfile,
		     $infile);

    # Some systems may return a two-byte code, so deal with that first
    if($retval >= 256) { $retval = $retval >> 8 };
    if($retval == 0)
    {
	rename($outfile,$infile) if($tidysafety < 4);
	unlink($tidyxmlerrors);
    }
    elsif($retval == 1)
    {
	rename($outfile,$infile) if($tidysafety < 3);
	unlink($tidyxmlerrors) if($tidysafety < 2);
    }
    elsif($retval == 2)
    {
	print STDERR "WARNING: Tidy errors encountered.  Check ",$tidyxmlerrors,"\n"
	    if($tidysafety > 0);
	unlink($tidyxmlerrors) if($tidysafety < 1);
    }
    else
    {
	# Something unexpected happened (program crash, sigint, other)
	die("Tidy did something unexpected (return value=",$retval,").  Check all output.");
    }
    return $retval;
}


=head1 EXAMPLE

 package OEB::Tools qw(split_metadata system_tidy_xml);
 $OEB::Tools::tidysafety = 2;

 my $opffile = split_metadata('ebook.html');
 my $otheropffile = 'alternate.opf';
 my $retval = system_tidy_xml($opffile,'tidy-backup.xml');
 my $oeb = OEB::Tools->new($opffile);
 $oeb->fixopf20;
 $oeb->fixmisc;
 $oeb->print;
 $oeb->save;

 $oeb->init($otheropffile);
 $oeb->fixoeb12;
 $oeb->save;

=head1 BUGS/TODO

=over

=item * need a twig procedure for sort_children to sort on GI + ID

=item * $datapath points to a relatively useless location by default.
While nothing very useful is stored there yet, it needs to be fixed to
a usable system directory before initial release.

=item * die() is called much too frequently for this to be integrated
into large applications yet.  Fatalities need to be converted either
into exceptions or return values, and I haven't decided which way to
go yet.  The error storage isn't used at all.

=item * It might be better to use sysread / index / substr / syswrite in
&split_metadata to handle the split in 10k chunks, to avoid massive
memory usage on large files.

This may not be worth the effort, since the average size for most
books is less than 500k, and the largest books are rarely if ever over
10M.

=item * The only generator is currently for .epub books.  PDF,
PalmDoc, Mobipocket, and iSiloX are eventually planned.

=item * There are no import/extraction tools yet.  Extraction from
PalmDoc, eReader, and Mobipocket is eventually planned.

=item * There is not yet any way to initialize a blank OPF entry for
creation of ebooks from scratch.

=item * Classic accessors aren't very readable.  The object may be
rebuilt with Class::Meta to use semi-affordance accessors.

=back

=head1 AUTHOR

Zed Pobre <zed@debian.org>

=head1 COPYRIGHT

Copyright © 2008 Zed Pobre

Licensed to the public under the terms of the GNU GPL, version 2

=cut
