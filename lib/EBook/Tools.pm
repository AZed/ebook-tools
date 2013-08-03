package EBook::Tools;
use warnings; use strict; use utf8;
use v5.10.1; # Needed for smart-match operator and given/when
use English qw( -no_match_vars );
use version 0.74; our $VERSION = qv("0.4.9");

#use warnings::unused;

# Perl Critic overrides:
## no critic (Package variable)
# RequireBriefOpen seems to be way too brief to be useful
## no critic (RequireBriefOpen)
# Double-sigils are needed for lexical filehandles in clear print statements
## no critic (Double-sigil dereference)
our $debug = 0;



=head1 NAME

EBook::Tools - Object class for manipulating and generating E-books


=head1 DESCRIPTION

This module provides an object interface and a number of related
procedures intended to create or modify documents centered around the
International Digital Publishing Forum (IDPF) standards, currently
both OEBPS v1.2 and OPS/OPF v2.0.

=cut

=head1 SYNOPSIS

 use EBook::Tools qw(split_metadata system_tidy_xml);
 $EBook::Tools::tidysafety = 2;

 my $opffile = split_metadata('ebook.html');
 my $otheropffile = 'alternate.opf';
 my $retval = system_tidy_xml($opffile,'tidy-backup.xml');
 my $ebook = EBook::Tools->new($opffile);
 $ebook->fix_opf20;
 $ebook->fix_misc;
 $ebook->print;
 $ebook->save;

 $ebook->init($otheropffile);
 $ebook->fix_oeb12;
 $ebook->gen_epub;


=head1 DEPENDENCIES

=head2 Perl Modules

=over

=item Archive::Zip

=item Data::UUID (or OSSP::UUID)

=item Date::Manip

Note that Date::Manip will die on MS Windows system unless the
TZ environment variable is set in a specific manner. See:

http://search.cpan.org/perldoc?Date::Manip#TIME_ZONES

=item File::MimeInfo

=item HTML::Parser

=item Lingua::EN::NameParse

=item Tie::IxHash

=item Time::Local

=item XML::Twig

=back

=head2 Other Programs

=over

=item Tidy

The command "tidy" needs to be available, and ideally on the path.  If
it isn't on the path, package variable L</$tidycmd> can be set to its
absolute path.  If tidy cannot be found, L</system_tidy_xml()> and
L</system_tidy_xhtml()> will be nonfunctional.

=back

=cut


require Exporter;
use base qw(Exporter);

our @EXPORT_OK;
@EXPORT_OK = qw (
    &create_epub_container
    &create_epub_mimetype
    &debug
    &excerpt_line
    &fix_datestring
    &find_in_path
    &find_links
    &find_opffile
    &hexstring
    &get_container_rootfile
    &print_memory
    &split_metadata
    &split_pre
    &strip_script
    &system_result
    &system_tidy_xml
    &system_tidy_xhtml
    &trim
    &twigelt_create_uuid
    &twigelt_fix_oeb12_atts
    &twigelt_fix_opf20_atts
    &twigelt_is_author
    &usedir
    &userconfigdir
    &ymd_validate
    );
our %EXPORT_TAGS = ('all' => [@EXPORT_OK]);

# OSSP::UUID will provide Data::UUID on systems such as Debian that do
# not distribute the original Data::UUID.
use Data::UUID;

use Archive::Zip qw( :CONSTANTS :ERROR_CODES );
use Carp;
use Cwd qw(getcwd realpath);
use Date::Manip;
use File::Basename qw(basename dirname fileparse);
# File::MimeInfo::Magic gets *.css right, but detects all html as
# text/html, even if it has an XML header.
use File::MimeInfo::Magic;
# File::MMagic gets text/xml right (though it still doesn't properly
# detect XHTML), but detects CSS as x-system, and has a number of
# other weird bugs.
#use File::MMagic;
use File::Path;     # Exports 'mkpath' and 'rmtree'
use File::Temp;
use HTML::Entities qw(decode_entities _decode_entities %entity2char);
#use HTML::Tidy;
use Lingua::EN::NameParse qw(case_surname);
use Tie::IxHash;
use Time::Local;
use XML::Twig;

=head1 CONFIGURABLE PACKAGE VARIABLES

=over

=item C<%dcelements12>

A tied IxHash mapping an all-lowercase list of Dublin Core metadata
element names to the capitalization dictated by the OEB 1.2
specification, used by the fix_oeb12() and fix_oeb12_dcmeta() methods.
Changing the tags in this list will change the tags recognized and
placed inside the <dc-metadata> element.

Order is preserved and significant -- fix_oeb12 will output DC
metadata elements in the same order as in this hash, though order for
tags of the same name is preserved from the input file.

=item C<%dcelements20>

A tied IxHash mapping an all-lowercase list of Dublin Core metadata
element names to the all-lowercase form dictated by the OPF 2.0
specification (which means it maps the all-lowercase tags to
themselves).  It is used by the fix_opf20() and fix_opf20_dcmeta()
methods.  Changing the tags in this list will change the tags
recognized and placed directly under the <metadata> element.

Order is preserved and significant -- fix_opf20 will output DC
metadata elements in the same order as in this hash, though order for
tags of the same name is preserved from the input file.

=item C<%nonxmlentity2char>

This is the %entity2char conversion map from HTML::Entities with the 5
pre-defined XML entities (amp, gt, lt, quot, apos) removed.  This is
used during by L</init()> to sanitize the OPF file data before
parsing.  This hash can be modified to allow and convert other
non-standard entities to unicode characters.  See HTML::Entities for
details.

=item C<%publishermap>

A hash mapping known variants of publisher names to a canonical form,
used by L</fix_publisher()>, and thus also indirectly by
L</fix_misc()>.

Keys should be entered in lowercase.  The hash can also be set empty
to prevent fix_publisher() from taking any action at all.

=item C<%referencetypes>

A hash mapping valid OPF 2.0 reference types to themselves, along with
common variants to standard types.

=item C<%relatorcodes>

A hash mapping the MARC Relator Codes (see:
http://www.loc.gov/marc/relators/relacode.html) to their descriptive
names.

=item C<$tidycmd>

The tidy executable name.  This has to be a fully qualified pathname
if tidy isn't on the path.  Defaults to 'tidy'.

=item C<$tidyxhtmlerrors>

The name of the error output file from system_tidy_xhtml().  Defaults
to 'tidyxhtml-errors.txt'

=item C<$tidyxmlerrors>

The name of the error output file from system_tidy_xml().  Defaults to
'tidyxml-errors.txt'

=item C<$tidysafety>

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

=item C<%validspecs>

A hash mapping valid specification strings to themselves, primarily
used to undefine unrecognized values.  Default valid values are 'OEB12'
and 'OPF20'.

=back

=cut

our $mobi2htmlcmd = 'mobi2html';
our $tidycmd = 'tidy'; # Specify full pathname if not on path
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
    "dc:contributor" => "dc:Contributor",
    "dc:subject"     => "dc:Subject",
    "dc:description" => "dc:Description",
    "dc:publisher"   => "dc:Publisher",
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
    "dc:contributor" => "dc:contributor",
    "dc:subject"     => "dc:subject",
    "dc:description" => "dc:description",
    "dc:publisher"   => "dc:publisher",
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

our %publishermap = (
    'ace'                   => 'Ace Books',
    'acebooks'              => 'Ace Books',
    'ace books'             => 'Ace Books',
    'baen'                  => 'Baen Publishing Enterprises',
    'baen publishing'       => 'Baen Publishing Enterprises',
    'ballantine'            => 'Ballantine Books',
    'ballantine books'      => 'Ballantine Books',
    'barnes and noble'      => 'Barnes and Noble Publishing',
    'barnesandnoble.com'    => 'Barnes and Noble Publishing',
    'cpan'                  => 'CPAN',
    'delrey'                => 'Del Rey Books',
    'del rey'               => 'Del Rey Books',
    'del rey books'         => 'Del Rey Books',
    'e-reads'               => 'E-Reads',
    'ereads'                => 'E-Reads',
    'ereads.com'            => 'E-Reads',
    'www.ereads.com'        => 'E-Reads',
    'feedbooks'             => 'Feedbooks',
    'feedbooks (www.feedbooks.com)' => 'Feedbooks',
    'www.feedbooks.com'     => 'Feedbooks',
    'fictionwise'           => 'Fictionwise',
    'fictionwise.com'       => 'Fictionwise',
    'www.fictionwise.com'   => 'Fictionwise',
    'harmony'               => 'Harmony Books',
    'harmony books'         => 'Harmony Books',
    'harpercollins'         => 'HarperCollins',
    'harper collins'        => 'HarperCollins',
    'harper-collins'        => 'HarperCollins',
    'manybooks'             => 'ManyBooks',
    'manybooks.net'         => 'ManyBooks',
    'penguin group'         => 'Penguin Group',
    'project gutenberg'     => 'Project Gutenberg',
    'gutenberg'             => 'Project Gutenberg',
    'gutenberg.org'         => 'Project Gutenberg',
    'www.gutenberg.org'     => 'Project Gutenberg',
    'randomhouse'           => 'Random House',
    'randomhouse.co.uk'     => 'Random House',
    'www.randomhouse.co.uk' => 'Random House',
    'random-house.com'      => 'Random House',
    'www.random-house.com'  => 'Random House',
    'rosetta'               => 'Rosetta Books',
    'rosettabooks'          => 'Rosetta Books',
    'rosetta books'         => 'Rosetta Books',
    'siren'                 => 'Siren Publishing',
    'siren publishing'      => 'Siren Publishing',
    'wildside'              => 'Wildside Press',
    'wildside press'        => 'Wildside Press',
    );


our %nonxmlentity2char = %entity2char;
delete($nonxmlentity2char{'amp'});
delete($nonxmlentity2char{'gt'});
delete($nonxmlentity2char{'lt'});
delete($nonxmlentity2char{'quot'});
delete($nonxmlentity2char{'apos'});

our %referencetypes = (
    # standard types
    'acknowledgements'   => 'acknowledgements',
    'bibliography'       => 'bibliography',
    'colophon'           => 'colophon',
    'copyright-page'     => 'copyright-page',
    'cover'              => 'cover',
    'dedication'         => 'dedication',
    'epigraph'           => 'epigraph',
    'foreword'           => 'foreword',
    'glossary'           => 'glossary',
    'index'              => 'index',
    'loi'                => 'loi',
    'lot'                => 'lot',
    'notes'              => 'notes',
    'preface'            => 'preface',
    'text'               => 'text',
    'title-page'         => 'title-page',
    'toc'                => 'toc',
    # common nonstandard types
    'start'              => 'text',
    'coverimage'         => 'other.ms-coverimage',
    'coverimagestandard' => 'other.ms-coverimage-standard',
    'thumbimage'         => 'other.ms-thumbimage',
    'thumbimagestandard' => 'other.ms-thumbimage-standard',
   );

our %relatorcodes = (
    'act' => 'Actor',
    'adp' => 'Adapter',
    'ann' => 'Annotator',
    'ant' => 'Bibliographic antecedent',
    'app' => 'Applicant',
    'arc' => 'Architect',
    'arr' => 'Arranger',
    'art' => 'Artist',
    'asg' => 'Assignee',
    'asn' => 'Associated name',
    'att' => 'Attributed name',
    'aui' => 'Author of introduction',
    'aus' => 'Author of screenplay',
    'aut' => 'Author',
    'bdd' => 'Binding designer',
    'bjd' => 'Bookjacket designer',
    'bkd' => 'Book designer',
    'bkp' => 'Book producer',
    'bnd' => 'Binder',
    'bpd' => 'Bookplate designer',
    'bsl' => 'Bookseller',
    'chr' => 'Choreographer',
    'cli' => 'Client',
    'cll' => 'Calligrapher',
    'clt' => 'Collotyper',
    'cmm' => 'Commentator',
    'cmp' => 'Composer',
    'cmt' => 'Compositor',
    'cnd' => 'Conductor',
    'cns' => 'Censor',
    'coe' => 'Contestant-appellee',
    'col' => 'Collector',
    'com' => 'Compiler',
    'cos' => 'Contestant',
    'cot' => 'Contestant-appellant',
    'cpe' => 'Complainant-appellee',
    'cph' => 'Copyright holder',
    'cpl' => 'Complainant',
    'cpt' => 'Complainant-appellant',
    'crp' => 'Correspondent',
    'crr' => 'Corrector',
    'cst' => 'Costume designer',
    'cte' => 'Contestee-appellee',
    'ctg' => 'Cartographer',
    'cts' => 'Contestee',
    'ctt' => 'Contestee-appellant',
    'dfd' => 'Defendant',
    'dfe' => 'Defendant-appellee',
    'dft' => 'Defendant-appellant',
    'dln' => 'Delineator',
    'dnc' => 'Dancer',
    'dnr' => 'Donor',
    'dpt' => 'Depositor',
    'drt' => 'Director',
    'dsr' => 'Designer',
    'dst' => 'Distributor',
    'dte' => 'Dedicatee',
    'dto' => 'Dedicator',
    'dub' => 'Dubious author',
    'edt' => 'Editor',
    'egr' => 'Engraver',
    'elt' => 'Electrotyper',
    'eng' => 'Engineer',
    'etr' => 'Etcher',
    'flm' => 'Film editor',
    'fmo' => 'Former owner',
    'fnd' => 'Funder/Sponsor',
    'frg' => 'Forger',
    'grt' => 'Graphic technician (discontinued code)',
    'hnr' => 'Honoree',
    'ill' => 'Illustrator',
    'ilu' => 'Illuminator',
    'ins' => 'Inscriber',
    'inv' => 'Inventor',
    'itr' => 'Instrumentalist',
    'ive' => 'Interviewee',
    'ivr' => 'Interviewer',
    'lbt' => 'Librettist',
    'lee' => 'Libelee-appellee',
    'lel' => 'Libelee',
    'len' => 'Lender',
    'let' => 'Libelee-appellant',
    'lie' => 'Libelant-appellee',
    'lil' => 'Libelant',
    'lit' => 'Libelant-appellant',
    'lse' => 'Licensee',
    'lso' => 'Licensor',
    'ltg' => 'Lithographer',
    'lyr' => 'Lyricist',
    'mon' => 'Monitor/Contractor',
    'mte' => 'Metal-engraver',
    'nrt' => 'Narrator',
    'org' => 'Originator',
    'oth' => 'Other',
    'pbl' => 'Publisher',
    'pfr' => 'Proofreader',
    'pht' => 'Photographer',
    'plt' => 'Platemaker',
    'pop' => 'Printer of plates',
    'ppm' => 'Papermaker',
    'prd' => 'Production personnel',
    'prf' => 'Performer',
    'pro' => 'Producer',
    'prt' => 'Printer',
    'pte' => 'Plaintiff-appellee',
    'ptf' => 'Plaintiff',
    'pth' => 'Patent holder',
    'ptt' => 'Plaintiff-appellant',
    'rbr' => 'Rubricator',
    'rce' => 'Recording engineer',
    'rcp' => 'Recipient',
    'rse' => 'Respondent-appellee',
    'rsp' => 'Respondent',
    'rst' => 'Respondent-appellant',
    'sce' => 'Scenarist',
    'scr' => 'Scribe',
    'scl' => 'Sculptor',
    'sec' => 'Secretary',
    'sgn' => 'Signer',
    'srv' => 'Surveyor',
    'str' => 'Stereotyper',
    'trc' => 'Transcriber',
    'trl' => 'Translator',
    'tyd' => 'Type designer',
    'tyg' => 'Typographer',
    'voc' => 'Vocalist',
    'wam' => 'Writer of accompanying material',
    'wde' => 'Wood-engraver',
    'wit' => 'Witness',
    );

our %validspecs = (
    'OEB12' => 'OEB12',
    'OPF20' => 'OPF20',
    'MOBI12' => 'MOBI12',
    );


#####################################################
########## CONSTRUCTORS AND INITIALIZATION ##########
#####################################################

my %rwfields = (
    'opffile'   => 'string', # OPF filename (with no path)
    'opfsubdir' => 'string', # Subdirectory name where opffile is found
    'spec'      => 'string',
    );
my %rofields = (
    'topdir'   => 'string', # Top-level directory of the unpacked book
    'twig'     => 'scalar',
    'twigroot' => 'scalar',
    'errors'   => 'arrayref',
    'warnings' => 'arrayref',
    );
my %privatefields = (
);

# A simple 'use fields' will not work here: use takes place inside
# BEGIN {}, so the @...fields variables won't exist.
require fields;
fields->import(
    keys(%rwfields),keys(%rofields),keys(%privatefields)
    );


=head1 CONSTRUCTORS AND INITIALIZATION

=head2 C<new($filename)>

Instantiates a new EBook::Tools object.  If C<$filename> is specified,
it will also immediately initialize itself via the C<init> method.

=cut

sub new   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my $class = ref($self) || $self;
    my ($filename) = @_;
    my $subname = (caller(0))[3];
    debug(2,"DEBUG[",$subname,"]");

    $self = fields::new($class);

    if($filename)
    {
	debug(2,"DEBUG: new object from '",$filename,"'");
	$self->init($filename);
    }
    return $self;
}


=head2 C<init($filename)>

Initializes the object from an existing OPF file.  If C<$filename> is
specified and exists, the OEB object will be set to read and write to
that file before attempting to initialize.  Otherwise, if the object
currently points to an OPF file it will use that name.  If there is no
OPF filename data, and C<$filename> was not specified, it will make a
last-ditch attempt to find an OPF file first by looking in
META-INF/container.xml, and if nothing is found there, by looking in
the current directory for a single OPF file.

If no such files or found (or more than one is found), the
initialization croaks.

=cut

sub init :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my ($filename) = @_;
    my $fh_opffile;
    my $opfstring;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    $self->{topdir} = getcwd();

    if($filename) { $self->{opffile} = $filename; }

    if(!$self->{opffile})
    {
        $opfstring = find_opffile();
        $self->{opffile} = $opfstring if($opfstring);
    }

    if(!$self->{opffile})
    {
	croak($subname,"(): Unable to find an OPF file to work with!\n");
    }

    if(! -f $self->{opffile})
    {
	croak($subname,"(): '",$self->{opffile},
              "' does not exist or is not a regular file!")
    }

    if(-z $self->{opffile})
    {
	croak("OPF file '",$self->{opffile},"' has zero size!");
    }

    # At this point, we have definitely found an OPF file to work
    # with, but it might not be in the top level directory, and with
    # the exception of final book construction and EPUB metadata, we
    # want to be in the directory of the OPF.
    $self->{opfsubdir} = dirname($self->{opffile});
    $self->{opffile} = basename($self->{opffile});
    usedir($self->opfdir);

    debug(2,"DEBUG: init using '",$self->{opfsubdir},"/",$self->{opffile},"'");

    # Initialize the twig before use
    $self->{twig} = XML::Twig->new(
	keep_atts_order => 1,
	output_encoding => 'utf-8',
	pretty_print => 'record'
	);

    # Read and decode entities before parsing to avoid parsing errors
    open($fh_opffile,'<:utf8',$self->{opffile})
        or croak($subname,"(): failed to open '",$self->{opffile},
                 "' for reading!");
    read($fh_opffile,$opfstring,-s $self->opffile)
        or croak($subname,"(): failed to read from '",$self->{opffile},"'!");
    close($fh_opffile)
        or croak($subname,"(): failed to close '",$self->{opffile},"'!");

    # We use _decode_entities and the custom hash to decode, but also
    # see below for the regexp
    _decode_entities($opfstring,\%nonxmlentity2char);

    # This runs decode_entities on the substring containing just the
    # entity for every entity *except* the 5 predefined internal
    # entities.  It seems to be about the same speed as running
    # _decode_entities on a small file, but having the hash map as a
    # package variable has additional utility, so that technique gets
    # used instead.
#    $opfstring =~
#        s/(&
#            (?! (?:lt|gt|quot|apos|amp);
#            )\w+;
#          )
#         / decode_entities($1) /gex;

    $self->{twig}->parse($opfstring);
    $self->{twigroot} = $self->{twig}->root;
    $self->opf_namespace;
    $self->twigcheck;
    debug(2,"DEBUG[/",$subname,"]");
    return $self;
}


=head2 C<init_blank(%args)>

Initializes an object containing nothing more than the basic OPF
framework, suitable for adding new documents when creating an e-book
from scratch.

=head3 Arguments

C<init_blank> takes up to three optional named arguments:

=over

=item C<opffile>

This specifies the OPF filename to use.  If not specified, defaults to
the name of the current working directory with ".opf" appended

=item C<author>

This specifies the content of the initial dc:creator element.  If not
specified, defaults to "Unknown Author".

=item C<title>

This specifies the content of the initial dc:title element. If not
specified, defaults to "Unknown Title".

=back

=head3 Example

 init_blank('opffile' => 'newfile.opf',
            'title' => 'The Great Unknown');

=cut

sub init_blank :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");


    my %valid_args = (
        'opffile' => 1,
        'author' => 1,
        'title' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    $args{opffile} ||= basename(getcwd) . ".opf";

    my $author = $args{author} || 'Unknown Author';
    my $title = $args{title} || 'Unknown Title';
    my $metadata;
    my $element;

    $self->{topdir} = getcwd();
    $self->{opfsubdir} = '.';
    $self->{opffile} = $args{opffile};
    $self->{twig} = XML::Twig->new(
	keep_atts_order => 1,
	output_encoding => 'utf-8',
	pretty_print => 'record'
        );

    $element = XML::Twig::Elt->new('package');
    $self->{twig}->set_root($element);
    $self->{twigroot} = $self->{twig}->root;
    $metadata = $self->{twigroot}->insert_new_elt('first_child','metadata');

    # dc:identifier
    $self->fix_packageid;

    # dc:title
    $element = $metadata->insert_new_elt('last_child','dc:title');
    $element->set_text($title);

    # dc:creator (author)
    $element = $metadata->insert_new_elt('last_child','dc:creator');
    $element->set_att('opf:role','aut');
    $element->set_text($author);

    $self->fix_opf20;
    return 1;
}


######################################
########## ACCESSOR METHODS ##########
######################################

=head1 ACCESSOR METHODS

The following methods return data deeper in the structure than the
auto-accessors, but still do not modify any object data or files.


=head2 C<adult()>

Returns the text of the Mobipocket-specific <Adult> element, if it
exists.  Expected values are 'yes' and undef.

=cut

sub adult :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    my $twigroot = $self->{twigroot};

    my $element = $twigroot->first_descendant(qr/^adult$/ix);
    return unless($element);

    if($element->text) { return $element->text; }
    else { return; }
}


=head2 C<contributor_list()>

Returns a list containing the text of all dc:contributor elements
(case-insensitive) or undef if none are found.

