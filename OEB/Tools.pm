package OEB::Tools;

#
# A collection of tools to manipulate documents in Open E-book
# formats.
#
# Copyright 2008 Zed Pobre
# Licensed to the public under the terms of the GNU GPL, version 2
#
# TODO:
# * fix broken dc:date formats
# * sub for sort_children to sort on GI + ID
# * Use OPS2.0 instead of OEB1.2 after all
#   * This means creating a fix_ops20 sub 
#

use warnings;
use strict;

our $debug = 0;

require Exporter;
our @ISA = ("Exporter");

our @EXPORT_OK = qw (
    &create_epub_container
    &create_epub_mimetype
    &get_container_rootfile
    &print_memory
    &split_metadata
    &system_tidy_xml
    &system_tidy_xhtml
    &twig_add_document
    &twig_delete_meta_filepos
    &twig_fix_lowercase_dcmeta
    &twig_fix_packageid
);

# OSSP::UUID will provide Data::UUID on systems such as Debian that do
# not distribute the original Data::UUID.
use Data::UUID;

use Archive::Zip qw( :CONSTANTS :ERROR_CODES );

use File::Basename 'fileparse';
use FindBin;
use HTML::Tidy;
use XML::Twig::XPath;

our $datapath = $FindBin::RealBin . "/OEB";

our $mobi2htmlcmd = 'mobi2html';
our $tidycmd = 'tidy'; # Specify full pathname if not on path
our $tidyconfig = 'tidy-oeb.conf';
our $tidyxhtmlerrors = 'tidyxhtml-errors.txt';
our $tidyxmlerrors = 'tidyxml-errors.txt';
our $tidysafety = 1;
# $tidysafety values:
# <1: no checks performed, no error files kept, works like a clean tidy -m
#     This setting is DANGEROUS
#  1: Overwrites original file if there were no errors, but even if
#     there were warnings.  Keeps a log of errors, but not warnings.
#  2: Overwrites original file if there were no errors, but even if
#     there were warnings.  Keeps a log of both errors and warnings.
#  3: Overwrites original file only if there were no errors or
#     warnings.  Keeps a log of both errors and warnings.
# 4+: Never overwrites original file.  Keeps a log of both errors and
#     warnings.



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
    "dc:Rights"      => "dc:rights"
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
    "dc:Rights"      => "dc:rights"
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
    "dc:Rights"      => "dc:Rights"
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

sub new
{
    my $self = shift;
    my $class = ref($self) || $self;
    $self = {
	opffile => undef,
	spec => undef,
	twig => XML::Twig->new(
	    keep_atts_order => 1,
	    output_encoding => 'utf-8',
	    pretty_print => 'record'
	    ),
	twigroot => undef,
        twigmeta => undef,
	error => undef,
	@_
    };
    bless($self, $class);
    return $self;
}


sub init
{
    my $self = shift;
    my ($filename) = @_;

    if($filename) { $$self{opffile} = $filename; }
    if(! $$self{opffile}) { $$self{opffile} = get_container_rootfile(); }

    if(! $$self{opffile})
    {
	die("Could not initialize OEB object!")
    }

    $$self{twig}->parsefile($$self{opffile});
    $$self{twigroot} = $$self{twig}->root;
    $$self{twigmeta} = $$self{twigroot}->first_child('metadata');

    return $self;
}

sub add_document
{
    my $self = shift;
    my ($id,$href,$mediatype) = @_;
    twig_add_document(\$$self{twig},$id,$href,$mediatype);
    return $self;
}

sub epubinit ()
{
    my $self = shift;
    create_epub_mimetype();
    create_epub_container($$self{opffile});
    return;
}

sub fixmisc ()
{
    my $self = shift;

    # Delete extra metadata
    twig_delete_meta_filepos(\$$self{twig});
    # Make sure the package ID is valid, and assign it if not
    twig_fix_packageid(\$$self{twig});
    # Fix miscellaneous Mobipocket-related issues
    twig_fix_mobi(\$$self{twig});
    return $self;
}

sub fixopf20 ()
{
    my $self = shift;

    twig_fix_opf20(\$$self{twig});
    $$self{spec} = $oebspecs{'OPF20'};
    return $self;
}

sub fixoeb12 ()
{
    my $self = shift;

    # Make the twig conform to the OEB 1.2 standard
    twig_fix_oeb12(\$$self{twig});
    $$self{spec} = $oebspecs{'OEB12'};
    return $self;
}

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

