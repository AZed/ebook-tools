package EBook::Tools::Mobipocket;
use warnings; use strict; use utf8;
use 5.010; # Needed for smart-match operator
use version; our $VERSION = qv("0.2.0");
# $Revision$ $Date$
# $Id$

# Perl Critic overrides:
## no critic (Package variable)
# Double-sigils are needed for lexical variables in clear print statements
## no critic (Double-sigil dereference)
# Mixed case subs and the variable %record are inherited from Palm::PDB
## no critic (ProhibitAmbiguousNames)
## no critic (ProhibitMixedCaseSubs)

require Exporter;
use base qw(Exporter Palm::Raw);

our @EXPORT_OK;
@EXPORT_OK = qw (
    &parse_mobi_exth
    &parse_mobi_header
    &parse_mobi_language
    &unpack_mobi_language
    );

sub import   ## no critic (Always unpack @_ first)
{
    &Palm::PDB::RegisterPDBHandlers( __PACKAGE__, [ "MOBI", "BOOK" ], );
    &Palm::PDB::RegisterPRCHandlers( __PACKAGE__, [ "MOBI", "BOOK" ], );
    EBook::Tools::EReader->export_to_level(1, @_);
    return;
}

=head1 NAME

EBook::Tools::Mobipocket - Components related to the
Mobipocket format.

=head1 SYNOPSIS

=head1 DEPENDENCIES

=over

=item * C<Compress::Zlib>

=item * C<HTML::Tree>

=item * C<Image::Size>

=item * C<List::MoreUtils>

=item * C<P5-Palm>

=back

=cut


use Carp;
use Compress::Zlib;
use EBook::Tools qw(debug hexstring split_metadata system_tidy_xhtml);
use EBook::Tools::PalmDoc qw(parse_palmdoc_header uncompress_palmdoc);
use Encode;
use Fcntl qw(SEEK_CUR SEEK_SET);
use File::Basename qw(dirname fileparse);
use File::Path;     # Exports 'mkpath' and 'rmtree'
use HTML::TreeBuilder;
use Image::Size;
use List::Util qw(min);
use List::MoreUtils qw(uniq);
use Palm::PDB;
use Palm::Raw();


our %exthtypes = (
    1 => 'drm_server_id',
    2 => 'drm_commerce_id',
    3 => 'drm_ebookbase_book_id',
    100 => 'author',
    101 => 'publisher',
    102 => 'imprint',
    103 => 'description',
    104 => 'isbn',
    105 => 'subject',
    106 => 'publicationdate',
    107 => 'review',
    108 => 'contributor',
    109 => 'rights',
    110 => 'subjectcode',
    111 => 'type',
    112 => 'source',
    113 => 'asin',
    114 => 'versionnumber',
    115 => 'sample',
    116 => 'startreading',
    117 => 'adult',
    118 => 'retailprice',
    119 => 'currency',
    120 => '120',
    200 => '200',
    201 => 'coveroffset',
    202 => 'thumboffset',
    203 => 'hasfakecover',
    204 => '204',
    205 => '205',
    206 => '206',
    207 => '207',
    300 => '300',
    401 => 'clippinglimit',
    402 => 'publisherlimit',
    403 => '403',
    501 => 'cdetype',
    502 => 'lastupdatetime',
    503 => 'updatedtitle',
    );

# A subset of %exthtypes where the value is an integer, not a string
our %exth_is_int = (
    114 => 'versionnumber',
    115 => 'sample',
    201 => 'coveroffset',
    202 => 'thumboffset',
    203 => 'hasfakecover',
    204 => '204',
    205 => '205',
    206 => '206',
    207 => '207',
    300 => '300',
    401 => 'clippinglimit',
    403 => '403',
    );

# A subset of %exthtypes where the value could conceivably show up
# several times
our %exth_repeats = (
    101 => 'publisher',
    104 => 'isbn',
    105 => 'subject',
    108 => 'contributor',
    110 => 'subjectcode',
    );


