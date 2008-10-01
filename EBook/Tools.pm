package EBook::Tools;
use warnings; use strict;
use version; our $VERSION = qv("0.1.0");
# $Revision$ $Date$
#use warnings::unused;

## Perl Critic overrides:
## RequireBriefOpen seems to be way too brief to be useful
## no critic (RequireBriefOpen)
our $debug = 0;

=head1 NAME

EBook::Tools - A collection of tools to manipulate documents in Open E-book formats.

=head1 DESCRIPTION

This module provides an object interface and a number of related
procedures intended to create or modify documents centered around the
International Digital Publishing Forum (IDPF) standards, currently
both OEBPS v1.2 and OPS/OPF v2.0.

=cut

require Exporter;
use base qw(Exporter);


=head1 DEPENDENCIES

=head2 Perl Modules

=over

=item Archive::Zip

=item Class::Meta

=item Class::Meta::Express

=item Date::Manip

Note that Date::Manip will die on MS Windows system unless the
TZ environment variable is set in a specific manner. See: 

http://search.cpan.org/perldoc?Date::Manip#TIME_ZONES

=item File::Basename

=item File::MimeInfo::Magic

=item Tie::IxHash

=item Time::Local

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
use Class::Meta::Express;
use Class::Meta::Types::Perl 'semi-affordance';
use Class::Meta::Types::String 'semi-affordance';
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
use Tie::IxHash;
use Time::Local;
use XML::Twig;

our @EXPORT_OK;
@EXPORT_OK = qw (
    &create_epub_container
    &create_epub_mimetype
    &fix_datestring
    &get_container_rootfile
    &print_memory
    &split_metadata
    &system_tidy_xml
    &system_tidy_xhtml
    &twig_create_uuid
    &ymd_validate
    );


=head1 CONFIGURABLE PACKAGE VARIABLES

=over

=item $datapath

The location where various external files (such as tidy configuration
files) can be found.

Defaults to the subdirectory 'data' in whatever directory the calling
script is actually in.  (See BUGS/TODO)

=item %dcelements12

A tied IxHash mapping an all-lowercase list of Dublin Core metadata
element names to the capitalization dictated by the OEB 1.2
specification, used by the fix_oeb12() and fix_oeb12_dcmeta() methods.
Changing the tags in this list will change the tags recognized and
placed inside the <dc-metadata> element.

Order is preserved and significant -- fix_oeb12 will output DC
metadata elements in the same order as in this hash, though order for
tags of the same name is preserved from the input file.

=item %dcelements20

A tied IxHash mapping an all-lowercase list of Dublin Core metadata
element names to the all-lowercase form dictated by the OPF 2.0
specification (which means it maps the all-lowercase tags to
themselves).  It is used by the fix_opf20() and fix_opf20_dcmeta()
methods.  Changing the tags in this list will change the tags
recognized and placed directly under the <metadata> element.

Order is preserved and significant -- fix_opf20 will output DC
metadata elements in the same order as in this hash, though order for
tags of the same name is preserved from the input file.

=item %oebspecs

A hash mapping valid specification strings to themselves, primarily
used to undefine unrecognized values.  Default valid values are 'OEB12'
and 'OPF20'.

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


our $utf8xmldec = '<?xml version="1.0" encoding="UTF-8" ?>' . "\n";
our $oeb12doctype = 
    '<!DOCTYPE package' . "\n" .
    '  PUBLIC "+//ISBN 0-9673008-1-9//DTD OEB 1.2 Package//EN"' . "\n" .
    '  "http://openebook.org/dtds/oeb-1.2/oebpkg12.dtd">' . "\n";
our $opf20package =
    '<package version="2.0" xmlns="http://www.idpf.org/2007/opf">' . "\n";

our %dcelements12;
tie %dcelements12, 'Tie::IxHash', (
    "dc:identifier"  => "dc:Identifier",
    "dc:title"       => "dc:Title",
    "dc:creator"     => "dc:Creator",
    "dc:subject"     => "dc:Subject",
    "dc:description" => "dc:Description",
    "dc:publisher"   => "dc:Publisher",
    "dc:contributor" => "dc:Contributor",
    "dc:date"        => "dc:Date",
    "dc:type"        => "dc:Type",
    "dc:format"      => "dc:Format",
    "dc:source"      => "dc:Source",
    "dc:language"    => "dc:Language",
    "dc:relation"    => "dc:Relation",
    "dc:coverage"    => "dc:Coverage",
    "dc:rights"      => "dc:Rights",
    "dc:copyrights"  => "dc:Rights"
    );

our %dcelements20;
tie %dcelements20, 'Tie::IxHash', (
    "dc:identifier"  => "dc:identifier",
    "dc:title"       => "dc:title",
    "dc:creator"     => "dc:creator",
    "dc:subject"     => "dc:subject",
    "dc:description" => "dc:description",
    "dc:publisher"   => "dc:publisher",
    "dc:contributor" => "dc:contributor",
    "dc:date"        => "dc:date",
    "dc:type"        => "dc:type",
    "dc:format"      => "dc:format",
    "dc:source"      => "dc:source",
    "dc:language"    => "dc:language",
    "dc:relation"    => "dc:relation",
    "dc:coverage"    => "dc:coverage",
    "dc:rights"      => "dc:rights",
    "dc:copyrights"  => "dc:rights"
    );

our %mobibooktypes = (
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

our %oebspecs = (
    'OEB12' => 'OEB12',
    'OPF20' => 'OPF20'
    );


########## ACCESSORS ##########

# Accessors are automatically generated by Class:Meta above

=head1 READ/WRITE ACCESSORS

Semi-affordance accessors are in use.  Read/Write (RW) accessors have the
listed method 'accessorname' to retrieve a value, and an additional method
'set_accessorname' to change it.  Read-Only (RO) accessors have just the
former.

=head2 opffile [RW]

Reads the name of the OPF filename the
object will use for the C<init> and C<save> methods.

=head2 spec [RW]

The version of the OEB specification currently in use.  Valid values
are C<OEB12> and C<OPF20>.  This value will default to undef until
C<fixoeb12> or C<fixopf20> is called, as there is no way for the
object to know what the format is until it attempts to enforce it.

=head2 twig [RW]

The main twig object used to store the OPF XML tree.

=head1 READ-ONLY ACCESSORS

=head2 twigroot [RO]

The twig object corresponding to the root tag, which should always be
<package>.  Modifying this will modify the twig, but since it has its
own methods for self-modification, and simply assigning a new value
will _not_ link the new root to the twig, this is technically read-only.

=head2 errors [RO]

An arrayref containing any generated error messages.

=head2 warnings [RO]

An arrayref containing any generated warning messages.

=cut

my %rwfields = (
    'opffile'  => 'string',
    'spec'     => 'string',
    'twig'     => 'scalar'
    );
my %rofields = (
    'twigroot' => 'scalar',
    'errors'   => 'arrayref',
    'warnings' => 'arrayref'
    );
my %privatefields = ();

# This doesn't seem to have any value?  Should probably either finish
# it or remove it...
my %methods = (
    'init' => 'PUBLIC',
    'init_blank' => 'PUBLIC',
    'add_document' => 'PUBLIC',
    'add_errors' => 'PUBLIC',
    'add_warnings' => 'PUBLIC'
    );
    
# A simple 'use fields' will not work here: use takes place inside
# BEGIN {}, so the @...fields variables won't exist.
require fields;
fields->import(
    keys(%rwfields),keys(%rofields),keys(%privatefields)
    );

class 
{
    meta 'ebooktools' => (default_type => 'scalar');
    ctor 'new'        => (create => 0);
    foreach my $field (keys %rwfields)
    {
	has $field => (is => $rwfields{$field});
    }
    foreach my $field (keys %rofields)
    {
	has $field => (
	    is    => $rofields{$field},
	    authz => 'READ'
	    );
    }
    foreach my $field (keys %privatefields)
    {
	has $field => (
	    is    => $rofields{$field},
	    authz => 'NONE'
	    );
    }
    foreach my $method (keys %methods)
    {
        method $method => ( view => $methods{$method} );
    }
};


########## CONSTRUCTORS AND INITIALIZATION ##########

=head1 CONSTRUCTORS AND INITIALIZATION

=head2 new($filename)

Instantiates a new EBook::Tools object.  If C<$filename> is specified,
it will also immediately initialize itself via the C<init> method.

=cut

sub new   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my $class = ref($self) || $self;
    my ($filename) = @_;

    print {*STDERR} "DEBUG[new]\n" if($debug);

    $self = fields::new($class);

    if($filename)
    {
	print {*STDERR} "DEBUG: initializing with '",$filename,"'\n"
            if($debug);
	$self->init($filename);
    }
    return $self;
}