In scalar context, returns the first contributor, not the last.

=cut

sub contributor_list :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    my @retval = ();
    my $twigroot = $self->{twigroot};

    my @elements = $twigroot->descendants(qr/dc:contributor/ix);
    return unless(@elements);

    foreach my $el (@elements)
    {
        push(@retval,$el->text) if($el->text);
    }
    return unless(@retval);
    if(wantarray) { return @retval; }
    else { return $retval[0]; }
}


=head2 C<coverimage()>

Returns the href to the cover image, or undef if none is found.

Checks the following in order:

=over

=item <reference type="other.ms-coverimage-standard">

=item <EmbeddedCover>

=item <meta name="cover"> (as href)

=item <meta name="cover"> (as item id)

=back

=cut

sub coverimage :method {
    my ($self) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $twigroot = $self->{twigroot};
    my $element;
    my $href;
    my $id;

    $element = $twigroot->first_descendant('reference[@type="other.ms-coverimage-standard"]');
    $href = $element->att('href') if $element;
    return $href if $href;

    $element = $twigroot->first_descendant('EmbeddedCover');
    $href = $element->text if $element;
    return $href if $href;

    $element = $twigroot->first_descendant('meta[@name="cover"]');
    if($element) {
        if(-f $element->att('content')) {
            return $element->att('content');
        }
        $id = $element->att('content');
        $element = $twigroot->first_descendant("item[\@id='${id}']");
        $href = $element->att('href') if $element;
        return $href if $href;
    }
    return;
}


=head2 C<date_list(%args)>

Returns the text of all dc:date elements (case-insensitive) matching
the specified attributes.

In scalar context, returns the first match, not the last.

Returns undef if no matches are found.

=head3 Arguments

=over

=item * C<id> - 'id' attribute that must be matched exactly for the
result to be added to the list

=item * C<event> 'opf:event' or 'event' attribute that must be
matched exactly for the result to be added to the list

=back

If both arguments are specified a value is added to the list if it
matches either one (i.e. the logic is OR).

=cut

sub date_list :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my %valid_args = (
        'id' => 1,
        'event' => 1,
        );
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my @elements = $self->{twigroot}->descendants(qr/^ dc:date $/ix);
    my @list = ();
    my $id;
    my $scheme;
    foreach my $el (@elements)
    {
        if($args{id})
        {
            $id = $el->att('id') || '';
            if($id eq $args{id})
            {
                push(@list,$el->text);
                next;
            }
        }
        if($args{event})
        {
            $scheme = $el->att('opf:event') || $el->att('event') || '';
            if($scheme eq $args{event})
            {
                push(@list,$el->text);
                next;
            }
        }
        next if($args{id} || $args{event});
        push(@list,$el->text);
    }
    return unless(@list);
    if(wantarray) { return @list; }
    else { return $list[0]; }
}


=head2 C<description()>

Returns the description of the e-book, if set, or undef otherwise.

=cut

sub description :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    my $twigroot = $self->{twigroot};

    my $element = $twigroot->first_descendant(qr/^dc:description$/ix);
    return unless($element);

    if($element->text) { return $element->text; }
    else { return; }
}


=head2 C<element_list(%args)>

Returns a list containing the text values of all elements matching the
specified criteria.

=head3 Arguments

=over

=item * C<cond>

The L<XML::Twig> search condition used to find the elements.
Typically this is just the GI (tag) of the element you wish to find,
but it can also be a C<qr//> expression, coderef, or anything else
that XML::Twig can work with.  See the XML::Twig documentation for
details.

If this is not specified, an error is added and the method returns
undef.

=item * C<id> (optional)

'id' attribute that must be matched exactly for the
result to be added to the list

=item * C<scheme> (optional)

'opf:scheme' or 'scheme' attribute that must be
matched exactly for the result to be added to the list

=item * C<event> (optional)

'opf:event' or 'event' attribute that must be matched exactly for the
result to be added to the list

=back

If more than one of the arguments C<id>, C<scheme>, or C<event> are
specified a value is added to the list if it matches any one (i.e. the
logic is OR).

=cut

sub element_list :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my %valid_args = (
        'cond' => 1,
        'id' => 1,
        'scheme' => 1,
        );
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }
    unless($args{cond})
    {
        $self->add_error($subname,"(): no search condition specified");
        return;
    }

    my @elements = $self->{twigroot}->descendants($args{cond});
    my @list = ();
    my $id;
    my $scheme;
    foreach my $el (@elements)
    {
        if($args{id})
        {
            $id = $el->att('id') || '';
            if($id eq $args{id})
            {
                push(@list,$el->text);
                next;
            }
        }
        if($args{event})
        {
            $scheme = $el->att('opf:event') || $el->att('event') || '';
            if($scheme eq $args{event})
            {
                push(@list,$el->text);
                next;
            }
        }
        if($args{scheme})
        {
            $scheme = $el->att('opf:scheme') || $el->att('scheme') || '';
            if($scheme eq $args{scheme})
            {
                push(@list,$el->text);
                next;
            }
        }
        next if($args{id} || $args{event} || $args{scheme});
        push(@list,$el->text);
    }
    return unless(@list);
    if(wantarray) { return @list; }
    else { return $list[0]; }
}


=head2 C<errors()>

Returns an arrayref containing any generated error messages.

=cut

sub errors :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{errors};
}


=head2 C<identifier()>

Returns the text of the dc:identifier element pointed to by the
'unique-identifier' attribute of the root 'package' element, or undef
if it could not be located.

=cut

sub identifier :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    my $identid = $self->{twigroot}->att('unique-identifier');
    return unless($identid);

    my $identifier = $self->{twig}->first_elt("*[\@id='$identid']");
    return unless($identifier);

    my $idtext = $identifier->text;
    return unless($idtext);

    return($idtext);
}


=head2 C<isbn_list(%args)>

Returns a list of all ISBNs matching the specified attributes.  See
L</twigelt_is_isbn()> for a detailed description of how the ISBN
elements are found.

Returns undef if no matches are found.

In scalar context returns the first match, not the last.

See also L</isbns(%args)>.

=head3 Arguments

=over

=item * C<id> (optional)

'id' attribute that must be matched exactly for the
result to be added to the list

=item * C<scheme> (optional)

'opf:scheme' or 'scheme' attribute that must be
matched exactly for the result to be added to the list

=back

If both arguments are specified a value is added to the list if it
matches either one (i.e. the logic is OR).

=cut

sub isbn_list :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my %valid_args = (
        'id' => 1,
        'scheme' => 1,
        );
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my @list = $self->element_list(cond => \&twigelt_is_isbn,
                                   %args);
    return unless(@list);
    if(wantarray) { return @list; }
    else { return $list[0]; }
}


=head2 C<isbns(%args)>

Returns all of the ISBN identifiers matching the specificied
attributes as a list of hashrefs, with one hash per ISBN identifier
presented in the order that the identifiers are found.  The hash keys
are 'id' (containing the value of the 'id' attribute), 'scheme'
(containing the value of either the 'opf:scheme' or 'scheme'
attribute, whichever is found first), and 'isbn' (containing the text
of the element).

If no entries are found, returns undef.

In scalar context returns the first match, not the last.

See also L</isbn_list(%args)>.

=head3 Arguments

C<isbns()> takes two optional named arguments:

=over

=item * C<id> - 'id' attribute that must be matched exactly for the
result to be added to the list

=item * C<scheme> - 'opf:scheme' or 'scheme' attribute that must be
matched exactly for the result to be added to the list

=back

If both arguments are specified a value is added to the list if it
matches either one (i.e. the logic is OR).

=cut

sub isbns :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my %valid_args = (
        'id' => 1,
        'scheme' => 1,
        );
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my @elements = $self->{twigroot}->descendants(\&twigelt_is_isbn);
    my @list = ();
    my $id;
    my $scheme;
    foreach my $el (@elements)
    {
        if($args{id})
        {
            $id = $el->att('id') || '';
            if($id eq $args{id})
            {
                push(@list,
                     {
                         'isbn' => $el->text,
                         'id'   => $el->att('id'),
                         'scheme'   => $el->att('scheme'),
                     });
                next;
            }
        }
        if($args{scheme})
        {
            $scheme = $el->att('opf:scheme') || $el->att('scheme') || '';
            if($scheme eq $args{scheme})
            {
                push(@list,
                     {
                         'isbn' => $el->text,
                         'id'   => $el->att('id'),
                         'scheme'   => $el->att('scheme'),
                     });
                next;
            }
        }
        next if($args{id} || $args{scheme});
        $scheme = $el->att('opf:scheme') || $el->att('scheme');
        push(@list,
             {
                 'isbn'   => $el->text,
                 'id'     => $el->att('id'),
                 'scheme' => $scheme,
             });
    }
    return unless(@list);
    if(wantarray) { return @list; }
    else { return $list[0]; }
}


=head2 C<languages()>

Returns a list containing the text of all dc:language
(case-insensitive) entries, or undef if none are found.

In scalar context returns the first match, not the last.

=cut

sub languages :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    my @retval = ();
    my @elements = $self->{twigroot}->descendants(qr/^dc:language$/ix);
    foreach my $el (@elements)
    {
        push(@retval,$el->text) if($el->text);
    }
    return unless(@retval);
    if(wantarray) { return @retval; }
    else { return $retval[0]; }
}


=head2 C<manifest(%args)>

Returns all of the items in the manifest as a list of hashrefs, with
one hash per manifest item in the order that they appear, where the
hash keys are 'id', 'href', and 'media-type', each returning the
appropriate attribute, if any.

In scalar context, returns the first match, not the last.

=head3 Arguments

C<manifest()> takes four optional named arguments:

=over

=item * C<id> - 'id' attribute to match

=item * C<href> - 'href' attribute to match

=item * C<mtype> - 'media-type' attribute to match

=item * C<logic> - logic to use (valid values are 'and' or 'or', default: 'and')

=back

If any of the named arguments are specified, C<manifest()> will return
only items matching the specified criteria.  This is an exact
case-sensitive match, but it can (especially in the case of mtype)
still return multiple elements.

=head3 Return values

Returns undef if there is no <manifest> element directly underneath
<package>, or if <manifest> contains no items.

=head3 See also

L</manifest_hrefs()>, L</spine()>

=head3 Example

 @manifest = $ebook->manifest(id => 'ncx',
                              mtype => 'text/xml',
                              logic => 'or');

=cut

sub manifest :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my %valid_args = (
        'id' => 1,
        'href' => 1,
        'mtype' => 1,
        'logic' => 1
        );
    my %valid_logic = (
        'and' => 1,
        'or' => 1
        );
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }
    if($args{logic})
    {
        croak($subname,
              "(): logic must be 'and' or 'or' (got '",$args{logic},"')")
            if(!$valid_logic{$args{logic}});
    }
    else { $args{logic} = 'and'; }

    debug(1,"DEBUG: manifest() called with '",join(" ",keys(%args)),"'");

    my @elements;
    my @retarray;
    my $cond;

    if($args{id})
    {
        debug(1,"DEBUG: manifest searching on id");
        $cond = "item[\@id='$args{id}'";
    }
    if($args{href})
    {
        debug(1,"DEBUG: manifest searching on href");
        if($cond) { $cond .= " $args{logic} \@href='$args{href}'"; }
        else { $cond = "item[\@href='$args{href}'"; }
    }
    if($args{mtype})
    {
        debug(1,"DEBUG: manifest searching on mtype");
        if($cond) { $cond .= " $args{logic} \@media-type='$args{mtype}'"; }
        else { $cond = "item[\@media-type='$args{mtype}'"; }
    }
    if($cond) { $cond .= "]"; }
    else { $cond = "item"; }

    my $manifest = $self->{twigroot}->first_child('manifest');
    return unless($manifest);

    debug(1,"DEBUG: manifest search condition = '",$cond,"'");
    @elements = $manifest->children($cond);
    return unless(@elements);

    foreach my $el (@elements)
    {
        push(@retarray,
             {
                 'id' => $el->id,
                 'href' => $el->att('href'),
                 'media-type' => $el->att('media-type')
             });
    }
    if(wantarray) { return @retarray; }
    else { return $retarray[0]; }
}


=head2 C<manifest_hrefs()>

Returns a list of all of the hrefs in the current OPF manifest, or the
empty list if none are found.

In scalar context returns the first href, not the last.

See also: C<manifest()>, C<spine_idrefs()>

=cut

sub manifest_hrefs :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my @items;
    my $href;
    my $manifest;
    my $mimetype;
    my @retval = ();

    $manifest = $self->{twigroot}->first_child('manifest');
    if(! $manifest) { return @retval; }

    @items = $manifest->descendants('item');
    foreach my $item (@items)
    {
	$href = $item->att('href');
        if($href) {
            $mimetype = mimetype($href) || "UNKNOWN";
            debug(3,"DEBUG: '",$href,"' has mime-type '",$mimetype,"'");
            push(@retval,$href);
        }
    }
    debug(2,"DEBUG[/",$subname,"]");
    if(wantarray) { return @retval; }
    else { return $retval[0]; }
}


=head2 C<opf_namespace()>

Some OPF generators explicity assign 'opf:' in the gi as a prefix on
OPF elements.  This makes later parsing more complex and is
unnecessary, so this is stripped before any parsing takes place.

=cut

sub opf_namespace :method {
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(3,"DEBUG[",$subname,"]");

    my @elements = $self->{twig}->descendants(qr/^opf:/ix);
    foreach my $el (@elements)
    {
        my $gi = $el->gi;
        $gi =~ s/^opf:(.*)/$1/ix;
        $el->set_gi($gi);
    }
    return;
}


=head2 C<opfdir()>

Returns the full filesystem path to the directory where the OPF
metadata file will be stored, or undef if either the top-level
directory or the OPF subdirectory is not found.

=cut

sub opfdir :method {
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(3,"DEBUG[",$subname,"]");
    return unless($self->{topdir});
    return unless($self->{opfsubdir});

    if($self->{opfsubdir} eq '.') {
        return $self->{topdir};
    }
    return $self->{topdir} . '/' . $self->{opfsubdir};
}


=head2 C<opffile()>

Returns the name of the file where the OPF metadata will be stored or
undef if no value is found..

=cut

sub opffile :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(3,"DEBUG[",$subname,"]");
    return unless($self->{opffile});
    return $self->{opffile};
}


=head2 C<opfpath()>

Returns the full filesystem path to the file where the OPF metadata
will be stored or undef if either the top level directory or the OPF
filename is not found.

=cut

sub opfpath :method {
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(3,"DEBUG[",$subname,"]");
    return unless($self->{topdir});
    return unless($self->{opfsubdir});
    return unless($self->{opffile});

    return $self->{topdir} . '/' . $self->{opfsubdir} . '/' . $self->{opffile};
}


=head2 C<primary_author()>

Finds the primary author of the book, defined as the first
'dc:creator' entry (case-insensitive) where either the attribute
opf:role="aut" or role="aut", or the first 'dc:creator' entry if no
entries with either attribute can be found.  Entries must actually
have text to be considered.

In list context, returns a two-item list, the first of which is the
text of the entry (the author name), and the second element of which
is the value of the 'opf:file-as' or 'file-as' attribute (where
'opf:file-as' is given precedence if both are present).

In scalar context, returns the text of the entry (the author name).

If no entries are found, returns undef.

Uses L</twigelt_is_author()> in the first half of the search.

=head3 Example

 my ($fileas, $author) = $ebook->primary_author;
 my $author = $ebook->primary_author;

=cut

sub primary_author :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my $twigroot = $self->{twigroot};
    my $element;
    my $fileas;

    $element = $twigroot->first_descendant(\&twigelt_is_author);
    $element = $twigroot->first_descendant(qr/dc:creator/ix) if(!$element);
    if(! $element) {
        carp("## WARNING: no dc:creator elements found!");
        return;
    }
    if(! $element->text) {
        carp("## WARNING: dc:creator element is empty!");
        return;
    }
    $fileas = $element->att('opf:file-as');
    $fileas = $element->att('file-as') unless($fileas);
    if(wantarray) { return ($element->text, $fileas); }
    else { return $element->text; }
}


=head2 C<print_errors()>

Prints the current list of errors to STDERR.

=cut

sub print_errors :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my $errorref = $self->{errors};

    if(!$self->errors)
    {
	debug(1,"DEBUG: no errors found!");
	return 1;
    }


    foreach my $error (@$errorref)
    {
	print "ERROR: ",$error,"\n";
    }
    return 1;
}


=head2 C<print_warnings()>

Prints the current list of warnings to STDERR.

=cut

sub print_warnings :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my $warningref = $self->{warnings};

    if(!$self->warnings)
    {
	debug(2,"DEBUG: no warnings found!");
	return 1;
    }


    foreach my $warning (@$warningref)
    {
	print "WARNING: ",$warning,"\n";
    }
    return 1;
}


=head2 C<print_opf()>

Prints the OPF file to the default filehandle

=cut

sub print_opf :method
{
    my $self = shift;
    my $filehandle = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    if(defined $filehandle) { $self->{twig}->print($filehandle); }
    else { $self->{twig}->print; }
    return 1;
}


=head2 C<publishers()>

Returns a list containing the text of all dc:publisher
(case-insensitive) entries, or undef if none are found.

In scalar context returns the first match, not the last.

=cut

sub publishers :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    my @pubs = ();
    my @elements = $self->{twigroot}->descendants(qr/^dc:publisher$/ix);
    foreach my $el (@elements)
    {
        push(@pubs,$el->text) if($el->text);
    }
    return unless(@pubs);
    if(wantarray) { return @pubs; }
    else { return $pubs[0]; }
}


=head2 C<retailprice()>

Returns a two-scalar list, the first scalar being the text of the
Mobipocket-specific <SRP> element, if it exists, and the second being
the 'Currency' attribute of that element, if it exists.

In scalar context, returns just the text (price).

Returns undef if the SRP element is not found.

=cut

sub retailprice :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    my $twigroot = $self->{twigroot};

    my $element = $twigroot->first_descendant(qr/^ SRP $/ix);
    return unless($element);
    if(wantarray) { return ($element->text,$element->att('Currency')); }
    else { return $element->text };
}


=head2 C<review()>

Returns the text of the Mobipocket-specific <Review> element, if it
exists.  Returns undef if one is not found.

=cut

sub review :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    my $twigroot = $self->{twigroot};

    my $element = $twigroot->first_descendant(qr/^review$/ix);
    return unless($element);
    return $element->text;
}


=head2 C<rights('id' => 'identifier')>

Returns a list containing the text of all of dc:rights or
dc:copyrights (case-insensitive) entries in the e-book, or undef if
none are found.

In scalar context returns the first match, not the last.

If the optional named argument 'id' is specified, it will only return
entries where the id attribute matches the specified identifier.
Although this still returns a list, if more than one entry is found, a
warning is logged.

Note that dc:copyrights is not a valid Dublin Core element -- it is
included only because some broken Mobipocket books use it.

=cut

sub rights :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    my %valid_args = (
        'id' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }


    my @rights = ();
    my $id = $args{id};
    my @elements = $self->{twigroot}->descendants(qr/^dc:(copy)?rights$/ix);

    foreach my $element (@elements)
    {
        if($id)
        {
            next if($element->att('id') ne $id);
            push @rights,$element->text if($element->text);
        }
        else { push @rights,$element->text if($element->text); }
    }

    if($id)
    {
        add_warning($subname
                     . "(): More than one rights entry found with id '"
                     . $id ."'" )
            if(scalar(@rights) > 1);
    }
    return unless(@rights);
    if(wantarray) { return @rights; }
    else { return $rights[0]; }
}


=head2 C<search_knownuids()>

Searches the OPF twig for the first dc:identifier (case-insensitive)
element with an ID matching known UID IDs.

Returns the ID if a match is found, undef otherwise

=cut

sub search_knownuids :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my @elements;

    @elements = $self->{twigroot}->descendants(\&twigelt_is_knownuid);
    return unless(@elements);
    debug(1,"DEBUG: found known UID '",$elements[0]->id,"'");
    return $elements[0]->id;
}


=head2 C<search_knownuidschemes()>

Searches descendants of the OPF twig element for the first
<dc:identifier> or <dc:Identifier> subelement with the attribute
'scheme' or 'opf:scheme' matching a known list of schemes for unique
IDs

NOTE: this is NOT a case-insensitive search!  If you have to deal with
really bizarre input, make sure that you run L</fix_oeb12()> or
L</fix_opf20()> before calling L</fix_packageid()> or L</fix_misc()>.

Returns the ID if a match is found, undef otherwise.

=cut

sub search_knownuidschemes :method   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my ($gi) = @_;
    if(!$gi) { $gi = 'dc:identifier'; }
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    my $topelement = $self->{twigroot};

    my @knownuidschemes = (
        'GUID',
	'UUID',
	'FWID',
	);

    # Creating a regexp to search on works, but doesn't let you
    # specify priority.  For that, you really do have to loop.
#    my $schemeregexp = "(" . join('|',@knownuidschemes) . ")";

    my @elems;
    my $id;

    my $retval = undef;

    foreach my $scheme (@knownuidschemes)
    {
	debug(2,"DEBUG: searching for scheme='",$scheme,"'");
	@elems = $topelement->descendants(
            "dc:identifier[\@opf:scheme=~/$scheme/ix or \@scheme=~/$scheme/ix]"
            );
        push @elems, $topelement->descendants(
            "dc:Identifier[\@opf:scheme=~/$scheme/ix or \@scheme=~/$scheme/ix]"
            );
	foreach my $elem (@elems)
	{
	    debug(2,"DEBUG: working on scheme '",$scheme,"'");
	    if(defined $elem)
	    {
		if($scheme eq 'FWID')
		{
		    # Fictionwise has a screwy output that sets the ID
		    # equal to the text.  Fix the ID to just be 'FWID'
		    debug(1,"DEBUG: fixing FWID");
		    $elem->set_id('FWID');
		}

		$id = $elem->id;
                unless(defined $id)
                {
		    debug(1,"DEBUG: assigning ID from scheme '",$scheme,"'");
		    $id = uc($scheme);
		    $elem->set_id($id);
                }
                $retval = $id;
		debug(1,"DEBUG: found Package ID: ",$id);
		last;
	    } # if(defined $elem)
	} # foreach my $elem (@elems)
	last if(defined $retval);
    }
    debug(2,"[/",$subname,"]");
    return $retval;
}


=head2 C<spec()>

Returns the version of the OEB specification currently in use.  Valid
values are C<OEB12> and C<OPF20>.  This value will default to undef
until C<fix_oeb12> or C<fix_opf20> is called, as there is no way for
the object to know what specification is being conformed to (if any)
until it attempts to enforce it.

=cut