our %mobilangcode;
$mobilangcode{0}{0}   = '';
$mobilangcode{54}{0}  = 'af'; # Afrikaans
$mobilangcode{28}{0}  = 'sq'; # Albanian
$mobilangcode{1}{0}   = 'ar'; # Arabic
$mobilangcode{1}{20}  = 'ar-dz'; # Arabic (Algeria)
$mobilangcode{1}{60}  = 'ar-bh'; # Arabic (Bahrain)
$mobilangcode{1}{12}  = 'ar-eg'; # Arabic (Egypt)
#$mobilangcode{1}{??} = 'ar-iq'; # Arabic (Iraq) -- Mobipocket broken
$mobilangcode{1}{44}  = 'ar-jo'; # Arabic (Jordan)
$mobilangcode{1}{52}  = 'ar-kw'; # Arabic (Kuwait)
$mobilangcode{1}{48}  = 'ar-lb'; # Arabic (Lebanon)
#$mobilangcode{1}{??} = 'ar-ly'; # Arabic (Libya) -- Mobipocket broken
$mobilangcode{1}{24}  = 'ar-ma'; # Arabic (Morocco)
$mobilangcode{1}{32}  = 'ar-om'; # Arabic (Oman)
$mobilangcode{1}{64}  = 'ar-qa'; # Arabic (Qatar)
$mobilangcode{1}{4}   = 'ar-sa'; # Arabic (Saudi Arabia)
$mobilangcode{1}{40}  = 'ar-sy'; # Arabic (Syria)
$mobilangcode{1}{28}  = 'ar-tn'; # Arabic (Tunisia)
$mobilangcode{1}{56}  = 'ar-ae'; # Arabic (United Arab Emirates)
$mobilangcode{1}{36}  = 'ar-ye'; # Arabic (Yemen)
$mobilangcode{43}{0}  = 'hy'; # Armenian
$mobilangcode{77}{0}  = 'as'; # Assamese
$mobilangcode{44}{0}  = 'az'; # "Azeri (IANA: Azerbaijani)
#$mobilangcode{44}{??} = 'az-cyrl'; # "Azeri (Cyrillic)" -- Mobipocket broken
#$mobilangcode{44}{??} = 'az-latn'; # "Azeri (Latin)" -- Mobipocket broken
$mobilangcode{45}{0}  = 'eu'; # Basque
$mobilangcode{35}{0}  = 'be'; # Belarusian
$mobilangcode{69}{0}  = 'bn'; # Bengali
$mobilangcode{2}{0}   = 'bg'; # Bulgarian
$mobilangcode{3}{0}   = 'ca'; # Catalan
$mobilangcode{4}{0}   = 'zh'; # Chinese
$mobilangcode{4}{12}  = 'zh-hk'; # Chinese (Hong Kong)
$mobilangcode{4}{8}   = 'zh-cn'; # Chinese (PRC)
$mobilangcode{4}{16}  = 'zh-sg'; # Chinese (Singapore)
$mobilangcode{4}{4}   = 'zh-tw'; # Chinese (Taiwan)
$mobilangcode{26}{0}  = 'hr'; # Croatian
$mobilangcode{5}{0}   = 'cs'; # Czech
$mobilangcode{6}{0}   = 'da'; # Danish
$mobilangcode{19}{0}  = 'nl'; # Dutch / Flemish
$mobilangcode{19}{8}  = 'nl-be'; # Dutch (Belgium)
$mobilangcode{9}{0}   = 'en'; # English
$mobilangcode{9}{12}  = 'en-au'; # English (Australia)
$mobilangcode{9}{40}  = 'en-bz'; # English (Belize)
$mobilangcode{9}{16}  = 'en-ca'; # English (Canada)
$mobilangcode{9}{24}  = 'en-ie'; # English (Ireland)
$mobilangcode{9}{32}  = 'en-jm'; # English (Jamaica)
$mobilangcode{9}{20}  = 'en-nz'; # English (New Zealand)
$mobilangcode{9}{52}  = 'en-ph'; # English (Philippines)
$mobilangcode{9}{28}  = 'en-za'; # English (South Africa)
$mobilangcode{9}{44}  = 'en-tt'; # English (Trinidad)
$mobilangcode{9}{8}   = 'en-gb'; # English (United Kingdom)
$mobilangcode{9}{4}   = 'en-us'; # English (United States)
$mobilangcode{9}{48}  = 'en-zw'; # English (Zimbabwe)
$mobilangcode{37}{0}  = 'et'; # Estonian
$mobilangcode{56}{0}  = 'fo'; # Faroese
$mobilangcode{41}{0}  = 'fa'; # Farsi / Persian
$mobilangcode{11}{0}  = 'fi'; # Finnish
$mobilangcode{12}{0}  = 'fr'; # French
$mobilangcode{12}{4}  = 'fr'; # French (Mobipocket bug?)
$mobilangcode{12}{8}  = 'fr-be'; # French (Belgium)
$mobilangcode{12}{12} = 'fr-ca'; # French (Canada)
$mobilangcode{12}{20} = 'fr-lu'; # French (Luxembourg)
$mobilangcode{12}{24} = 'fr-mc'; # French (Monaco)
$mobilangcode{12}{16} = 'fr-ch'; # French (Switzerland)
$mobilangcode{55}{0}  = 'ka'; # Georgian
$mobilangcode{7}{0}   = 'de'; # German
$mobilangcode{7}{12}  = 'de-at'; # German (Austria)
$mobilangcode{7}{20}  = 'de-li'; # German (Liechtenstein)
$mobilangcode{7}{16}  = 'de-lu'; # German (Luxembourg)
$mobilangcode{7}{8}   = 'de-ch'; # German (Switzerland)
$mobilangcode{8}{0}   = 'el'; # Greek, Modern (1453-)
$mobilangcode{71}{0}  = 'gu'; # Gujarati
$mobilangcode{13}{0}  = 'he'; # Hebrew (also code 'iw'?)
$mobilangcode{57}{0}  = 'hi'; # Hindi
$mobilangcode{14}{0}  = 'hu'; # Hungarian
$mobilangcode{15}{0}  = 'is'; # Icelandic
$mobilangcode{33}{0}  = 'id'; # Indonesian
$mobilangcode{16}{0}  = 'it'; # Italian
$mobilangcode{16}{4}  = 'it'; # Italian (Mobipocket bug?)
$mobilangcode{16}{8}  = 'it-ch'; # Italian (Switzerland)
$mobilangcode{17}{0}  = 'ja'; # Japanese
$mobilangcode{75}{0}  = 'kn'; # Kannada
$mobilangcode{63}{0}  = 'kk'; # Kazakh
$mobilangcode{87}{0}  = 'x-kok'; # Konkani (real language code is 'kok'?)
$mobilangcode{18}{0}  = 'ko'; # Korean
$mobilangcode{38}{0}  = 'lv'; # Latvian
$mobilangcode{39}{0}  = 'lt'; # Lithuanian
$mobilangcode{47}{0}  = 'mk'; # Macedonian
$mobilangcode{62}{0}  = 'ms'; # Malay
#$mobilangcode{62}{??}  = 'ms-bn'; # Malay (Brunei Darussalam) -- not supported
#$mobilangcode{62}{??}  = 'ms-my'; # Malay (Malaysia) -- Mobipocket bug
$mobilangcode{76}{0}  = 'ml'; # Malayalam
$mobilangcode{58}{0}  = 'mt'; # Maltese
$mobilangcode{78}{0}  = 'mr'; # Marathi
$mobilangcode{97}{0}  = 'ne'; # Nepali
$mobilangcode{20}{0}  = 'no'; # Norwegian
#$mobilangcode{??}{??} = 'nb'; # Norwegian Bokmål (Mobipocket not supported)
#$mobilangcode{??}{??} = 'nn'; # Norwegian Nynorsk (Mobipocket not supported)
$mobilangcode{72}{0}  = 'or'; # Oriya
$mobilangcode{21}{0}  = 'pl'; # Polish
$mobilangcode{22}{0}  = 'pt'; # Portuguese
$mobilangcode{22}{8}  = 'pt'; # Portuguese (Mobipocket bug?)
$mobilangcode{22}{4}  = 'pt-br'; # Portuguese (Brazil)
$mobilangcode{70}{0}  = 'pa'; # Punjabi
$mobilangcode{23}{0}  = 'rm'; # "Rhaeto-Romanic" (IANA: Romansh)
$mobilangcode{24}{0}  = 'ro'; # Romanian
#$mobilangcode{24}{??}  = 'ro-mo'; # Romanian (Moldova) (Mobipocket output is 0)
$mobilangcode{25}{0}  = 'ru'; # Russian
#$mobilangcode{25}{??}  = 'ru-mo'; # Russian (Moldova) (Mobipocket output is 0)
$mobilangcode{59}{0}  = 'sz'; # "Sami (Lappish)" (not an IANA language code)
                              # IANA code for "Northern Sami" is 'se'
                              # 'SZ' is the IANA region code for Swaziland
$mobilangcode{79}{0}  = 'sa'; # Sanskrit
$mobilangcode{26}{12} = 'sr'; # Serbian -- Mobipocket Cyrillic/Latin distinction broken
#$mobilangcode{26}{12} = 'sr-cyrl'; # Serbian (Cyrillic) (Mobipocket bug)
#$mobilangcode{26}{12} = 'sr-latn'; # Serbian (Latin) (Mobipocket bug)
$mobilangcode{27}{0}  = 'sk'; # Slovak
$mobilangcode{36}{0}  = 'sl'; # Slovenian
$mobilangcode{46}{0}  = 'sb'; # "Sorbian" (not an IANA language code)
                              # 'SB' is IANA region code for 'Solomon Islands'
                              # Lower Sorbian = 'dsb'
                              # Upper Sorbian = 'hsb'
                              # Sorbian Languages = 'wen'