=head2 init($filename)

Initializes the object from an existing OPF file.  If C<$filename> is
specified and exists, the OEB object will be set to read and write to
that file before attempting to initialize.  Otherwise, if the object
currently points to an OPF file it will use that name.  If there is no
OPF filename data, and C<$filename> was not specified, it will make a
last-ditch attempt to find an OPF file first by looking in
META-INF/container.xml, and if nothing is found there, by looking in
the current directory for a single OPF file.

If no such files or found (or more than one is found), the
initialization will die horribly.

=cut

sub init    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my ($filename) = @_;

    print {*STDERR} "DEBUG[init]\n" if($debug);

    if($filename) { $$self{opffile} = $filename; }

    if(!$self->opffile) { $self->set_opffile( get_container_rootfile() ); }
    
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


=head2 init_blank()

Initializes an object containing nothing more than the basic OPF
framework, suitable for adding new documents when creating an e-book
from scratch.

=cut

sub init_blank    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my ($filename) = @_;
    my $metadata;
    my $element;

    print {*STDERR} "DEBUG[init_blank]\n" if($debug);

    if($filename) { $$self{opffile} = $filename; }
    $$self{twig} = XML::Twig->new(
	keep_atts_order => 1,
	output_encoding => 'utf-8',
	pretty_print => 'record'
        );

    $element = XML::Twig::Elt->new('package');
    $$self{twig}->set_root($element);
    $$self{twigroot} = $$self{twig}->root;
    $metadata = $$self{twigroot}->insert_new_elt('first_child','metadata');
    $element = twig_create_uuid();
    $element->paste('first_child',$metadata);

    # Fix the <package> attributes
    $$self{twigroot}->set_atts('version' => '2.0',
                               'xmlns' => 'http://www.idpf.org/2007/opf');

    # Fix the <metadata> attributes
    $metadata->set_atts('xmlns:dc' => "http://purl.org/dc/elements/1.1/",
			'xmlns:opf' => "http://www.idpf.org/2007/opf");

    # Set the specification
    $$self{spec} = $oebspecs{'OPF20'};
    return 1;
}

########## METHODS ##########

=head1 METHODS

Unless otherwise specified, all methods return undef if an error was
added to the error list, and true otherwise (even if a warning was
added to the warning list).

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

An attempt was made to determine the mimetype automatically, but as of
2008.09, no available modules do this well enough to be usable.

=back

=cut

sub add_document   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my ($id,$href,$mediatype) = @_;
    die("method add_document() called as a procedure") unless(ref $self);

    my $topelement = $$self{twigroot};

    if(!defined $mediatype)
    {
	$mediatype = 'application/xhtml+xml';

#	my $mimetype = mimetype($href);
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

    return 1;
}


=head2 add_errors(@errors)

Adds @errors to the list of object errors.  Each member of
@errors should be a string containing the entire text of the
error, with no ending newline.

SEE ALSO: add_warnings, clear_errors, clear_warnerr

=cut

sub add_errors   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (@newerrors) = @_;
    die("method add_errors() called as a procedure") unless(ref $self);

    my $currenterrors;
    $currenterrors = $$self{errors} if($$self{errors});

    print {*STDERR} "DEBUG[add_errors]\n" if($debug);

    if(@newerrors)
    {
	printf("DEBUG: adding %d error(s)\n",scalar(@newerrors))
	    if($debug);
	push(@$currenterrors,@newerrors);
    }
    $$self{errors} = $currenterrors;
    return 1;
}


=head2 add_warnings(@warnings)

Adds @warnings to the list of object warnings.  Each member of
@warnings should be a string containing the entire text of the
warning, with no ending newline.

SEE ALSO: add_errors, clear_warnings, clear_warnerr

=cut

sub add_warnings   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (@newwarnings) = @_;
    my @currentwarnings;
    die("method add_warnings() called as a procedure") unless(ref $self);

    print {*STDERR} "DEBUG[add_warnings]\n" if($debug);
            
    @currentwarnings = @{$$self{warnings}} if($$self{warnings});
    
    if(@newwarnings)
    {
	printf("DEBUG: adding %d warning(s)\n",scalar(@newwarnings))
	    if($debug);
	push(@currentwarnings,@newwarnings);
    }
    $$self{warnings} = \@currentwarnings;

    return 1;
}


=head2 clear_errors()

Clear the current list of errors

=cut

sub clear_errors
{
    my $self = shift;
    die("method clear_errors() called as a procedure") unless(ref $self);

    $self->{errors} = ();
    return 1;
}


=head2 clear_warnerr()

Clear both the error and warning lists

=cut

sub clear_warnerr
{
    my $self = shift;
    die("method clear_warnerr() called as a procedure") unless(ref $self);

    $self->{errors} = ();
    $self->{warnings} = ();
    return 1;
}


=head2 clear_warnings()

Clear the current list of warnings

=cut

sub clear_warnings
{
    my $self = shift;
    die("method clear_warnings() called as a procedure") unless(ref $self);

    $self->{warnings} = ();
    return 1;
}


=head2 delete_meta_filepos()

Deletes metadata elements with the attribute 'filepos' underneath
the given parent element

These are secondary metadata elements included in the output from
mobi2html may that are not used.

=cut

sub delete_meta_filepos
{
    my $self = shift;
    die("method delete_meta_filepos() called as a procedure") unless(ref $self);

    my @elements = $$self{twigroot}->descendants('metadata[@filepos]');
    foreach my $el (@elements)
    {
	$el->delete;
    }
    return 1;
}


=head2 epubinit()

Generates the C<mimetype> and C<META-INF/container.xml> files expected
by a .epub container, but does not actually generate the .epub file
itself.  This will be called automatically by C<gen_epub>.

=cut

