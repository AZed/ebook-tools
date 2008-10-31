package EBook::Tools::Unpack;
use warnings; use strict; use utf8;
use 5.010; # Needed for smart-match operator
require Exporter;
use base qw(Exporter);
use version; our $VERSION = qv("0.1.1");
# $Revision $ $Date $


=head1 NAME

EBook::Tools::Unpack - An object class for unpacking E-book files into
their component parts and metadata

=head1 SYNOPSIS

 use EBook::Tools::Unpack;
 my $unpacker = EBook::Tools::Unpack->new(
    'file'     => $filename,
    'dir'      => $dir,
    'encoding' => $encoding,
    'format'   => $format,
    'raw'      => $raw,
    'author'   => $author,
    'title'    => $title,
    'opffile'  => $opffile,
    'tidy'     => $tidy,
    'nosave'   => $nosave,
    );
 $unpacker->unpack;

or, more simply:

 use EBook::Tools::Unpack;
 my $unpacker = EBook::Tools::Unpack->new('file' => 'mybook.prc');
 $unpacker->unpack;


=head1 DEPENDENCIES

=head2 Perl Modules

=over

=item * C<HTML::Tree>

=item * C<Image::Size>

=item * C<List::MoreUtils>

=item * C<P5-Palm>

=back

=cut


use Carp;
use Compress::Zlib;
use EBook::Tools qw(debug hexstring split_metadata system_tidy_xhtml);
use EBook::Tools::EReader qw(cp1252_to_pml pml_to_html);
use EBook::Tools::Mobipocket;
use EBook::Tools::PalmDoc qw(uncompress_palmdoc);
use Encode;
use Fcntl qw(SEEK_CUR SEEK_SET);
use File::Basename qw(dirname fileparse);
use File::Path;     # Exports 'mkpath' and 'rmtree'
use Image::Size;
use Palm::PDB;

our @EXPORT_OK;
@EXPORT_OK = qw (
    );

our %mobilangcode;
$mobilangcode{0}{0}   = undef;
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


our %palmdbcodes = (
    '.pdfADBE' => 'adobereader',
    'TEXtREAd' => 'palmdoc',
    'BVokBDIC' => 'bdicty',
    'DB99DBOS' => 'db',
    'PNPdPPrs' => 'ereader',
    'PNRdPPrs' => 'ereader',
    'vIMGView' => 'fireviewer',
    'PmDBPmDB' => 'handbase',
    'InfoINDB' => 'infoview',
    'ToGoToGo' => 'isilo1',
    'SDocSilX' => 'isilo3',
    'JbDbJBas' => 'jfile',
    'JfDbJFil' => 'jfilepro',
    'DATALSdb' => 'list',
    'Mdb1Mdb1' => 'mobiledb',
    'BOOKMOBI' => 'mobipocket',
    'DataPlkr' => 'plucker',
    'DataSprd' => 'quicksheet',
    'SM01SMem' => 'supermemo',
    'TEXtTlDc' => 'tealdoc',
    'InfoTlIf' => 'tealinfo',
    'DataTlMl' => 'tealmeal',
    'DataTlPt' => 'tealpaint',
    'dataTDBP' => 'thinkdb',
    'TdatTide' => 'tides',
    'ToRaTRPW' => 'tomeraider',
    'BDOCWrdS' => 'wordsmith',
    'zTXTGPlm' => 'ztxt',
    );

our %pdbcompression = (
    1 => 'no compression',
    2 => 'PalmDoc compression',
    17480 => 'Mobipocket DRM',
    );

our %unpack_dispatch = (
    'ereader'    => \&unpack_ereader,
    'mobipocket' => \&unpack_mobi,
    'palmdoc'    => \&unpack_palmdoc,
    'aportisdoc' => \&unpack_palmdoc,
    );

my %record_links;


#################################
########## CONSTRUCTOR ##########
#################################