$mobilangcode{10}{0}  = 'es'; # Spanish
$mobilangcode{10}{4}  = 'es'; # Spanish (Mobipocket bug?)
$mobilangcode{10}{44} = 'es-ar'; # Spanish (Argentina)
$mobilangcode{10}{64} = 'es-bo'; # Spanish (Bolivia)
$mobilangcode{10}{52} = 'es-cl'; # Spanish (Chile)
$mobilangcode{10}{36} = 'es-co'; # Spanish (Colombia)
$mobilangcode{10}{20} = 'es-cr'; # Spanish (Costa Rica)
$mobilangcode{10}{28} = 'es-do'; # Spanish (Dominican Republic)
$mobilangcode{10}{48} = 'es-ec'; # Spanish (Ecuador)
$mobilangcode{10}{68} = 'es-sv'; # Spanish (El Salvador)
$mobilangcode{10}{16} = 'es-gt'; # Spanish (Guatemala)
$mobilangcode{10}{72} = 'es-hn'; # Spanish (Honduras)
$mobilangcode{10}{8}  = 'es-mx'; # Spanish (Mexico)
$mobilangcode{10}{76} = 'es-ni'; # Spanish (Nicaragua)
$mobilangcode{10}{24} = 'es-pa'; # Spanish (Panama)
$mobilangcode{10}{60} = 'es-py'; # Spanish (Paraguay)
$mobilangcode{10}{40} = 'es-pe'; # Spanish (Peru)
$mobilangcode{10}{80} = 'es-pr'; # Spanish (Puerto Rico)
$mobilangcode{10}{56} = 'es-uy'; # Spanish (Uruguay)
$mobilangcode{10}{32} = 'es-ve'; # Spanish (Venezuela)
$mobilangcode{48}{0}  = 'sx'; # "Sutu" (not an IANA language code)
                              # "Sutu" is another name for "Southern Sotho"?
                              # IANA code for "Southern Sotho" is 'st'
$mobilangcode{65}{0}  = 'sw'; # Swahili
$mobilangcode{29}{0}  = 'sv'; # Swedish
$mobilangcode{29}{8}  = 'sv-fi'; # Swedish (Finland)
$mobilangcode{73}{0}  = 'ta'; # Tamil
$mobilangcode{68}{0}  = 'tt'; # Tatar
$mobilangcode{74}{0}  = 'te'; # Telugu
$mobilangcode{30}{0}  = 'th'; # Thai
$mobilangcode{49}{0}  = 'ts'; # Tsonga
$mobilangcode{50}{0}  = 'tn'; # Tswana
$mobilangcode{31}{0}  = 'tr'; # Turkish
$mobilangcode{34}{0}  = 'uk'; # Ukrainian
$mobilangcode{32}{0}  = 'ur'; # Urdu
$mobilangcode{67}{0}  = 'uz'; # Uzbek
$mobilangcode{67}{8}  = 'uz'; # Uzbek (Mobipocket bug?)
#$mobilangcode{67}{??} = 'uz-cyrl'; # Uzbek (Cyrillic)
#$mobilangcode{67}{??} = 'uz-latn'; # Uzbek (Latin)
$mobilangcode{42}{0}  = 'vi'; # Vietnamese
$mobilangcode{52}{0}  = 'xh'; # Xhosa
$mobilangcode{53}{0}  = 'zu'; # Zulu

our $mobigen_cmd = '';
our $mobidedrm_cmd = '';

our %pdbencoding = (
    '1252' => 'Windows-1252',
    '65001' => 'UTF-8',
    );


#################################
########## CONSTRUCTOR ##########
#################################

=head1 CONSTRUCTOR

=head2 C<new()>

Instantiates a new Ebook::Tools::Mobipocket object.

=cut

sub new   ## no critic (Always unpack @_ first)
{
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    
    $self->{'creator'} = 'BOOK';
    $self->{'type'} = 'MOBI';
    
    $self->{attributes}{resource} = 0;
    
    $self->{appinfo} = undef;
    $self->{sort} = undef;
    $self->{records} = [];

    $self->{header} = {};
    $self->{encoding} = 1252;
    $self->{text} = '';
    $self->{imagedata} = {};
    $self->{unknowndata} = {};
    $self->{recindexlinks} = {};
    $self->{recindex} = 1; # Image index used to keep track of which image
                           # record maps to which link.  This has to start
                           # at 1 to match what mobipocket does with the
                           # recindex attributes in the text

    $self->{title}     = '';
    $self->{author}    = '';
    $self->{rights}    = '';
    $self->{publisher} = '';
    $self->{isbn}      = '';

    return $self;
}


=head1 ACCESSOR METHODS

=head2 C<text()>

Returns the text of the file

=cut

sub text :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $length = length($self->{text});

    debug(2,"WARNING: actual text length (",$length,
         ") does not match specified text length (",
         $self->{header}{palm}{textlength},")")
        unless($length == $self->{header}{palm}{textlength});

    return $self->{text};
}


=head1 MODIFIER METHODS

These methods have two naming/capitalization schemes -- methods
directly related to the subclassing of Palm::PDB use its MethodName
capitalization style.  Any other methods are
lowercase_with_underscores for consistency with the rest of
EBook::Tools.

=head2 C<ParseRecord(%record)>

Parses PDB records, updating the object attributes.  This method is
called automatically on every database record during C<Load()>.

=cut