sub epubinit
{
    my $self = shift;
    die("method epubinit() called as a procedure") unless(ref $self);

    create_epub_mimetype();
    create_epub_container($$self{opffile});
    return 1;
}


=head2 fix_dates()

Standardizes all <dc:date> elements via fix_datestring().  Adds a
warning to the object for each date that could not be fixed.

Called from fix_misc().

=cut

sub fix_dates
{
    my $self = shift;
    die("method fix_dates() called as a procedure") unless(ref $self);

    print "DEBUG[fix_dates]\n" if($debug);

    my @dates;
    my $newdate;

    @dates = $$self{twigroot}->descendants('dc:date');
    push(@dates,$$self{twigroot}->descendants('dc:Date'));
    
    # Fix date formating
    foreach my $dcdate (@dates)
    {
	if(!$dcdate->text)
	{
	    $self->add_warnings("WARNING: found dc:date with no value -- skipping");
	}
	else
	{
	    $newdate = fix_datestring($dcdate->text);
	    if(!$newdate)
	    {
		$self->add_warnings(
		    sprintf("fixmisc(): can't deal with date '%s' -- skipping.",$dcdate->text)
		    );
	    }
	    else
	    {
		print "DEBUG: setting date from '",$dcdate->text,
		"' to '",$newdate,"'\n" if($debug);
		$dcdate->set_text($newdate);
	    }
	}
    }
    return 1;
}

=head2 fix_manifest()

Fixes problems with the OPF manifest, specifically:

=over

=item Moves all <item> elements underneath <manifest>, creating
<manifest> if necessary.

=item Checks all of the hrefs in the manifest for further links, and
attempts to make sure that any linked items that can be found also
have manifest entries.  Any added entries are then themselves checked,
until no more entries can be found to add.  Adds a warning message for
every link that could not be added.

=back

=cut

sub fix_manifest
{
    my $self = shift;
    die("method fix_manifest() called as a procedure") unless(ref $self);

    my $twig = $$self{twig};
    my $twigroot = $$self{twigroot};
    
    print "DEBUG[fix_manifest]\n" if($debug);

    my $manifest = $twigroot->first_descendant('manifest');
    my @elements;
    my $parent;

    # Sanity checks
    die("Tried to fix undefined twig to OEB1.2!") if(!$twig);
    die("Tried to fix twig with no root to OEB1.2!") if(!$twigroot);
    die("Can't fix OEB1.2 if twigroot isn't <package>!")
	if($twigroot->gi ne 'package');

    # If <manifest> doesn't exist, create it
    if(! $manifest)
    {
	print "DEBUG: creating <manifest>\n" if($debug);
	$manifest = $twigroot->insert_new_elt('last_child','manifest');
    }

    # Make sure that the manifest is the first child of the twigroot,
    # which should be <package>
    $parent = $manifest->parent;
    if($parent != $twigroot)
    {
	print "DEBUG: moving <manifest>\n" if($debug);
	$manifest->move('last_child',$twigroot);
    }

    @elements = $twigroot->descendants(qr/^item$/ix);
    foreach my $el (@elements)
    {
        if(!$el->id)
        {
            if(!$el->att('href'))
            {
                # No ID, no href, there's something very fishy here
                # Leave it alone, but log a warning
                $self->add_warnings(
                    "fix_manifest(): item with no id or href -- skipping"
                    );
                print "DEBUG: skipping item with no id or href\n" if($debug);
                next;
            }
            # We have a href, but no ID.  Log a warning, but move it anyway.
            $self->add_warnings(
                'fix_manifest(): handling item with no ID! '
                . sprintf "(href='%s')",$el->att('href')
                );
            print "DEBUG: processing item with no id (href='",$el->att('href'),"')\n"
                if($debug);
            $el->move('last_child',$manifest);
        }
        print "DEBUG: processing item '",$el->id,"' (href='",$el->att('href'),"')\n"
            if($debug > 1);
        $el->move('last_child',$manifest);
    }

    return 1;
}

=head2 fix_misc()

Fixes miscellaneous potential problems in OPF data.  Specifically,
this is a shortcut to calling delete_meta_filepos(), fix_dates(),
fix_packageid(), and fix_mobi().  Note that the final fix_mobi call
will force the OEB 1.2 structure and add a nonstandard element
(<output>) if it didn't exist before the call, so if you want your
output to validate against standard OEB1.2 or OPF2.0, use the other
calls independently.

=over

=item * Standardizes all <dc:date> elements via fix_datestring()

=item * Deletes any secondary <metadata> elements containing the
"filepos" attribute (potentially left over from Mobipocket
conversions) via delete_meta_filepos();

=item * Verifies and corrects the package ID via fix_packageid()

=item * Handles Mobipocket issues via fix_mobi().  (WARNING: this may
add nonstandard elements to the file, causing it to no longer validate
as OEB1.2 or OPF2.0.)

=back

=cut

sub fix_misc
{
    my $self = shift;
    die("method fix_misc() called as a procedure") unless(ref $self);

    print "DEBUG[fix_misc]\n" if($debug);

    my @dates;
    my $newdate;

    $self->delete_meta_filepos();
    $self->fix_packageid();
    $self->fix_dates();
    $self->fix_mobi();

    print "DEBUG: returning from fixmisc\n" if($debug > 1);
    return 1;
}


=head2 fix_mobi()

Manipulates the twig to fix Mobipocket-specific issues

=over 

=item * Force the OEB 1.2 structure (although not the namespace, DTD,
or capitalization), so that <dc-metadata> and <x-metadata> are
guaranteed to exist.

=item * Find and move all Mobi-specific elements to <x-metadata>

=item * If no <output> element exists, creates one for a utf-8 ebook

=back

=cut