=head1 CONSTRUCTOR

=head2 C<new(%args)>

Instantiates a new Ebook::Tools::Unpack object.

=head3 Arguments

=over

=item * C<file>

The file to unpack.  Specifying this is mandatory.

=item * C<dir>

The directory to unpack into.  If not specified, defaults to the
basename of the file.

=item * C<encoding>

If specified, overrides the encoding to use when unpacking.  This is
normally detected from the file and does not need to be specified.

Valid values are '1252' (specifying Windows-1252) and '65001'
(specifying UTF-8).

=item * C<key>

The decryption key to use if necessary (not yet implemented)

=item * C<keyfile>

The file holding the decryption keys to use if necessary (not yet
implemented)

=item * C<language>

If specified, overrides the detected language information.

=item * C<opffile>

The name of the file in which the metadata will be stored.  If not
specified, defaults to the value of C<dir> with C<.opf> appended.

=item * C<raw>

If set true, this forces no corrections to be done on any extracted
text and a lot of raw, unparsed, unmodified data to be dumped into the
directory along with everything else.  It's useful for debugging
exactly what was in the file being unpacked, and (when combined with
C<nosave>) reducing the time needed to extract parsed data from an
ebook container without actually unpacking it.

=item * C<author>

Overrides the detected author name.

=item * C<title>

Overrides the detected title.

=item * C<tidy>

If set to true, the unpacker will run tidy on any HTML output files to
convert them to valid XHTML.  Be warned that this can occasionally
change the formatting, as Tidy isn't very forgiving on certain common
tricks (such as empty <pre> elements with style elements) that abuse
the standard.

=item * C<nosave>

If set to true, the unpacker will run through all of the unpacking
steps except those that actually write to the disk.  This is useful
for testing, but also (particularly when combined with C<raw>) can be
used for extracting parsed data from an ebook container without
actually unpacking it.

=back

=cut

my @fields = (
    'file',
    'dir',
    'encoding',
    'format',
    'formatinfo',
    'htmlconvert',
    'raw',
    'key',
    'keyfile',
    'opffile',
    'author',
    'language',
    'title',
    'datahashes',
    'detected',
    'tidy',
    'nosave',
    );
    
require fields;
fields->import(@fields);

sub new   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my (%args) = @_;
    my $class = ref($self) || $self;
    my $subname = (caller(0))[3];
    debug(2,"DEBUG[",$subname,"]");

    my %valid_args = (
        'file' => 1,
        'dir' => 1,
        'encoding' => 1,
        'key' => 1,
        'keyfile' => 1,
        'format' => 1,
        'htmlconvert' => 1,
        'raw' => 1,
        'author' => 1,
        'language' => 1,
        'title' => 1,
        'opffile' => 1,
        'tidy' => 1,
        'nosave' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }
    croak($subname,"(): no input file specified")
        unless($args{file});
    croak($subname,"(): '",$args{file},"' not found")
        unless(-f $args{file});

    $self = fields::new($class);
    $self->{file} = $args{file};
    $self->{dir} = $args{dir} || $self->filebase;
    $self->{encoding} = $args{encoding};
    $self->{format} = $args{format} if($args{format});
    $self->{key} = $args{key} if($args{key});
    $self->{keyfile} = $args{keyfile} if($args{keyfile});
    $self->{opffile} = $args{opffile} || ($self->{dir} . ".opf");
    $self->{author} = $args{author} if($args{author});
    $self->{title} = $args{title} if($args{title});
    $self->{datahashes} = {};
    $self->{detected} = {};
    $self->{htmlconvert} = $args{htmlconvert};
    $self->{raw} = $args{raw};
    $self->{tidy} = $args{tidy};
    $self->{nosave} = $args{nosave};

    $self->detect_format unless($self->{format});
    return $self;
}


=head1 ACCESSOR METHODS

See L</new()> for more details on what some of these mean.  Note
that some values cannot be autodetected until an unpack method
executes.