sub ParseRecord :method   ## no critic (Always unpack @_ first)
{
    ## The long if-elsif chain is the best logic for record number handling
    ## no critic (Cascading if-elsif chain)
    my $self = shift;
    my %record = @_;
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    my $currentrecord;
    if(!defined $$self{records})
    {
        $currentrecord = 0;
    }
    else
    {
        $currentrecord = scalar @{$$self{records}};
    }

    my $data = $record{data};
    my $recordtext;

    if($currentrecord == 0)
    {
        $self->ParseRecord0($data);
    }
    elsif($currentrecord < $$self{header}{mobi}{nontextrecord})
    {
        # Text records come immediately after the header record
        # Raw record data is deleted to save memory
        $self->ParseRecordText(\$data);
    }
    elsif($currentrecord >= $$self{header}{mobi}{firstimagerecord}
          && $currentrecord <= $$self{header}{mobi}{lastimagerecord})
    { 
        # Image records come immediately after the text if they exist
        # Raw record data is deleted to save memory
        my ($imagex,$imagey,$imagetype) = imgsize(\$data);
        $self->ParseRecordImage(\$data) if(defined($imagex) && $imagetype);
    }
    elsif($currentrecord == $$self{header}{mobi}{flisrecord})
    {
        $recordtext = uncompress_palmdoc($data);
        if($recordtext)
        {
            debug(2,"DEBUG: record ",$currentrecord," is FLIS record");
            debug(2,"       '",$recordtext,"'");
            $$self{unknowndata}{$currentrecord} = $recordtext;
        }
        else
        {
            debug(1,"DEBUG: record ",$currentrecord," isn't FLIS record?");
            $$self{unknowndata}{$currentrecord} = $data;
        }
    }
    elsif($currentrecord == $$self{header}{mobi}{fcisrecord})
    {
        $recordtext = uncompress_palmdoc($data);
        if($recordtext)
        {
            debug(2,"DEBUG: record ",$currentrecord," is FCIS record");
            debug(2,"       '",$recordtext,"'");
            $$self{unknowndata}{$currentrecord} = $recordtext;
        }
        else
        {
            debug(1,"DEBUG: record ",$currentrecord," isn't FCIS record?");
            $$self{unknowndata}{$currentrecord} = $data;
        }
    }
    else
    {
        $recordtext = uncompress($record{data});
        $recordtext = uncompress_palmdoc($record{data}) unless($recordtext);
        if($recordtext)
        {
            debug(1,"DEBUG: record ",$currentrecord," has extra text:");
            debug(1,"       '",$recordtext,"'");
            $$self{unknowndata}{$currentrecord} = $recordtext;
        }
        else
        {
            debug(1,"DEBUG: record ",$currentrecord," is unknown (",
                  length($data)," bytes)");
            $$self{unknowndata}{$currentrecord} = $data;
        }
    }
        
    return \%record;
}


=head2 C<ParseRecord0($data)>

Parses the header record and places the parsed values into the hashref
C<$self->{header}{palm}>, the hashref C<$self->{header}{mobi}>, and
C<$self->{header}{exth}> by calling L</parse_palmdoc_header()>,
L</parse_mobi_header()>, and L</parse_mobi_exth()> respectively.

=cut

sub ParseRecord0 :method
{
    my $self = shift;
    my $data = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $headerdata;  # used for holding temporary data segments
    my $headersize;  # size of variable-length header data
    my %headermobi;
    
    my @list;
    
    # First 16 bytes are a slightly modified palmdoc header
    # See http://wiki.mobileread.com/wiki/MOBI
    $headerdata = substr($data,0,16);
    $$self{header}{palm} = parse_palmdoc_header($headerdata);
    
    # Find out how long the Mobipocket header actually is
    $headerdata = substr($data,16,8);
    @list = unpack("a4N",$headerdata);
    croak($subname,
          "(): Unrecognized Mobipocket header ID '",$list[0],
          "' (expected 'MOBI')")
        unless($list[0] eq 'MOBI');
    $headersize = $list[1];
    croak($subname,"(): unable to determine Mobipocket header size")
        unless($list[1]);
    
    # Unpack the full Mobipocket header
    $headerdata = substr($data,16,$headersize);
    %headermobi = %{parse_mobi_header($headerdata)};
    $$self{header}{mobi} = \%headermobi;
    $$self{encoding} = $headermobi{encoding};
    
    if($headermobi{exthflags} & 0x040) # If bit 6 is set, EXTH exists
    {
        debug(2,"DEBUG: Unpacking EXTH data");
        $headerdata = substr($data,$headersize+16);
        $$self{header}{exth} = parse_mobi_exth($headerdata);
    }
    
    if($headermobi{titleoffset} && $headermobi{titlelength})
    {
        # This is a better guess at the title than the one
        # derived from $pdb->name
        $$self{title} = 
            substr($data,$headermobi{titleoffset},$headermobi{titlelength});
        debug(1,"DEBUG: Extracted title '",$$self{title},"'");
    }


    croak($subname,"(): DRM code ",
          sprintf("0x%08x",$headermobi{drmcode}),
          " found, but DRM is not supported.\n")
        if($headermobi{drmcode}
           && ($headermobi{drmcode} != hex("0xffffffff")) );

    return 1;
}    


=head2 C<ParseRecordImage(\$dataref)>

Parses image records, updating object attributes, most notably adding
the image data to the hash C<$self->{imagedata}, adding the image
filename to C<$self->{recindexlinks}, and incrementing
C<$self->{recindex}>.

Takes as an argument a reference to the record data.  Croaks if it
isn't provided, or isn't a reference.

This is called automatically by L</ParseRecord()> and
L</ParseResource()> as needed.

=cut

sub ParseRecordImage :method
{
    my $self = shift;
    my $dataref = shift;
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    croak($subname,"(): no image data provided\n") unless($dataref);
    croak($subname,"(): image data is not a reference\n") unless(ref $dataref);

    $$self{recindex} = 1 unless(defined $$self{recindex});

    my $currentrecord = scalar @{$$self{records}};
    my ($imagex,$imagey,$imagetype) = imgsize($dataref);
    my $idxstring = sprintf("%04d",$$self{recindex});
    my $imagename = $$self{name} . '-' . $idxstring . '.' . lc($imagetype);

    debug(1,"DEBUG: record ",$currentrecord," is image '",$imagename,
          "' (",$imagex," x ",$imagey,")");
    $$self{imagedata}{$imagename} = $dataref;
    $$self{recindexlinks}{$$self{recindex}} = $imagename; 
    $$self{recindex}++;
    return 1;
}


=head2 C<ParseRecordText(\$dataref)>

Parses text records, updating object attributes, most notably
appending text to C<$self->{text}>.  Takes as an argument a reference
to the record data.

This is called automatically by L</ParseRecord()> and
L</ParseResource()> as needed.

=cut

sub ParseRecordText :method
{
    my $self = shift;
    my $dataref = shift;
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    my $currentrecord = scalar @{$$self{records}};
    my $compression = $$self{header}{palm}{compression};
    my $recordtext;

    if($compression == 1)       # No compression
    {
        $recordtext = $$dataref;
    }
    elsif($compression == 2)    # PalmDoc compression
    {
        $recordtext = uncompress_palmdoc($$dataref);
    }
    else
    {
        croak($subname,"(): unknown compression value (",
              $compression,")\n");
    }

    if($recordtext)
    {
        $self->{text} .= $recordtext;
        debug(3,"DEBUG: record ",$currentrecord," is text");
    }
    else
    {
        debug(1,"DEBUG: record ",$currentrecord,
              " could not be decompressed (",
              length($$dataref)," bytes)");
        $$self{unknowndata}{$currentrecord} = $$dataref;
    }
    return 1;
}


=head2 fix_html(%args)

Takes raw Mobipocket text and replaces the custom tags and file
position anchors

=head3 Arguments

=over

=item * C<filename>

The name of the output HTML file (used in generating hrefs).  The
procedure croaks if this is not supplied.

=item * C<nonewlines> (optional)