sub fix_mobi
{
    my $self = shift;
    die("method fix_mobi() called as a procedure") unless(ref $self);

    print "DEBUG[fix_mobi]\n" if($debug);

    # Sanity checks
    die("Tried to fix mobipocket issues on undefined twig!")
	if(!$$self{twig});
    my $twigroot = $$self{twigroot}
	or die("Tried to fix mobipocket issues on twig with no root!");
    die("Tried to fix mobipocket issues, but twigroot isn't <package>!")
	if($twigroot->gi ne 'package');
    my $metadata = $twigroot->first_descendant('metadata')
	or die("Tried to fix mobipocket issues on twig with no metadata!");

    my %mobicontenttypes = (
	'text/x-oeb1-document' => 'text/x-oeb1-document',
	'application/x-mobipocket-subscription' 
	=> 'application/x-mobipocket-subscription',
	'application/x-mobipocket-subscription-feed' 
	=> 'application/x-mobipocket-subscription-feed',
	'application/x-mobipocket-subscription-magazine'
	=> 'application/x-mobipocket-subscription-magazine',
	'image/gif' => 'image/gif',
	'application/msword' => 'application/msword',
	'application/vnd.ms-excel' => 'application/vnd.ms-excel',
	'application/vnd.ms-powerpoint' => 'application/vnd.ms-powerpoint',
	'text/plain' => 'text/plain',
	'text/html' => 'text/html',
	'application/vnd.mobipocket-game' => 'application/vnd.mobipocket-game',
	'application/vnd.mobipocket-franklin-ua-game'
	=> 'application/vnd.mobipocket-franklin-ua-game'
	);
    
    my %mobiencodings = (
	'Windows-1252' => 'Windows-1252',
	'utf-8' => 'utf-8'
	);

    my @mobitags = (
        'output',
        'Adult',
        'Demo',
        'DefaultLookupIndex',
        'DictionaryInLanguage',
        'DictionaryOutLanguage',
        'DictionaryVeryShortName',
        'DatabaseName',
        'EmbeddedCover',
        'Review',
        'SRP',
        'Territory'
        );

    my $dcmeta;
    my $xmeta;
    my @elements;
    my $output;
    my $parent;


    # Mobipocket currently requires that its custom elements be found
    # underneath <x-metadata>.  Since the presence of <x-metadata>
    # requires that the Dublin Core tags be under <dc-metadata>, we
    # have to use at least the OEB1.2 structure (deprecated, but still
    # allowed in OPF2.0), though we don't have to convert everything.
    $self->fix_oeb12_metastructure();
    $dcmeta = $twigroot->first_descendant('dc-metadata');
    $xmeta = $twigroot->first_descendant('x-metadata');

    # If <x-metadata> doesn't exist, create it.  Even if there are no
    # mobi-specific tags, this method will create at least one
    # (<output>) which will need it.
    if(!$xmeta)
    {
        print "DEBUG: creating <x-metadata>\n" if($debug);
        $xmeta = $dcmeta->insert_new_elt('after','x-metadata')
    }

    foreach my $tag (@mobitags)
    {
        @elements = $twigroot->descendants($tag);
        next unless (@elements);
        
        # In theory, only one Mobipocket-specific element should ever
        # be present in a document.  We'll deal with multiples anyway,
        # but send a warning.
        if(scalar(@elements) > 1)
        {
            add_warnings('fix_mobi(): Found ' . scalar(@elements) . " '"
                         . $tag . "' elements, but only one should exist.");
        }

        foreach my $el (@elements)
        {
            $el->move('last_child',$xmeta);
        }
    }

    $output = $xmeta->first_child('output');
    if($output)
    {
	my $encoding = $mobiencodings{$output->att('encoding')};
	my $contenttype = $mobicontenttypes{$output->att('content-type')};
        
	if($contenttype)
	{
	    $output->set_att('encoding','utf-8') if(!$encoding);
	    print "DEBUG: setting encoding only and returning\n"
		if($debug > 1);
	    return 1;
	}
    }
    else
    {
        print "DEBUG: creating <output> under <x-metadata>\n" if($debug);
        $output = $xmeta->insert_new_elt('last_child','output');
    }


    # At this stage, we definitely have <output> in the right place.
    # Set the attributes and return.
    $output->set_att('encoding' => 'utf-8',
		     'content-type' => 'text/x-oeb1-document');
    print "DEBUG: returning from fix_mobi" if($debug > 1);
    return 1;
}


=head2 fix_oeb12()

Modifies the OPF data to conform to the OEB 1.2 standard

Specifically, this involves:

=over

=item * adding the OEB 1.2 doctype

=item * removing OPF 2.0 version and namespace attributes

=item * setting the OEB 1.2 namespace on <package>

=item * moving all of the dc-metadata elements underneath an element
with tag <dc-metadata>, which itself is forced to be underneath
<metadata>, which is created if it doesn't exist.

=item * moving any remaining tags underneath <x-metadata>, again
forced to be under <metadata>

=item * making the dc-metadata tags conform to the OEB v1.2 capitalization

=cut

sub fix_oeb12
{
    my $self = shift;
    die("method fix_oeb12() called as a procedure") unless(ref $self);

    my $twig = $$self{twig};
    my $twigroot = $$self{twigroot};
    
    print "DEBUG[fix_oeb12]\n" if($debug);

    # Sanity checks
    die("Tried to fix undefined twig to OEB1.2!") if(!$twig);
    die("Tried to fix twig with no root to OEB1.2!") if(!$twigroot);
    die("Can't fix OEB1.2 if twigroot isn't <package>!")
	if($twigroot->gi ne 'package');


    # Make the twig conform to the OEB 1.2 standard
    my $metadata;
    my $dcmeta;
    my $xmeta;
    my @elements;

    # Start by setting the OEB 1.2 doctype
    $$self{twig}->set_doctype('package',
                              "http://openebook.org/dtds/oeb-1.2/oebpkg12.dtd",
                              "+//ISBN 0-9673008-1-9//DTD OEB 1.2 Package//EN");
    
    # Remove <package> version attribute used in OPF 2.0
    $twigroot->del_att('version');

    # Set OEB 1.2 namespace attribute on <package>
    $twigroot->set_att('xmlns' => 'http://openebook.org/namespaces/oeb-package/1.0/');

    # Verify and correct locations for <metadata>, <dc-metadata>, and
    # <x-metadata>, creating them as needed.
    $self->fix_oeb12_metastructure;
    $metadata = $twigroot->first_descendant('metadata');
    $dcmeta = $metadata->first_descendant('dc-metadata');
    $xmeta = $metadata->first_descendant('x-metadata');

    # Clobber metadata attributes 'xmlns:dc' and 'xmlns:opf'
    # attributes used in OPF2.0
    $metadata->del_atts('xmlns:dc','xmlns:opf');

    # Assign the correct namespace attribute for OEB 1.2
    $dcmeta->set_att('xmlns:dc',"http://purl.org/dc/elements/1.1/");

    # Set the correct tag name and move it into <dc-metadata>
#    $regexp = "(" . join('|',keys(%dcelements12)) .")";

    foreach my $dcel (keys %dcelements12)
    {
        @elements = $twigroot->descendants(qr/^$dcel$/ix);
        foreach my $el (@elements)
        {
            print "DEBUG: processing '",$el->gi,"'\n" if($debug > 1);
            die("Found invalid DC element '",$el->gi,"'!") if(!$dcelements12{lc $el->gi});
            $el->set_gi($dcelements12{lc $el->gi});
            $el = twig_fix_oeb12_atts($el);
            $el->move('last_child',$dcmeta);
        }
    }
    
    # Deal with any remaining elements under <metadata> that don't
    # match *-metadata
    @elements = $metadata->children(qr/^(?!(?s:.*)-metadata)/x);
    if(@elements)
    {
	if($debug)
	{
	    print "DEBUG: extra metadata elements found: ";
	    foreach my $el (@elements) { print $el->gi," "; }
	    print "\n";
	}
	# Create x-metadata under metadata if necessary
	if(! $xmeta)
	{
	    print "DEBUG: creating <x-metadata>\n" if($debug);
	    $xmeta = $metadata->insert_new_elt('last_child','x-metadata')
	}

	foreach my $el (@elements)
	{
	    $el->move('last_child',$xmeta);
	}
    }

    # Find any <meta> elements anywhere in the package and move them
    # under <x-metadata>.  Force the tag to lowercase.

    @elements = $twigroot->children(qr/^meta$/ix);
    foreach my $el (@elements)
    {
        $el->set_gi(lc $el->gi);
        $el->move('last_child',$xmeta);
    }

    $$self{spec} = $oebspecs{'OEB12'};
    print "DEBUG: returning from fix_oeb12\n" if($debug > 1);
    return 1;
}


=head2 fix_oeb12_dcmetatags()