=head2 C<author>

=head2 C<dir>

=head2 C<file>

=head2 C<filebase>

In scalar context, this is the basename of C<file>.  In list context,
it actually returns the basename, directory, and extension as per
C<fileparse> from L<File::Basename>.

=head2 C<format>

=head2 C<key>

=head2 C<keyfile>

=head2 C<language>

This returns the language specified by the user, if any.  It remains
undefined if the user has not requested that a language code be set
even if a language was autodetected.

=head2 C<opffile>

=head2 C<raw>

=head2 C<title>

This returns the title specified by the user, if any.  It remains
undefined if the user has not requested a title be set even if a title
was autodetected.

=head2 C<detected>

This returns a hash containing the autodetected metadata, if any.

=cut

sub author
{
    my $self = shift;
    return $$self{author};
}

sub dir
{
    my $self = shift;
    return $$self{dir};
}

sub file
{
    my $self = shift;
    return $$self{file};
}

sub filebase
{
    my $self = shift;
    return fileparse($$self{file},'\.\w+$');
}

sub format
{
    my $self = shift;
    return $$self{format};
}

sub key
{
    my $self = shift;
    return $$self{key};
}

sub keyfile
{
    my $self = shift;
    return $$self{keyfile};
}

sub language
{
    my $self = shift;
    return $$self{language};
}

sub opffile
{
    my $self = shift;
    return $$self{opffile};
}

sub raw
{
    my $self = shift;
    return $$self{raw};
}

sub title
{
    my $self = shift;
    return $$self{opffile};
}

sub detected
{
    my $self = shift;
    return $$self{detected};
}


=head1 MODIFIER METHODS

=head2 C<detect_format()>

Attempts to automatically detect the format of the input file.  Croaks
if it can't.  This both sets the object internal values and returns a
two-scalar list, where the first scalar is the detected format and the
second is a string that may contain additional detected information
(such as a title or version).

This is automatically called by L</new()> if the C<format> argument is
not specified.

=cut

sub detect_format :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    my $filename = $$self{file};
    my $fh;
    my $ident;
    my $info;
    my $index;
    debug(2,"DEBUG[",$subname,"]");

    open($fh,"<",$filename)
        or croak($subname,"(): failed to open '",$filename,"' for reading");
 
    # Check for PalmDB identifiers
    sysseek($fh,60,SEEK_SET);
    sysread($fh,$ident,8);

    debug(3,"DEBUG: $ident");
    if($palmdbcodes{$ident})
    {
        $$self{format} = $palmdbcodes{$ident};
        sysseek($fh,0,SEEK_SET);
        read($fh,$info,32);
        $index = index($info,"\0");
        if($index < 0)
        {
            debug(0,"WARNING: detected header in '",$filename,
                  "' is not null-terminated.");
        }
        else
        {
            $info = substr($info,0,$index);
        }
        debug(1,"DEBUG: Autodetected book format '",$$self{format},
              "', info '",$info,"'");
        $$self{formatinfo} = $info;
        # The info here is always the title, but there may be better
        # ways of extracting it later.
        $$self{detected}{title} = $info;
        return ($ident,$info)
    }
    croak($subname,"(): unable to determine book format");
}


=head2 C<detect_from_mobi_headers()>

Detects metadata values from the MOBI headers retrieved via
L</unpack_mobi_header()> and L</unpack_mobi_exth()> and places them
into the C<detected> attribute.

=cut