sub spec :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{spec};
}


=head2 C<spine()>

Returns all of the manifest items referenced in the spine as a list of
hashrefs, with one hash per manifest item in the order that they
appear, where the hash keys are 'id', 'href', and 'media-type', each
returning the appropriate attribute, if any.

In scalar context, returns the first item, not the last.

Returns undef if there is no <spine> element directly underneath
<package>, or if <spine> contains no itemrefs.  If <spine> exists, but
<manifest> does not, or a spine itemref exists but points an ID not
found in the manifest, spine() logs an error and returns undef.

See also: L</spine_idrefs()>, L</manifest()>

=cut

sub spine :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $spine = $self->{twigroot}->first_child('spine');
    return unless($spine);
    my @spinerefs;
    my $idref;
    my $element;
    my @retarray;

    my $manifest = $self->{twigroot}->first_child('manifest');
    if(!$manifest)
    {
        $self->add_error(
            $subname . "(): <spine> found without <manifest>"
            );
        debug(1,"DEBUG: <spine> found without <manifest>!");
        return;
    }

    @spinerefs = $spine->children('itemref');
    return unless(@spinerefs);

    foreach my $spineref (@spinerefs)
    {
        $idref = $spineref->att('idref');
        if(!$idref)
        {
            $self->add_warning(
                $subname . "(): <itemref> found with no idref -- skipping"
                );
            debug(1,"DEBUG: <itemref> found with no idref -- skipping");
            next;
        }
        $element = $manifest->first_child("item[\@id='$idref']");
        if(!$element)
        {
            $self->add_error(
                $subname ."(): id '" . $idref . "' not found in manifest!"
                );
            debug(1,"DEBUG: id '",$idref," not found in manifest!");
            return;
        }
        push(@retarray,
             {
                 'id' => $element->id,
                 'href' => $element->att('href'),
                 'media-type' => $element->att('media-type')
             });
    }
    if(wantarray) { return @retarray; }
    else { return $retarray[0]; }
}


=head2 C<spine_idrefs()>

Returns a list of all of the idrefs in the current OPF spine, or the
empty list if none are found.

In scalar context, returns the first idref, not the last.

See also: L</spine()>, L</manifest_hrefs()>

=cut

sub spine_idrefs :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $spine = $self->{twigroot}->first_child('spine');;
    my @retval = ();
    my @itemrefs;
    my $idref;

    if(! $spine) { return @retval; }

    @itemrefs = $spine->children('itemref');
    foreach my $item (@itemrefs)
    {
	$idref = $item->att('idref');
	push(@retval,$idref) if($idref);
    }
    if(wantarray) { return @retval; }
    else { return $retval[0]; }
}


=head2 C<subject_list()>

Returns a list containing the text of all dc:subject elements or undef
if none are found.

In scalar context, returns the first subject, not the last.

=cut

sub subject_list :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    my @retval = ();
    my $twigroot = $self->{twigroot};

    my @subjects = $twigroot->descendants(qr/dc:subject/ix);
    return unless(@subjects);

    foreach my $subject (@subjects)
    {
        push(@retval,$subject->text) if($subject->text);
    }
    return unless(@retval);
    if(wantarray) { return @retval; }
    else { return $retval[0]; }
}


=head2 C<title()>

Returns the title of the e-book, or undef if no dc:title element
(case-insensitive) exists.  If a dc:title element exists, but contains
no text, returns an empty string.

=cut

sub title :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    my $twigroot = $self->{twigroot};

    my $element = $twigroot->first_descendant(qr/^dc:title$/ix);
    return unless($element);
    return ($element->text || '');
}


=head2 C<twig()>

Returns the raw L<XML::Twig> object used to store the OPF metadata.

Although this twig can be manipulated via the standard XML::Twig
methods, doing so requires caution and is not recommended.  In
particular, changing the root element from here will cause the
EBook::Tools internal twig and twigroot attributes to become unlinked
and the result of any subsequent action is not defined.

=cut

sub twig :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{twig};
}


=head2 C<twigcheck()>

Croaks showing the calling location unless C<$self> has both a twig and a
twigroot, and the twigroot is <package>.  Used as a sanity check for
methods that use twig or twigroot.

=cut

sub twigcheck :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(3,"DEBUG[",$subname,"]");

    my @calledfrom = caller(1);
    croak("twigcheck called from unknown location") if(!@calledfrom);

    croak($calledfrom[3],"(): undefined twig")
        if(!$self->{twig});
    croak($calledfrom[3],"(): twig isn't a XML::Twig")
        if( (ref $self->{twig}) ne 'XML::Twig' );
    croak($calledfrom[3],"(): twig root missing")
        if(!$self->{twigroot});
    croak($calledfrom[3],"(): twig root isn't a XML::Twig::Elt")
        if( (ref $self->{twigroot}) ne 'XML::Twig::Elt' );
    croak($calledfrom[3],"(): twig root is '" . $self->{twigroot}->gi
          . "' (needs to be 'package')")
        if($self->{twigroot}->gi ne 'package');
    debug(3,"DEBUG[/",$subname,"]");
    return 1;
}


=head2 C<twigroot()>

Returns the raw L<XML::Twig> root element used to store the OPF
metadata.

This twig element can be manipulated via the standard XML::Twig::Elt
methods, but care should be taken not to attempt to cut this element
from its twig as doing so will cause the EBook::Tools internal twig
and twigroot attributes to become unlinked and the result of any
subsequent action is not defined.

=cut

sub twigroot :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{twigroot};
}


=head2 C<warnings()>

Returns an arrayref containing any generated warning messages.

=cut

sub warnings :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{warnings};
}


######################################
########## MODIFIER METHODS ##########
######################################

=head1 MODIFIER METHODS

Unless otherwise specified, all modifier methods return undef if an
error was added to the error list, and true otherwise (even if a
warning was added to the warning list).


=head2 C<add_document($href,$id,$mediatype)>

Adds a document to the OPF manifest and spine, creating <manifest> and
<spine> if necessary.  To add an item only to the OPF manifest, see
add_item().

=head3 Arguments

=over

=item C<$href>

The href to the document in question.  Usually, this is just a
filename (or relative path and filename) of a file in the current
working directory.  If you are planning to eventually generate a .epub
book, all hrefs MUST be in or below the current working directory.

The method returns undef if $href is not defined or empty.

=item C<$id>

The XML ID to use.  If not specified, defaults to the href with
invalid characters removed.

This must be unique not only to the manifest list, but to every
element in the OPF file.  If a duplicate ID exists, the method sets an
error and returns undef.

=item C<$mediatype> (optional)

The mime type of the document.  If not specified, will attempt to
autodetect the mime type, and if that fails, will default to
'application/xhtml+xml'.

=back

=cut

sub add_document :method   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my ($href,$id,$mediatype) = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    $href = trim($href);
    return unless($href);

    my $twig = $self->{twig};
    my $topelement = $self->{twigroot};
    my $element;

    $id = $href unless($id);
    $id =~ s/[^\w.-]//gx; # Delete all nonvalid XML 1.0 namechars
    $id =~ s/^[.\d -]+//gx; # Delete all nonvalid XML 1.0 namestartchars

    $element = $twig->first_elt("*[\@id='$id']");
    if($element)
    {
        $self->add_error(
            $subname . "(): ID '" . $id . "' already exists"
            . " (in a '" . $element->gi ."' tag)"
            );
        return;
    }

    if(!$mediatype)
    {
	my $mimetype = mimetype($href);
	if($mimetype) { $mediatype = $mimetype; }
	else { $mediatype = "application/xhtml+xml"; }
	debug(2,"DEBUG: '",$href,"' has mimetype '",$mimetype,"'");
    }

    my $manifest = $topelement->first_child('manifest');
    $manifest = $topelement->insert_new_elt('last_child','manifest')
        if(!$manifest);
    my $spine = $topelement->first_child('spine');
    $spine = $topelement->insert_new_elt('last_child','spine')
        if(!$spine);

    my $item = $manifest->insert_new_elt('last_child','item');
    $item->set_id($id);
    $item->set_att(
	'href' => $href,
	'media-type' => $mediatype
	);

    my $itemref = $spine->insert_new_elt('last_child','itemref');
    $itemref->set_att('idref' => $id);

    return 1;
}


=head2 C<add_error(@errors)>

Adds @errors to the list of object errors.  Each member of
@errors should be a string containing the entire text of the
error, with no ending newline.

SEE ALSO: L</add_warning()>, L</clear_errors()>, L</clear_warnerr()>

=cut

sub add_error :method   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (@newerror) = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(3,"DEBUG[",$subname,"]");

    my $currenterrors;
    $currenterrors = $self->{errors} if($self->{errors});

    if(@newerror)
    {
        my $error = join('',@newerror);
	debug(1,"ERROR: ",$error);
	push(@$currenterrors,$error);
    }
    $self->{errors} = $currenterrors;
    return 1;
}


=head2 C<add_identifier(%args)>

Creates a new dc:identifier element containing the specified text, id,
and scheme.

If a <dc-metadata> element exists underneath <metadata>, the
identifier element will be created underneath the <dc-metadata> in OEB
1.2 format, otherwise the title element is created underneath
<metadata> in OPF 2.0 format.

Returns the twig element containing the new identifier.

=head3 Arguments

C<add_identifier()> takes three named arguments, one mandatory, two
optional.

=over

=item * C<text> - the text of the identifier.  This is mandatory, and
the method croaks if it is not present.

=item * C<scheme> - 'opf:scheme' or 'scheme' attribute to be added (optional)

=item * C<id> - 'id' attribute to be added.  If this is specified, and
the id is already in use, a warning will be added but the method will
continue, removing the id attribute from the element that previously
contained it.

=back

=cut

sub add_identifier :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my %valid_args = (
        'text' => 1,
        'id' => 1,
        'scheme' => 1,
        );
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }
    croak($subname,"(): identifier text not specified")
        unless($args{text});

    $self->fix_metastructure_basic();
    my $meta = $self->{twigroot}->first_child('metadata');
    my $dcmeta = $meta->first_child('dc-metadata');
    my $element;
    my $idelem;
    my $newid = $args{id};
    $idelem = $self->{twig}->first_elt("*[\@id='$newid']") if($newid);

    if($dcmeta)
    {
        $element = $dcmeta->insert_new_elt('last_child','dc:Identifier');
        $element->set_att('scheme' => $args{scheme}) if($args{scheme});
    }
    else
    {
        $element = $meta->insert_new_elt('last_child','dc:identifier');
        $element->set_att('opf:scheme' => $args{scheme}) if($args{scheme});
    }
    $element->set_text($args{text});

    if($idelem && $idelem->cmp($element) )
    {
        $self->add_warning(
            $subname,"(): reassigning id '",$newid,
            "' from a '",$idelem->gi,"' element!"
            );
        $idelem->del_att('id');
    }
    $element->set_att('id' => $newid) if($newid);

    return $element;
}


=head2 C<add_item($href,$id,$mediatype)>

Adds a document to the OPF manifest (but not spine), creating
<manifest> if necessary.  To add an item only to both the OPF manifest
and spine, see add_document().

=head3 Arguments

=over

=item C<$href>

The href to the document in question.  Usually, this is just a
filename (or relative path and filename) of a file in the current
working directory.  If you are planning to eventually generate a .epub
book, all hrefs MUST be in or below the current working directory.

=item C<$id>

The XML ID to use.  If not specified, defaults to the href with all
nonword characters removed.

This must be unique not only to the manifest list, but to every
element in the OPF file.  If a duplicate ID exists, the method sets an
error and returns undef.

=item C<$mediatype> (optional)

The mime type of the document.  If not specified, will attempt to
autodetect the mime type, and if that fails, will set an error and
return undef.

=back

=cut

sub add_item :method   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my ($href,$id,$mediatype) = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    $href = trim($href);
    return unless($href);

    my $twig = $self->{twig};
    my $topelement = $self->{twigroot};
    my $element;

    $id = $href unless($id);
    $id =~ s/[^\w.-]//gx; # Delete all nonvalid XML 1.0 namechars
    $id =~ s/^[.\d -]+//gx; # Delete all nonvalid XML 1.0 namestartchars

    $element = $twig->first_elt("*[\@id='$id']");
    if($element)
    {
        $self->add_error(
            $subname . "(): ID '" . $id . "' already exists"
            . " (in a '" . $element->gi ."' tag)"
            );
        debug(2,"DEBUG[/",$subname,"]");
        return;
    }

    if(!$mediatype)
    {
	my $mimetype = mimetype($href);
	if($mimetype) { $mediatype = $mimetype; }
	else { $mediatype = "application/xhtml+xml"; }
	debug(2,"DEBUG: '",$href,"' has mimetype '",$mediatype,"'");
    }

    my $manifest = $self->{twigroot}->first_child('manifest');
    $manifest = $topelement->insert_new_elt('last_child','manifest')
        if(!$manifest);

    debug(2,"DEBUG: adding item '",$id,"': '",$href,"'");
    my $item = $manifest->insert_new_elt('last_child','item');
    $item->set_id($id);
    $item->set_att(
	'href' => $href,
	'media-type' => $mediatype
	);

    debug(2,"DEBUG[/",$subname,"]");
    return 1;
}


=head2 add_metadata(%args)

Creates a metadata element with the specified text, attributes, and parent.

If a <dc-metadata> element exists underneath <metadata>, the language
element will be created underneath the <dc-metadata> and any standard
attributes will be created in OEB 1.2 format, otherwise the element is
created underneath <metadata> in OPF 2.0 format.

Returns 1 on success, returns undef if no gi or if no text was specified.

=cut

=head3 Arguments

=over

=item C<gi>

The generic identifier (tag) of the metadata element to alter or
create.  If not specified, the method sets an error and returns undef.

=item C<parent>

The generic identifier (tag) of the parent to use for any newly
created element.  If not specified, defaults to 'dc-metadata' if
'dc-metadata' exists underneath 'metadata', and 'metadata' otherwise.

A newly created element will be created under the first element found
with this gi.  A modified element will be moved under the first
element found with this gi.

Newly created elements will use OPF 2.0 attribute names if the parent
is 'metadata' and OEB 1.2 attribute names otherwise.

=item C<text>

This specifies the element text to set.  If not specified, the method
sets an error and returns undef.

=item C<id> (optional)

This specifies the ID to set on the element.  If set and the ID is
already in use, a warning is logged and the ID is removed from the
other location and assigned to the element.

=item C<fileas> (optional)

This specifies the file-as attribute to set on the element.

=item C<role> (optional)

This specifies the role attribute to set on the element.

=item C<scheme> (optional)

This specifies the scheme attribute to set on the element.

=back

=head3 Example

 $retval = $ebook->add_metadata(gi => 'AuthorNonstandard',
                                text => 'Element Text',
                                id => 'customid',
                                fileas => 'Text, Element',
                                role => 'xxx',
                                scheme => 'code');

=cut

sub add_metadata :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(3,"DEBUG[",$subname,"]");
    my %valid_args = (
        'gi' => 1,
        'parent' => 1,
        'text' => 1,
        'id' => 1,
        'fileas' => 1,
        'role' => 1,
        'scheme' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $gi = $args{gi};
    unless($gi)
    {
        $self->add_error($subname,"(): no gi specified");
        return;
    }

    my $text = $args{text};
    unless($text)
    {
        $self->add_error($subname,"(): no text specified");
        return;
    }

    my $newid = $args{id};
    my $idelem;
    my $element;
    my $meta;
    my $dcmeta;
    my $parent;
    my %dcatts;

    $self->fix_metastructure_basic();
    $parent =  $self->{twigroot}->first_descendant(qr/^ $args{parent} $/ix)
        if($args{parent});
    $meta = $self->{twigroot}->first_child('metadata');
    $dcmeta = $meta->first_child('dc-metadata');
    $parent = $parent || $dcmeta || $meta;
    if($parent->gi eq 'metadata')
    {
        %dcatts = (
            'file-as' => 'opf:file-as',
            'role' => 'opf:role',
            'scheme' => 'opf:scheme',
            );
    }
    else
    {
        %dcatts = (
            'file-as' => 'file-as',
            'role' => 'role',
            'scheme' => 'scheme'
        );
    }

    debug(2,"DEBUG: creating '",$gi,"' under <",$parent->gi,">");
    $element = $parent->insert_new_elt('last_child',$gi);
    $element->set_att($dcatts{'file-as'},$args{fileas})
        if($args{fileas});
    $element->set_att($dcatts{'role'},$args{role})
        if($args{role});
    $element->set_att($dcatts{'scheme'},$args{scheme})
        if($args{scheme});
    $element->set_text($text);

    $idelem = $self->{twig}->first_elt("*[\@id='$newid']") if($newid);
    if($idelem && $idelem->cmp($element) )
    {
        $self->add_warning(
            $subname,"(): reassigning id '",$newid,
            "' from a '",$idelem->gi,"' to a '",$element->gi,"'!"
            );
        $idelem->del_att('id');
    }
    $element->set_att('id' => $newid) if($newid);
    return 1;
}


=head2 C<add_subject(%args)>

Creates a new dc:subject element containing the specified text, code,
and id.

If a <dc-metadata> element exists underneath <metadata>, the
subject element will be created underneath the <dc-metadata> in OEB
1.2 format, otherwise the title element is created underneath
<metadata> in OPF 2.0 format.

Returns the twig element containing the new subject.

=head3 Arguments

C<add_subject()> takes four named arguments, one mandatory, three
optional.

=over

=item * C<text> - the text of the subject.  This is mandatory, and
the method croaks if it is not present.

=item * C<scheme> (optional) - 'opf:scheme' or 'scheme' attribute to
be added.  Be warned that neither the OEB 1.2 nor the OPF 2.0
specifications allow a scheme to be added to this element, so if this
is specified, the resulting OPF file will fail to validate against
either standard.

=item * C<basiccode> (optional) - 'BASICCode' attribute to be added.
Be warned that this is a Mobipocket-specific attribute that does not
exist in either the OEB 1.2 nor the OPF 2.0 specifications, so if this
is specified, the resulting OPF file will fail to validate against
either standard.

=item * C<id> (optional) - 'id' attribute to be added.  If this is
specified, and the id is already in use, a warning will be added but
the method will continue, removing the id attribute from the element
that previously contained it.

=back

=cut

sub add_subject :method     ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my %valid_args = (
        'text' => 1,
        'id' => 1,
        'scheme' => 1,
        'basiccode' => 1,
        );
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }
    croak($subname,"(): subject text not specified")
        unless($args{text});

    $self->fix_metastructure_basic();
    my $meta = $self->{twigroot}->first_child('metadata');
    my $dcmeta = $meta->first_child('dc-metadata');
    my $element;
    my $idelem;
    my $newid = $args{id};
    $idelem = $self->{twig}->first_elt("*[\@id='$newid']") if($newid);

    if($dcmeta)
    {
        $element = $dcmeta->first_child('dc:Subject[text()="' . $args{text} .  '"]');
        if(! $element) {
            $element = $dcmeta->insert_new_elt('last_child','dc:Subject');
        }
        $element->set_att('scheme' => $args{scheme}) if($args{scheme});
    }
    else
    {
        $element = $meta->first_child('dc:subject[text()="' . $args{text} .  '"]');
        if(! $element) {
            $element = $meta->insert_new_elt('last_child','dc:subject');
        }
        $element->set_att('opf:scheme' => $args{scheme}) if($args{scheme});
    }
    $element->set_text($args{text});
    $element->set_att('BASICCode' => $args{basiccode}) if($args{basiccode});

    if($idelem && $idelem->cmp($element) )
    {
        $self->add_warning(
            $subname,"(): reassigning id '",$newid,
            "' from a '",$idelem->gi,"' element!"
            );
        $idelem->del_att('id');
    }
    $element->set_att('id' => $newid) if($newid);

    return $element;
}


=head2 C<add_warning(@newwarning)>

Joins @newwarning to a single string and adds it to the list of object
warnings.  The warning should not end with a newline newline.

SEE ALSO: L</add_error()>, L</clear_warnings()>, L</clear_warnerr()>

=cut

sub add_warning :method   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (@newwarning) = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(3,"DEBUG[",$subname,"]");

    my @currentwarnings;
    @currentwarnings = @{$self->{warnings}} if($self->{warnings});

    if(@newwarning)
    {
        my $warning = join('',@newwarning);
	debug(1,"WARNING: ",$warning);
	push(@currentwarnings,$warning);
    }
    $self->{warnings} = \@currentwarnings;

    debug(3,"DEBUG[/",$subname,"]");
    return 1;
}


=head2 C<clear_errors()>

Clear the current list of errors

=cut

sub clear_errors :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    $self->{errors} = ();
    return 1;
}


=head2 C<clear_warnerr()>

Clear both the error and warning lists

=cut

sub clear_warnerr :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    $self->{errors} = ();
    $self->{warnings} = ();
    return 1;
}


=head2 C<clear_warnings()>

Clear the current list of warnings

=cut

sub clear_warnings :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    $self->{warnings} = ();
    return 1;
}


=head2 C<delete_meta_filepos()>

Deletes metadata elements with the attribute 'filepos' underneath
the given parent element

These are secondary metadata elements included in the output from
mobi2html may that are not used.

=cut

sub delete_meta_filepos :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my @elements = $self->{twigroot}->descendants('metadata[@filepos]');
    foreach my $el (@elements)
    {
	$el->delete;
    }
    return 1;
}


=head2 C<delete_subject(%args)

Deletes dc:subject and dc:Subject elements based on text content or
the id, scheme, or basiccode attributes.  Matches are case-sensitive.

Specifying multiple arguments will delete subject matching any of them.

This has the same potential arguments as add_subject.

Returns the count of elements deleted.

=cut