If this is set to true, the procedure will not attempt to insert
newlines for readability.  This will leave the output in a single
unreadable line, but has the advantage of reducing the processing
time, especially useful if tidy is going to be run on the output
anyway.

=back

=cut

sub fix_html :method   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");
    my %valid_args = (
        'filename' => 1,
        'nonewlines' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }
    my $filename = $args{filename};
    my $encoding = $$self{encoding} || 1252;
    croak($subname,"(): no text found")
        unless($$self{text});
    croak($subname,"(): no filename supplied")
        unless($filename);

    my $tree;
    my @elements;
    my $recindex;
    my $link;

    # The very first thing that has to be done is map out all of the
    # filepos references and generate anchors at the referenced
    # positions.  This must be done first because any other
    # modifications to the text will invalidate those positions.
    $self->fix_html_filepos();

    # Convert or remove the Mobipocket-specific tags
    $$self{text} =~ s#<mbp:pagebreak [\s\n]*
                     #<br style="page-break-after: always" #gix;
    $$self{text} =~ s#</mbp:pagebreak>##gix;
    $$self{text} =~ s#</?mbp:nu>##gix;
    $$self{text} =~ s#</?mbp:section>##gix;
    $$self{text} =~ s#</?mbp:frameset##gix;
    $$self{text} =~ s#</?mbp:slave-frame##gix;


    # More complex alterations will require a HTML tree
    $tree = HTML::TreeBuilder->new();
    $tree->ignore_unknown(0);

    # If the encoding is UTF-8, we have to decode it before the parse
    # or the parser will break
    if($encoding == 65001)
    {
        debug(1,"DEBUG: decoding utf8 text");
        croak($subname,"(): failed to decode UTF-8 text")
            unless(decode_utf8($$self{text}));
        $tree->parse($$self{text});
    }
    else { $tree->parse($$self{text}); }
    $tree->eof();

    # Replace img recindex links with img src links 
    debug(2,"DEBUG: converting img recindex attributes");
    @elements = $tree->find('img');
    foreach my $el (@elements)
    {
        $recindex = $el->attr('recindex') + 0;
        debug(3,"DEBUG: converting recindex ",$recindex," to src='",
              $self->{recindexlinks}{$recindex},"'");
        $el->attr('recindex',undef);
        $el->attr('hirecindex',undef);
        $el->attr('lorecindex',undef);
        $el->attr('src',$self->{recindexlinks}{$recindex});
    }

    # Replace filepos attributes with href attributes
    debug(2,"DEBUG: converting filepos attributes");
    @elements = $tree->look_down('filepos',qr/.*/x);
    foreach my $el (@elements)
    {
        $link = $el->attr('filepos');
        if($link)
        {
            debug(3,"DEBUG: converting filepos ",$link," to href");
            $link = '#fp' . $link;
            $el->attr('href',$link);
            $el->attr('filepos',undef);
        }
    }

    debug(2,"DEBUG: converting HTML tree");
    $$self{text} = $tree->as_HTML;

    croak($subname,"(): HTML tree output is empty")
        unless($$self{text});

    # Strip embedded nulls
    debug(2,"DEBUG: stripping nulls");
    $$self{text} =~ s/\0//gx;

    # HTML::TreeBuilder will remove all of the newlines, so add some
    # back in for readability even if tidy isn't called
    # This is unfortunately quite slow.
    unless($args{nonewlines})
    {
        debug(1,"DEBUG: adding newlines");
        $$self{text} =~ s#<(body|html)> \s* \n?
                         #<$1>\n#gix;
        $$self{text} =~ s#\n? <div
                         #\n<div#gix;
        $$self{text} =~ s#</div> \s* \n?
                         #</div>\n#gix;
        $$self{text} =~ s#</h(\d)> \s* \n?
                         #</h$1>\n#gix;
        $$self{text} =~ s#</head> \s* \n?
                         #</head>\n#gix;
        $$self{text} =~ s#\n? <(br|p)([\s>])
                         #\n<$1$2#gix;
        $$self{text} =~ s#</p>\s*
                         #</p>\n#gix;
    }
    return 1;
}


=head2 C<fix_html_filepos()>

Takes the raw HTML text of the object and replaces the filepos
anchors.  This has to be called before any other action that modifies
the text, or the filepos positions will not be valid.

Returns 1 if successful, undef if there was no text to fix.

This is called automatically by L</fix_html()>.

=cut

sub fix_html_filepos :method
{
    # There doesn't appear to be any clearer way of handling this
    # than the if-elsif chain.
    ## no critic (Cascading if-elsif chain)
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my @filepos = ($$self{text} =~ /filepos="?([0-9]+)/gix);
    my $length = length($$self{text});
    return unless($length);
    my $atpos;

    debug(1,"DEBUG: creating filepos anchors");
    foreach my $pos (uniq reverse sort @filepos)
    {
        # First, see if we're pointing to a position outside the text
        if($pos >= $length-4)
        {
            debug(1,"DEBUG: filepos ",$pos," outside text, skipping");
            next;
        }

        # Second, figure out what we're dealing with at the filepos
        # offset indicated
            $atpos = substr($$self{text},$pos,5);
        if($atpos =~ /^<mbp/ix)
        {
            # Mobipocket-specific element
            # Insert a whole new <a id> here
            debug(2,"DEBUG: filepos ",$pos," points to '<mbp',",
                  " creating new anchor");
            substring($$self{text},$pos,4,'<a id="' . $pos . '"></a><mbp');
        }
        elsif($atpos =~ /^<(a|p)[ >]/ix)
        {
            # 1-character block-level elements
            debug(2,"DEBUG: filepos ",$pos," points to '",$1,"', updating id");
            substr($$self{text},$pos,2,"<$1 id=\"fp" . $pos . '"');
        }
        elsif($atpos =~ /^<(h\d)[ >]/ix)
        {
            # 2-character block-level elements
            debug(2,"DEBUG: filepos ",$pos," points to '",$1,"', updating id");
            substr($$self{text},$pos,3,"<$1 id=\"fp" . $pos . '"');
        }
        elsif($atpos =~ /^<(div)[ >]/ix)
        {
            # 3-character block-level elements
            debug(2,"DEBUG: filepos ",$pos," points to '",$1,"', updating id");
            substr($$self{text},$pos,4,"<$1 id=\"fp" . $pos . '"');
        }
        elsif($atpos =~ /^</ix)
        {
            # All other elements
            debug(2,"DEBUG: filepos ",$pos," points to '",$atpos,
                  "', creating new anchor");
            substr($$self{text},$pos,1,'<a id="' . $pos . '"></a><');
        }
        else
        {
            # Not an element
            carp("WARNING: filepos ",$pos," pointing to '",$atpos,
                 "' not handled!");
        }
    }
    return 1;
}


=head2 C<write_images()>

Writes each image record to the disk.

Returns the number of images written.

=cut

sub write_images :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    my %imagedata = %{$self->{imagedata}};

    foreach my $image (sort keys %imagedata)
    {
        debug(1,"Writing image '",$image,"' [",
              length(${$imagedata{$image}})," bytes]");
        open(my $fh,">:raw",$image)
            or croak("Unable to open '",$image,"' to write image\n");
        print {*$fh} ${$imagedata{$image}};
        close($fh)
            or croak("Unable to close image file '",$image,"'\n");
    }
    return scalar(keys %imagedata);
}