sub detect_from_mobi_headers :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $mobilang = $$self{datahashes}{mobi}{language};
    my $mobiregion = $$self{datahashes}{mobi}{region};
    my $mobidilang = $$self{datahashes}{mobi}{dictionaryinlanguage};
    my $mobidiregion = $$self{datahashes}{mobi}{dictionaryinregion};
    my $mobidolang = $$self{datahashes}{mobi}{dictionaryoutlanguage};
    my $mobidoregion = $$self{datahashes}{mobi}{dictionaryoutregion};
    my @mobiexth = @{$$self{datahashes}{mobiexth}};
    my $language;   # <dc:language>
    my $dilanguage; # <DictionaryInLanguage>
    my $dolanguage; # <DictionaryOutLanguage>
    my $data;
    my %exthtypes = %EBook::Tools::Mobipocket::exthtypes;

    my %exth_is_int = (
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

    my %exth_repeats = (
        101 => 'publisher',
        104 => 'isbn',
        105 => 'subject',
        108 => 'contributor',
        110 => 'subjectcode',
        );

    $$self{encoding} = $$self{datahashes}{mobi}{encoding} unless($$self{encoding});

    # dc:Language
    if($mobilang)
    {
        $language = $mobilangcode{$mobilang}{$mobiregion};
        if($language)
        {
            debug(2,"DEBUG: found language '",$language,"'",
                  " (language code ",$mobilang,",",
                  " region code ",$mobiregion,")");
            $$self{detected}{language} = $language;
        }
        else
        {
            debug(1,"DEBUG: language code ",$mobilang,
                  ", region code ",$mobiregion," not known",
                  " -- ignoring region code");
            $language = $mobilangcode{$mobilang}{0};
            if(!$language)
            {
                carp("WARNING: language code ",$mobilang,
                     " not recognized!\n");
            }
            else
            {
                debug(1,"DEBUG: found downgraded language '",$language,"'",
                      " (language code ",$mobilang,",",
                      " region code 0)");
                $$self{detected}{language} = $language;
            }                        
        } # if($language) / else
    } # if($mobilang)

    # DictionaryInLanguage
    if($mobidilang)
    {
        $dilanguage = $mobilangcode{$mobidilang}{$mobidiregion};
        if($dilanguage)
        {
            debug(2,"DEBUG: found dictionary input language '",$dilanguage,"'",
                  " (language code ",$mobidilang,",",
                  " region code ",$mobidiregion,")");
            $$self{detected}{dictionaryinlanguage} = $dilanguage;
        }
        else
        {
            debug(1,"DEBUG: dictionary input language code ",$mobidilang,
                  ", region code ",$mobidiregion," not known",
                  " -- ignoring region code");
            $language = $mobilangcode{$mobidilang}{0};
            if(!$language)
            {
                carp("WARNING: dictionary input language code ",$mobidilang,
                     " not recognized!\n");
            }
            else
            {
                debug(1,"DEBUG: found downgraded dictionary input language '",
                      $dilanguage,"'",
                      " (language code ",$mobidilang,",",
                      " region code 0)");
                $$self{detected}{dictionaryinlanguage} = $dilanguage;
            }                        
        } # if($dilanguage) / else
    } # if($mobidilang)

    # DictionaryOutLanguage
    if($mobidolang)
    {
        $dolanguage = $mobilangcode{$mobidolang}{$mobidoregion};
        if($dolanguage)
        {
            debug(2,"DEBUG: found dictionary output language '",$dolanguage,"'",
                  " (language code ",$mobidolang,",",
                  " region code ",$mobidoregion,")");
            $$self{detected}{dictionaryoutlanguage} = $dolanguage;
        }
        else
        {
            debug(1,"DEBUG: dictionary output language code ",$mobidolang,
                  ", region code ",$mobidiregion," not known",
                  " -- ignoring region code");
            $dolanguage = $mobilangcode{$mobidolang}{0};
            if(!$language)
            {
                carp("WARNING: dictionary output language code ",$mobidolang,
                     " not recognized!\n");
            }
            else
            {
                debug(1,"DEBUG: found downgraded dictionary output language '",
                      $dolanguage,"'",
                      " (language code ",$mobidolang,",",
                      " region code 0)");
                $$self{detected}{dictionaryoutlanguage} = $dolanguage;
            }                        
        } # if($dolanguage) / else
    } # if($mobidolang)

    # EXTH records
    foreach my $exth (@mobiexth)
    {
        my $type = $exthtypes{$$exth{type}};
        unless($type)
        {
            carp($subname,"(): unknown EXTH record type ",$$exth{type});
            next;
        }
        if($exth_is_int{$$exth{type}})
        {
            $data = '0x' . hexstring($$exth{data});
        }
        else
        {
            $data = $$exth{data};
        }
        
        debug(2,"DEBUG: EXTH ",$type," = '",$data,"'");
        if($exth_repeats{$$exth{type}})
        {
            my @extharray = ();
            my $oldexth = $$self{detected}{$type};
            if(ref $oldexth eq 'ARRAY') { @extharray = @$oldexth; }
            elsif($oldexth) { push(@extharray,$oldexth); }
            push(@extharray,$data);
            $$self{detected}{$type} = \@extharray;
        }
        else
        {
            $$self{detected}{$type} = $data;
        }
    }

    return 1;
}