Makes a case-insensitive search for tags matching a known list of DC
metadata elements and corrects the capitalization to the OEB 1.2
standard.  Also corrects 'dc:Copyrights' to 'dc:Rights'.  See global
variable $dcelements12.

The fix_oeb12() methods does this also, but fix_oeb12_dcmeta() is
usable separately for the case where you want DC metadata elements
with consistent tag names, but don't want them moved from wherever
they are.

=cut

sub fix_oeb12_dcmetatags
{
    my $self = shift;
    die("method fix_oeb12_dcmetatags() called as a procedure") unless(ref $self);

    my $topelement = $$self{twigroot};

    my $meta;
    my $dcmeta;
    my @elements;

    foreach my $dcmetatag (keys %dcelements12)
    {
	@elements = $topelement->descendants(qr/^$dcmetatag$/ix);
	foreach my $el (@elements)
	{
	    $el->set_tag($dcelements12{lc $el->tag})
		if($dcelements12{lc $el->tag});
	}
    }
    return 1;
}

=head2 fix_oeb12_metastructure()

Verifies the existence of <metadata>, <dc-metadata>, and <x-metadata>,
creating the first two (but not <x-metadata>!) as needed, and making
sure that <metadata> is a child of <package>, while <dc-metadata> and
<x-metadata> are children of <metadata>.

Used in fix_oeb12() and fix_mobi().

=cut

sub fix_oeb12_metastructure
{
    my $self = shift;
    die("method fix_oeb12_metastructure() called as a procedure")
        unless(ref $self);

    my $twig = $$self{twig};
    my $twigroot = $$self{twigroot};
    
    print "DEBUG[fix_oeb12_metastructure]\n" if($debug);

    # Sanity checks
    die("Tried to fix OEB1.2 metadata structure in undefined twig!")
        if(!$twig);
    die("Tried to fix OEB1.2 metadata structure in twig with no root!")
        if(!$twigroot);
    die("Tried to fix OEB1.2 metadata structure, but root isn't <package>!")
	if($twigroot->gi ne 'package');

    my $metadata = $twigroot->first_descendant('metadata');
    my $dcmeta;
    my $xmeta;
    my $parent;

    # If <metadata> doesn't exist, we're in a real mess, but go ahead
    # and try to create it anyway
    if(! $metadata)
    {
	print "DEBUG: creating <metadata>\n" if($debug);
	$metadata = $twigroot->insert_new_elt('first_child','metadata');
    }
    
    # If <dc-metadata> doesn't exist, we'll have to create it.
    $dcmeta = $twigroot->first_descendant('dc-metadata');
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
    
    # Make sure that metadata is the first child of the twigroot,
    # which should be <package>
    $parent = $metadata->parent;
    if($parent != $twigroot)
    {
	print "DEBUG: moving <metadata>\n" if($debug);
	$metadata->move('first_child',$twigroot);
    }
    
    # Make sure that x-metadata is a child of metadata, but don't
    # create it if it is missing
    $xmeta = $metadata->first_descendant('x-metadata');
    if($xmeta)
    {
        # Make sure x-metadata belongs to metadata
        $parent = $xmeta->parent;
        if($parent != $metadata)
	{
	    print "DEBUG: moving <x-metadata>\n" if($debug);
	    $xmeta->move('after',$dcmeta);
	}
    }
    return 1;
}


=head2 fix_opf20()

Modifies the OPF data to conform to the OPF 2.0 standard

Specifically, this involves:

=over

=item * moving all of the dc-metadata and x-metadata elements directly underneath <metadata>

=item * removing the <dc-metadata> and <x-metadata> elements themselves

=item * lowercasing the dc-metadata tags (and fixing dc:copyrights to dc:rights)

=item * setting namespaces on dc-metata OPF attributes

=item * setting version and xmlns attributes on <package>

=item * setting xmlns:dc and xmlns:opf on <metadata>

=cut

sub fix_opf20
{
    my $self = shift;
    die("method fix_opf20() called as a procedure") unless(ref $self);

    # Sanity checks
    die("Tried to fix undefined OPF2.0 twig!")
	if(!$$self{twig});
    my $twigroot = $$self{twigroot}
	or die("Tried to fix OPF2.0 twig with no root!");
    die("Can't fix OPF2.0 twig if twigroot isn't <package>!")
	if($twigroot->gi ne 'package');

    print "DEBUG[fix_opf20]\n" if($debug);

    my $metadata = $twigroot->first_descendant('metadata');
    my $parent;
    my @elements;

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
            $el = twig_fix_opf20_atts($el);
	    $el->move('first_child',$metadata);
	}
    }
    
    # Find any <meta> elements anywhere in the package and move them
    # under <x-metadata>.  Force the tag to lowercase.

    @elements = $twigroot->children(qr/^meta$/ix);
    foreach my $el (@elements)
    {
        $el->set_gi(lc $el->gi);
        $el->move('last_child',$metadata);
    }

    # Fix the <package> attributes
    $twigroot->set_atts('version' => '2.0',
			'xmlns' => 'http://www.idpf.org/2007/opf');

    # Fix the <metadata> attributes
    $metadata->set_atts('xmlns:dc' => "http://purl.org/dc/elements/1.1/",
			'xmlns:opf' => "http://www.idpf.org/2007/opf");

    # Clobber the doctype, if present
    $$self{twig}->set_doctype(0,0,0,0);

    # Set the specification
    $$self{spec} = $oebspecs{'OPF20'};

    print "DEBUG: returning from fix_opf20\n" if($debug);
    return 1;
}


=head2 fix_opf20_dcmetatags()

Makes a case-insensitive search for tags matching a known list of DC
metadata elements and corrects the capitalization to the OPF 2.0
standard.  Also corrects 'dc:copyrights' to 'dc:rights'.  See package
variable $dcelements20.

The fix_opf20() methods does this also, but fix_opf20_dcmeta() is
usable separately for the case where you want DC metadata elements
with consistent tag names, but don't want them moved from wherever
they are.

=cut

sub fix_opf20_dcmetatags
{
    my $self = shift;
    die("method fix_opf20_dcmeta() called as a procedure") unless(ref $self);

    my $topelement = $$self{twigroot};

    my $meta;
    my $dcmeta;
    my @elements;

    foreach my $dcmetatag (keys %dcelements20)
    {
	@elements = $topelement->descendants(qr/^$dcmetatag$/ix);
	foreach my $el (@elements)
	{
	    $el->set_tag($dcelements20{lc $el->tag})
		if($dcelements20{lc $el->tag});
	}
    }
    return;
}


=head2 fix_packageid()

Checks the <package> element for the attribute 'unique-identifier',
makes sure that it is mapped to a valid dc:identifier subelement, and
if not, searches those subelements for an identifier to assign, or
creates one if nothing can be found.

=cut