sub manifest_hrefs ()
{
    my $self = shift;

    my @items;
    my $href;
    my $manifest;
    my @retval;

    $manifest = $$self{twigroot}->first_child('manifest');
    if(! $manifest) { return @retval; }

    @items = $manifest->descendants('item');
    foreach my $item (@items)
    {
	$href = $item->att('href');
	push(@retval,$href);
    }
    return @retval;
}

sub printopf ()
{
    my $self = shift;
    my $filehandle = shift;

    if(defined $filehandle) { $$self{twig}->print($filehandle); }
    else { $$self{twig}->print; }
    return;
}

sub save ()
{
    my $self = shift;
    
    open(OPFFILE,">",$$self{opffile})
	or die("Could not open ",$$self{opffile}," to save to!");
    $$self{twig}->print(\*OPFFILE);
    close(OPFFILE) or die ("Failure while closing ",$$self{opffile},"!");
    return $self;
}

sub twig ()
{
    my $self = shift;
    return $$self{twig};
}

sub twigroot ()
{
    my $self = shift;
    return $$self{twig}->root;
}

########## GENERAL SUBS ##########

#
# sub create_epub_container($opffile)
#
# Creates the XML file META-INF/container.xml pointing to the
# specified OPF file.
#
# Creates the META-INF directory if necessary.  Will destroy any
# non-directory file named 'META-INF' in the current directory.
#
# Arguments:
#   $opffile : The OPF filename (and path, if necessary) to use in the
#	       container.  If not specified, looks for a sole OPF file in the
#	       current working directory.  Fails if more than one is found.
#
# Returns a twig representing the container data if successful, undef
# otherwise
#
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


#
# sub create_epub_mimetype ()
#
# Creates a file named 'mimetype' in the current working directory
# containing 'application/epub+zip' (no trailing newline)
#
# Destroys and overwrites that file if it exists.
#
# Arguments: none
# Returns the mimetype string if successful, undef otherwise.
#
sub create_epub_mimetype ()
{
    my $mimetype = "application/epub+zip";
    
    open(EPUBMIMETYPE,">",'mimetype') or return undef;
    print EPUBMIMETYPE $mimetype;
    close(EPUBMIMETYPE);

    return $mimetype;
}


#
# sub get_container_rootfile($container)
#
# Opens and parses an OPS/epub container, extracting the 'full-path'
# attribute of element 'rootfile'
#
# Arguments:
#   $container : the OPS container to parse.  Defaults to
#                'META-INF/container.xml'
#
# Returns a string containing the rootfile on success, undef on failure.
#
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

#
# sub print_memory($label)
#
# Checks /proc/$PID/statm and prints out a line to STDERR showing the
# current memory usage
#
# Arguments: 
#   $label : If defined, will be output along with the memory usage.
#            Intended to be used to 
# Returns nothing
#
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