=head2 C<gen_opf(%args)>

This generates an OPF file from detected and specified metadata.  It
does not honor the C<nosave> flag, and will always write its output.

Normally this is called automatically from inside the C<unpack>
methods, but can be called manually after an unpack if the C<nosave>
flag was set to write an OPF anyway.

Returns the filename of the OPF file.

=head3 Arguments

=over

=item * C<opffile> (optional)

If specified, this overrides the object attribute C<opffile>, and
determines the filename to use for the generated OPF file.  If not
specified, and the object attribute C<opffile> has somehow been
cleared (the attribute is set during L</new()>), it will be generated
by looking at the C<htmlfile> argument.  If no value can be found, the
method croaks.  If a value was found somewhere other than the object
attribute C<opffile>, then the object attribute is updated to match.

=item * C<textfile> (optional)

The file containing the main text of the document.  If specified, the
method will attempt to split metadata out of the file and add whatever
remains to the manifest of the OPF.

=back

=cut

sub gen_opf :method
{
    my $self = shift;
    my (%args) = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");
    my %valid_args = (
        'opffile' => 1,
        'textfile' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }
    my $ebook = EBook::Tools->new();
    my $textfile = $args{textfile};
    my $opffile = $args{htmlfile} || $$self{opffile};
    $opffile = split_metadata($textfile,$opffile) if($textfile);
    my $detected;
    my $code;
    my $index;

    my @test = [ '1', '2' ];
    my $testref = \@test;

    croak($subname,"(): could not determine OPF filename\n")
        unless($opffile);
    $$self{opffile} ||= $opffile;

    if(-f $opffile)
    {
        $ebook->init($opffile);
    }
    else
    {
        $ebook->init_blank(opffile => $opffile,
                           title => $$self{title},
                           author => $$self{author});
    }
    $ebook->fix_metastructure_oeb12();
    $ebook->add_document($textfile,'text-main') if($textfile);
    
    # Set author, title, and opffile from manual overrides
    $ebook->set_primary_author(text => $$self{author}) if($$self{author});
    $ebook->set_title(text => $$self{title}) if($$self{title});
    $ebook->set_opffile($$self{opffile}) if($$self{opffile});
    
    # If we still don't have author or title, set it from the best
    # extraction we have
    $ebook->set_primary_author(text => $$self{detected}{author})
        if(!$$self{author} && $$self{detected}{author});
    $ebook->set_title(text => $$self{detected}{title})
        if(!$$self{title} && $$self{detected}{title});
    
    # Set the language codes
    $ebook->set_language(text => $$self{detected}{language})
        if($$self{detected}{language});
    $ebook->set_metadata(gi => 'DictionaryInLanguage',
                         text => $$self{detected}{dictionaryinlanguage})
        if($$self{detected}{dictionaryinlanguage});
    $ebook->set_metadata(gi => 'DictionaryOutLanguage',
                         text => $$self{detected}{dictionaryoutlanguage})
        if($$self{detected}{dictionaryoutlanguage});


    # Set the remaining autodetected metadata, some of which may or
    # may not be in array form
    $detected = $$self{detected}{contributor};
    if( $detected && (ref($detected) eq 'ARRAY') )
    {
        foreach my $text (@$detected)
        {
            $ebook->add_metadata(gi => 'dc:Contributor',
                                 parent => 'dc-metadata',
                                 text => $text);
        }
    }
    elsif($detected)
    {
        $ebook->add_metadata(gi => 'dc:Contributor',
                             parent => 'dc-metadata',
                             text => $detected);
    }

    $detected = $$self{detected}{publisher};
    if( $detected && (ref($detected) eq 'ARRAY') )
    {
        foreach my $text (@$detected)
        {
            $ebook->add_metadata(gi => 'dc:Publisher',
                                 parent => 'dc-metadata',
                                 text => $text);
        }
    }
    elsif($detected)
    {
        $ebook->set_publisher(text => $detected);
    }

    $ebook->set_description(text => decode_utf8($$self{detected}{description}))
        if($$self{detected}{description});

    $detected = $$self{detected}{isbn};
    if( $detected && (ref($detected) eq 'ARRAY') )
    {
        foreach my $text (@$detected)
        {
            $ebook->add_identifier(text => $text,
                                   scheme => 'ISBN')
        }
    }
    elsif($detected)
    {
        $ebook->add_identifier(text => $detected,
                               scheme => 'ISBN')
    }

    $detected = $$self{detected}{subject};
    if( $detected && (ref($detected) eq 'ARRAY') )
    {
        $index = 0;
        foreach my $text (@$detected)
        {
            $code = @{$$self{detected}{subjectcode}}[$index];
            $ebook->add_subject(text => $text,
                                basiccode => $code);
            $index++;
        }
    }
    elsif($detected)
    {
        $code = $$self{detected}{subjectcode};
        $ebook->add_subject(text => $$self{detected}{subject},
                            basiccode => $code)
    }

    $ebook->set_date(text => $$self{detected}{publicationdate},
                     event => 'publication')
        if($$self{detected}{publicationdate});
    $ebook->set_rights(text => $$self{detected}{rights})
        if($$self{detected}{rights});
    $ebook->set_type(text => $$self{detected}{type})
        if($$self{detected}{type});
    $ebook->set_adult($$self{detected}{adult})
        if($$self{detected}{adult});
    $ebook->set_review(text => decode_utf8($$self{detected}{review}))
        if($$self{detected}{review});
    $ebook->set_retailprice(text => $$self{detected}{retailprice},
                            currency => $$self{detected}{currency})
        if($$self{detected}{retailprice});
    
    # Automatically clean up any mess
    $ebook->fix_misc;
    $ebook->fix_oeb12;
    $ebook->fix_mobi;
    unlink($opffile);
    $ebook->save;
    return 1;    
}