sub fix_packageid
{
    my $self = shift;
    die("method fix_packageid() called as a procedure") unless(ref $self);
    my $twigroot = $$self{twigroot};

    print "DEBUG[fix_packageid]\n" if($debug);

    # Sanity checks
    die("Tried to fix packageid of undefined twig")
	if(!$$self{twig});
    die("Tried to fix packageid of twig with no root")
	if(!$twigroot);
    die("Can't fix packageid if twigroot isn't <package>!")
	if($twigroot->gi ne 'package');

    my $packageid;
    my $meta = $twigroot->first_child('metadata');
    my $element;

    $packageid = $twigroot->att('unique-identifier');
    if(defined $packageid) 
    {
        # Check that the ID maps to a valid identifier
	# If not, undefine it
	print "DEBUG: checking existing packageid '",$packageid,"'\n"
	    if($debug);

	# The twig ID handling system is unreliable, especially when
	# multiple twigs may be existing simultenously.  Use
	# XML::Twig->first_elt instead of XML::Twig->elt_id, even
	# though it's slower.
	#$element = $$self{twig}->elt_id($packageid);
	$element = $$self{twig}->first_elt("*[\@id='$packageid']");
    
	if($element)
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
	$packageid = $self->search_knownuids;
    }

    # If no unique ID found so far, start searching known schemes
    if(!defined $packageid)
    {
	$packageid = $self->search_knownuidschemes;
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
    return 1;
}


=head2 fix_spine()

Fixes problems with the OPF spine, specifically:

=over

=item Moves all <itemref> elements underneath <spine>, creating
<spine> if necessary.

=back

=cut

sub fix_spine
{
    my $self = shift;
    die("method fix_spine() called as a procedure") unless(ref $self);
    my $twig = $$self{twig};
    my $twigroot = $$self{twigroot};
    
    print "DEBUG[fix_spine]\n" if($debug);

    my $spine = $twigroot->first_descendant('spine');
    my @elements;
    my $parent;

    # Sanity checks
    die("Tried to fix undefined twig to OEB1.2!") if(!$twig);
    die("Tried to fix twig with no root to OEB1.2!") if(!$twigroot);
    die("Can't fix OEB1.2 if twigroot isn't <package>!")
	if($twigroot->gi ne 'package');

    # If <spine> doesn't exist, create it
    if(! $spine)
    {
	print "DEBUG: creating <spine>\n" if($debug);
	$spine = $twigroot->insert_new_elt('last_child','spine');
    }

    # Make sure that the manifest is the first child of the twigroot,
    # which should be <package>
    $parent = $spine->parent;
    if($parent != $twigroot)
    {
	print "DEBUG: moving <spine>\n" if($debug);
	$spine->move('last_child',$twigroot);
    }

    @elements = $twigroot->descendants(qr/^itemref$/ix);
    foreach my $el (@elements)
    {
        if(!$el->att('idref'))
        {
            # No idref means it's broken.
            # Leave it alone, but log a warning
            $self->add_warnings("fix_spine(): <itemref> with no idref -- skipping");
            print "DEBUG: skipping itemref with no idref\n" if($debug);
            next;
        }
        print "DEBUG: processing itemref '",$el->att('idref'),"')\n"
            if($debug > 1);
        $el->move('last_child',$spine);
    }

    return 1;
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

sub gen_epub    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my ($filename) = @_;
    die("method gen_epub() called as a procedure") unless(ref $self);

    my $zip = Archive::Zip->new();
    my $member;

    $self->epubinit();

    if(! $$self{opffile} )
    {
	$self->add_errors(
	    "Cannot create epub without an OPF (did you forget to init?)");
	return;
    }
    if(! -f $$self{opffile} )
    {
	$self->add_errors(
	    sprintf("OPF '%s' does not exist (did you forget to save?)",
		    $$self{opffile})
	    );
	return;
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
	    error("No items found in manifest!");
	    return;
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
	error(sprintf("Failed to create epub as '%s'",$filename));
	return;
    }
    return 1;
}


=head2 manifest_hrefs()

Returns a list of all of the hrefs in the current OPF manifest, or the
empty list if none are found.

=cut

sub manifest_hrefs
{
    my $self = shift;
    die("method manifest_hrefs() called as a procedure") unless(ref $self);

    print "DEBUG[manifest_hrefs]\n" if($debug);

    my @items;
    my $href;
    my $manifest;
    my @retval = ();

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
	push(@retval,$href) if($href);
    }
    return @retval;
}


=head2 print_warnings()

Prints the current list of warnings to STDERR.

=cut

sub print_warnings
{
    my $self = shift;
    die("method print_warnings() called as a procedure") unless(ref $self);

    my $warningref = $$self{warnings};

    print "DEBUG[print_warnings]\n" if($debug);

    if(!$self->warnings)
    {
	print "DEBUG: no warnings found!\n" if($debug);
	return 1;
    }
    
    
    foreach my $warning (@$warningref)
    {
	print "WARNING: ",$warning,"\n";
    }
    return 1;
}


=head2 print_opf()

Prints the OPF file to the default filehandle

=cut

sub print_opf
{
    my $self = shift;
    my $filehandle = shift;
    die("method print_opf() called as a procedure") unless(ref $self);

    if(defined $filehandle) { $$self{twig}->print($filehandle); }
    else { $$self{twig}->print; }
    return 1;
}

=head2 save()

Saves the OPF file to disk

=cut

sub save
{
    my $self = shift;
    die("method save() called as a procedure") unless(ref $self);

    my $opffile;
    
    if(!open($opffile,">",$self->{opffile}))
    {
	add_errors(sprintf("Could not open '%s' to save to!",$self->{opffile}));
	return;
    }
    $self->{twig}->print(\*$opffile);

    if(!close($opffile))
    {
	add_errors(sprintf("Failure while closing '%s'!",$self->{opffile}));
	return;
    }
    return 1;
}


=head2 search_knownuids($gi)

Searches an XML twig for the first element with an ID matching known
UID IDs

If set, $gi must match the generic identifier (tag) of the element
for it to be returned, otherwise 'dc:identifier'

=head3 Arguments:

=over

=item $gi: generic identifier (tag) to check against

If set, the element must match this tag for the ID to be returned.

Default value: 'dc:identifier' (case-insensitive match)

=back

Returns the ID if a match is found, undef otherwise

=cut

sub search_knownuids    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my ($gi) = @_;
    if(!defined $gi) { $gi = 'dc:identifier'; }
    die("method search_knownuids() called as a procedure") unless(ref $self);

    print "DEBUG:[search_knownuids(",$gi,")]\n" if($debug);

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

    my $element;

    my $retval = undef;

    foreach my $id (@knownuids)
    {
	# The twig ID handling system is unreliable, especially when
	# multiple twigs may be existing simultenously.  Use
	# XML::Twig->first_elt instead of XML::Twig->elt_id, even
	# though it's slower.
	#$element = $$self{twig}->elt_id($id);
	$element = $$self{twig}->first_elt("*[\@id='$id']");

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


=head3 sub search_knownuidschemes()

Searches descendants of an XML twig element for the first
<dc:identifier> or <dc:Identifier> subelement with the attribute
'scheme' or 'opf:scheme' matching a known list of schemes for unique
IDs

NOTE: this is NOT a case-insensitive search!  If you have to deal with
really bizarre input, make sure that you run fix_oeb12() or
fix_opf20() before calling fix_packageid() or fix_misc().

Returns the ID if a match is found, undef otherwise.

=cut

sub search_knownuidschemes   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my ($gi) = @_;
    if(!defined $gi) { $gi = 'dc:identifier'; }
    die("method search_knownuidschemes() called as a procedure")
        unless(ref $self);

    my $topelement = $$self{twigroot}->first_descendant('metadata');

    if(!$topelement)
    {
	add_error("search_knownuidschemes(): no metadata element present!");
	return;
    }

    my @knownuidschemes = qw (
	GUID
	UUID
	FWID
	ISBN
	);

    # Creating a regexp to search on works, but doesn't let you
    # specify priority.  For that, you really do have to loop.
#    my $schemeregexp = "(" . join('|',@knownuidschemes) . ")";

    my @elems;
    my $id;

    my $retval = undef;

    print "DEBUG[twig_search_knownuidschemes]\n" if($debug);

    foreach my $scheme (@knownuidschemes)
    {
	print "DEBUG: searching for scheme='",$scheme,"'\n" if($debug);
	@elems = $topelement->descendants("dc:identifier[\@opf:scheme='$scheme']");
	push(@elems,$topelement->descendants("dc:identifier[\@scheme='$scheme']"));
	push(@elems,$topelement->descendants("dc:Identifier[\@opf:scheme='$scheme']"));
	push(@elems,$topelement->descendants("dc:Identifier[\@scheme='$scheme']"));
	foreach my $elem (@elems)
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
	} # foreach my $elem (@elems)
	last if(defined $retval);
    }
    print "DEBUG: returning from twig_search_knownuidschemes\n" if($debug);
    return $retval;
}