sub delete_subject :method {
    my $self = shift;
    my (%args) = @_;
    my %valid_args = (
        'text' => 1,
        'id' => 1,
        'scheme' => 1,
        'basiccode' => 1,
        );
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my @elements;
    my $count = 0;

    if(defined $args{text}) {
        @elements = $self->{twigroot}->descendants('dc:subject[text()="' . $args{text} . '"]');
        foreach my $el (@elements)
        {
            $el->delete;
            $count++;
        }
        @elements = $self->{twigroot}->descendants('dc:Subject[text()="' . $args{text} . '"]');
        foreach my $el (@elements)
        {
            $el->delete;
            $count++;
        }
    }

    if($args{id}) {
        @elements = $self->{twigroot}->descendants('dc:subject[@id="' . $args{id} . '"]');
        foreach my $el (@elements)
        {
            $el->delete;
            $count++;
        }
        @elements = $self->{twigroot}->descendants('dc:Subject[@id="' . $args{id} . '"]');
        foreach my $el (@elements)
        {
            $el->delete;
            $count++;
        }
    }

    if($args{scheme}) {
        @elements = $self->{twigroot}->descendants('dc:subject[@scheme="' . $args{scheme} . '"]');
        foreach my $el (@elements)
        {
            $el->delete;
            $count++;
        }
        @elements = $self->{twigroot}->descendants('dc:subject[@opf:scheme="' . $args{scheme} . '"]');
        foreach my $el (@elements)
        {
            $el->delete;
            $count++;
        }
        @elements = $self->{twigroot}->descendants('dc:Subject[@scheme="' . $args{scheme} . '"]');
        foreach my $el (@elements)
        {
            $el->delete;
            $count++;
        }
        @elements = $self->{twigroot}->descendants('dc:Subject[@opf:scheme="' . $args{scheme} . '"]');
        foreach my $el (@elements)
        {
            $el->delete;
            $count++;
        }
    }

    if($args{basiccode}) {
        @elements = $self->{twigroot}->descendants('dc:subject[@BASICCode="' . $args{id} . '"]');
        foreach my $el (@elements)
        {
            $el->delete;
            $count++;
        }
        @elements = $self->{twigroot}->descendants('dc:Subject[@BASICCode="' . $args{id} . '"]');
        foreach my $el (@elements)
        {
            $el->delete;
            $count++;
        }
    }
    debug(2,"DEBUG: Deleted ",$count," elements");
    return $count;
}


=head2 C<fix_creator()>

Normalizes creator names and file-as attributes

Names are normalized to 'First Last' format, while file-as attributes
are normalized to 'Last, First' format.

=cut

sub fix_creator :method {
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $twigroot = $self->{twigroot};
    my @elements = $twigroot->descendants(qr/dc:creator/ix);
    my $nameparse = new Lingua::EN::NameParse(
        allow_reversed  => 1,
        extended_titles => 1,
        force_case      => 1,
        lc_prefix       => 1,
       );
    foreach my $el (@elements) {
        my $fileas = $el->att('opf:file-as') || '';
        my $name = $el->text || '';
        my $fixed;

        if ( $nameparse->parse($name) ) {
	    $self->add_warning(
                "WARNING: failure while parsing name: ",
                $nameparse->properties->{non_matching});
        }
        debug(2,"DEBUG: creator name '",$name,"' -> '",
               $nameparse->case_all,"'");
        $el->set_text($nameparse->case_all);
        debug(2,"DEBUG: creator file-as '",$fileas,"' -> '",
               $nameparse->case_all_reversed,"'");
        $el->set_att('opf:file-as',$nameparse->case_all_reversed);
    }
}


=head2 C<fix_dates()>

Standardizes all <dc:date> elements via fix_datestring().  Adds a
warning to the object for each date that could not be fixed.

Called from L</fix_misc()>.

=cut

sub fix_dates :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my @dates;
    my $newdate;

    @dates = $self->{twigroot}->descendants('dc:date');
    push(@dates,$self->{twigroot}->descendants('dc:Date'));

    foreach my $dcdate (@dates)
    {
	if(!$dcdate->text)
	{
	    $self->add_warning(
                "WARNING: found dc:date with no value -- skipping");
	}
	else
	{
	    $newdate = fix_datestring($dcdate->text);
	    if(!$newdate)
	    {
		$self->add_warning(
		    sprintf("fixmisc(): can't deal with date '%s' -- skipping",
                            $dcdate->text)
		    );
	    }
	    elsif($dcdate->text ne $newdate)
	    {
		debug(2,"DEBUG: setting date from '",$dcdate->text,
                      "' to '",$newdate,"'");
		$dcdate->set_text($newdate);
	    }
	}
    }
    return 1;
}


=head2 C<fix_guide()>

Fixes problems related to the OPF guide elements, specifically:

=over

=item * Ensures the guide element exists

=item * Moves all reference elements directly underneath the guide element

=item * Finds nonstandard reference types and either converts them to
standard or prefaces them with 'other.'

=item * Finds reference elements with a href with only an anchor
portion and assigns them to the first spine href.  This only works if
the spine is in working condition, so it may be wise to run
L</fix_spine()> before C<fix_guide()> if the input is expected to be
very badly broken.

=back

Logs a warning if a reference href is found that does not appear in
the manifest.

=cut

sub fix_guide :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $twigroot = $self->{twigroot};
    my $guide = $twigroot->first_descendant('guide');
    my $parent;
    my $href;
    my $type;
    my @spine;

    # If <guide> doesn't exist, create it
    unless($guide)
    {
        debug(1,"DEBUG: creating <guide>");
        $guide = $twigroot->insert_new_elt('last_child','guide');
    }

    # Make sure that the guide is a child of the twigroot,
    $parent = $guide->parent;
    if( $parent->cmp($twigroot) )
    {
        debug(1,"DEBUG: moving <guide>");
        $guide->move('last_child',$twigroot);
    }


    my @elements = $twigroot->descendants(qr/^reference$/ix);
    foreach my $el (@elements) {
        $type = $el->att('type');
        if($referencetypes{$type}) {
            $el->set_att('type',$referencetypes{$type});
        }
        elsif($type !~ /^other./x) {
            $type = 'other.' . $type;
            $el->set_att('type',$type);
        }

        $href = $el->att('href');
        if (!$href) {
            # No href means it is broken.
            # Leave it alone, but log a warning
            $self->add_warning(
                "fix_guide(): <reference> with no href -- skipping");
            next;
        }
        if ($href =~ /^#/) {
            # Anchor-only href.  Attempt to fix from the first
            # spine entry
            @spine = $self->spine;
            if (!@spine) {
                $self->add_warning(
                    "fix_guide(): Cannot correct reference href '",$href,
                    "', spine is empty");
            }
            elsif (!$spine[0]->{href}) {
                $self->add_warning(
                    "fix_guide(): Cannot correct reference href '",$href,
                    "', cannot find href for first spine entry");
            }
            else {
                debug(1,"DEBUG: correcting reference href from '",$href,
                      "' to '",$spine[0]->{href} . $href,"'");
                $el->set_att('href',$spine[0]->{href} . $href);
            }
        }
        debug(3,"DEBUG: processing reference '",$href,"')");
        $el->move('last_child',$guide);
    } # foreach my $el (@elements)

    return 1;
}


=head2 C<fix_languages(%args)>

Checks through the <dc:language> elements (case-insensitive) and
removes any duplicates.  If no <dc:language> elements are found, one
is created.

TODO: Also convert language names to IANA language and region codes.

=head3 Arguments

=over

=item * C<default>

The default language string to use when creating a new language
element.  If not specified, defaults to 'en'.

=back

=cut

sub fix_languages :method
{
    my $self = shift;
    my %args = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my %valid_args = (
        'default' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $twigroot = $self->{twigroot};
    my $defaultlang = $args{default} || 'en';
    my $langel;
    my @elements = $twigroot->descendants(qr/dc:language/ix);
    while($langel = shift(@elements) )
    {
        foreach my $el (@elements)
        {
            $el->delete if(twigelt_detect_duplicate($el,$langel) );
        }
    }

    @elements = $self->languages;
    if(!@elements)
    {
        $self->set_language(text => $defaultlang);
    }
    return 1;
}


=head2 C<fix_links()>

Checks through the links in the manifest and checks them for anything
they might link to, adding anything missing to the manifest.

A warning is added for every manifest item missing a href.

If no <manifest> element exists directly underneath the <package>
root, or <manifest> contains no items, the method logs a warning and
returns undef.  Otherwise, it returns 1.

=cut

sub fix_links :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $twigroot = $self->{twigroot};

    my $manifest = $twigroot->first_child('manifest');
    my @unchecked;

    # The %links hash points a href to one of three values:
    # * undef : the link has not been checked at all
    # * 0 : the link has been checked and is not reachable
    # * 1 : the link has been checked and exists
    my %links;
    my @newlinks;
    my $href;
    my $mimetype;

    my %linking_mimetypes = (
        'text/html' => 1,
        'text/xhtml' => 1,
        'text/xml' => 1,
        'text/x-oeb1-document' => 1,
        'application/atom+xml' => 1,
        'application/xhtml+xml' => 1,
        'application/xml' => 1
        );

    if(!$manifest)
    {
        $self->add_warning(
            "fix_links(): no manifest found!"
            );
        return;
    }
    @unchecked = $self->manifest_hrefs;
    if(!@unchecked)
    {
        $self->add_warning(
            "fix_links(): empty manifest found!"
            );
        return;
    }

    # Initialize %links, so we don't try to add something already in
    # the manifest
    foreach my $mhref (@unchecked)
    {
        $links{$mhref} = undef unless(exists $links{$mhref});
    }

    while(@unchecked)
    {
        debug(3,"DEBUG: ",scalar(@unchecked),
              " items left to check at start of loop");
        $href = shift(@unchecked);
        $href = trim($href);
        debug(3,"DEBUG: checking '",$href,"'");
        next if(defined $links{$href});

        # Skip mailto: links
        if($href =~ m#^mailto:#ix) {
            debug(1,"DEBUG: mailto link '",$href,"' skipped");
            $links{$href} = 0;
            next;
        }

        # Skip URIs for now
        if($href =~ m#^ \w+://#ix)
        {
            debug(1,"DEBUG: URI '",$href,"' skipped");
            $links{href} = 0;
            next;
        }
        if(! -f $href)
        {
            $self->add_warning(
                "fix_links(): '" . $href . "' not found"
                );
            $links{$href} = 0;
            next;
        }

        $mimetype = mimetype($href);

        if(!$linking_mimetypes{$mimetype})
        {
            debug(2,"DEBUG: '",$href,"' has mimetype '",$mimetype,
                "' -- not checking");
            $links{$href} = 1;
            next;
        }

        debug(1,"DEBUG: finding links in '",$href,"'");
        push(@newlinks,find_links($href));
        trim(@newlinks) if(@newlinks);
        $links{$href} = 1;
        foreach my $newlink (@newlinks)
        {
            # Skip mailto: links
            if($newlink =~ m#^mailto:#ix) {
                debug(1,"DEBUG: mailto link '",$href,"' skipped");
                next;
            }
            # Skip URIs for now
            elsif($newlink =~ m#^ \w+://#ix)
            {
                debug(1,"DEBUG: URI '",$newlink,"' skipped");
                next;
            }
            elsif(!exists $links{$newlink})
            {
                debug(2,"DEBUG: adding '",$newlink,"' to the list");
                push(@unchecked,$newlink);
                $self->add_item($newlink);
            }
        }
        debug(2,"DEBUG: ",scalar(@unchecked),
            " items left to check at end of loop");
    } # while(@unchecked)
    debug(2,"DEBUG[/",$subname,"]");
    return 1;
}

=head2 C<fix_manifest()>

Finds all <item> elements and moves them underneath <manifest>,
creating <manifest> if necessary.

Logs a warning but continues if it finds an <item> with a missing id
or href attribute.  If both id and href attributes are missing, logs a
warning, skips moving the item entirely (unless it was already
underneath <manifest>, in which case it is moved to preserve its sort
order along all other items under <manifest>), but otherwise
continues.

=cut

sub fix_manifest :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $twigroot = $self->{twigroot};

    my $manifest = $twigroot->first_descendant('manifest');
    my @elements;
    my $parent;

    my $href;
    my $id;

    # If <manifest> doesn't exist, create it
    if(! $manifest)
    {
	debug(1,"DEBUG: creating <manifest>");
	$manifest = $twigroot->insert_new_elt('last_child','manifest');
    }

    # Make sure that the manifest is the first child of the twigroot,
    # which should be <package>
    $parent = $manifest->parent;
    if($parent != $twigroot)
    {
	debug(1,"DEBUG: moving <manifest>");
	$manifest->move('last_child',$twigroot);
    }

    @elements = $twigroot->descendants(qr/^item$/ix);
    foreach my $el (@elements)
    {
        $href = $el->att('href');
        $id = $el->id;
        if(!$id)
        {
            if(!$href)
            {
                # No ID, no href, there's something very fishy here,
                # so log a warning.
                # If it is already underneath <manifest>, move it to
                # preserve sort order, but otherwise leave it alone
                $self->add_warning(
                    "fix_manifest(): found item with no id or href"
                    );
                debug(1,"fix_manifest(): found item with no id or href");
                if($el->parent == $manifest)
                {
                    $el->move('last_child',$manifest);
                }
                else
                {
                    print "DEBUG: skipping item with no id or href\n"
                        if($debug);
                }
                next;
            } # if(!$href)
            # We have a href, but no ID.  Log a warning, but move it anyway.
            $self->add_warning(
                'fix_manifest(): handling item with no ID! '
                . sprintf "(href='%s')",$href
                );
            debug(1,"DEBUG: processing item with no id (href='",$href,"')");
            $el->move('last_child',$manifest);
        } # if(!$id)
        if(!$href)
        {
            # We have an ID, but no href.  Log a warning, but move it anyway.
            $self->add_warning(
                "fix_manifest(): item with id '" . $id . "' has no href!"
                );
            debug(1,"fix_manifest(): item with id '",$id,"' has no href!");
            $el->move('last_child',$manifest);
        }
        else
        {
            # We have an ID and a href
            debug(3,"DEBUG: processing item '",$id,"' (href='",$href,"')");
            $el->move('last_child',$manifest);
        }
    }
    return 1;
}

=head2 C<fix_metastructure_basic()>

Verifies that <metadata> exists (creating it if necessary), and moves
it to be the first child of <package>.  If additional <metadata>
elements exist, their children are moved into the first one found and
then the extras are deleted.

Used in L</fix_metastructure_oeb12()>, L</fix_packageid()>, and
L</set_primary_author(%args)>.

=cut

sub fix_metastructure_basic :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(3,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $twigroot = $self->{twigroot};
    my $metadata = $twigroot->first_descendant('metadata');

    my @extras = $twigroot->descendants('metadata');
    shift @extras;

    if(! $metadata)
    {
	debug(1,"DEBUG: creating <metadata>");
	$metadata = $twigroot->insert_new_elt('first_child','metadata');
    }

    foreach my $extra (@extras) {
        my @elements = $extra->children;
        foreach my $el (@elements) {
            debug(2,"DEBUG: moving <",$el->gi,"> into primary metadata");
            $el->move('last_child',$metadata);
        }
        $extra->delete;
    }
    debug(3,"DEBUG: moving <metadata> to be the first child of <package>");
    $metadata->move('first_child',$twigroot);
    return 1;
}


=head2 C<fix_metastructure_oeb12()>

Verifies the existence of <metadata>, <dc-metadata>, and <x-metadata>,
creating them as needed, and making sure that <metadata> is a child of
<package>, while <dc-metadata> and <x-metadata> are children of
<metadata>.

Used in L</fix_oeb12()> and L</fix_mobi()>.

=cut

sub fix_metastructure_oeb12 :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(3,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $twigroot = $self->{twigroot};

    my $metadata;
    my $dcmeta;
    my $xmeta;
    my $parent;

    # Start by forcing the basic <package><metadata> structure
    $self->fix_metastructure_basic;
    $metadata = $twigroot->first_child('metadata');

    # If <dc-metadata> doesn't exist, we'll have to create it.
    $dcmeta = $twigroot->first_descendant('dc-metadata');
    if(! $dcmeta)
    {
	debug(2,"DEBUG: creating <dc-metadata>");
	$dcmeta = $metadata->insert_new_elt('first_child','dc-metadata');
    }

    # Make sure that $dcmeta is a child of $metadata
    $parent = $dcmeta->parent;
    if($parent != $metadata)
    {
	debug(2,"DEBUG: moving <dc-metadata>");
	$dcmeta->move('first_child',$metadata);
    }

    # If <x-metadata> doesn't exist, create it
    $xmeta = $metadata->first_descendant('x-metadata');
    if(! $xmeta)
    {
        debug(2,"DEBUG: creating <x-metadata>");
        $xmeta = $metadata->insert_new_elt('last_child','x-metadata');
    }

    # Make sure that x-metadata is a child of metadata
    $parent = $xmeta->parent;
    if($parent != $metadata)
    {
        debug(2,"DEBUG: moving <x-metadata>");
        $xmeta->move('after',$dcmeta);
    }
    return 1;
}


=head2 C<fix_misc()>

Fixes miscellaneous potential problems in OPF data.  Specifically,
this is a shortcut to calling L</delete_meta_filepos()>,
L</fix_packageid()>, L</fix_dates()>, L</fix_languages()>,
L</fix_publisher()>, L</fix_manifest()>, L</fix_spine()>,
L</fix_guide()>, and L</fix_links()>.

The objective here is that you can run either C<fix_misc()> and either
L</fix_oeb12()> or L</fix_opf20()> and a perfectly valid OPF file will
result from only two calls.

=cut

sub fix_misc :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    $self->delete_meta_filepos();
    $self->delete_subject('text' => '');
    $self->fix_packageid();
    $self->fix_creator();
    $self->fix_dates();
    $self->fix_languages();
    $self->fix_publisher();
    $self->fix_manifest();
    $self->fix_spine();
    $self->fix_guide();
    $self->fix_links();

    debug(2,"DEBUG[/",$subname,"]");
    return 1;
}


=head2 C<fix_mobi()>

Manipulates the twig to fix Mobipocket-specific issues

=over

=item * Force the OEB 1.2 structure (although not the namespace, DTD,
or capitalization), so that <dc-metadata> and <x-metadata> are
guaranteed to exist.

=item * Find and move all Mobi-specific elements to <x-metadata>

=item * If no <output> element exists, creates one for a utf-8 ebook

=back

Note that the forced creation of <output> will cause the OPF file to
become noncompliant with IDPF specifications.

=cut

sub fix_mobi :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $twigroot = $self->{twigroot};

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


    # Mobipocket currently requires that its custom elements be found
    # underneath <x-metadata>.  Since the presence of <x-metadata>
    # requires that the Dublin Core tags be under <dc-metadata>, we
    # have to use at least the OEB1.2 structure (deprecated, but still
    # allowed in OPF2.0), though we don't have to convert everything.
    $self->fix_metastructure_oeb12();
    $dcmeta = $twigroot->first_descendant('dc-metadata');
    $xmeta = $twigroot->first_descendant('x-metadata');

    # If <x-metadata> doesn't exist, create it.  Even if there are no
    # mobi-specific tags, this method will create at least one
    # (<output>) which will need it.
    if(!$xmeta)
    {
        debug(2,"DEBUG: creating <x-metadata>");
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
            $self->add_warning(
                'fix_mobi(): Found ' . scalar(@elements) . " '" . $tag .
                "' elements, but only one should exist."
                );
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
	    debug(2,"DEBUG: setting encoding only and returning");
	    return 1;
	}
    }
    else
    {
        debug(1,"DEBUG: creating <output> under <x-metadata>");
        $output = $xmeta->insert_new_elt('last_child','output');
    }


    # At this stage, we definitely have <output> in the right place.
    # Set the attributes and return.
    $output->set_att('encoding' => 'utf-8',
		     'content-type' => 'text/x-oeb1-document');
    debug(2,"DEBUG[/",$subname,"]");
    return 1;
}


=head2 C<fix_oeb12()>

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

=back

=cut

sub fix_oeb12 :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $twigroot = $self->{twigroot};
    my $metadata;
    my $dcmeta;
    my $xmeta;
    my @elements;

    # Verify and correct locations for <metadata>, <dc-metadata>, and
    # <x-metadata>, creating them as needed.
    $self->fix_metastructure_oeb12;
    $metadata = $twigroot->first_descendant('metadata');
    $dcmeta = $metadata->first_descendant('dc-metadata');
    $xmeta = $metadata->first_descendant('x-metadata');

    # Clobber metadata attributes 'xmlns:dc' and 'xmlns:opf'
    # used only in OPF2.0
    $metadata->del_atts('xmlns:dc','xmlns:opf');

    # Assign the DC namespace attribute to dc-metadata for OEB 1.2
    $dcmeta->set_att('xmlns:dc',"http://purl.org/dc/elements/1.1/");

    # Set the correct tag name and move it into <dc-metadata> in the
    # right order
    foreach my $dcel (keys %dcelements12)
    {
        @elements = $twigroot->descendants(qr/^$dcel$/ix);
        foreach my $el (@elements)
        {
            debug(3,"DEBUG: processing '",$el->gi,"'");
            croak("Found invalid DC element '",$el->gi,"'!")
                if(!$dcelements12{lc $el->gi});
            $el->set_gi($dcelements12{lc $el->gi});
            $el = twigelt_fix_oeb12_atts($el);
            $el->move('last_child',$dcmeta);
        }
    }

    # Handle non-DC metadata, deleting <x-metadata> if it isn't
    # needed.
    @elements = $metadata->children(qr/^(?!(?s:.*)-metadata)/x);
    if(@elements)
    {
	if($debug)
	{
	    print {*STDERR} "DEBUG: extra metadata elements found: ";
	    foreach my $el (@elements) { print {*STDERR} $el->gi," "; }
	    print {*STDERR} "\n";
	}
	foreach my $el (@elements)
	{
	    $el->move('last_child',$xmeta);
	}
    }
    @elements = $twigroot->children(qr/^meta$/ix);
    foreach my $el (@elements)
    {
        $el->set_gi(lc $el->gi);
        $el->move('last_child',$xmeta);
    }
    @elements = $xmeta->children;
    $xmeta->delete unless(@elements);

    # Fix <manifest> and <spine>
    $self->fix_manifest;
    $self->fix_spine;

    # Set the OEB 1.2 doctype
    $self->{twig}->set_doctype('package',
                              "http://openebook.org/dtds/oeb-1.2/oebpkg12.dtd",
                              "+//ISBN 0-9673008-1-9//DTD OEB 1.2 Package//EN");

    # Clean up <package>
    $twigroot->del_att('version');
    $twigroot->set_att(
        'xmlns' => 'http://openebook.org/namespaces/oeb-package/1.0/');
    $self->fix_packageid;

    $self->{spec} = $validspecs{'OEB12'};
    debug(2,"DEBUG[/",$subname,"]");
    return 1;
}


=head2 C<fix_oeb12_dcmetatags()>

Makes a case-insensitive search for tags matching a known list of DC
metadata elements and corrects the capitalization to the OEB 1.2
standard.  Also corrects 'dc:Copyrights' to 'dc:Rights'.  See global
variable $dcelements12.

The L</fix_oeb12()> method does this also, but fix_oeb12_dcmetatags()
is usable separately for the case where you want DC metadata elements
with consistent tag names, but don't want them moved from wherever
they are.

=cut

sub fix_oeb12_dcmetatags :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $topelement = $self->{twigroot};

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


=head2 C<fix_opf20()>

Modifies the OPF data to conform to the OPF 2.0 standard

Specifically, this involves:

=over