#
# sub split_metadata($mobihtmlfile)
#
# Takes a psuedo-HTML file output by mobi2html and splits out the
# metadata values into an XML file in preparation for conversion to
# OPF.  Rewrites the html file without the metadata.
#
# If tidy cannot be run, split_metadata MUST output the OEB 1.2
# doctype (and thus not conform to OPF 2.0, which doesn't use a dtd at
# all), as the the metadata values may contain HTML entities and Tidy
# is needed to convert them to UTF-8 characters
#
# Arguments:
#   $mobihtmlfile : The filename of the pseudo-HTML file
#
# Returns:
#   1: a string containing the XML
#   2: the base filename with the final extension stripped
# Dies horribly on failure
#
# TODO: use sysread / index / substr / syswrite to handle the split in
# 10k chunks, to avoid massive memory usage on large files
#
sub split_metadata ( $ )
{
    my ($mobihtmlfile) = @_;

    my $delim = $/;

    my $metafile;
    my $metastring;
    my $htmlfile;

    my $filebase;
    my $filedir;
    my $fileext;

    my $tidy; # boolean to check if tidy is available

    my $retval;

    
    ($filebase,$filedir,$fileext) = fileparse($mobihtmlfile,'\.\w+$');
    $metafile = $filebase . ".xml";
    $htmlfile = $filebase . "-html.html";

    open(MOBIHTML,"<",$mobihtmlfile)
	or die("Failed to open ",$mobihtmlfile," for reading!\n");

    open(META,">",$metafile)
	or die("Failed to open ",$metafile," for writing!\n");

    open(HTML,">",$htmlfile)
	or die("Failed to open ",$htmlfile," for writing!\n");


    # Preload the return value with the OPF headers
    print META $utf8xmldec,$oeb12doctype,"<package>\n";

    # Finding and removing all of the metadata requires that the
    # entire thing be handled as one slurped string, so temporarily
    # undefine the perl delimiter
    #
    # Since multiple <metadata> sections may be present, cannot use
    # </metadata> as a delimiter.
    undef $/;
    while(<MOBIHTML>)
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
    close(MOBIHTML);

    system_tidy_xml($metafile);
#    system_tidy_xhtml($htmlfile,$mobihtmlfile);
    rename($htmlfile,$mobihtmlfile)
	or die("Failed to rename ",$htmlfile," to ",$mobihtmlfile,"!\n");

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
#                Default value: 'dc:Identifier'
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
    if(!defined $condition) { $condition = 'dc:Identifier'; }

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
#         Default: 'dc:Identifier'
#
# Returns the element.
#
sub twig_create_uuid
{
    my ($gi) = @_;
    my $element;

    if(!defined $gi) { $gi = 'dc:Identifier'; }
    
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
    my @elements;

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

    # Set the correct tag name and move it into <dc-metadata>
    foreach my $dcmetatag (keys %dcelements12)
    {
	@elements = $twigroot->descendants($dcmetatag);
	foreach my $el (@elements)
	{
	    $el->set_gi($dcelements12{$dcmetatag});
	    $el->move('last_child',$dcmeta);
	}
    }
    # Deal with any remaining elements under <metadata>
    @elements = $metadata->children(qr/!(dc-metadata|x-metadata)/);
    if(@elements)
    {
	print "DEBUG: elements found: ";
	foreach my $el (@elements) { print $el->gi," "; }
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

    print "DEBUG[twig_fix_ops20]\n" if($debug);

    # Sanity checks
    die("Tried to fix undefined OPS2.0 twig!")
	if(!$$twigref);
    my $twigroot = $$twigref->root
	or die("Tried to fix OPS2.0 twig with no root!");
    die("Can't fix OPS2.0 twig if twigroot isn't <package>!")
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
    foreach my $dcmetatag (keys %dcelements12to20)
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
# for it to be returned, otherwise 'dc:Identifier'
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
# sub twig_search_knownuidschemes($topelement,$gi)
#
# Searches descendants of an XML twig element for the first subelement
# with the attribute 'scheme' matching a known list of schemes for
# unique IDs
#
# If set, $gi must match the generic identifier (tag) of the element
# for it to be returned, otherwise 'dc:Identifier'
#
# Arguments:
#   $topelement : twig element to start descendant search
#   $gi: generic identifier (tag) to check against
#        Default value: 'dc:identifier' (case-insensitive match)
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
    my $scheme;

    my @elems;
    my $elem;
    my $id;

    my $retval = undef;

    print "DEBUG[twig_search_knownuidschemes]\n";
    foreach $scheme (@knownuidschemes)
    {
	print "DEBUG: searching for scheme='",$scheme,"'\n" if($debug);
	@elems = $topelement->descendants(qr/dc:identifier[\@scheme='$scheme']/i);
	foreach $elem (@elems)
	{
	    if(defined $elem)
	    {
		if($scheme eq 'FWID')
		{
		    # Fictionwise has a screwy output that sets the ID
		    # equal to the text.  Fix the ID to just be 'FWID'
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

#
# sub system_tidy_xml($xmlfile)
#
# Runs tidy on an XML file modifying in place
# The tidy program must be in the path
#
# Arguments:
#   $xmlfile : The filename to tidy
#
# Global variables:
#   $datapath : the location of the config files
#   $tidycmd : the location of the tidy executable
#   $tidyconfig : the name of the tidy config file to use
#   $tidyxmlerrors : the filename to use to output errors
#   $tidysafety: the safety factor to use
#
# Returns the return value from tidy
# Dies horribly if the return value is unexpected
#
# Expected return codes from tidy:
# 0 - no errors
# 1 - warnings only (leave errorfile)
# 2 - errors (leave errorfile and htmlfile)
#
sub system_tidy_xml
{
    my $infile;
    my $outfile;
    my @configopt = ();
    my $retval;

    ($infile,$outfile) = @_;
    
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


#
# sub system_tidy_xhtml($infile,$outfile)
#
# Runs tidy on a XHTML file semi-safely (using a secondary file)
# Converts HTML to XHTML if necessary
# The tidy program must be in the path
#
# Arguments:
#  $htmlfile : The filename to tidy
#
# Global variables:
#   $tidycmd : the location of the tidy executable
#   $tidyconfig : the location of the config file to use
#   $tidyxhtmlerrors : the filename to use to output errors
#   $tidysafety: the safety factor to use
#
# Returns the return value from tidy
# Dies horribly if the return value is unexpected
#
# Expected return codes from tidy:
# 0 - no errors
# 1 - warnings only (leave errorfile)
# 2 - errors (leave errorfile and htmlfile)
#
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