########## PROCEDURES ##########

=head1 PROCEDURES

All procedures are exportable, but none are exported by default.

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
    my $containerfh;

    if($opffile eq '') { return; }

    if(-e 'META-INF')
    {
	if(! -d 'META-INF')
	{
	    unlink('META-INF') or return;
	    mkdir('META-INF') or return;
	}
    }
    else { mkdir('META-INF') or return; }

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

    open($containerfh,'>','META-INF/container.xml') or die;
    $twig->print(\*$containerfh);
    close($containerfh);
    return $twig;
}


=head2 create_epub_mimetype ()

Creates a file named 'mimetype' in the current working directory
containing 'application/epub+zip' (no trailing newline)

Destroys and overwrites that file if it exists.

Returns the mimetype string if successful, undef otherwise.

=cut

sub create_epub_mimetype ()  ## no critic (ProhibitSubroutinePrototypes)
{
    my $mimetype = "application/epub+zip";
    my $fh;
    
    open($fh,">",'mimetype') or return;
    print $fh,$mimetype;
    close($fh);

    return $mimetype;
}


=head2 fix_datestring($datestring)

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

=head3 Returns $fixeddate

=over

=item $fixeddate : the corrected string, or undef on failure

=back

=cut

sub fix_datestring
{
    my ($datestring) = @_;
    return unless($datestring);

    my $date;
    my ($year,$month,$day);
    my $fixeddate;

    print "DEBUG[fix_date]: '",$datestring,"'\n" if($debug);

    $_ = $datestring;

    print "DEBUG: checking M(M)/D(D)/YYYY\n" if($debug > 1);
    if(( ($month,$day,$year) = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/x ) == 3)
    {
	# We have a XX/XX/XXXX datestring
	print "DEBUG: found '",$month,"/",$day,"/",$year,"'\n" if($debug > 1);
	($year,$month,$day) = ymd_validate($year,$month,$day);
	if($year)
	{
	    $fixeddate = $year;
	    $fixeddate .= sprintf("-%02u",$month)
		unless( ($month == 1) && ($day == 1) );
	    $fixeddate .= sprintf("-%02u",$day) unless($day == 1);
	    print "DEBUG: returning '",$fixeddate,"'\n" if($debug > 1);
	    return $fixeddate;
	}
    }

    print "DEBUG: checking M(M)/YYYY\n" if($debug > 1);
    if(( ($month,$year) = /^(\d{1,2})\/(\d{4})$/x ) == 2)
    {
	# We have a XX/XXXX datestring
	print "DEBUG: found '",$month,"/",$year,"'\n" if($debug > 1);
	if($month <= 12)
	{
	    # We probably have MM/YYYY
	    $fixeddate = sprintf("%04u-%02u",$year,$month);
	    print "DEBUG: returning '",$fixeddate,"'\n" if($debug > 1);
	    return $fixeddate;
	}
    }

    # These regexps will reduce '2009-xx-01' to just 2009
    # We don't want this, so don't use them.
#    ($year,$month,$day) = /(\d{4})-?(\d{2})?-?(\d{2})?/;
#    ($year,$month,$day) = /(\d{4})(?:-?(\d{2})-?(\d{2}))?/;

    # Force exact match)
    print "DEBUG: checking YYYY-MM-DD\n" if($debug > 1);
    ($year,$month,$day) = /^(\d{4})-(\d{2})-(\d{2})$/x;
    ($year,$month,$day) = ymd_validate($year,$month,$day);

    if(!$year)
    {
	print "DEBUG: checking YYYYMMDD\n" if($debug > 1);
	($year,$month,$day) = /^(\d{4})(\d{2})(\d{2})$/x;
	($year,$month,$day) = ymd_validate($year,$month,$day);
    }

    if(!$year)
    {
	print "DEBUG: checking YYYY-M(M)\n" if($debug > 1);
	($year,$month) = /^(\d{4})-(\d{1,2})$/x;
	($year,$month) = ymd_validate($year,$month,undef);
    }

    if(!$year)
    {
	print "DEBUG: checking YYYY\n" if($debug > 1);
	($year) = /^(\d{4})$/x;
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
	$fixeddate = sprintf("%04u",$year);
	if($month)
	{
	    print "month=",$month," " if($debug);
	    $fixeddate .= sprintf("-%02u",$month);
	    if($day)
	    {
		print "day=",$day if($debug);
		$fixeddate .= sprintf("-%02u",$day);
	    }
	}
	print "\n" if($debug);
	print "DEBUG: returning '",$fixeddate,"'\n" if($debug);
	return $fixeddate if($fixeddate);
    }

    if(!$year)
    {
	printf("fix_date: didn't find a valid date in '%s'!",$datestring)
	    if($debug > 1);
	return;
    }
    elsif($debug)
    {
	print "DEBUG: found ",sprintf("04u",$year);
	print sprintf("-02u",$month) if($month);
	print sprintf("-02u",$day),"\n" if($day);
    }

    $fixeddate = sprintf("%04u",$year);
    $fixeddate .= sprintf("-%02u-%02u",$month,$day);
    return $fixeddate;
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
	$twig->parsefile($container) or return;
	$rootfile = $twig->root->first_descendant('rootfile');
	return if(!defined $rootfile);
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
    my $PROCSTATM;
      
    if(!open($PROCSTATM,"<","/proc/$$/statm"))
    {
	print "[",$label,"]: " if(defined $label);
	print "Couldn't open /proc/$$/statm [$!]\n";
    }

    @mem = split(/\s+/,<$PROCSTATM>);
    close($PROCSTATM);

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

sub split_metadata
{
    my ($metahtmlfile) = @_;

    my $metafile;
    my $metastring;
    my $htmlfile;

    my ($filebase,$filedir,$fileext);
    my ($fh_metahtml,$fh_meta,$fh_html);
    
    ($filebase,$filedir,$fileext) = fileparse($metahtmlfile,'\.\w+$');
    $metafile = $filebase . ".opf";
    $htmlfile = $filebase . "-html.html";

    open($fh_metahtml,"<",$metahtmlfile)
	or die("Failed to open ",$metahtmlfile," for reading!\n");
    open($fh_meta,">",$metafile)
	or die("Failed to open ",$metafile," for writing!\n");
    open($fh_html,">",$htmlfile)
	or die("Failed to open ",$htmlfile," for writing!\n");


    # Preload the return value with the OPF headers
    print $fh_meta $utf8xmldec,$oeb12doctype,"<package>\n";
    #print $fh_meta $utf8xmldec,$opf20package;

    # Finding and removing all of the metadata requires that the
    # entire thing be handled as one slurped string, so temporarily
    # undefine the perl delimiter
    #
    # Since multiple <metadata> sections may be present, cannot use
    # </metadata> as a delimiter.
    local $/;
    while(<$fh_metahtml>)
    {
	($metastring) = /(<metadata>.*<\/metadata>)/x;
	if(!defined $metastring) { last; }
	print $fh_meta $metastring,"\n";
	s/(<metadata>.*<\/metadata>)//x;
	print $fh_html $_,"\n";
    }
    print $fh_meta "</package>\n";

    close($fh_html);
    close($fh_meta);
    close($fh_metahtml);

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


=begin comment

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

=end comment

=cut


=begin comment

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

=end comment

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
    my ($infile,$outfile) = @_;
    my @configopt = ();
    my $retval;

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


=head2 twig_create_uuid($gi)

Creates an unlinked element with the specified gi (tag), and then
assigns it the id and scheme attributes 'UUID'.

head3 Arguments

=over

=item  $gi : The gi (tag) to use for the element

Default: 'dc:identifier'

=back

Returns the element.

=cut

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


=head2 twig_fix_oeb12_atts($element)

Checks the attributes in a twig element to see if they match OPF names
with an opf: namespace, and if so, removes the namespace.  Used by the
fix_oeb12() method.

Takes as a sole argument a twig element.

Returns that element with the modified attributes, or undef if the
element didn't exist.  Returns an unmodified element if both att and
opf:att exist.

=cut

sub twig_fix_oeb12_atts
{
    my ($element) = @_;
    return unless($element);

    my %opfatts_no_ns = (
        "opf:role" => "role",
        "opf:file-as" => "file-as",
        "opf:scheme" => "scheme",
        "opf:event" => "event"
        );

    print "DEBUG[twig_fix_opf12_atts]\n" if($debug);

    foreach my $att ($element->att_names)
    {
        print "DEBUG:   checking attribute '",$att,"'\n" if($debug);
        if($opfatts_no_ns{$att})
        {
            # If the opf:att attribute properly exists already, do nothing.
            if($element->att($opfatts_no_ns{att}))
            {
                print "DEBUG:   found both '",$att,
                "' and '",$opfatts_no_ns{$att},"' -- skipping.\n"
                    if($debug);
                next;
            }
            print "DEBUG:   changing attribute '",$att,
            "' => '",$opfatts_no_ns{$att},"'\n"
                if($debug);
            $element->change_att_name($att,$opfatts_no_ns{$att});
        }
    }
    return $element;
}

=head2 twig_fix_opf20_atts($element)

Checks the attributes in a twig element to see if they match OPF
names, and if so, prepends the OPF namespace.  Used by the fix_opf20()
method.

Takes as a sole argument a twig element.

Returns that element with the modified attributes, or undef if the
element didn't exist.

=cut

sub twig_fix_opf20_atts
{
    my ($element) = @_;
    return unless($element);

    my %opfatts_ns = (
        "role" => "opf:role",
        "file-as" => "opf:file-as",
        "scheme" => "opf:scheme",
        "event" => "opf:event"
        );

    print "DEBUG[twig_fix_opf20_atts]\n" if($debug);

    foreach my $att ($element->att_names)
    {
        print "DEBUG:   checking attribute '",$att,"'\n" if($debug);
        if($opfatts_ns{$att})
        {
            # If the opf:att attribute properly exists already, do nothing.
            if($element->att($opfatts_ns{att}))
            {
                print "DEBUG:   found both '",$att,"' and '",$opfatts_ns{$att},
                "' -- skipping.\n"
                    if($debug);
                next;
            }
            print "DEBUG:   changing attribute '",$att,"' => '",$opfatts_ns{$att},"'\n"
                if($debug);
            $element->change_att_name($att,$opfatts_ns{$att});
        }
    }
    return $element;
}

=head2 ymd_validate($year,$month,$day)

Make sure month and day have valid values.  Return the passed values
if they are, return 3 undefs if not.  Testing of month or day can be
skipped by passing undef in that spot.

=cut

sub ymd_validate
{
    my ($year,$month,$day) = @_;

    return (undef,undef,undef) unless($year);

    if($month)
    {
	return (undef,undef,undef) if($month > 12);
	if($day)
	{
	    if(!eval { timelocal(0,0,0,$day,$month-1,$year); })
	    {
		print "DEBUG: timelocal validation failed for year=",
		$year," month=",$month," day=",$day,"\n" if($debug);
		return (undef,undef,undef);
	    }
	}
	return ($year,$month,$day);
    }

    # We don't have a month.  If we *do* have a day, the result is
    # broken, so send back the undefs.
    return (undef,undef,undef) if($day);
    return ($year,undef,undef);
}


########## END CODE ##########

=head1 EXAMPLE

 package EBook::Tools qw(split_metadata system_tidy_xml);
 $EBook::Tools::tidysafety = 2;

 my $opffile = split_metadata('ebook.html');
 my $otheropffile = 'alternate.opf';
 my $retval = system_tidy_xml($opffile,'tidy-backup.xml');
 my $ebook = EBook::Tools->new($opffile);
 $ebook->fixopf20;
 $ebook->fixmisc;
 $ebook->print;
 $ebook->save;

 $ebook->init($otheropffile);
 $ebook->fixoeb12;
 $ebook->save;

=head1 BUGS/TODO

=over

=item * $datapath points to a relatively useless location by default.
While nothing very useful is stored there yet, it needs to be fixed to
a usable system directory or removed entirely.

=item * It might be better to use sysread / index / substr / syswrite in
&split_metadata to handle the split in 10k chunks, to avoid massive
memory usage on large files.

This may not be worth the effort, since the average size for most
books is less than 500k, and the largest books are rarely if ever over
10M.

=item * fix_manifest doesn't actually check links yet

=item * No mechanism for generating NCX files.

=item * Need a simple script to generate an OPF file from a single
text/html file

=item * The only generator is currently for .epub books.  PDF,
PalmDoc, Mobipocket, and iSiloX are eventually planned.

=item * There are no import/extraction tools yet.  Extraction from
PalmDoc, eReader, and Mobipocket is eventually planned.

=item * Although I like keeping warnings associated with the ebook
object, it may be better to throw exceptions on errors and catch them
later.  This probably won't be implemented until it bites someone who
complains, though.

=item * Contemplate Carp's croak() instead of die().

=item * Filehandle naming conventions haven't been standardized.

=item * Unit tests are very incomplete

=back

=head1 AUTHOR

Zed Pobre <zed@debian.org>

=head1 COPYRIGHT

Copyright 2008 Zed Pobre

Licensed to the public under the terms of the GNU GPL, version 2

=cut

1;