=item * moving all of the dc-metadata and x-metadata elements directly
underneath <metadata>

=item * removing the <dc-metadata> and <x-metadata> elements themselves

=item * lowercasing the dc-metadata tags (and fixing dc:copyrights to
dc:rights)

=item * setting namespaces on dc-metata OPF attributes

=item * setting version and xmlns attributes on <package>

=item * setting xmlns:dc and xmlns:opf on <metadata>

=back

=cut

sub fix_opf20 :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    # Ensure a sane structure
    $self->fix_metastructure_basic();

    # If there is an existing cover image, ensure it hits all standards
    my $coverimage = $self->coverimage;
    $self->set_cover('href' => $coverimage) if $coverimage;

    my $twigroot = $self->{twigroot};
    my $metadata = $twigroot->first_descendant('metadata');
    my @elements;

    # If <dc-metadata> exists, make sure that it is directly
    # underneath <metadata> so that its children will collapse to the
    # correct position, then erase it.
    @elements = $twigroot->descendants('dc-metadata');
    if(@elements)
    {
	foreach my $dcmeta (@elements)
	{
	    debug(1,"DEBUG: moving <dc-metadata>");
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
	    debug(1,"DEBUG: moving <x-metadata>");
	    $xmeta->move('last_child',$metadata);
	    $xmeta->erase;
	}
    }

    # For all DC elements at any location, set the correct tag name
    # and attribute namespace and move it directly under <metadata>
    foreach my $dcmetatag (keys %dcelements20)
    {
	@elements = $twigroot->descendants(qr/$dcmetatag/ix);
	foreach my $el (@elements)
	{
	    debug(2,"DEBUG: checking DC element <",$el->gi,">");
	    $el->set_gi($dcelements20{$dcmetatag});
            $el = twigelt_fix_opf20_atts($el);
	    $el->move('last_child',$metadata);
	}
    }

    # Find any <meta> elements anywhere in the package and move them
    # under <metadata>.  Force the tag to lowercase.

    @elements = $twigroot->descendants(qr/^meta$/ix);
    foreach my $el (@elements)
    {
        debug(2,'DEBUG: checking meta element <',$el->gi,
              ' name="',$el->att('name'),'">');
        $el->set_gi(lc $el->gi);
        $el->move('last_child',$metadata);
    }

    # Fix the <package> attributes
    $twigroot->set_att('version' => '2.0',
                       'xmlns' => 'http://www.idpf.org/2007/opf');
    $self->fix_packageid;

    # Fix the <metadata> attributes
    $metadata->set_att('xmlns:dc' => "http://purl.org/dc/elements/1.1/",
                       'xmlns:opf' => "http://www.idpf.org/2007/opf",
                       'xmlns:xsi' => "http://www.w3.org/2001/XMLSchema-instance");

    # Fix <manifest> and <spine>
    $self->fix_manifest;
    $self->fix_spine;

    # Clobber the doctype, if present
    $self->{twig}->set_doctype(0,0,0,0);

    # Set the specification
    $self->{spec} = $validspecs{'OPF20'};

    debug(2,"DEBUG[/",$subname,"]");
    return 1;
}


=head2 C<fix_opf20_dcmetatags()>

Makes a case-insensitive search for tags matching a known list of DC
metadata elements and corrects the capitalization to the OPF 2.0
standard.  Also corrects 'dc:copyrights' to 'dc:rights'.  See package
variable %dcelements20.

The L</fix_opf20()> method does this also, but
C<fix_opf20_dcmetatags()> is usable separately for the case where you
want DC metadata elements with consistent tag names, but don't want
them moved from wherever they are.

=cut

sub fix_opf20_dcmetatags :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $topelement = $self->{twigroot};
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


=head2 C<fix_packageid()>

Checks the <package> element for the attribute 'unique-identifier',
makes sure that it is mapped to a valid dc:identifier subelement, and
if not, searches those subelements for an identifier to assign, or
creates one if nothing can be found.

Requires that <metadata> exist.  Croaks if it doesn't.  Run
L</fix_oeb12()> or L</fix_opf20()> before calling this if the input
might be very broken.

=cut

sub fix_packageid :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    # Start by enforcing the basic structure needed
    $self->fix_metastructure_basic();
    my $twigroot = $self->{twigroot};
    my $packageid = $twigroot->att('unique-identifier');

    my $meta = $twigroot->first_child('metadata')
        or croak($subname,"(): metadata not found");
    my $element;

    if($packageid)
    {
        # Check that the ID maps to a valid identifier
	# If not, undefine it
	debug(2,"DEBUG: checking existing packageid '",$packageid,"'");

	# The twig ID handling system is unreliable, especially when
	# multiple twigs may be existing simultaneously.  Use
	# XML::Twig->first_elt instead of XML::Twig->elt_id, even
	# though it is slower.
        #
        # As of Twig 3.32, this will cause 'uninitialized value'
        # warnings to be spewed for each time no descendants are
        # found.
	#$element = $self->{twig}->elt_id($packageid);
	$element = $self->{twig}->first_elt("*[\@id='$packageid']");

	if($element)
	{
	    if(lc($element->tag) ne 'dc:identifier')
	    {
		debug(1,"DEBUG: packageid '",$packageid,
                      "' points to a non-identifier element ('",
                      $element->tag,"')");
                debug(1,"DEBUG: undefining existing packageid '",
                      $packageid,"'");
		undef($packageid);
	    }
	    elsif(!$element->text)
	    {
		debug(1,"DEBUG: packageid '",$packageid,
                      "' points to an empty identifier.");
		debug(1,"DEBUG: undefining existing packageid '",
                      $packageid,"'");
		undef($packageid);
	    }
	}
	else { undef($packageid); };
    }

    if(!$packageid)
    {
	# Search known IDs for a unique Package ID
	$packageid = $self->search_knownuids;
    }

    # If no unique ID found so far, start searching known schemes
    if(!$packageid)
    {
	$packageid = $self->search_knownuidschemes;
    }

    # And if we still don't have anything, we have to make one from
    # scratch using Data::UUID
    if(!$packageid)
    {
	debug(1,"DEBUG: creating new UUID");
	$element = twigelt_create_uuid();
	$element->paste('first_child',$meta);
	$packageid = 'UUID';
    }

    # At this point, we have a unique ID.  Assign it to package
    $twigroot->set_att('unique-identifier',$packageid);
    debug(2,"[/",$subname,"]");
    return 1;
}


=head2 C<fix_publisher()>

Standardizes publisher names in all dc:publisher entities, mapping
known variants of a publisher's name to a canonical form via package
variable %publishermap.

Publisher entries with no text are deleted.

=cut

sub fix_publisher :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my @publishers = $self->twigroot->descendants(qr/^dc:publisher$/ix);
    foreach my $pub (@publishers)
    {
        debug(3,"Examining publisher entry in element '",$pub->gi,"'");
        if(!$pub->text)
        {
            debug(1,'Deleting empty publisher entry');
            $pub->delete;
            next;
        }
        elsif( $publishermap{lc $pub->text} &&
               ($publishermap{lc $pub->text} ne $pub->text) )
        {
            debug(1,"DEBUG: Changing publisher from '",$pub->text,"' to '",
                  $publishermap{lc $pub->text},"'");
            $pub->set_text($publishermap{lc $pub->text});
        }
    }
    return 1;
}


=head2 C<fix_spine()>

Fixes problems with the OPF spine, specifically:

=over

=item Moves all <itemref> elements underneath <spine>, creating
<spine> if necessary.

=back

=cut

sub fix_spine :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck();

    my $twigroot = $self->{twigroot};
    my $manifest = $twigroot->first_descendant('manifest');
    my $spine = $twigroot->first_descendant('spine');
    my @elements;
    my $parent;

    @elements = $twigroot->descendants(qr/^itemref$/ix);
    if(@elements)
    {
        # If <spine> doesn't exist, create it
        if(! $spine)
        {
            debug(1,"DEBUG: creating <spine>");
            $spine = $twigroot->insert_new_elt('last_child','spine');
        }

        # Make sure that the spine is a child of the twigroot,
        $parent = $spine->parent;
        if($parent != $twigroot)
        {
            debug(1,"DEBUG: moving <spine>");
            $spine->move('last_child',$twigroot);
        }

        # If an NCX item exists in the manifest, reference it as a
        # spine attribute
        if($manifest->has_child('@id="ncx"')) {
            $spine->set_att('toc' => 'ncx');
        }

        foreach my $el (@elements)
        {
            if(!$el->att('idref'))
            {
                # No idref means it is broken.
                # Leave it alone, but log a warning
                $self->add_warning(
                    "fix_spine(): <itemref> with no idref -- skipping");
                next;
            }
            debug(3,"DEBUG: processing itemref '",$el->att('idref'),"')");
            $el->move('last_child',$spine);
        }
    }
    else # No elements, delete spine if it exists
    {
        $spine->delete if($spine);
    }

    return 1;
}


=head2 C<gen_epub(%args)>

Creates a .epub format e-book.  This will create (or overwrite) the
files 'mimetype' and 'META-INF/container.xml' in the current
directory, creating the subdirectory META-INF as needed.

A NCX file will also be created if missing.

=head3 Arguments

This method can take two optional named arguments.

=over

=item C<filename>

The filename of the .epub output file.  If not specified, takes the
base name of the opf file and adds a .epub extension.

=item C<dir>

The directory to output the .epub file.  If not specified, uses the
current working directory.  If a specified directory does not exist,
it will be created, or the method will croak.

=back

=head3 Example

 gen_epub(filename => 'mybook.epub',
          dir => '../epub_books');

=cut

sub gen_epub :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my %valid_args = (
        'filename' => 1,
        'dir' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $filename = $args{filename};
    my $dir = $args{dir};
    my $zip = Archive::Zip->new();
    my $member;
    my $cwd = usedir($self->{topdir});

    $self->gen_epub_files();
    if(! $self->{opffile} )
    {
	$self->add_error(
	    "Cannot create epub without an OPF (did you forget to init?)");
        debug(1,"Cannot create epub without an OPF");
	return;
    }
    if(! -f $self->opfpath)
    {
	$self->add_error(
	    sprintf("OPF '%s' does not exist (did you forget to save?)",
		    $self->opfpath)
	    );
        debug(1,"OPF '",$self->opfpath,"' does not exist");
	return;
    }

    debug(3,"DEBUG: adding core metadata to zip archive");
    $member = $zip->addFile('mimetype');
    $member->desiredCompressionMethod(COMPRESSION_STORED);

    $member = $zip->addFile('META-INF/container.xml');
    $member->desiredCompressionLevel(9);

    $member = $zip->addFile($self->{opfsubdir} . '/' . $self->{opffile});
    $member->desiredCompressionLevel(9);

    debug(3,"DEBUG: adding manifest files to zip archive");
    foreach my $file ($self->manifest_hrefs())
    {
	if(! $file)
	{
	    error("No items found in manifest!");
            debug(1,"No items found in manifest!");
	    return;
	}
	if(-f $self->{opfsubdir} . '/' . $file)
	{
	    $member = $zip->addFile($self->{opfsubdir} . '/' . $file);
	    $member->desiredCompressionLevel(9);
	}
	else { print STDERR "WARNING: ",$self->{opfsubdir} . '/' . $file," not found, skipping.\n"; }
    }

    if(! $filename) {
	$filename = basename($self->{topdir}) . '.epub';
    }

    if($dir)
    {
        unless(-d $dir)
        {
            mkpath($dir)
                or croak("Unable to create working directory '",$dir,"'!");
        }
        $filename = "$dir/$filename";
    }

    unless ( $zip->writeToFileNamed($filename) == AZ_OK )
    {
	$self->add_error(
            sprintf("Failed to create epub as '%s'",$filename));
        debug(1,"Failed to create epub as '",$filename,"'");
	return;
    }

    usedir($cwd);
    return 1;
}


=head2 C<gen_epub_files()>

Generates the C<mimetype> and C<META-INF/container.xml> files expected
by a .epub container, but does not actually generate the .epub file
itself.  This will be called automatically by C<gen_epub>.

The OPF will be normalized to the OPF 2.0 format.

If no NCX element exists, it will also be created.

=cut

sub gen_epub_files :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my $manifest = $self->{twigroot}->first_descendant('manifest');

    $self->fix_opf20();
    if( ! $manifest->first_child('item[@id="ncx"]') ) {
        $self->gen_ncx();
    }
    $self->save();

    # These two functions must happen from the top-level directory, not the OPF directory
    if($self->{opfsubdir} ne '.') {
        debug(3,"DEBUG: switching to ",$self->{topdir}," to generate EPUB metadata");
        my $cwd = usedir($self->{topdir});
        create_epub_mimetype();
        create_epub_container($self->{opfsubdir} . '/' . $self->{opffile});
        usedir($cwd);
    }
    else {
        create_epub_mimetype();
        create_epub_container($self->{opffile});
    }

    return 1;
}


=head2 C<gen_ncx($filename)>

Creates a NCX-format table of contents from the package
unique-identifier, the dc:title, dc:creator, and spine elements, and
then add the NCX entry to the manifest if it is not already
referenced.

Adds an error and fails if any of those cannot be found.  The first
available dc:title is taken, but will prioritize dc:creator elements
with opf:role="aut" over those with no role attribute (see
twigelt_is_author() for details).

WARNING: This method REQUIRES that the e-book be in OPF 2.0 format to
function correctly.  Call fix_opf20() before calling gen_ncx().
gen_ncx() will log an error and fail if $self{spec} is not set to
OPF20.

=head3 Arguments

=over

=item $filename : The filename to save to.  If not specified, will use
'toc.ncx'.

=back

This method will overwrite any existing file.

Returns a twig containing the NCX XML, or undef on failure.

=cut

sub gen_ncx :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my ($filename) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    $filename = 'toc.ncx' if(!$filename);

    my $cwd = usedir($self->opfdir);
    my $twigroot = $self->{twigroot};
    my $identifier = $self->identifier;
    my $element;            # Generic element container
    my $parent;             # Generic parent element container
    my $ncx;                # NCX twig
    my $ncxroot;            # NCX twig root <ncx>
    my $ncxitem;            # manifest item pointing to the NCX document
    my $navmap;             # NCX element <navMap>
    my $navpoint;           # NCX element <navPoint>
    my %navpointorder;      # Hash mapping playOrder to id
    my $navpointindex = 1;  # playOrder number starting at 1
    my $title;              # E-book title
    my $author;             # E-book primary author
    my @spinelist;          # List of hashrefs containing spine data
    my $manifest;           # OPF manifest element
    my $spine;		    # OPF spine element

    if($self->{spec} ne 'OPF20')
    {
        $self->add_error(
            $subname . "(): specification is currently set to '"
            . $self->{spec} . "' -- need 'OPF20'"
            );
        debug(1,"DEBUG: gen_ncx() FAILED: wrong specification ('",
              $self->{spec},"')!");
        return;
    }

    if(!$identifier)
    {
        $self->add_error( $subname . "(): no unique-identifier found" );
        debug(1,"DEBUG: gen_ncx() FAILED: no unique-identifier!");
        return;
    }

    # Get the title
    $title = $self->title();
    if(!$title)
    {
        $self->add_error( $subname . "(): no title found" );
        debug(1,"DEBUG: gen_ncx() FAILED: no title!");
        return;
    }

    # Get the author
    $author = $self->primary_author();
    if(!$author)
    {
        $self->add_error( $subname . "(): no title found" );
        debug(1,"DEBUG: gen_ncx() FAILED: no title!");
        return;
    }

    # Get the spine list
    @spinelist = $self->spine();
    if(!@spinelist)
    {
        $self->add_error( $subname . "(): no spine found" );
        debug(1,"DEBUG: gen_ncx() FAILED: no spine!");
        return;
    }

    # Make sure the manifest element exists
    # (This should in theory never fail, since it is also checked by
    # spine() above)
    $manifest = $twigroot->first_descendant('manifest');
    if(!$manifest)
    {
        $self->add_error( $subname . "(): no manifest found" );
        debug(1,"DEBUG: gen_ncx() FAILED: no manifest!");
        return;
    }

    $ncx = XML::Twig->new(
	output_encoding => 'utf-8',
	pretty_print => 'record'
	);

    # <ncx>
    $element = XML::Twig::Elt->new('ncx');
    $element->set_att('xmlns' => 'http://www.daisy.org/z3986/2005/ncx/');
    $ncx->set_root($element);
    $ncxroot = $ncx->root;

    # <head>
    $parent = $ncxroot->insert_new_elt('first_child','head');
    $element = $parent->insert_new_elt('last_child','meta');
    $element->set_att(
        'name' => 'dtb:uid',
        'content' => $identifier
        );

    $element = $parent->insert_new_elt('last_child','meta');
    $element->set_att(
        'name'    => 'dtb:depth',
        'content' => '1'
        );
    $element = $parent->insert_new_elt('last_child','meta');
    $element->set_att(
        'name' => 'dtb:totalPageCount',
        'content' => '0'
        );

    $element = $parent->insert_new_elt('last_child','meta');
    $element->set_att(
        'name' => 'dtb:maxPageNumber',
        'content' => '0'
        );

    # <docTitle>
    $parent = $parent->insert_new_elt('after','docTitle');
    $element = $parent->insert_new_elt('first_child','text');
    $element->set_text($title);

    # <navMap>
    $navmap = $parent->insert_new_elt('after','navMap');

    foreach my $spineitem (@spinelist)
    {
        # <navPoint>
        $navpoint = $navmap->insert_new_elt('last_child','navPoint');
        $navpoint->set_att('id' => $$spineitem{'id'},
                           'playOrder' => $navpointindex);
        $navpointindex++;

        # <navLabel>
        $parent = $navpoint->insert_new_elt('last_child','navLabel');
        $element = $parent->insert_new_elt('last_child','text');
        $element->set_text($$spineitem{'id'});

        # <content>
        $element = $navpoint->insert_new_elt('last_child','content');
        $element->set_att('src' => $$spineitem{'href'});
    }

    # Backup existing file
    if(-e $filename)
    {
        rename($filename,"$filename.backup")
            or croak($subname,"(): could not backup ",$filename,"!");
    }

    # Twig handles utf-8 on its own.  Setting binmode :utf8 here will
    # cause double-conversion.
    open(my $fh_ncx,'>',$filename)
        or croak($subname,"(): failed to open '",$filename,"' for writing!");
    $ncx->print(\*$fh_ncx);
    close($fh_ncx)
        or croak($subname,"(): failed to close '",$filename,"'!");

    # Search for existing NCX entries and modify the first one found,
    # creating a new one if there are no matches.
    $ncxitem = $manifest->first_child('item[@id="ncx"]');
    $ncxitem = $manifest->first_child("item[\@href='$filename']")
        if(!$ncxitem);
    $ncxitem = $manifest->first_child('item[@media-type="application/x-dtbncx+xml"]')
        if(!$ncxitem);
    $ncxitem = $manifest->insert_new_elt('first_child','item')
        if(!$ncxitem);

    $ncxitem->set_att(
        'id' => 'ncx',
        'href' => $filename,
        'media-type' => 'application/x-dtbncx+xml'
        );

    # Move the NCX item to the top of the manifest
    $ncxitem->move('first_child',$manifest);

    # Ensure that the spine references the NCX
    $spine = $twigroot->first_descendant('spine');
    $spine->set_att('toc' => 'ncx');

    usedir($cwd);
    return $ncx;
}


=head2 C<save()>

Saves the OPF file to disk.  Existing files are backed up to
filename.backup.

=cut

sub save :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    croak($subname,"(): no opffile specified (did you forget to init?)")
        if(!$self->{opffile});

    my $fh_opf;
    my $cwd = usedir($self->opfdir);
    my $filename = $self->{opffile};

    # Backup existing file
    if(-e $filename)
    {
        rename($filename,"$filename.backup")
            or croak($subname,"(): could not backup ",$filename,"!");
    }


    # Twig handles utf8 on its own.  If you open this file with
    # binmode :utf8, it will double-convert.
    if(!open($fh_opf,">",$self->{opffile}))
    {
	add_error(sprintf("Could not open '%s' to save to!",$self->{opffile}));
	return;
    }
    $self->{twig}->print(\*$fh_opf);

    if(!close($fh_opf))
    {
	add_error(sprintf("Failure while closing '%s'!",$self->{opffile}));
	return;
    }

    usedir($cwd);
    return 1;
}


=head2 C<set_adult($bool)>

Sets the Mobipocket-specific <Adult> element, creating or deleting it
as necessary.  If C<$bool> is true, the text is set to 'yes'.  If it
is defined but false, any existing elements are deleted.  If it is
undefined, the method immediately returns.

If a new element has to be created, L</fix_metastructure_oeb12> is
called to ensure that <x-metadata> exists and the element is created
under <x-metadata>, as Mobipocket elements are not recognized by
Mobipocket's software when placed directly under <metadata>

=cut

sub set_adult :method
{
    my $self = shift;
    my $adult = shift;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    return 1 unless(defined $adult);

    my $xmeta;
    my $element;
    my @elements;

    if($adult)
    {
        $element = $self->{twigroot}->first_descendant(qr/^adult$/ix);
        unless($element)
        {
            $self->fix_metastructure_oeb12();
            $xmeta = $self->{twigroot}->first_descendant('x-metadata');
            $element = $xmeta->insert_new_elt('last_child','Adult');
        }
        $element->set_text('yes');
    }
    else
    {
        @elements = $self->{twigroot}->descendants(qr/^adult$/ix);
        foreach my $el (@elements)
        {
            debug(2,"DEBUG: deleting <Adult> flag");
            $el->delete;
        }
    }
    return 1;
}


=head2 C<set_cover(%args)>

Sets a cover image

In OPF 2.0, this is done by setting both a meta and a guide reference
element.  In OEB1.2, this is done by setting the <EmbeddedCover> tag.

If the filename is not currently listed as an item in the manifest, it is added.

=head3 Arguments

=over

=item C<href>

The filename of the image file to use.  This is mandatory.

=item C<id>

The id attribute to assign to its item element

=item C<spec>

The specification to use, either OEB12 or OPF20.  If this is left
undefined, the current spec state will be checked, and if that is
undefined, it will default to OPF20.

=back

=cut