=head2 C<unpack()>

This is a dispatcher for the specific unpacking methods needed to
unpack a particular format.  Unless you feel a need to override the
unpacking method specified or detected during object construction, it
is probalby better to call this than the specific unpacking methods.

=cut

sub unpack :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $filename = $$self{file};
    croak($subname,"(): no input file specified\n")
        unless($filename);
    my $retval;

    croak($subname,
          "(): don't know how to handle format '",$$self{format},"'\n")
        if(!$unpack_dispatch{$$self{format}});
    $retval = $unpack_dispatch{$$self{format}}->($self);
    return $retval;
}


=head2 C<unpack_ereader()>

Unpacks Fictionwise/PeanutPress eReader (-er.pdb) files.

=cut

sub unpack_ereader :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $pdb = EBook::Tools::EReader->new();
    my @records;
    my $textname;
    my $fh_text;
    my $fh_data;
    my %datahash;

    my $reccount = 0; # The Record ID cannot be reliably used to identify 
                      # the first record.  This increments as each
                      # record is examined
    my $nontextrec;
    my $version;
    my @list;
    my @footnoteids = ();
    my @footnotes = ();
    

    $pdb->Load($$self{file});
    @records = @{$pdb->{records}};
    $version = $pdb->{header}->{version};
    croak($subname,"(): no pdb records found!\n") unless(@records);

    $$self{datahashes}{ereader} = $pdb->{header};
    $$self{detected}{title}     = $pdb->{title};
    $$self{detected}{author}    = $pdb->{author};
    $$self{detected}{rights}    = $pdb->{rights};
    $$self{detected}{publisher} = $pdb->{publisher};
    $$self{detected}{isbn}      = $pdb->{isbn};
    debug(1,"DEBUG: PDB title: '",$$self{detected}{title},"'");
    debug(1,"DEBUG: PDB author: '",$$self{detected}{author},"'");
    debug(1,"DEBUG: PDB copyright: '",$$self{detected}{rights},"'");
    debug(1,"DEBUG: PDB publisher: '",$$self{detected}{publisher},"'");
    debug(1,"DEBUG: PDB ISBN: '",$$self{detected}{isbn},"'");

    if($$self{htmlconvert}) { $textname = $self->filebase . ".html"; }
    else { $textname = $self->filebase . ".pml"; }
    unless($$self{nosave})
    {
        $self->usedir;
        if($$self{htmlconvert})
        {
            open($fh_text,'>:utf8',$textname)
                or croak($subname,"(): unable to open '",$textname,
                         "' for writing!\n");
            print {*$fh_text} $pdb->html;
        }
        else
        {
            open($fh_text,'>:raw',$textname)
                or croak($subname,"(): unable to open '",$textname,
                         "' for writing!\n");
            print {*$fh_text} $pdb->pml;
        }
        close($fh_text)
            or croak($subname,"(): unable to close '",$textname,"'!\n");
        $self->gen_opf(textfile => $textname);
    }
    return 1;
}