=head2 C<write_text($filename)>

Writes the book text to disk with the given filename.  This filename
must match the filename given to L</fix_html()> for the internal links
to be consistent.

Croaks if C<$filename> is not specified.

Returns 1 on success, or undef if there was no text to write.

=cut

sub write_text :method
{
    my $self = shift;
    my $filename = shift;
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    croak($subname,"(): no filename specified.\n")
        unless($filename);
    return unless($$self{text});

    debug(1,"DEBUG: writing text to '",$filename,
          "', encoding ",$pdbencoding{$$self{encoding}});

    open(my $fh,">",$filename)
        or croak($subname,"(): unable to open '",$filename,"' for writing!\n");
    if($$self{encoding} == 65001) { binmode($fh,":utf8"); }
    else { binmode($fh); }
    print {*$fh} $$self{text};
    close($fh)
        or croak($subname,"(): unable to close '",$filename,"'!\n");
    
    croak($subname,"(): failed to generate any text")
        if(-z $filename);
    
    return 1;
}


=head2 C<write_unknown_records()>

Writes each unidentified record to disk with a filename in the format of
'raw-record-####', where #### is the record number (not the record ID).

Returns the number of records written.

=cut

sub write_unknown_records :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    my %unknowndata = %{$self->{unknowndata}};

    foreach my $rec (sort keys %unknowndata)
    {
        my $recstring = sprintf("%04d",$rec);
        debug(1,"Dumping raw record ",$recstring);
        my $rawname = "raw-record-" . $recstring;
        open(my $fh,">:raw",$rawname)
            or croak("Unable to open '",$rawname,"' to write raw record\n");
        print {*$fh} $$self{unknowndata}{$rec};
        close($fh)
            or croak("Unable to close raw record file '",$rawname,"'\n");
    }
    return scalar(keys %unknowndata);
}


################################
########## PROCEDURES ##########
################################

=head2 parse_mobi_exth($headerdata)

Takes as an argument a scalar containing the variable-length
Mobipocket EXTH data from the first record.  Returns an array of
hashes, each hash containing the data from one EXTH record with values
from that data keyed to recognizable names.

If C<$headerdata> doesn't appear to be an EXTH header, carps a warning
and returns an empty list.

See:

http://wiki.mobileread.com/wiki/MOBI

=head3 Hash keys

=over

=item * C<type>

A numeric value indicating the type of EXTH data in the record.  See
package variable C<%exthtypes>.

=item * C<length>

The length of the C<data> value in bytes

=item * C<data>

The data of the record.

=back

=cut