sub set_cover :method
{
    my ($self,%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    my %valid_args = (
        'href' => 1,
        'id' => 1,
        'spec' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $href = $args{href};
    my $newid = $args{id};
    my $spec = $args{spec};
    my $id;
    my $mimetype;
    my $manifest;
    my $guide;
    my $dcmeta;
    my $element;

    if(! $href) {
        $self->add_error($subname,"(): no href specified");
        return;
    }
    $mimetype = mimetype($href);
    if($mimetype !~ m#^image/#ix) {
        $self->add_warning(
            $subname,"(): ",$href,
            " does not appear to be an image (detected: ",$mimetype,")"
           );
    }

    if(! $spec) {
        $spec = $self->spec || 'OPF20';
    }

    # Ensure that there is a matching manifest item
    $manifest = $self->{twigroot}->first_child('manifest');
    $element = $manifest->first_child('item[@href="' . $href . '"]');
    if($element) {
        if($newid) {
            $element->set_id($newid);
        }
    }
    else {
        $element = $manifest->insert_new_elt('first_child','item');
        if($newid) {
            $element->set_id($newid);
        }
        else {
            $element->set_id($href);
        }
        $element->set_att('href',$href);
        $element->set_att('media-type',$mimetype);
    }
    $id = $element->id;

    given($spec) {
        when(/OPF20/) {
            $self->fix_metastructure_basic;
            $self->fix_guide;
            $guide = $self->{twigroot}->first_child('guide');
            $element = $guide->first_child('reference[@type="other.ms-coverimage-standard"]');
            if($element) {
                $element->set_att('href',$href);
                $element->set_att('title','Cover');
            }
            else {
                $element = $guide->insert_new_elt('last_child','reference');
                $element->set_att('href',$href);
                $element->set_att('title','Cover');
                $element->set_att('type','other.ms-coverimage-standard');
            }
            $self->set_meta('name' => 'cover',
                            'content' => $href);
        }
        when(/OEB12/) {
            $self->fix_metastructure_oeb12;
            $dcmeta = $self->{twigroot}->first_child('dc-metadata');
            $element = $dcmeta->first_child('EmbeddedCover');
            if($element) {
                $element->set_text($href);
            }
            else {
                $element = $dcmeta->insert_new_elt('last_child','EmbeddedCover');
                $element->set_text($href);
            }
        }
        default {
            self->add_error($subname,"(): unknown specification type: '",$spec,"'");
        }
    }
        return;
}


=head2 C<set_date(%args)>

Sets the date metadata for a given event.  If more than one dc:date or
dc:Date element is present with the specified event attribute, sets
the first.  If no dc:date element is present with the specified event
attribute, a new element is created.

If a <dc-metadata> element exists underneath <metadata>, the date
element will be created underneath the <dc-metadata> in OEB 1.2
format, otherwise the title element is created underneath <metadata>
in OPF 2.0 format.

Returns 1 on success, logs an error and returns undef if no text or
event was specified.

=head3 Arguments

=over

=item C<text>

This specifies the description to use as the text of the element.  If
not specified, the method sets an error and returns undef.

=item C<event>

This optionally specifies the event attribute for the date.  This
attribute is not valid in OPF 3.0 (which only allows publication date
in this element) and should no longer be used.

=item C<id> (optional)

This specifies the ID to set on the element.  If set and the ID is
already in use, a warning is logged and the ID is removed from the
other location and assigned to the element.

=back

=cut

sub set_date :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    my %valid_args = (
        'text' => 1,
        'event' => 1,
        'id' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $text = $args{text};
    my $event = $args{event};
    my $newid = $args{id};
    unless($text)
    {
        $self->add_error($subname,"(): no text specified");
        return;
    }

    my $meta = $self->{twigroot}->first_child('metadata');
    my $dcmeta = $meta->first_child('dc-metadata');
    my $idelem;
    $idelem = $self->{twig}->first_elt("*[\@id='$newid']") if($newid);

    $self->fix_metastructure_basic();

    my $element;
    if($event) {
        $element = $self->{twigroot}->first_descendant(
            "dc:date[\@opf:event=~/$event/ix or \@event=~/$event/ix]");
        $element = $self->{twigroot}->first_descendant(
            "dc:Date[\@opf:event=~/$event/ix or \@event=~/$event/ix]")
          unless($element);
    }
    else {
        $element = $self->{twigroot}->first_descendant("dc:date");
        $element = $self->{twigroot}->first_descendant("dc:Date")
          unless($element);
    }

    if($element)
    {
        $element->set_text($text);
    }
    elsif($dcmeta)
    {
        $element = $dcmeta->insert_new_elt('last_child','dc:Date');
        $element->set_text($text);
        if($event) {
            $element->set_att('event',$event);
        }
    }
    else
    {
        $element = $meta->insert_new_elt('last_child','dc:date');
        $element->set_text($text);
        if($event) {
            $element->set_att('opf:event',$event);
        }
    }

    if($idelem && $idelem->cmp($element) )
    {
        $self->add_warning(
            $subname,"(): reassigning id '",$newid,
            "' from a '",$idelem->gi,"' element!"
            );
        $idelem->del_att('id');
    }
    $element->set_att('id' => $newid) if($newid);
    return 1;
}


=head2 set_description(%args)

Sets the text and optionally ID of the first dc:description element
found (case-insensitive).  Creates the element if one did not exist.
If a <dc-metadata> element exists underneath <metadata>, the
description element will be created underneath the <dc-metadata> in
OEB 1.2 format, otherwise the title element is created underneath
<metadata> in OPF 2.0 format.

Returns 1 on success, returns undef if no publisher was specified.

=head3 Arguments

C<set_description()> takes one required and one optional named argument

=over

=item C<text>

This specifies the description to use as the text of the element.  If
not specified, the method returns undef.

=item C<id> (optional)

This specifies the ID to set on the element.  If set and the ID is
already in use, a warning is logged and the ID is removed from the
other location and assigned to the element.

=back

=head3 Example

 $retval = $ebook->set_description('text' => 'A really good book',
                                   'id' => 'mydescid');

=cut

sub set_description :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    my %valid_args = (
        'text' => 1,
        'id' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $text = $args{text};
    unless($text)
    {
        $self->add_error($subname,"(): no text specified");
        return;
    }

    $self->fix_metastructure_basic();
    my $element = $self->{twigroot}->first_descendant(qr/^dc:description$/ix);
    my $meta = $self->{twigroot}->first_child('metadata');
    my $dcmeta = $meta->first_child('dc-metadata');

    my $gi = ($dcmeta) ? 'dc:Description' : 'dc:description';
    $self->set_metadata(gi => $gi,
                        text => $text,
                        id => $args{id});

    return 1;
}


=head2 C<set_language(%args)>

Sets the text and optionally the ID of the first dc:language element
found (case-insensitive).  Creates the element if one did not exist.
If a <dc-metadata> element exists underneath <metadata>, the language
element will be created underneath the <dc-metadata> in OEB 1.2
format, otherwise the title element is created underneath <metadata>
in OPF 2.0 format.

Returns 1 on success, returns undef if no text was specified.

=head3 Arguments

=over

=item C<text>

This specifies the language set as the text of the element.  If not
specified, the method sets an error and returns undef.  This should be
an IANA language code, and it will be lowercased before it is set.

=item C<id> (optional)

This specifies the ID to set on the element.  If set and the ID is
already in use, a warning is logged and the ID is removed from the
other location and assigned to the element.

=back

=head3 Example

 $retval = $ebook->set_language('text' => 'en-us',
                                'id' => 'langid');

=cut

sub set_language :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    my %valid_args = (
        'text' => 1,
        'id' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $text = lc($args{text});
    unless($text)
    {
        $self->add_error($subname,"(): no text specified");
        return;
    }

    $self->fix_metastructure_basic();
    my $element = $self->{twigroot}->first_descendant(qr/^dc:language$/ix);
    my $meta = $self->{twigroot}->first_child('metadata');
    my $dcmeta = $meta->first_child('dc-metadata');

    my $gi = ($dcmeta) ? 'dc:Language' : 'dc:language';
    $self->set_metadata(gi => $gi,
                        text => $text,
                        id => $args{id});
    return 1;
}


=head2 set_meta(%args)

Sets a <meta> element in the <metadata> element area.

=head3 Arguments

=over

=item C<name>

The name attribute to use when finding or creating the <meta> element.
This must be specified.

=item C<content>

The value of the content attribute to set.  If this value is empty or
undefined, but C<name> is provided and matches an existing element,
that element will be deleted.

=back

=cut

sub set_meta :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(3,"DEBUG[",$subname,"]");
    my %valid_args = (
        'name' => 1,
        'content' => 1,
        );
    foreach my $arg (keys %args) {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $name = $args{name};
    my $content = $args{content};

    unless($name) {
        $self->add_error($subname,"(): no name specified for the meta tag");
        return;
    }

    $self->fix_metastructure_basic();
    my $metadata = $self->{twigroot}->first_child('metadata');
    my $element = $metadata->first_descendant('meta[@name="' . $name . '"]');

    if($element) {
        if(! $content) {
            debug(2,"DEBUG: deleting <meta name='",$name,"'>");
            $element->delete;
        }
        else {
            debug(2,"DEBUG: updating <meta name='",$name,"'>");
            $element->set_att('content',$content);
        }
    }
    else {
        if($content) {
            debug(2,"DEBUG: creating <meta name='",$name,"'>");
            $element = $metadata->insert_new_elt('last_child','meta');
            $element->set_att('name',$name);
            $element->set_att('content',$content);
        }
    }
}


=head2 set_metadata(%args)

Sets the text and optionally the ID of the first specified element
type found (case-insensitive).  Creates the element if one did not
exist (with the exact capitalization specified).

If a <dc-metadata> element exists underneath <metadata>, the language
element will be created underneath the <dc-metadata> and any standard
attributes will be created in OEB 1.2 format, otherwise the element is
created underneath <metadata> in OPF 2.0 format.

Returns 1 on success, returns undef if no gi or if no text was specified.

=cut

=head3 Arguments

=over

=item C<gi>

The generic identifier (tag) of the metadata element to alter or
create.  If not specified, the method sets an error and returns undef.

=item C<parent>

The generic identifier (tag) of the parent to use for any newly
created element.  If not specified, defaults to 'dc-metadata' if
'dc-metadata' exists underneath 'metadata', and 'metadata' otherwise.

A newly created element will be created under the first element found
with this gi.  A modified element will be moved under the first
element found with this gi.

Newly created elements will use OPF 2.0 attribute names if the parent
is 'metadata' and OEB 1.2 attribute names otherwise.

=item C<text>

This specifies the element text to set.  If not specified, the method
sets an error and returns undef.

=item C<id> (optional)

This specifies the ID to set on the element.  If set and the ID is
already in use, a warning is logged and the ID is removed from the
other location and assigned to the element.

=item C<fileas> (optional)

This specifies the file-as attribute to set on the element.

=item C<role> (optional)

This specifies the role attribute to set on the element.

=item C<scheme> (optional)

This specifies the scheme attribute to set on the element.

=back

=head3 Example

 $retval = $ebook->set_metadata(gi => 'AuthorNonstandard',
                                text => 'Element Text',
                                id => 'customid',
                                fileas => 'Text, Element',
                                role => 'xxx',
                                scheme => 'code');

=cut

sub set_metadata :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(3,"DEBUG[",$subname,"]");
    my %valid_args = (
        'gi' => 1,
        'parent' => 1,
        'text' => 1,
        'id' => 1,
        'fileas' => 1,
        'role' => 1,
        'scheme' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $gi = $args{gi};
    unless($gi)
    {
        $self->add_error($subname,"(): no gi specified");
        return;
    }

    my $text = $args{text};
    unless($text)
    {
        $self->add_error($subname,"(): no text specified");
        return;
    }

    my $newid = $args{id};
    my $idelem;
    $idelem = $self->{twig}->first_elt("*[\@id='$newid']") if($newid);

    my $element = $self->{twigroot}->first_descendant(qr/^ $gi $/ix);
    my $meta;
    my $dcmeta;
    my $parent;
    my %dcatts;

    $self->fix_metastructure_basic();
    $parent =  $self->{twigroot}->first_descendant(qr/^ $args{parent} $/ix)
        if($args{parent});
    $meta = $self->{twigroot}->first_child('metadata');
    $dcmeta = $meta->first_child('dc-metadata');
    $parent = $parent || $dcmeta || $meta;
    if($parent->gi eq 'metadata')
    {
        %dcatts = (
            'file-as' => 'opf:file-as',
            'role' => 'opf:role',
            'scheme' => 'opf:scheme',
            );
    }
    else
    {
        %dcatts = (
            'file-as' => 'file-as',
            'role' => 'role',
            'scheme' => 'scheme'
        );
    }


    if($element)
    {
        debug(2,"DEBUG: updating '",$gi,"'");
        if($element->att('opf:file-as') && $args{fileas})
        {
            debug(3,"DEBUG:   setting opf:file-as '",$args{fileas},"'");
            $element->set_att('opf:file-as',$args{fileas});
        }
        elsif($args{fileas})
        {
            debug(3,"DEBUG:   setting file-as '",$args{fileas},"'");
            $element->set_att('file-as',$args{fileas});
        }
        if($element->att('opf:role') && $args{role})
        {
            debug(3,"DEBUG:   setting opf:role '",$args{role},"'");
            $element->set_att('opf:role',$args{role});
        }
        elsif($args{role})
        {
            debug(3,"DEBUG:   setting role '",$args{role},"'");
            $element->set_att('role',$args{role});
        }
        if($element->att('opf:scheme') && $args{scheme})
        {
            debug(3,"DEBUG:   setting opf:scheme '",$args{scheme},"'");
            $element->set_att('opf:scheme',$args{scheme});
        }
        elsif($args{scheme})
        {
            debug(3,"DEBUG:   setting scheme '",$args{scheme},"'");
            $element->set_att('scheme',$args{scheme});
        }
        debug(3,"DEBUG:   setting text");
        $element->set_text($text);

        unless($element->parent->gi eq $parent->gi)
        {
            debug(2,"DEBUG: moving <",$element->gi,"> under <",
                  $parent->gi,">");
            $element->move('last_child',$parent);
        }
    }
    else
    {
        debug(2,"DEBUG: creating '",$gi,"' under <",$parent->gi,">");
        $element = $parent->insert_new_elt('last_child',$gi);
        $element->set_att($dcatts{'file-as'},$args{fileas})
            if($args{fileas});
        $element->set_att($dcatts{'role'},$args{role})
            if($args{role});
        $element->set_att($dcatts{'scheme'},$args{scheme})
            if($args{scheme});
        $element->set_text($text);
    }

    if($idelem && $idelem->cmp($element) )
    {
        $self->add_warning(
            $subname,"(): reassigning id '",$newid,
            "' from a '",$idelem->gi,"' to a '",$element->gi,"'!"
            );
        $idelem->del_att('id');
    }
    $element->set_att('id' => $newid) if($newid);
    return 1;
}


=head2 set_opffile($filename)

Sets the filename used to store the OPF metadata.

Returns 1 on success; sets an error message and returns undef if no
filename was specified.

=cut

sub set_opffile :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my ($filename) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    unless($filename)
    {
        debug(1,$subname,"(): no filename specified!");
        $self->add_warning($subname,"(): no filename specified!");
        return;
    }
    $self->{opffile} = $filename;
    return 1;
}


=head2 set_retailprice(%args)

Sets the Mobipocket-specific <SRP> element (Suggested Retail Price),
creating or deleting it as necessary.

If a new element has to be created, L</fix_metastructure_oeb12> is
called to ensure that <x-metadata> exists and the element is created
under <x-metadata>, as Mobipocket elements are not recognized by
Mobipocket's software when placed directly under <metadata>

=head3 Arguments

=over

=item * C<text>

The price to set as the text of the element.  If this is undefined,
the method sets an error and returns undef.  If it is set but false,
any existing <SRP> element is deleted.

=item * C<currency> (optional)

The value to set on the 'Currency' attribute.  If not provided,
defaults to 'USD' (US Dollars)

=back

=cut

sub set_retailprice :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my %args = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    $self->twigcheck;

    my %valid_args = (
        'text' => 1,
        'currency' => 1,
        );

    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }
    unless(defined $args{text})
    {
        $self->add_error($subname,"(): text not defined");
        return;
    }

    my $xmeta;
    my $element;
    my @elements;

    if($args{text})
    {
        $element = $self->{twigroot}->first_descendant(qr/^ SRP $/ix);
        unless($element)
        {
            $self->fix_metastructure_oeb12();
            $xmeta = $self->{twigroot}->first_descendant('x-metadata');
            $element = $xmeta->insert_new_elt('last_child','SRP');
        }
        $element->set_text($args{text});
        $element->set_att('Currency',$args{currency}) if($args{currency});
    }
    else
    {
        @elements = $self->{twigroot}->descendants(qr/^ SRP $/ix);
        foreach my $el (@elements)
        {
            debug(2,"DEBUG: deleting <SRP>");
            $el->delete;
        }
    }
    return 1;
}


=head2 set_primary_author(%args)

Sets the text, id, file-as, and role attributes of the primary author
element (see L</primary_author()> for details on how this is found),
or if no primary author exists, creates a new element containing the
information.

This method calls L</fix_metastructure_basic()> to enforce the
presence of the <metadata> element.  When creating a new element, the
method will use the OEB 1.2 element name and create the element
underneath <dc-metadata> if an existing <dc-metadata> element is found
underneath <metadata>.  If no existing <dc-metadata> element is found,
the new element will be created with the OPF 2.0 element name directly
underneath <metadata>.  Regardless, it is probably a good idea to call
L</fix_oeb12()> or L</fix_opf20()> after calling this method to ensure
a consistent scheme.

=head3 Arguments

Three optional named arguments can be passed:

=over

=item * C<text>

Specifies the author text to set.  If omitted and a primary author
element exists, the text will be left as is; if omitted and a primary
author element cannot be found, an error message will be generated and
the method will return undef.

=item * C<fileas>

Specifies the 'file-as' attribute to set.  If omitted and a primary
author element exists, any existing attribute will be left untouched;
if omitted and a primary author element cannot be found, the newly
created element will not have this attribute.

=item * C<id>

Specifies the 'id' attribute to set.  If this is specified, and the id
is already in use, a warning will be added but the method will
continue, removing the id attribute from the element that previously
contained it.

If this is omitted and a primary author element exists, any existing
id will be left untouched; if omitted and a primary author element
cannot be found, the newly created element will not have an id set.

=back

If called with no arguments, the only effect this method has is to
enforce that either an 'opf:role' or 'role' attribute is set to 'aut'
on the primary author element.

=head3 Return values

Returns 1 if successful, returns undef and sets an error message if
the author argument is missing and no primary author element was
found.

=cut

sub set_primary_author :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    my %valid_args = (
        'text' => 1,
        'fileas' => 1,
        'id' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $twigroot = $self->{twigroot};
    $self->fix_metastructure_basic();
    my $meta = $twigroot->first_child('metadata');
    my $dcmeta = $meta->first_child('dc-metadata');
    my $element;
    my $newauthor = $args{text};
    my $newfileas = $args{fileas};
    my $newid = $args{id};
    my $idelem;
    $idelem = $self->{twig}->first_elt("*[\@id='$newid']") if($newid);

    $element = $twigroot->first_descendant(\&twigelt_is_author);
    $element = $twigroot->first_descendant(qr/dc:creator/ix) if(!$element);

    unless($element)
    {
        unless($newauthor)
        {
            add_error(
                $subname,
                "(): cannot create a new author element when the author is not specified");
            return;
        }
        if($dcmeta)
        {
            $element = $dcmeta->insert_new_elt('last_child','dc:Creator');
            $element->set_att('role' => 'aut');
            $element->set_att('file-as' => $newfileas) if($newfileas);
        }
        else
        {
            $element = $meta->insert_new_elt('last_child','dc:creator');
            $element->set_att('opf:role' => 'aut');
            $element->set_att('opf:file-as' => $newfileas) if($newfileas);
        }
    } # unless($element)
    $element->set_text($newauthor);

    if($idelem && $idelem->cmp($element) )
    {
        $self->add_warning(
            $subname,"(): reassigning id '",$newid,
            "' from a '",$idelem->gi,"' element!"
            );
        $idelem->del_att('id');
    }
    $element->set_att('id' => $newid) if($newid);
    return 1;
}


=head2 C<set_publisher(%args)>

Sets the text and optionally the ID of the first dc:publisher element
found (case-insensitive).  Creates the element if one did not exist.
If a <dc-metadata> element exists underneath <metadata>, the publisher
element will be created underneath the <dc-metadata> in OEB 1.2
format, otherwise the title element is created underneath <metadata>
in OPF 2.0 format.

Returns 1 on success, returns undef if no publisher was specified.

=head3 Arguments

C<set_publisher()> takes one required and one optional named argument

=over

=item C<text>

This specifies the publisher name to set as the text of the element.
If not specified, the method returns undef.

=item C<id> (optional)

This specifies the ID to set on the element.  If set and the ID is
already in use, a warning is logged and the ID is removed from the
other location and assigned to the element.

=back

=head3 Example

 $retval = $ebook->set_publisher('text' => 'My Publishing House',
                                 'id' => 'mypubid');

=cut

sub set_publisher :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    my %valid_args = (
        'text' => 1,
        'id' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $publisher = $args{text};
    return unless($publisher);

    my $newid = $args{id};
    my $idelem;
    $idelem = $self->{twig}->first_elt("*[\@id='$newid']") if($newid);

    $self->fix_metastructure_basic();
    my $element = $self->{twigroot}->first_descendant(qr/^dc:publisher$/ix);
    my $meta = $self->{twigroot}->first_child('metadata');
    my $dcmeta = $meta->first_child('dc-metadata');

    if(!$element && $dcmeta)
    {
        $element = $dcmeta->insert_new_elt('last_child','dc:Publisher');
    }
    elsif(!$element)
    {
        $element = $meta->insert_new_elt('last_child','dc:publisher');
    }
    $element->set_text($publisher);
    if($idelem && $idelem->cmp($element) )
    {
        $self->add_warning(
            $subname,"(): reassigning id '",$newid,
            "' from a '",$idelem->gi,"' element!"
            );
        $idelem->del_att('id');
    }
    $element->set_att('id' => $newid) if($newid);
    return 1;
}


=head2 set_review(%args)

Sets the text and optionally ID of the first <Review> element found
(case-insensitive), creating the element if one did not exist.

This is a Mobipocket-specific element and if it needs to be created it
will always be created under <x-metadata> with
L</fix_metastructure_oeb12()> called to ensure that <x-metadata>
exists.

Returns 1 on success, returns undef if no review text was specified

=head3 Arguments

=over

=item C<text>

This specifies the description to use as the text of the element.  If
not specified, the method returns undef.

=item C<id> (optional)

This specifies the ID to set on the element.  If set and the ID is
already in use, a warning is logged and the ID is removed from the
other location and assigned to the element.

=back

=head3 Example

 $retval = $ebook->set_review('text' => 'This book is perfect!',
                              'id' => 'revid');

=cut