=head2 C<unpack_mobi()>

Unpacks Mobipocket (.prc / .mobi) files.

=cut

sub unpack_mobi :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $mobi = EBook::Tools::Mobipocket->new();
    my @records;
    my $data;
    my $opffile;
    my @list;    # Generic temporary list storage

    # Used for extracting images
    my ($imagex,$imagey,$imagetype);
    my $imageid = 0;
    my $imagename;
    my $firstimagerec = 0;

    # Used for file output
    my ($fh_html,$fh_image,$fh_raw);
    my $htmlname = $self->filebase . ".html";
    my $rawname;
    my $text_record_count;

    my $reccount = 0; # The Record ID cannot be reliably used to identify 
                      # the first record.  This increments as each
                      # record is examined

    $mobi->Load($$self{file});
    $self->usedir unless($$self{nosave});

    @records = @{$mobi->{records}};
    croak($subname,"(): no pdb records found!") unless(@records);

    $$self{datahashes}{palm} = $mobi->{header}{palm};
    $$self{datahashes}{mobi} = $mobi->{header}{mobi};
    $$self{datahashes}{mobiexth} = $mobi->{header}{exth};
    $$self{detected}{title} = $mobi->{title};
    $self->detect_from_mobi_headers();
    
    if($$self{raw} && !$$self{nosave})
    {
        $mobi->write_unknown_records();
    }

    croak($subname,"(): found no text in '",$$self{file},"'!")
        unless($mobi->{text});

    $mobi->fix_html(filename => $htmlname) unless($$self{raw});

    unless($$self{nosave})
    {
        $mobi->write_text($htmlname);
        $mobi->write_images();
        $self->gen_opf(textfile => $htmlname);

        if($$self{tidy})
        {
            debug(1,"Tidying '",$htmlname,"'");
            system_tidy_xhtml($htmlname);
        }
    }
    return 1;
}