sub parse_mobi_exth
{
    my ($headerdata) = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    croak($subname,"(): no header data provided")
        unless($headerdata);

    my $length = length($headerdata);
    my @list;
    my $chunk;
    my @exthrecords = ();

    my $offset;
    my $recordcnt;


    $chunk = substr($headerdata,0,12);
    @list = unpack("a4NN",$chunk);
    if($list[0] ne 'EXTH')
    {
        debug(1,"(): Unrecognized Mobipocket EXTH ID '",$list[0],
             "' (expected 'EXTH')");
        return @exthrecords;
    }
    # The EXTH data never seems to be as long as remaining data after
    # the Mobipocket main header, so only check to see if it is
    # shorter, not equal
    if($length < $list[1])
    {
        debug(1,"EXTH header specified length ",$list[1]," but found ",
             $length," bytes.\n");
    }

    $recordcnt = $list[2];
    unless($recordcnt)
    {
        debug(1,"EXTH flag set, but no EXTH records present");
        return @exthrecords;
    }

    $offset = 12;
    debug(2,"DEBUG: Examining ",$recordcnt," EXTH records");
    foreach my $recordpos (1 .. $recordcnt)
    {
        my %exthrecord;

        $chunk = substr($headerdata,$offset,8);
        $offset += 8;
        @list = unpack("NN",$chunk);
        $exthrecord{type} = $list[0];
        $exthrecord{length} = $list[1] - 8;

        unless($exthtypes{$exthrecord{type}})
        {
            carp($subname,"(): EXTH record ",$recordpos," has unknown type ",
                 $exthrecord{type},"\n");
            $offset += $exthrecord{length};
            next;
        }
        unless($exthrecord{length})
        {
            carp($subname,"(): EXTH record ",$recordpos," has zero length\n");
            next;
        }
        if( ($exthrecord{length} + $offset) > $length )
        {
            carp($subname,"(): EXTH record ",$recordpos,
                 " longer than available data");
            last;
        }
        $exthrecord{data} = substr($headerdata,$offset,$exthrecord{length});
        debug(3,"DEBUG: EXTH record ",$recordpos," [",$exthtypes{$exthrecord{type}},
              "] has ",$exthrecord{length}, " bytes");
        push(@exthrecords,\%exthrecord);
        $offset += $exthrecord{length};
    }
    debug(1,"DEBUG: Found ",$#exthrecords+1," EXTH records");
    return \@exthrecords;
}


=head2 parse_mobi_header($headerdata)

Takes as an argument a scalar containing the variable-length
Mobipocket-specific header data from the first record.  Returns a hash
containing values from that data keyed to recognizable names.

See:

http://wiki.mobileread.com/wiki/MOBI

=head3 keys

The returned hash will have the following keys (documented in the
order in which they are encountered in the header):

=over

=item C<identifier>

This should always be the string 'MOBI'.  If it isn't, the procedure
croaks.

=item C<headerlength>

This is the size of the complete header.  If this value is different
from the length of the argument, the procedure croaks.

=item C<type>

A numeric code indicating what category of Mobipocket file this is.

=item C<encoding>

A numeric code representing the encoding.  Expected values are '1252'
(for Windows-1252) and '65001 (for UTF-8).

The procedure carps a warning if an unexpected value is encountered.

=item C<uniqueid>

This is thought to be a unique ID for the book, but its actual use is
unknown.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<version>

This is thought to be the Mobipocket format version.  A second version
code shows up again later as C<version2> which is usually the same on
unprotected books but different on DRMd books.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<reserved>

40 bytes of reserved data.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<firstimagerecord>

This is thought to be an index to the first record containing image
data.  If there are no images in the book, this value will be
4294967295 (0xffffffff)

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<titleoffset>

Offset in record 0 (not from start of file) of the full title of the
book.

=item C<titlelength>

Length in bytes of the full title of the book 

=item C<languageunknown>

16 bits of unknown data thought to be related to the book language.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<language>

A pseudo-IANA language code string representing the main book language
(i.e. the value of <dc:language>).  See C<%mobilangcodes> for an exact
map of raw values to this string and notes on non-compliant results.

=item C<dilanguageunknown>

16 bits of unknown data thought to be related to the dictionary input
language.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<dilanguage>

A pseudo-IANA language code string for the DictionaryInLanguage
element.  See C<%mobilangcodes> for an exact map of raw values to this
string and notes on non-compliant results.

=item C<dolanguageunknown>

16 bits of unknown data thought to be related to the dictionary output
language.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<dolanguage>

A pseudo-IANA language code string for the DictionaryOutLanguage
element.  See C<%mobilangcodes> for an exact map of raw values to this
string and notes on non-compliant results.

=item C<version2>

This is another Mobipocket format version related to DRM.  If no DRM
is present, it should be the same as C<version>.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<nontextrecord>

This is thought to be an index to the first PDB record other than the
header record that does not contain the book text.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<unknown96>

Unsigned long int (32-bit) at offset 96.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<unknown100>

Unsigned long int (32-bit) at offset 100.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<unknown104>

Unsigned long int (32-bit) at offset 104.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<unknown108>

Unsigned long int (32-bit) at offset 108.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<exthflags>

A 32-bit bitfield related to the Mobipocket EXTH data.  If bit 6
(0x40) is set, then there is at least one EXTH record.

=item C<unknown116>

36 bytes of unknown data at offset 116.  This value will be undefined
if the header data was not long enough to contain it.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<drmcode>

A number thought to be related to DRM.  If present and no DRM is set,
contains either the value 0xFFFFFFFF (normal books) or 0x00000000
(samples).  This value will be undefined if the header data was not
long enough to contain it.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<unknown156>

20 bytes of unknown data at offset 156, usually zeroes.  This value
will be undefined if the header data was not long enough to contain
it.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<unknown176>

16 bits of unknown data at offset 176.  This value will be undefined
if the header data was not long enough to contain it.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<lastimagerecord>

This is thought to be an index to the last record containing image
data.  If there are no images in the book, this value will be 65535
(0xffff).

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<unknown180>

32 bits of unknown data at offset 180.  This value will be undefined
if the header data was not long enough to contain it.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<fcisrecord>

This is thought to be an index to a 'FCIS' record, so named because
those are always the first four characters when the record data is
decompressed using uncompress_palmdoc().

This value will be undefined if the header data was not long enough to
contain it.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<unknown188>

32 bits of unknown data at offset 188.  This value will be undefined
if the header data was not long enough to contain it.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<flisrecord>

This is thought to be an index to a 'FLIS' record, so named because
those are always the first four characters when the record data is
decompressed using uncompress_palmdoc().

This value will be undefined if the header data was not long enough to
contain it.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<unknown196>

32 bits of unknown data at offset 180.  This value will be undefined
if the header data was not long enough to contain it.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<unknown200>

Unknown data of unknown length running to the end of the header.  This
value will be undefined if the header data was not long enough to
contain it.

Use with caution.  This key may be renamed in the future if more
information is found.

=back

=cut

sub parse_mobi_header   ## no critic (ProhibitExcessComplexity)
{
    # There's no way to refactor this without breaking up chunks into
    # separate subroutines, which is a bad idea.
    my ($headerdata) = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    croak($subname,"(): no header data provided")
        unless($headerdata);

    my $length = length($headerdata);
    my @enckeys = keys(%pdbencoding);
    my $chunk;     # current chunk of headerdata being unpacked
    my @list;      # temporary holding area for unpacked data
    my %header;    # header hash to return;
    my $hexstring; # hexadecimal debugging output string

    croak($subname,"(): header data is too short! (only ",$length," bytes)")
        if($length < 116);

    # The Mobipocket header data is large enough that it's easier to
    # deal with when handled in smaller chunks

    # First chunk is 24 bytes before reserved block
    $chunk = substr($headerdata,0,24);
    @list = unpack("a4NNNNN",$chunk);
    if($list[0] ne 'MOBI')
    {
        croak($subname,
              "(): Unrecognized Mobipocket header ID '",$list[0],
              "' (expected 'MOBI')");
    }
    if($list[1] != $length)
    {
        croak($subname,
              "(): header specified length ",$list[1]," but found ",
              $length," bytes.");
    }

    $header{identifier}   = $list[0];
    $header{headerlength} = $list[1];
    $header{type}         = $list[2];
    $header{encoding}     = $list[3];
    $header{uniqueid}     = $list[4];
    $header{version}      = $list[5];

    debug(1,"DEBUG: Found encoding ",$pdbencoding{$header{encoding}});
    carp($subname,"(): unknown encoding '",$header{encoding},"'")
        unless($header{encoding} ~~ @enckeys);

    # Second chunk is 40 bytes of reserved data, usually all 0xff
    $header{reserved} = substr($headerdata,24,40);
    $hexstring = hexstring($header{reserved});
    debug(2,"DEBUG: reserved data: 0x",$hexstring)
        if($hexstring ne ('ff' x 40));

    # Third chunk is 12 bytes up to the language block
    $chunk = substr($headerdata,64,12);
    @list = unpack("NNN",$chunk);
    $header{firstimagerecord} = $list[0];
    $header{titleoffset}      = $list[1];
    $header{titlelength}      = $list[2];

    # Fourth chunk is 12 bytes containing the language codes
    $chunk = substr($headerdata,76,12);
    @list = unpack("nCCnCCnCC",$chunk);
    $header{languageunknown}   = $list[0];
    $header{language}          = parse_mobi_language($list[2],$list[1]);
    $header{dilanguageunknown} = $list[3];
    $header{dilanguage}        = parse_mobi_language($list[5],$list[4]);
    $header{dolanguageunknown} = $list[6];
    $header{dolanguage}        = parse_mobi_language($list[8],$list[7]);

    # Fifth chunk is 8 bytes until next unknown block
    $chunk = substr($headerdata,88,8);
    @list = unpack("NN",$chunk);
    $header{version2}      = $list[0];
    $header{nontextrecord} = $list[1];

    debug(2,"DEBUG: first non-text record: ",$header{nontextrecord});
    if($header{firstimagerecord} == 0xffffffff)
    {
        debug(2,"DEBUG: no image records present");
    }
    else
    {
        debug(2,"DEBUG: first image record: ",$header{firstimagerecord});
    }

    # Sixth chunk is 16 bytes of unknown data, often zeros
    $chunk = substr($headerdata,96,16);
    @list = unpack("NNNN",$chunk);
    $header{unknown96}  = $list[0];
    $header{unknown100} = $list[1];
    $header{unknown104} = $list[2];
    $header{unknown108} = $list[3];
    if($header{unknown96} || $header{unknown100}
       || $header{unknown104} || $header{unknown108})
    {
        debug(2,"DEBUG: unknown data at offset 96: ",
              sprintf("0x%08x 0x%08x 0x%08x 0x%08x",
                      $header{unknown96},$header{unknown100},
                      $header{unknown104},$header{unknown108}) );
    }

    # Seventh and last chunk guaranteed to be present is the EXTH
    # bitfield
    $chunk = substr($headerdata,112,4);
    $header{exthflags} = unpack("N",$chunk);

    # Remaining chunks are only parsed if the header is long enough

    # Eighth chunk is 36 bytes of unknown data
    $header{unknown116} = substr($headerdata,116,36) if($length >= 152);

    # Ninth chunk is 32 bits of DRM-related data
    if($length >= 156)
    {
        $chunk = substr($headerdata,152,4);
        $header{drmcode} = unpack("N",$chunk);
        debug(1,"DEBUG: Found DRM code ",sprintf("0x%08x",$header{drmcode}));
    }

    # Tenth chunk is 20 bytes of unknown data, usually zeroes
    if($length >= 176)
    {
        $header{unknown156} = substr($headerdata,156,20);
        $hexstring = hexstring($header{unknown156});
        debug(2,"DEBUG: unknown data at offset 156: 0x",$hexstring)
            if($hexstring ne ('00' x 20))
    }

    # Eleventh chunk is 2 16-bit values and 5 32-bit values, usually nonzero
    if($length >= 200)
    {
        $chunk = substr($headerdata,176,24);
        @list = unpack("nnNNNNN",$chunk);
        $header{unknown176}      = $list[0];
        $header{lastimagerecord} = $list[1];
        $header{unknown180}      = $list[2];
        $header{fcisrecord}      = $list[3];
        $header{unknown188}      = $list[4];
        $header{flisrecord}      = $list[5];
        $header{unknown196}      = $list[6];
    }

    # Last possible chunk is unknown data lasting to the end
    # of the header.
    if($length >= 201)
    {
        $header{unknown200} = substr($headerdata,200,$length-200);
        debug(2,"DEBUG: Found ",$length-200,
              " bytes of unknown final data in Mobipocket header");
        debug(2,"       0x",hexstring($header{unknown200}));
    }

    foreach my $key (sort keys %header)
    {
        my $value = (length $header{$key} > 10)?
            ( '0x' . hexstring($header{$key}) )
            : $header{$key};
        debug(2,'DEBUG: mobi{',$key,'}=',$value);
    }
    return \%header;
}


=head2 C<parse_mobi_language($languagecode, $regioncode)>

Takes the integer values C<$languagecode> and C<$regioncode> unpacked from
the Mobipocket header and returns a language string mostly (but not
entirely) conformant to the IANA language subtag registry codes.

Croaks if C<$languagecode> is not provided.  If C<$regioncode> is not
provided or not recognized, it is disregarded and the base language
string (with no region or script) is returned.

If C<$languagecode> is not provided, the sub croaks.  If it isn't
recognized, a warning is carped and the sub returns undef.  Note that
0,0 is a recognized code returning an empty string.

See C<%mobilanguagecodes> for an exact map of values.  Note that the
bottom two bits of the region code appear to be unused (i.e. the
values are all multiples of 4).

=cut

sub parse_mobi_language
{
    my ($languagecode,$regioncode) = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    croak($subname,"(): no language code provided\n")
        unless(defined $languagecode);

    my $language = $mobilangcode{$languagecode}{$regioncode};

    if(defined $language)
    {
        debug(2,"DEBUG: found language '",$language,"'",
              " (language code ",$languagecode,",",
              " region code ",$regioncode,")");
    }
    else
    {
        debug(1,"DEBUG: language code ",$languagecode,
              ", region code ",$regioncode," not known",
              " -- ignoring region code");
        $language = $mobilangcode{$languagecode}{0};
        if(!$language)
        {
            carp("WARNING: language code ",$languagecode,
                 " not recognized!\n");
        }
        else
        {
            debug(1,"DEBUG: found downgraded language '",$language,"'",
                  " (language code ",$languagecode,",",
                  " region code 0)");
        }                        
    } # if($language) / else
    return $language;
}


=head2 C<unpack_mobi_language($data)>

Takes as an argument 4 bytes of data.  If less data is provided, the
sub croaks.  If more, a debug warning is provided, but the sub
continues.

In scalar context returns a language string mostly (but not entirely)
conformant to the IANA language subtag registry codes.

In list context, returns the language string, an unknown code integer,
a region code integer, and a language code integer, with the last
three being directly unpacked values.

See C<%mobilangcodes> for an exact map of values.  Note that the
bottom two bits of the region code appear to be unused (i.e. the
values are all multiples of 4).  The unknown code integer appears to
be unused, and is generally zero.

=cut

sub unpack_mobi_language
{
    my $data = shift;

    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    croak($subname,"(): no language data provided")
        unless($data);

    croak($subname,"(): language data is too short (only ",length($data),
          " bytes, need 4\n")
        if(length($data) < 4);

    debug(1,$subname,"(): expected 4 bytes of data, but received ",
          length($data))
        if(length($data) > 4);

    my ($unknowncode,$regioncode,$languagecode) = unpack('nCC',$data);
    my $language = parse_mobi_language($languagecode,$regioncode);

    my @returnlist = ($language,$unknowncode,$regioncode,$languagecode);
    if(wantarray) { return @returnlist; }
    else { return $returnlist[0]; }
}


########## END CODE ##########

=head1 BUGS AND LIMITATIONS

=over

=item * Mobipocket HuffDic encoding (used mostly on dictionaries)
isn't supported yet.

=item * Not all Mobipocket data is understood, so a conversion from
OPF to Mobipocket .prc back to OPF will not result in all data being
retained.  Patches welcome.

=item * Mobipocket EXTH subjectcode records may not end up attached to
the correct subject element if the number of subject records differs
from the number of subjectcode records.  This is because the
Mobipocket format leaves the EXTH subjectcode records completely
unlinked from the subject records, and there is no way to detect if a
subject with no associated subjectcode comes before a subject with an
associated subjectcode.

Fortunately, this should rarely be a problem with real data, as
Mobipocket Creator only allows a single subject to be set, and the
only other way to have a subjectcode attached to a subject is to
manually edit the OPF file and insert an additional dc:Subject element
with a BASICCode attribute.

Mobipocket has indicated that they may move data currently in their
custom elements and attributes to the standard <meta> elements in a
future release, so this problem may become moot then.

=back

=head1 AUTHOR

Zed Pobre <zed@debian.org>

=head1 LICENSE AND COPYRIGHT

Copyright 2008 Zed Pobre

Licensed to the public under the terms of the GNU GPL, version 2

=cut

1;