sub set_review :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    my %valid_args = (
        'text' => 1,
        'id' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $text = $args{text};
    unless($text)
    {
        $self->add_error($subname,"(): no text specified");
        return;
    }

    $self->fix_metastructure_oeb12();
    $self->set_metadata(gi => 'Review',
                        parent => 'x-metadata',
                        text => $args{text},
                        id => $args{id});

    return 1;
}


=head2 C<set_rights(%args)>

Sets the text of the first dc:rights or dc:copyrights element found
(case-insensitive).  If the element found has the gi of dc:copyrights,
it will be changed to dc:rights.  This is to correct certain
noncompliant Mobipocket files.

Creates the element if one did not exist.  If a <dc-metadata> element
exists underneath <metadata>, the title element will be created
underneath the <dc-metadata> in OEB 1.2 format, otherwise the title
element is created underneath <metadata> in OPF 2.0 format.

Returns 1 on success, returns undef if no rights string was specified.

=head3 Arguments

=over

=item * C<text>

This specifies the text of the element.  If not specified, the method
returns undef.

=item * C<id> (optional)

This specifies the ID to set on the element.  If set and the ID is
already in use, a warning is logged but the method continues anyway.

=back

=cut

sub set_rights :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    my %valid_args = (
        'text' => 1,
        'id' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }
    my $rights = $args{text};
    return unless($rights);
    my $newid = $args{id};
    my $idelem;
    $idelem = $self->{twig}->first_elt("*[\@id='$newid']") if($newid);

    $self->fix_metastructure_basic();
    my $element = $self->{twigroot}->first_descendant(qr/^dc:(copy)?rights$/ix);
    my $meta = $self->{twigroot}->first_child('metadata');
    my $dcmeta = $meta->first_child('dc-metadata');
    my $parent = $dcmeta || $meta;

    $element ||= $parent->insert_new_elt('last_child','dc:rights');
    $element->set_text($rights);
    $element->set_gi('dc:Rights') if($element->gi eq 'dc:Copyrights');
    $element->set_gi('dc:rights') if($element->gi eq 'dc:copyrights');
    if($idelem && $idelem->cmp($element) )
    {
        $self->add_warning(
            $subname,"(): reassigning id '",$newid,
            "' from a '",$idelem->gi,"' element!"
            );
        $idelem->del_att('id');
    }
    $element->set_att('id' => $newid) if($newid);
    return 1;
}


=head2 C<set_spec($spec)>

Sets the OEB specification to match when modifying OPF data.
Allowable values are 'OEB12', 'OPF20', and 'MOBI12'.

Returns 1 if successful; returns undef and sets an error message if an
unknown specification was set.

=cut

sub set_spec :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my ($spec) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    unless($validspecs{$spec})
    {
        $self->add_error($subname,"(): invalid specification '",$spec,"'");
        return;
    }
    $self->{spec} = $validspecs{$spec};
    return 1;
}


=head2 C<set_title(%args)>

Sets the text or id of the first dc:title element found
(case-insensitive).  Creates the element if one did not exist.  If a
<dc-metadata> element exists underneath <metadata>, the title element
will be created underneath the <dc-metadata> in OEB 1.2 format,
otherwise the title element is created underneath <metadata> in OPF
2.0 format.

=head3 Arguments

set_title() takes two optional named arguments.  If neither is
specified, the method will do nothing.

=over

=item * C<text>

This specifies the text of the element.  If not specified, and no
title element is found, an error will be set and the method will
return undef -- set_title() will refuse to create a dc:title element
with no text.

=item * C<id>

This specifies the ID to set on the element.  If set and the ID is
already in use, a warning is logged but the method continues anyway.

=back

=cut

sub set_title :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my %valid_args = (
        'text' => 1,
        'id' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }
    my $title = $args{text};
    my $newid = $args{id};
    my $idelem;
    $idelem = $self->{twig}->first_elt("*[\@id='$newid']") if($newid);

    $self->fix_metastructure_basic();
    my $element = $self->{twigroot}->first_descendant(qr/^dc:title$/ix);
    my $meta = $self->{twigroot}->first_child('metadata');
    my $dcmeta = $meta->first_child('dc-metadata');
    my $parent = $dcmeta || $meta;
    unless($element)
    {
        unless($title)
        {
            add_error($subname,
                      "(): no title specified, but no existing title found");
            return;
        }
        $element = $parent->insert_new_elt('last_child','dc:title');
    }
    $element->set_text($title) if($title);

    if($idelem && $idelem->cmp($element) )
    {
        $self->add_warning(
            $subname,"(): reassigning id '",$newid,
            "' from a '",$idelem->gi,"' element!"
            );
        $idelem->del_att('id');
    }
    $element->set_att('id' => $newid) if($newid);
    return 1;
}


=head2 C<set_type(%args)>

Sets the text and optionally the ID of the first dc:type element
found (case-insensitive).  Creates the element if one did not exist.
If a <dc-metadata> element exists underneath <metadata>, the publisher
element will be created underneath the <dc-metadata> in OEB 1.2
format, otherwise the title element is created underneath <metadata>
in OPF 2.0 format.

Returns 1 on success, returns undef if no publisher was specified.

=head3 Arguments

C<set_type()> takes one required and one optional named argument

=over

=item C<text>

This specifies the publisher name to set as the text of the element.
If not specified, the method returns undef.

=item C<id> (optional)

This specifies the ID to set on the element.  If set and the ID is
already in use, a warning is logged and the ID is removed from the
other location and assigned to the element.

=back

=head3 Example

 $retval = $ebook->set_type('text' => 'Short Story',
                            'id' => 'mytypeid');

=cut

sub set_type :method    ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname . "() called as a procedure") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    my %valid_args = (
        'text' => 1,
        'id' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $text = $args{text};
    return unless($text);

    my $newid = $args{id};
    my $idelem;
    $idelem = $self->{twig}->first_elt("*[\@id='$newid']") if($newid);

    $self->fix_metastructure_basic();
    my $element = $self->{twigroot}->first_descendant(qr/^dc:type$/ix);
    my $meta = $self->{twigroot}->first_child('metadata');
    my $dcmeta = $meta->first_child('dc-metadata');

    if(!$element && $dcmeta)
    {
        $element = $dcmeta->insert_new_elt('last_child','dc:Type');
    }
    elsif(!$element)
    {
        $element = $meta->insert_new_elt('last_child','dc:type');
    }
    $element->set_text($text);
    if($idelem && $idelem->cmp($element) )
    {
        $self->add_warning(
            $subname,"(): reassigning id '",$newid,
            "' from a '",$idelem->gi,"' element!"
            );
        $idelem->del_att('id');
    }
    $element->set_att('id' => $newid) if($newid);
    return 1;
}


################################
########## PROCEDURES ##########
################################

=head1 PROCEDURES

All procedures are exportable, but none are exported by default.  All
procedures can be exported by using the ":all" tag.


=head2 C<capitalize($string)>

Capitalizes the first letter of each word in $string.

Returns the corrected string.

=cut

sub capitalize {
    my ($string) = @_;
    $string =~ s/(?<=\w)(.)/\l$1/gx;
    return $string;
}


=head2 C<create_epub_container($opffile)>

Creates the XML file META-INF/container.xml pointing to the
specified OPF file.

Creates the META-INF directory if necessary.  Will destroy any
non-directory file named 'META-INF' in the current directory.  If
META-INF/container.xml already exists, it will rename that file to
META-INF/container.xml.backup.

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
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $twig;
    my $twigroot;
    my $rootfiles;
    my $element;
    my $fh_container;

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


    # Backup existing file
    if(-e 'META-INF/container.xml')
    {
        rename('META-INF/container.xml','META-INF/container.xml.backup')
            or croak($subname,"(): could not backup container.xml!");
    }

    # Twig handles utf-8 on its own.  Setting binmode :utf8 here will
    # cause a double-conversion.
    open($fh_container,'>','META-INF/container.xml')
        or croak($subname,"(): could not write to 'META-INF/container.xml'\n");
    $twig->print(\*$fh_container);
    close($fh_container)
        or croak($subname,"(): could not close 'META-INF/container.xml'\n");
    return $twig;
}


=head2 C<create_epub_mimetype()>

Creates a file named 'mimetype' in the current working directory
containing 'application/epub+zip' (no trailing newline)

Destroys and overwrites that file if it exists.

Returns the mimetype string if successful, undef otherwise.

=cut

sub create_epub_mimetype
{
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $mimetype = "application/epub+zip";
    my $fh_mimetype;

    open($fh_mimetype,">",'mimetype') or return;
    print {*$fh_mimetype} $mimetype;
    close($fh_mimetype) or croak($subname,"(): failed to close filehandle [$!]");

    return $mimetype;
}


=head2 C<debug($level,@message)>

Prints a debugging message to C<STDERR> if package variable C<$debug>
is greater than or equal to C<$level>.  A trailing newline is
appended, and should not be part of @message.

Returns true or dies.

=cut

sub debug
{
    my ($level,@message) = @_;
    my $subname = ( caller(0) )[3];
    croak($subname,"(): no debugging level specified") unless($level);
    croak($subname,"(): invalid debugging level '",$level,"'")
        unless( $level =~ /^\d$/ );
    croak($subname,"(): no message specified") unless(@message);
    print {*STDERR} @message,"\n" if($debug >= $level);
    return 1;
}


=head2 C<excerpt_line($text)>

Takes as an argument a list of text pieces that will be joined.  If
the joined length is less than 70, all of the joined text is returned.

If the joined length is greater than 70, the return string is the
first 30 characters followed by C<' [...] '> followed by the last 30
characters.

=cut

sub excerpt_line
{
    my @parts = @_;
    my $subname = ( caller(0) )[3];
    my $text = join('',@parts);
    if(length($text) > 70)
    {
        $text =~ /^ (.{30}) .*? (.{30}) $/sx;
        return ($1 . ' [...] ' . $2);
    }
    else { return $text; }
}


=head2 C<find_in_path($pattern,@extradirs)>

Searches through C<$ENV{PATH}> (and optionally any additional
directories specified in C<@extradirs>) for the first regular file
matching C<$pattern>.  C<$pattern> itself can take two forms: if
passed a C<qr//> regular expression, that expression is used directly.
If passed any other string, that string will be used for a
case-insensitive exact match where the extension '.bat', '.com', or
'.exe' is optional (i.e. the final pattern will be
C<qr/^ $pattern (\.bat|\.com|\.exe)? $/ix>).

Returns the first match found, or undef if there were no matches or if
no pattern was specified.

=cut

sub find_in_path
{
    my ($pattern,@extradirs) = @_;
    return unless($pattern);
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    my $regexp;
    my @dirs;
    my $fh_dir;
    my @filelist;
    my $envsep = ':';
    my $filesep = '/';
    if($OSNAME eq 'MSWin32')
    {
        $envsep = ';';
        $filesep = "\\";
    }

    if(ref($pattern) eq 'Regexp') { $regexp = $pattern; }
    else { $regexp = qr/^ $pattern (\.bat|\.com|\.exe)? $/ix; }

    @dirs = split(/$envsep/,$ENV{PATH});
    unshift(@dirs,@extradirs) if(@extradirs);
    foreach my $dir (@dirs)
    {
        if(-d $dir)
        {
            if(opendir($fh_dir,$dir))
            {
                @filelist = grep { /$regexp/ } readdir($fh_dir);
                @filelist = grep { -f "$dir/$_" } @filelist;
                closedir($fh_dir);

                if(@filelist) { return $dir . $filesep . $filelist[0]; }
            }
        }
    }
    return;
}

=head2 C<find_links($filename)>

Searches through a file for href and src attributes, and returns a
list of unique links with any named anchors removed
(e.g. 'myfile.html#part7' returns as just 'myfile.html').  If no links
are found, or the file does not exist, returns undef.

Does not check to see if the links are local.  Requires that links be
surrounded by double quotes, not single or left bare.  Assumes that
any link will not be broken across multiple lines, so it will (for
example) fail to find:

 <img src=
 "myfile.jpg">

though it can find:

 <img
  src="myfile.jpg">

This also does not distinguish between local files and remote links.

=cut

sub find_links
{
    my ($filename) = @_;
    return unless(-f $filename);
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    my $fh;
    my %linkhash;
    my @links;

    my $subdir = dirname($filename);
    if($subdir eq '.') {
        $subdir = '';
    }
    else {
        $subdir = $subdir . '/';
    }

    open($fh,'<:raw',$filename)
        or croak($subname,"(): unable to open '",$filename,"'\n");

    while(<$fh>)
    {
        @links = /(?:href|src) \s* = \s* "
                  ([^">]+)/gix;
        foreach my $link (@links)
        {
            # Strip off any named anchors
            $link =~ s/#.*$//;
            next unless($link);

            # If the link is not a URI and we are in a subdirectory
            # relative to the OPF, ensure that subdirectory is placed
            # as a prefix.
            if($subdir and $link !~ m#^ \w+://#ix) {
                $link = $subdir . $link;
            }
            debug(2, "DEBUG: found link '",$link,"'");
            $linkhash{$link}++;
        }
    }
    if(%linkhash) { return keys(%linkhash); }
    else { return; }
}


=head2 C<find_opffile()>

Attempts to locate an OPF file, first by calling
L</get_container_rootfile()> to check the contents of
C<META-INF/container.xml>, and then by looking for a single file with
the extension C<.opf> in the current working directory.

Returns the filename of the OPF file, or undef if nothing was found.

=cut

sub find_opffile
{
    my $subname = ( caller(0) )[3];
    my $opffile = get_container_rootfile();

    if(!$opffile)
    {
	my @candidates = glob("*.opf");
        if(scalar(@candidates) > 1)
        {
            debug(1,"DEBUG: Multiple OPF files found, but no container",
                  " to specify which one to choose!");
            return;
        }
        if(scalar(@candidates) < 1)
        {
            debug(1,"DEBUG: No OPF files found!");
            return;
        }
        $opffile = $candidates[0];
    }
    return $opffile;
}


=head2 C<fix_datestring($datestring)>

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
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $date;
    my ($year,$month,$day);
    my $fixeddate;

    $_ = $datestring;

    debug(3,"DEBUG: checking M(M)/D(D)/YYYY");
    if(( ($month,$day,$year) = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/x ) == 3)
    {
	# We have a XX/XX/XXXX datestring
	debug(3,"DEBUG: found '",$month,"/",$day,"/",$year,"'");
	($year,$month,$day) = ymd_validate($year,$month,$day);
	if($year)
	{
	    $fixeddate = $year;
	    $fixeddate .= sprintf("-%02u",$month)
		unless( ($month == 1) && ($day == 1) );
	    $fixeddate .= sprintf("-%02u",$day) unless($day == 1);
	    debug(3,"DEBUG: returning '",$fixeddate,"'");
	    return $fixeddate;
	}
    }

    debug(3,"DEBUG: checking M(M)/YYYY");
    if(( ($month,$year) = /^(\d{1,2})\/(\d{4})$/x ) == 2)
    {
	# We have a XX/XXXX datestring
	debug(3,"DEBUG: found '",$month,"/",$year,"'");
	if($month <= 12)
	{
	    # We probably have MM/YYYY
	    $fixeddate = sprintf("%04u-%02u",$year,$month);
	    debug(3,"DEBUG: returning '",$fixeddate,"'");
	    return $fixeddate;
	}
    }

    # These regexps will reduce '2009-xx-01' to just 2009
    # We don't want this, so don't use them.
#    ($year,$month,$day) = /(\d{4})-?(\d{2})?-?(\d{2})?/;
#    ($year,$month,$day) = /(\d{4})(?:-?(\d{2})-?(\d{2}))?/;

    # Force exact match)
    debug(3,"DEBUG: checking YYYY-MM-DD");
    ($year,$month,$day) = /^(\d{4})-(\d{2})-(\d{2})$/x;
    ($year,$month,$day) = ymd_validate($year,$month,$day);

    if(!$year)
    {
	debug(3,"DEBUG: checking YYYYMMDD");
	($year,$month,$day) = /^(\d{4})(\d{2})(\d{2})$/x;
	($year,$month,$day) = ymd_validate($year,$month,$day);
    }

    if(!$year)
    {
	debug(3,"DEBUG: checking YYYY-M(M)");
	($year,$month) = /^(\d{4})-(\d{1,2})$/x;
	($year,$month) = ymd_validate($year,$month,undef);
    }

    if(!$year)
    {
	debug(3,"DEBUG: checking YYYY");
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
	$year = UnixDate($date,"%Y");
	$month = UnixDate($date,"%m");
	$day = UnixDate($date,"%d");
	debug(2,"DEBUG: Date::Manip found '",UnixDate($date,"%Y-%m-%d"),"'");
    }

    if($year)
    {
	# If we still have a $year, $month and $day either don't exist
	# or are plausibly valid.
	print {*STDERR} "DEBUG: found year=",$year," " if($debug >= 2);
	$fixeddate = sprintf("%04u",$year);
	if($month)
	{
	    print {*STDERR} "month=",$month," " if($debug >= 2);
	    $fixeddate .= sprintf("-%02u",$month);
	    if($day)
	    {
		print {*STDERR} "day=",$day if($debug >= 2);
		$fixeddate .= sprintf("-%02u",$day);
	    }
	}
	print {*STDERR} "\n" if($debug >= 2);
	debug(2,"DEBUG: returning '",$fixeddate,"'");
	return $fixeddate if($fixeddate);
    }

    if(!$year)
    {
	debug(3,"fix_date: didn't find a valid date in '",$datestring,"'!");
	return;
    }
    elsif($debug)
    {
	print {*STDERR} "DEBUG: found ",sprintf("04u",$year);
	print {*STDERR} sprintf("-02u",$month) if($month);
	print {*STDERR} sprintf("-02u",$day),"\n" if($day);
    }

    $fixeddate = sprintf("%04u",$year);
    $fixeddate .= sprintf("-%02u-%02u",$month,$day);
    return $fixeddate;
}


=head2 C<get_container_rootfile($container)>

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
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $twig = XML::Twig->new();
    my $rootfile;
    my $retval = undef;

    $container = 'META-INF/container.xml' if(! $container);

    if(-f $container)
    {
	$twig->parsefile($container) or return;
	$rootfile = $twig->root->first_descendant('rootfile');
	return unless($rootfile);
	$retval = $rootfile->att('full-path');
    }
    return $retval;
}


=head2 C<hexstring($bindata)>

Takes as an argument a scalar containing a sequence of binary bytes.
Returns a string converting each octet of the data to its two-digit
hexadecimal equivalent.  There is no leading "0x" on the string.

=cut

sub hexstring
{
    my $data = shift;
    my $subname = ( caller(0) )[3];
    debug(4,"DEBUG[",$subname,"]");

    croak($subname,"(): no data provided")
        unless($data);

    my $byte;
    my $retval = '';
    my $pos = 0;

    while($pos < length($data))
    {
        $byte = unpack("C",substr($data,$pos,1));
        $retval .= sprintf("%02x",$byte);
        $pos++;
    }
    return $retval;
}


=head2 C<print_memory($label)>

Checks /proc/$PID/statm and prints out a line to STDERR showing the
current memory usage.  This is a debugging tool that will likely fail
to do anything useful on a system without a /proc system compatible
with Linux.

=head3 Arguments

=over

=item $label

If defined, will be output along with the memory usage.

=back

Returns 1 on success, undef otherwise.

=cut

sub print_memory
{
    my ($label) = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my @mem;
    my $fh_procstatm;

    if(!open($fh_procstatm,"<","/proc/$$/statm"))
    {
	print "[",$label,"]: " if(defined $label);
	print "Couldn't open /proc/$$/statm [$!]\n";
        return;
    }

    @mem = split(/\s+/,<$fh_procstatm>);
    close($fh_procstatm);

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
    return 1;
}



=head2 C<split_metadata($metahtmlfile, $metafile)>

Takes a psuedo-HTML containing one or more <metadata>...</metadata>
blocks and splits out the metadata blocks into an XML file ready to be
used as an OPF document.  The input HTML file is rewritten without the
metadata.

If $metafile (or the temporary HTML-only file created during the
split) already exists, it will be moved to filename.backup.

=head3 Arguments

=over

=item C<$metahtmlfile>

The filename of the pseudo-HTML file

=item C<$metafile> (optional)

The filename to write out any extracted metadata.  If not specified,
will default to the basename of $metahtmlfile with '.opf' appended.

=back

Returns the filename the metadata was written to, or undef if no
metadata was found.

=cut

sub split_metadata
{
    my ($metahtmlfile,$metafile) = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    croak($subname,"(): no input file specified")
        if(!$metahtmlfile);

    croak($subname,"(): input file has zero size")
        if(-z $metahtmlfile);

    my @metablocks;
    my @guideblocks;
    my $htmlfile;

    my ($filebase,$filedir,$fileext);
    my ($fh_metahtml,$fh_meta,$fh_html);

    ($filebase,$filedir,$fileext) = fileparse($metahtmlfile,'\.\w+$');
    $metafile = $filedir . $filebase . ".opf" if(!$metafile);
    $htmlfile = $filedir . $filebase . "-html.html";

    debug(2,"DEBUG: metahtml='",$metahtmlfile,"'  meta='",$metafile,
          "  html='",$htmlfile,"'");

    # Move existing output files to avoid overwriting them
    if(-f $metafile)
    {
        debug(3, "DEBUG: moving metafile '",$metafile,"'");
        croak ($subname,"(): output file '",$metafile,
               "' exists and could not be moved!")
            if(! rename($metafile,"$metafile.backup") );
    }
    if(-f $htmlfile)
    {
        debug(3, "DEBUG: moving htmlfile '",$htmlfile,"'");
        croak ($subname,"(): output file '",$htmlfile,
               "' exists and could not be moved!")
            if(! rename($htmlfile,"$metafile.backup") );
    }

    debug(2,"  splitting '",$metahtmlfile,"'");
    open($fh_metahtml,"<:raw",$metahtmlfile)
	or croak($subname,"(): Failed to open '",$metahtmlfile,"' for reading!");
    open($fh_meta,">:raw",$metafile)
	or croak($subname,"(): Failed to open '",$metafile,"' for writing!");
    open($fh_html,">:raw",$htmlfile)
	or croak($subname,"(): Failed to open '",$htmlfile,"' for writing!");


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
        s/\sfilepos=\d+//gix;
	(@metablocks) = m#(<metadata>.*</metadata>)#gisx;
	(@guideblocks) = m#(<guide>.*</guide>)#gisx;
	last unless(@metablocks || @guideblocks);
	print {*$fh_meta} @metablocks,"\n" if(@metablocks);
	print {*$fh_meta} @guideblocks,"\n" if(@guideblocks);
	s#<metadata>.*</metadata>##gisx;
	s#<guide>.*</guide>##gisx;
	print {*$fh_html} $_,"\n";
    }
    print $fh_meta "</package>\n";

    close($fh_html)
        or croak($subname,"(): Failed to close '",$htmlfile,"'!");
    close($fh_meta)
        or croak($subname,"(): Failed to close '",$metafile,"'!");
    close($fh_metahtml)
        or croak($subname,"(): Failed to close '",$metahtmlfile,"'!");

    if( (-z $htmlfile) && (-z $metafile) )
    {
        croak($subname,"(): ended up with no text in any output file",
              " -- bailing out!");
    }

    # It is very unlikely that split_metadata will be called twice
    # from the same program, so undef all capture variables reclaim
    # the memory.  Just going out of scope will not necessarily do
    # this.
    undef(@metablocks);
    undef(@guideblocks);
    undef($_);

    if(-z $htmlfile)
    {
        debug(1,"split_metadata(): HTML has zero size.",
             "  Not replacing original.");
        unlink($htmlfile);
    }
    else
    {
        rename($htmlfile,$metahtmlfile)
            or croak("split_metadata(): Failed to rename ",$htmlfile,
                     " to ",$metahtmlfile,"!\n");
    }

    if(-z $metafile)
    {
        croak($subname,
              "(): unable to remove empty output file '",$metafile,"'!")
            if(! unlink($metafile) );
        return;
    }
    return $metafile;
}