=head2 unpack_palmdoc()

Unpacks PalmDoc / AportisDoc (.pdb) files

=cut

sub unpack_palmdoc :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $filename = $$self{file};

    my $ebook = EBook::Tools->new();
    my $pdb = EBook::Tools::PalmDoc->new();
    my ($outfile,$bookmarkfile,$fh);
    my %bookmarks;
    $outfile = $self->filebase . ".txt";
    $bookmarkfile = $self->filebase . "-bookmarks.txt";

    $pdb->Load($filename);
    debug(2,"DEBUG: PalmDoc Name: ",$pdb->{'name'});
    debug(2,"DEBUG: PalmDoc Version: ",$pdb->{'version'});
    debug(2,"DEBUG: PalmDoc Type: ",$pdb->{'type'});
    debug(2,"DEBUG: PalmDoc Creator: ",$pdb->{'creator'});

    $$self{title}   ||= $pdb->{'name'};
    $$self{author}  ||= 'Unknown Author';
    $$self{opffile} ||= $$self{title} . ".opf";

    unless($$self{nosave})
    {
        $self->usedir;
        open($fh,">:raw",$outfile)
            or croak("Failed to open '",$outfile,"' for writing!");
        print {*$fh} $pdb->text;
        close($fh)
            or croak("Failed to close '",$outfile,"'!");

        open($fh,">:raw",$bookmarkfile)
            or croak("Failed to open '",$bookmarkfile,"' for writing!");

        %bookmarks = $pdb->bookmarks;
        if(%bookmarks) 
        {
            foreach my $offset (sort {$a <=> $b} keys %bookmarks)
            {
                print {*$fh} $offset,"\t",$bookmarks{$offset},"\n";
            }
            close($fh)
                or croak("Failed to close '",$bookmarkfile,"'!");
        }

        $ebook->init_blank(opffile => $$self{opffile},
                           title => $$self{title},
                           author => $$self{author});
        $ebook->add_document($outfile,'text-main','text/plain');
        $ebook->save;
    }
    return $$self{opffile};
}


=head2 usedir()

Changes the current working directory to the directory specified by
the object, creating it if necessary.

=cut

sub usedir :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");
    unless(-d $$self{dir})
    {
        debug(2,"  Creating directory '",$$self{dir},"'");
        mkpath($$self{dir})
            or croak("Unable to create output directory '",$$self{dir},"'!\n");
    }
    chdir($$self{dir})
        or croak("Unable to change working directory to '",$$self{dir},"'!\n");
    return 1;
}


########## PROCEDURES ##########

=head1 PROCEDURES

No procedures are exported by default, and in fact since the final
module location for some of these procedures has not yet been
finalized, none are even exportable.

Consider these to be private subroutines and use at your own risk.

=cut


########## END CODE ##########

=head1 BUGS/TODO

=over

=item * DRM isn't handled.  Infrastructure to support this via an
external plug-in module may eventually be built, but it will never
become part of the main module for legal reasons.

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

=item * Unit tests are incomplete

=item * Documentation is incomplete.  Accessors in particular could
use some cleaning up.

=item * Need to implement setter methods for object attributes

=item * Palm::Doc is currently used for extraction, with a lot of code
in this module dedicated to extracting information that it can't.  It
may be better to split out that code into a dedicated module to
replace Palm::Doc completely.

=item * Import/extraction/unpacking is currently limited to PalmDoc
and Mobipocket.  Extraction from eReader and Microsoft Reader (.lit)
is also eventually planned.  Other formats may follow from there.

=back

=head1 AUTHOR

Zed Pobre <zed@debian.org>

=head1 COPYRIGHT

Copyright 2008 Zed Pobre

Licensed to the public under the terms of the GNU GPL, version 2

=cut

1;