=head2 C<split_pre($htmlfile,$outfilebase)>

Splits <pre>...</pre> blocks out of a source HTML file into their own
separate HTML files including required headers.  Each block will be
written to its own file following the naming format
C<$outfilebase-###.html>, where ### is a three-digit number beginning
at 001 and incrementing for each block found.  If C<$outfilebase> is
not specified, it defaults to the basename of C<$htmlfile> with
"-pre-###.html" appended.  The

Returns a list containing all filenames created.

=cut

sub split_pre
{
    my ($htmlfile,$outfilebase) = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    croak($subname,"(): no input file specified")
        if(!$htmlfile);

    my ($filebase,$filedir,$fileext);
    my ($fh_html,$fh_htmlout,$fh_pre);
    my $htmloutfile;
    my @preblocks;
    my @prefiles = ();
    my $prefile;
    my $count = 0;

    my $htmlheader = <<'END';
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
<head>
<title></title>
</head>
<body>
END

    ($filebase,$filedir,$fileext) = fileparse($htmlfile,'\.\w+$');
    $outfilebase = "$filebase-pre" if(!$outfilebase);
    $htmloutfile = "$filebase-nopre.html";

    open($fh_html,"<:raw",$htmlfile)
	or croak($subname,"(): Failed to open '",$htmlfile,"' for reading!");
    open($fh_htmlout,">:raw",$htmloutfile)
        or croak($subname,"(): Failed to open '",$htmloutfile,"' for writing!");

    local $/;
    while(<$fh_html>)
    {
	(@preblocks) = /(<pre>.*?<\/pre>)/gisx;
	last unless(@preblocks);

        foreach my $pre (@preblocks)
        {
            $count++;
            debug(1,"DEBUG: split_pre() splitting block ",
                  sprintf("%03d",$count));
            $prefile = sprintf("%s-%03d.html",$outfilebase,$count);
            if(-f $prefile)
            {
                rename($prefile,"$prefile.backup")
                    or croak("Unable to rename '",$prefile,
                             "' to '",$prefile,".backup'");
            }
            open($fh_pre,">:raw",$prefile)
                or croak("Unable to open '",$prefile,"' for writing!");
            print {*$fh_pre} $utf8xmldec;
            print {*$fh_pre} $htmlheader,"\n";
            print {*$fh_pre} $pre,"\n";
            print {*$fh_pre} "</body>\n</html>\n";
            close($fh_pre) or croak("Unable to close '",$prefile,"'!");
            push @prefiles,$prefile;
        }
	s/(<pre>.*?<\/pre>)//gisx;
	print {*$fh_htmlout} $_,"\n";
        close($fh_htmlout)
            or croak($subname,"(): Failed to close '",$htmloutfile,"'!");
        rename($htmloutfile,$htmlfile)
            or croak($subname,"(): Failed to rename '",$htmloutfile,"' to '",
                     $htmlfile,"'!");
    }
    return @prefiles;
}


=head2 C<strip_script(%args)>

Strips any <script>...</script> blocks out of a HTML file.

=head3 Arguments

=over

=item C<infile>

Specifies the input file.  If not specified, the sub croaks.

=item C<outfile>

Specifies the output file.  If not specified, it defaults to C<infile>
(i.e. the input file is overwritten).

=item C<noscript>

If set to true, the sub will strip <noscript>...</noscript> blocks as
well.

=back

=cut

sub strip_script
{
    my %args = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    croak($subname,"(): no input file specified")
        if(!$args{infile});

    my %valid_args = (
        'infile'  => 1,
        'outfile' => 1,
        'noscript' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $infile = $args{infile};
    my $outfile = $args{outfile};
    $outfile = $infile unless($outfile);

    my ($fh_in,$fh_out);
    my $html;
    local $/;

    open($fh_in,"<:raw",$infile)
	or croak($subname,"(): Failed to open '",$infile,"' for reading!\n");
    $html = <$fh_in>;
    close($fh_in)
	or croak($subname,"(): Failed to close '",$infile,"'!\n");

    $html =~ s#<script>.*?</script>\n?##gix;
    $html =~ s#<noscript>.*?</noscript>\n?##gix
        if($args{noscript});

    open($fh_out,">:raw",$outfile)
	or croak($subname,"(): Failed to open '",$outfile,"' for writing!\n");
    print {*$fh_out} $html;
    close($fh_out)
	or croak($subname,"(): Failed to close '",$outfile,"'!\n");

    return 1;
}


=head2 C<system_result($caller,$retval,@syscmd)

Checks the result of a system call and croak on failure with an
appropriate message.  For this to work, it MUST be used as the line
immediately following the system command.

=head3 Arguments

=over

=item $caller

The calling function (used in output message)

=item $retval

The return value of the system command

=item @syscmd

The array passed to the system call

=back

=head3 Return Values

Returns 0 on success

Croaks on failure.

=cut

sub system_result {
    my ($caller,$retval,@syscmd) = @_;

    if ( ($CHILD_ERROR >> 8) == 0 ) {
        return 0;
    }
    elsif ($CHILD_ERROR == -1) {
        croak($caller," child failed to execute (ERRNO=",$ERRNO,"):\n ",
              join(' ',@syscmd),"\n")
    }
    elsif ($CHILD_ERROR & 127) {
        my $withcoredump = ($CHILD_ERROR & 128) ? 'with' : 'without';
        croak($caller," child died with signal ",($CHILD_ERROR & 127)," ",
              $withcoredump," coredump:\n ",join(' ',@syscmd),"\n");
    }
    else {
        croak($caller," child exited with value ",$CHILD_ERROR >> 8,":\n ",
              join(' ',@syscmd),"\n")
    }
}


=head2 C<system_tidy_xhtml($infile,$outfile)>

Runs tidy on a XHTML file semi-safely (using a secondary file)

Converts HTML to XHTML if necessary

=head3 Arguments

=over

=item $infile

The filename to tidy

=item $outfile

The filename to use for tidy output if the safety condition to
overwrite the input file isn't met.

Defaults to C<infile-tidy.ext> if not specified.

=back

=head3 Global variables used

=over

=item $tidycmd

the location of the tidy executable

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
    my $retval;

    croak("system_tidy_xhtml called with no input file") if(!$infile);
    if(!$outfile)
    {
        my ($filebase,$filedir,$fileext) = fileparse($infile,'\.\w+$');
        $outfile = $filebase . "-tidy" . $fileext;
    }
    croak("system_tidy_xhtml called with no output file") if(!$outfile);

    $retval = system($tidycmd,
		     '-q','-utf8','--tidy-mark','no',
                     '--wrap','0',
                     '--clean','yes',
		     '-asxhtml',
                     '--output-xhtml','yes',
                     '--add-xml-decl','yes',
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
	print {*STDERR} "WARNING: Tidy errors encountered.  Check ",$tidyxhtmlerrors,"\n"
	    if($tidysafety > 0);
	unlink($tidyxhtmlerrors) if($tidysafety < 1);
    }
    else
    {
	# Something unexpected happened (program crash, sigint, other)
	croak("Tidy did something unexpected (return value=",$retval,
              ").  Check all output.");
    }
    return $retval;
}


=head2 C<system_tidy_xml($infile,$outfile)>

Runs tidy on an XML file semi-safely (using a secondary file)

=head3 Arguments

=over

=item C<$infile>

The filename to tidy

=item C<$outfile> (optional)

The filename to use for tidy output if the safety condition to
overwrite the input file isn't met.

Defaults to C<infile-tidy.ext> if not specified.

=back

=head3 Global variables used

=over

=item C<$tidycmd>

the name of the tidy executable

=item C<$tidyxmlerrors>

the filename to use to output errors

=item C<$tidysafety>

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
    my $retval;

    croak("system_tidy_xml called with no input file") if(!$infile);

    if(!$outfile)
    {
        my ($filebase,$filedir,$fileext) = fileparse($infile,'\.\w+$');
        $outfile = $filebase . "-tidy" . $fileext;
    }
    croak("system_tidy_xml called with no output file") if(!$outfile);

    $retval = system($tidycmd,
		     '-q','-utf8','--tidy-mark','no',
                     '--wrap','0',
		     '-xml',
                     '--add-xml-decl','yes',
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
	croak("Tidy did something unexpected (return value=",$retval,
              ").  Check all output.");
    }
    return $retval;
}


=head2 C<trim>

Removes any whitespace characters from the beginning or end of every
string in @list (also works on scalars).

 trim;               # trims $_ inplace
 $new = trim;        # trims (and returns) a copy of $_
 trim $str;          # trims $str inplace
 $new = trim $str;   # trims (and returns) a copy of $str
 trim @list;         # trims @list inplace
 @new = trim @list;  # trims (and returns) a copy of @list

This was shamelessly copied from japhy's example at perlmonks.org:

http://www.perlmonks.org/?node_id=36684

If needed for large lists, it would probably be better to use
String::Strip.

=cut

sub trim   ## no critic (Always unpack @_ first)
{
    ## no critic (Comma used to separate statements)
    @_ = $_ if not @_ and defined wantarray;
    @_ = @_ if defined wantarray;
    for ( @_ ? @_ : $_ ) { s/^\s+//, s/\s+$// }
    return wantarray ? @_ : $_[ 0 ] if defined wantarray;
}


=head2 C<twigelt_create_uuid($gi)>

Creates an unlinked element with the specified gi (tag), and then
assigns it the id and scheme attributes 'UUID'.

=head3 Arguments

=over

=item  $gi : The gi (tag) to use for the element

Default: 'dc:identifier'

=back

Returns the element.

=cut

sub twigelt_create_uuid
{
    my ($gi) = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");
    my $element;

    if(!$gi) { $gi = 'dc:identifier'; }

    my $uuidgen = Data::UUID->new();
    $element = XML::Twig::Elt->new($gi);
    $element->set_id('UUID');
    $element->set_att('scheme' => 'UUID');
    $element->set_text($uuidgen->create_str());
    return $element;
}


=head2 C<twigelt_detect_duplicate($element1, $element2)>

Takes two twig elements and returns 1 if they have the same GI (tag),
text, and attributes, but are not actually the same element.  The GI
comparison is case-insensitive.  The others are case-sensitive.

Returns 0 otherwise.

Croaks if passed anything but twig elements.

=cut

sub twigelt_detect_duplicate
{
    my ($element1,$element2) = @_;
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    croak($subname,"(): arguments must be XML::Twig::Elt objects")
        unless( $element1->isa('XML::Twig::Elt')
                && $element2->isa('XML::Twig::Elt') );

    my (%atts1, %atts2);

    unless($element1->cmp($element2))
    {
        debug(3,"  both elements have the same position");
        return 0;
    }

    unless( lc($element1->gi) eq lc($element2->gi) )
    {
        debug(3,"  elements have different GIs");
        return 0;
    }

    unless($element1->text eq $element2->text)
    {
        debug(3,"  elements have different text");
        return 0;
    }

    %atts1 = %{$element1->atts};
    %atts2 = %{$element2->atts};

    my $attkeys1 = join('',sort keys %atts1);
    my $attkeys2 = join('',sort keys %atts2);

    # This is much simpler with the ~~ operator, but Perl 5.10
    # features are being avoided until 5.10 is standard both on MacOSX
    # and Debian
    # Note that the ~~ operator only checks keys of hashes, not values
#    unless(%atts1 ~~ %atts2)
    unless($attkeys1 eq $attkeys2)
    {
        debug(3,"  elements have different attributes");
        return 0;
    }

    foreach my $att (keys %atts1)
    {
        unless($element1->att($att) eq $element2->att($att))
        {
            debug(3,"  elements have different values for attribute '",
                  $att,"'");
            return 0;
        }
    }
    debug(3,"  elements are duplicates of each other!");
    return 1;
}

=head2 C<twigelt_fix_oeb12_atts($element)>

Checks the attributes in a twig element to see if they match OPF names
with an opf: namespace, and if so, removes the namespace.  Used by the
fix_oeb12() method.

Takes as a sole argument a twig element.

Returns that element with the modified attributes, or undef if the
element didn't exist.  Returns an unmodified element if both att and
opf:att exist.

=cut

sub twigelt_fix_oeb12_atts
{
    my ($element) = @_;
    return unless($element);
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    my %opfatts_no_ns = (
        "opf:role" => "role",
        "opf:file-as" => "file-as",
        "opf:scheme" => "scheme",
        "opf:event" => "event"
        );

    foreach my $att ($element->att_names)
    {
        debug(3,"DEBUG:   checking attribute '",$att,"'");
        if($opfatts_no_ns{$att})
        {
            # If the opf:att attribute properly exists already, do nothing.
            if($element->att($opfatts_no_ns{$att}))
            {
                debug(1,"DEBUG:   found both '",$att,"' and '",
                      $opfatts_no_ns{$att},"' -- skipping.");
                next;
            }
            debug(1,"DEBUG:   changing attribute '",$att,"' => '",
                  $opfatts_no_ns{$att},"'");
            $element->change_att_name($att,$opfatts_no_ns{$att});
        }
    }
    return $element;
}


=head2 C<twigelt_fix_opf20_atts($element)>

Checks the attributes in a twig element to see if they match OPF
names, and if so, prepends the OPF namespace.  Used by the fix_opf20()
method.

Takes as a sole argument a twig element.

Returns that element with the modified attributes, or undef if the
element didn't exist.

=cut

sub twigelt_fix_opf20_atts
{
    my ($element) = @_;
    return unless($element);
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    my %opfatts_ns = (
        "role" => "opf:role",
        "file-as" => "opf:file-as",
        "scheme" => "opf:scheme",
        "event" => "opf:event"
        );

    foreach my $att ($element->att_names)
    {
        debug(2,"DEBUG:   checking attribute '",$att,"'");
        if($opfatts_ns{$att})
        {
            # If the opf:att attribute properly exists already, do nothing.
            if($element->att($opfatts_ns{$att}))
            {
                debug(1,"DEBUG:   found both '",$att,"' and '",
                      $opfatts_ns{$att},"' -- skipping.");
                next;
            }
            debug(1,"DEBUG:   changing attribute '",$att,"' => '",
                  $opfatts_ns{$att},"'");
            $element->change_att_name($att,$opfatts_ns{$att});
        }
    }
    return $element;
}


=head2 C<twigelt_is_author($element)>

Takes as an argument a twig element.  Returns true if the element is a
dc:creator (case-insensitive) with either a opf:role="aut" or
role="aut" attribute defined.  Returns undef otherwise, and also if
the element has no text.

Croaks if fed no argument, or fed an argument that isn't a twig
element.

Intended to be used as a twig search condition.

=head3 Example

 my @elements = $ebook->twigroot->descendants(\&twigelt_is_author);

=cut

sub twigelt_is_author
{
    my ($element) = @_;
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    croak($subname,"(): no element provided") unless($element);

    my $ref = ref($element) || '';

    croak($subname,"(): argument was of type '",$ref,
          "', needs to be 'XML::Twig::Elt' or a subclass")
        unless($element->isa('XML::Twig::Elt'));

    return if( (lc $element->gi) ne 'dc:creator');
    return unless($element->text);

    my $role = $element->att('opf:role') || $element->att('role');
    return unless($role);

    return 1 if($role eq 'aut');
    return;
}


=head2 C<twigelt_is_isbn($element)>

Takes as an argument a twig element.  Returns true if the element is a
dc:identifier (case-insensitive) where any of the id, opf:scheme, or
scheme attributes start with 'isbn', '-isbn', 'eisbn', or 'e-isbn'
(again case-insensitive).

Returns undef otherwise, and also if the element has no text.

Croaks if fed no argument, or fed an argument that isn't a twig
element.

Intended to be used as a twig search condition.

=head3 Example

 my @elements = $ebook->twigroot->descendants(\&twigelt_is_isbn);

=cut

sub twigelt_is_isbn
{
    my ($element) = @_;
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    croak($subname,"(): no element provided") unless($element);

    my $ref = ref($element) || '';
    my $id;
    my $scheme;

    croak($subname,"(): argument was of type '",$ref,
          "', needs to be 'XML::Twig::Elt' or a subclass")
        unless($element->isa('XML::Twig::Elt'));

    return if( (lc $element->gi) ne 'dc:identifier');
    return unless($element->text);

    $id = $element->id || '';
    return 1 if($id =~ /^e?-?isbn/ix);

    $scheme = $element->att('opf:scheme') || '';
    return 1 if($scheme =~ /^e?-?isbn/ix);
    $scheme = $element->att('scheme') || '';
    return 1 if($scheme =~ /^e?-?isbn/ix);
    return;
}


=head2 C<twigelt_is_knownuid($element)>

Takes as an argument a twig element.  Returns true if the element is a
dc:identifier (case-insensitive) element with an C<id> attribute
matching the known IDs of proper unique identifiers suitable for a
package-id (also case-insensitive).  Returns undef otherwise.

Croaks if fed no argument, or fed an argument that isn't a twig element.

Intended to be used as a twig search condition.

=head3 Example

 my @elements = $ebook->twigroot->descendants(\&twigelt_is_knownuid);

=cut

sub twigelt_is_knownuid
{
    my ($element) = @_;
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    croak($subname,"(): no element provided") unless($element);

    my $ref = ref($element) || '';

    croak($subname,"(): argument was of type '",$ref,
          "', needs to be 'XML::Twig::Elt' or a subclass")
        unless($element->isa('XML::Twig::Elt'));

    return if( (lc $element->gi) ne 'dc:identifier');
    my $id = $element->id;
    return unless($id);

    my %knownuids = (
        'package-id' => 56,
        'overdriveguid' => 48,
        'guid' => 40,
        'uuid' => 32,
        'uid'  => 24,
        'calibre_id' => 16,
        'fwid' => 8,
        );

    if($knownuids{lc $id})
    {
#        debug(2,"DEBUG: '",$element->gi,"' has known UID '",$id,"'");
        return 1;
    }
    return;
}


=head2 C<usedir($dir)>

Changes the current working directory to the one specified, creating
it if necessary.

Returns the current working directory before the change.  If no
directory is specified, returns the current working directory without
changing anything.

Croaks on any failure.

=cut

sub usedir
{
    my ($dir) = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]: $dir");

    my $cwd = getcwd();
    return $cwd unless($dir);

    unless(-d $dir)
    {
        debug(2,"  Creating directory '",$dir,"'");
        mkpath($dir)
            or croak("Unable to create output directory '",$dir,"'!\n");
    }
    chdir($dir)
        or croak("Unable to change working directory to '",$dir,"'!\n");
    return $cwd;
}


=head2 C<userconfigdir()>

Returns the directory in which user configuration files and helper
programs are expected to be found, creating that directory if it does
not exist.  Typically, this directory is C<"$ENV{HOME}/.ebooktools">,
but on MSWin32 systems if that directory does not already exist,
C<"$ENV{USERPROFILE}/ApplicationData/EBook-Tools"> is returned (and
potentially created) instead.

If C<$ENV{HOME}> (and C<$ENV{USERPROFILE}> on MSWin32) are not set, the
sub returns undef.

=cut

sub userconfigdir
{
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    my $dir;
    $dir = $ENV{HOME} . '/.ebooktools' if($ENV{HOME});
    if($OSNAME eq 'MSWin32')
    {
        if(! -d $dir)
        {
            $dir = $ENV{USERPROFILE} . '\Application Data\EBook-Tools'
                if($ENV{USERPROFILE});
        }
    }
    if($dir)
    {
        if(! -d $dir)
        {
            mkpath($dir)
                or croak($subname,
                         "(): unable to create configuration directory '",
                         $dir,"'!\n");
        }
        return $dir;
    }
    else { return; }
}


=head2 C<ymd_validate($year,$month,$day)>

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
		debug(1,"DEBUG: timelocal validation failed for year=",
                      $year," month=",$month," day=",$day);
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

=head1 BUGS AND LIMITATIONS

=over

=item * need to implement fix_primary_author() to convert names to
standard 'last, first' naming format

=item * fix_links() could be improved to download remote URIs instead
of ignoring them.

=item * fix_links() needs to check the <reference> links under <guide>

=item * fix_links() needs to be redone with HTML::TreeBuilder to avoid
the weakness with newlines between attribute names and values

=item * Need to implement fix_tours() that should collect the related
elements and delete the parent if none are found.  Empty <tours>
elements aren't allowed.

=item * fix_languages() needs to convert language names into IANA
language codes.

=item * set_language() should add a warning if the text isn't a valid
IANA language code.

=item * NCX generation only generates from the spine.  It should be
possible to use a TOC html file for generation instead.  In the long
term, it should be possible to generate one from the headers and
anchors in arbitrary HTML files.

=item * It might be better to use sysread / index / substr / syswrite in
&split_metadata to handle the split in 10k chunks, to avoid massive
memory usage on large files.

This may not be worth the effort, since the average size for most
books is less than 500k, and the largest books are rarely over 10M.

=item * The only generator is currently for .epub books.  PDF,
PalmDoc, Mobipocket, Plucker, and iSiloX are eventually planned.

=item * Although I like keeping warnings associated with the ebook
object, it may be better to throw exceptions on errors and catch them
later.  This probably won't be implemented until it bites someone who
complains, though.

=item * Unit tests are incomplete

=back

=head1 AUTHOR

Zed Pobre <zed@debian.org>

=head1 LICENSE AND COPYRIGHT

Copyright 2008 Zed Pobre

Licensed to the public under the terms of the GNU GPL, version 2

=cut

1;
