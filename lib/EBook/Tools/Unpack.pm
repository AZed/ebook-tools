package EBook::Tools::Unpack;
use warnings; use strict; use utf8;
use 5.010; # Needed for smart-match operator
require Exporter;
use base qw(Exporter);
use version; our $VERSION = qv("0.1.0");
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


=head2 DEPENDENCIES

=head3 Perl Modules

=over

=item * C<File::Path>

=item * C<HTML::Tree>

=item * C<Image::Size>

=item * C<List::MoreUtils>

=item * C<P5-Palm>

=item * C<Palm::Doc>

=back

=cut




use Carp;
use EBook::Tools qw(debug split_metadata system_tidy_xhtml);
use Fcntl qw(SEEK_CUR SEEK_SET);
use File::Basename qw(dirname fileparse);
use File::Path;     # Exports 'mkpath' and 'rmtree'
use HTML::TreeBuilder;
use Image::Size;
use List::MoreUtils qw(uniq);
use Palm::PDB;
use Palm::Doc;
#use Palm::Raw;

our @EXPORT_OK;
@EXPORT_OK = qw (
    );

our %mobilangcode;
$mobilangcode{0}{0}  = undef;
$mobilangcode{54}{0} = 'af'; # Afrikaans
$mobilangcode{28}{0} = 'sq'; # Albanian
$mobilangcode{1}{0}  = 'ar'; # Arabic
$mobilangcode{1}{20} = 'ar-dz'; # Arabic (Algeria)
$mobilangcode{1}{60} = 'ar-bh'; # Arabic (Bahrain)
$mobilangcode{1}{12} = 'ar-eg'; # Arabic (Egypt)
#$mobilangcode{1}{??} = 'ar-iq'; # Arabic (Iraq) -- Mobipocket support is broken
$mobilangcode{1}{44} = 'ar-jo'; # Arabic (Jordan)
$mobilangcode{1}{52} = 'ar-kw'; # Arabic (Kuwait)
$mobilangcode{1}{48} = 'ar-lb'; # Arabic (Lebanon)
#$mobilangcode{1}{??} = 'ar-ly'; # Arabic (Libya) -- Mobipocket support is broken
$mobilangcode{1}{24} = 'ar-ma'; # Arabic (Morocco)
$mobilangcode{1}{32} = 'ar-om'; # Arabic (Oman)
$mobilangcode{1}{64} = 'ar-qa'; # Arabic (Qatar)
$mobilangcode{1}{4}  = 'ar-sa'; # Arabic (Saudi Arabia)
$mobilangcode{1}{40} = 'ar-sy'; # Arabic (Syria)
$mobilangcode{1}{28} = 'ar-tn'; # Arabic (Tunisia)
$mobilangcode{1}{56} = 'ar-ae'; # Arabic (United Arab Emirates)
$mobilangcode{1}{36} = 'ar-ye'; # Arabic (Yemen)
$mobilangcode{43}{0} = 'hy'; # Armenian
$mobilangcode{77}{0} = 'as'; # Assamese
$mobilangcode{44}{0} = 'az'; # "Azeri (Cyrillic)" (IANA: Azerbaijani)
#$mobilangcode{44}{??} = 'az-??'; # "Azeri (Latin)" -- Mobipocket support is broken
$mobilangcode{45}{0} = 'eu'; # Basque
$mobilangcode{35}{0} = 'be'; # Belarusian
$mobilangcode{69}{0} = 'bn'; # Bengali
$mobilangcode{2}{0}  = 'bg'; # Bulgarian
$mobilangcode{3}{0}  = 'ca'; # Catalan
$mobilangcode{4}{0}  = 'zh'; # Chinese
$mobilangcode{4}{12} = 'zh-hk'; # Chinese (Hong Kong)
$mobilangcode{4}{8}  = 'zh-cn'; # Chinese (PRC)
$mobilangcode{4}{16} = 'zh-sg'; # Chinese (Singapore)
$mobilangcode{4}{4}  = 'zh-tw'; # Chinese (Taiwan)
$mobilangcode{26}{0} = 'hr'; # Croatian
$mobilangcode{5}{0}  = 'cs'; # Czech
$mobilangcode{6}{0}  = 'da'; # Danish
$mobilangcode{19}{0} = 'nl'; # Dutch / Flemish
$mobilangcode{19}{8} = 'nl-be'; # Dutch (Belgium)
$mobilangcode{9}{0}  = 'en'; # English
$mobilangcode{9}{12} = 'en-au'; # English (Australia)
$mobilangcode{9}{40} = 'en-bz'; # English (Belize)
$mobilangcode{9}{16} = 'en-ca'; # English (Canada)
$mobilangcode{9}{24} = 'en-ie'; # English (Ireland)
$mobilangcode{9}{32} = 'en-jm'; # English (Jamaica)
$mobilangcode{9}{20} = 'en-nz'; # English (New Zealand)
$mobilangcode{9}{52} = 'en-ph'; # English (Philippines)
$mobilangcode{9}{28} = 'en-za'; # English (South Africa)
$mobilangcode{9}{44} = 'en-tt'; # English (Trinidad)
$mobilangcode{9}{8}  = 'en-gb'; # English (United Kingdom)
$mobilangcode{9}{4}  = 'en-us'; # English (United States)
$mobilangcode{9}{48} = 'en-zw'; # English (Zimbabwe)
$mobilangcode{37}{0} = 'et'; # Estonian
$mobilangcode{56}{0} = 'fo'; # Faroese
$mobilangcode{41}{0} = 'fa'; # Persian / Farsi
$mobilangcode{11}{0} = 'fi'; # Finnish
$mobilangcode{12}{0} = 'fr'; # French
$mobilangcode{55}{0} = 'ka'; # Georgian
$mobilangcode{7}{0}  = 'de'; # German
$mobilangcode{8}{0}  = 'el'; # Greek, Modern (1453-)
$mobilangcode{71}{0} = 'gu'; # Gujarati
$mobilangcode{13}{0} = 'he'; # Hebrew (also code 'iw'?)
$mobilangcode{57}{0} = 'hi'; # Hindi
$mobilangcode{14}{0} = 'hu'; # Hungarian
$mobilangcode{15}{0} = 'is'; # Icelandic
$mobilangcode{33}{0} = 'id'; # Indonesian
$mobilangcode{16}{0} = 'it'; # Italian
$mobilangcode{17}{0} = 'ja'; # Japanese
$mobilangcode{75}{0} = 'kn'; # Kannada
$mobilangcode{63}{0} = 'kk'; # Kazakh
$mobilangcode{87}{0} = 'x-kok'; # Konkani (real language code is 'kok'?)
$mobilangcode{18}{0} = 'ko'; # Korean
$mobilangcode{38}{0} = 'lv'; # Latvian
$mobilangcode{39}{0} = 'lt'; # Lithuanian
$mobilangcode{47}{0} = 'mk'; # Macedonian
$mobilangcode{62}{0} = 'ms'; # Malay
$mobilangcode{76}{0} = 'ml'; # Malayalam
$mobilangcode{58}{0} = 'mt'; # Maltese
$mobilangcode{78}{0} = 'mr'; # Marathi
$mobilangcode{97}{0} = 'ne'; # Nepali
$mobilangcode{20}{0} = 'no'; # Norwegian
$mobilangcode{72}{0} = 'or'; # Oriya
$mobilangcode{21}{0} = 'pl'; # Polish
$mobilangcode{22}{0} = 'pt'; # Portuguese
$mobilangcode{70}{0} = 'pa'; # Punjabi
$mobilangcode{23}{0} = 'rm'; # "Rhaeto-Romanic" (not an official language code?)
$mobilangcode{24}{0} = 'ro'; # Romanian
$mobilangcode{25}{0} = 'ru'; # Russian
$mobilangcode{59}{0} = 'sz'; # "Sami (Lappish)" (not an official language code?)
$mobilangcode{79}{0} = 'sa'; # Sanskrit
$mobilangcode{26}{12} = 'sr'; # Serbian -- Mobipocket Cyrillic/Latin distinction broken
$mobilangcode{27}{0} = 'sk'; # Slovak
$mobilangcode{36}{0} = 'sl'; # Slovenian
$mobilangcode{46}{0} = 'sb'; # "Sorbian" (not an official language code?)
$mobilangcode{10}{0} = 'es'; # Spanish
$mobilangcode{48}{0} = 'sx'; # "Sutu" (not an official language code?)
$mobilangcode{65}{0} = 'sw'; # Swahili
$mobilangcode{29}{0} = 'sv'; # Swedish
$mobilangcode{73}{0} = 'ta'; # Tamil
$mobilangcode{68}{0} = 'tt'; # Tatar
$mobilangcode{74}{0} = 'te'; # Telugu
$mobilangcode{30}{0} = 'th'; # Thai
$mobilangcode{49}{0} = 'ts'; # Tsonga
$mobilangcode{50}{0} = 'tn'; # Tswana
$mobilangcode{31}{0} = 'tr'; # Turkish
$mobilangcode{34}{0} = 'uk'; # Ukrainian
$mobilangcode{32}{0} = 'ur'; # Urdu
$mobilangcode{67}{0} = 'uz'; # Uzbek
$mobilangcode{42}{0} = 'vi'; # Vietnamese
$mobilangcode{52}{0} = 'xh'; # Xhosa
$mobilangcode{53}{0} = 'zu'; # Zulu


our %palmdbcodes = (
    '.pdfADBE' => 'adobereader',
    'TEXtREAd' => 'palmdoc',
    'BVokBDIC' => 'bdicty',
    'DB99DBOS' => 'db',
    'PNPdPPrs' => 'ereader',
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

our %pdbencoding = (
    '1252' => 'Windows-1252',
    '65001' => 'UTF-8',
    );

our %unpack_dispatch = (
    'palmdoc' => \&unpack_palmdoc,
    'aportisdoc' => \&unpack_palmdoc,
    'mobipocket' => \&unpack_mobi,
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
    'raw',
    'key',
    'keyfile',
    'opffile',
    'author',
    'language',
    'languageauto',
    'title',
    'titleauto',
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
    $self->{key} = $args{key} if($args{key});
    $self->{keyfile} = $args{keyfile} if($args{keyfile});
    $self->{format} = $args{format} if($args{format});
    $self->{author} = $args{author} if($args{author});
    $self->{title} = $args{title} if($args{title});
    $self->{opffile} = $args{opffile} || ($self->{dir} . ".opf");
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

=head2 C<languageauto>

This returns the autodetected language, if any, whether or not the
user specified a different language be set during unpacking.

=head2 C<opffile>

=head2 C<raw>

=head2 C<title>

This returns the title specified by the user, if any.  It remains
undefined if the user has not requested a title be set even if a title
was autodetected.

=head2 C<titleauto>

This returns the autodetected title, if any, whether or not the user
specified a different title.

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

sub languageauto
{
    my $self = shift;
    return $$self{languageauto};
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

sub titleauto
{
    my $self = shift;
    return $$self{titleauto};
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
        $$self{titleauto} = $info;
        return ($ident,$info)
    }
    croak($subname,"(): unable to determine book format");
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


=head2 C<unpack_mobi()>

Unpacks Mobipocket files

=cut

sub unpack_mobi :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $pdb = Palm::Doc->new();
    my $ebook = EBook::Tools->new();
    my @records;
    my $data;
    my $opffile;
    my $language;
    my $text;
    my @list;    # Generic temporary list storage

    # Used for extracting images
    my $idstring;
    my $imageid = 0;
    my ($imagex,$imagey,$imagetype);
    my $imagename;
    my $firstimagerec = 0;

    # Used for file output
    my ($fh_html,$fh_image,$fh_raw);
    my $htmlname = $self->filebase . ".html";
    my $rawname;
    my $text_record_count;

    # Palmdoc/Mobipocket record 0 header data
    my $headerdata;  # used for holding temporary data segments
    my $headersize;  # size of variable-length header data

    my %headerpalm;
    my %headermobi;  # 0: 'MOBI' (can be used to sanity-check)
                     # 1: Total length of Mobipocket header in bytes
                     # 2: Mobipocket book type code
                     # 3: Text encoding
                     #    1252 = Windows-1252
                     #    65001 = UTF-8
                     # 4: Unique ID (?)
                     # 5: Mobipocket format version
                     # 
    my @headerexth;
    my $reccount = 0; # The Record ID cannot be reliably used to identify 
                      # the first record.  This increments as each
                      # record is examined
    my $imgindex = 1; # Image index used to keep track of which image
                      # record maps to which link.  This has to start
                      # at 1 to match what mobipocket does with the
                      # recindex attributes in the text

    $pdb->Load($$self{file});
    $self->usedir unless($$self{nosave});

    @records = @{$pdb->{records}};
    croak($subname,"(): no pdb records found!") unless(@records);

    # Factor out this entire block?
    foreach my $rec (@records)
    {
        debug(3,"DEBUG: parsing record ",$rec->{id});
        $data = $rec->{data};
        $idstring = sprintf("%04d",$rec->{id});
        if($reccount == 0)
        {
            # First 16 bytes are a slightly modified palmdoc header
            # See http://wiki.mobileread.com/wiki/MOBI
            $headerdata = substr($data,0,16);
            %headerpalm = unpack_palmdoc_header($headerdata);

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
            %headermobi = unpack_mobi_header($headerdata);

            croak($subname,"(): DRM code ",
                  sprintf("0x%08x",$headermobi{drmcode}),
                  " found, but DRM is not supported.\n")
                if($headermobi{drmcode}
                   && ($headermobi{drmcode} != hex("0xffffffff")) );

            if($headermobi{titleoffset} && $headermobi{titlelength})
            {
                # This is a better guess at the title than the one
                # derived from $pdb->name
                $$self{titleauto} = 
                    substr($data,$headermobi{titleoffset},$headermobi{titlelength});
                debug(1,"DEBUG: Extracted title '",$$self{titleauto},"'");
            }
            if($headermobi{language})
            {
                $language = $mobilangcode{$headermobi{language}}{$headermobi{region}};
                if($language)
                {
                    debug(1,"DEBUG: found language '",$language,"'",
                          " (language code ",$headermobi{language},",",
                          " region code ",$headermobi{region},")");
                    $$self{languageauto} = $language;
                }
                else
                {
                    debug(1,"DEBUG: language code ",$headermobi{language},
                          ", region code ",$headermobi{region}," not known",
                          " -- ignoring region code");
                    $language = $mobilangcode{$headermobi{language}}{0};
                    if(!$language)
                    {
                        carp("WARNING: Language code ",$headermobi{language},
                             " not recognized!\n");
                    }
                    else
                    {
                        debug(1,"DEBUG: found language '",$language,"'",
                              " (language code ",$headermobi{language},",",
                              " region code 0)");
                        $$self{languageauto} = $language;
                    }                        
                } # if($language) / else
            } # if($headermobi{language})
            $$self{encoding} = $headermobi{encoding} unless($$self{encoding});
            $firstimagerec = $headermobi{imagerecord} if($headermobi{imagerecord});
        }
        elsif($reccount >= $firstimagerec)
        { 
            ($imagex,$imagey,$imagetype) = imgsize(\$data);
        }

        if(defined($imagex) && $imagetype)
        {
            $imagename = 
                $self->filebase . '-' . $idstring . '.' . lc($imagetype);
            debug(1,"DEBUG: unpacking image '",$imagename,
                  "' (",$imagex," x ",$imagey,")");
            unless($$self{nosave})
            {
                open($fh_image,">",$imagename)
                    or croak("Unable to open '",$imagename,"' to write image!");
                binmode($fh_image);
                print {*$fh_image} $data;
                close($fh_image)
                    or croak("Unable to close image file '",$imagename,"'");
            }
            $record_links{$imgindex} = $imagename;
            $imgindex++;
        }
        elsif($$self{raw})  # Dump non-image records as well
        {
            unless($$self{nosave})
            {
                debug(1,"Dumping raw record #",$idstring);
                $rawname = "raw-record." . $idstring;
                open($fh_raw,">",$rawname)
                    or croak("Unable to open '",$rawname,"' to write raw record!");
                binmode($fh_raw);
                print {*$fh_raw} $data;
                close($fh_raw)
                    or croak("Unable to close raw record file '",$rawname,"'");
            }
        }
        else # Skipping non-image records for this first pass
        {
            debug(3,"  First pass skipping record #",$idstring);
        }
        $reccount++;
    } # foreach my $rec (@records)

    $text = $pdb->text;
    croak($subname,"(): found no text in '",$$self{file},"'!")
        unless($text);

    fix_mobi_html('textref' => \$text,
                  'filename' => $htmlname,
                  'encoding' => $$self{encoding} )
        unless($$self{raw});

    # Factor out this entire block?
    unless($$self{nosave})
    {
        open($fh_html,">",$htmlname);
        if($$self{encoding} == 65001) { binmode($fh_html,":utf8"); }
        else { binmode($fh_html); }
        debug(1,"DEBUG: writing corrected text to '",$htmlname,"'");
        print {*$fh_html} $text;
        close($fh_html);
        
        croak($subname,"(): unpack failed to generate any text")
            if(-z $htmlname);

        $opffile = split_metadata($htmlname);
        
        $ebook->init($opffile);
        $ebook->add_document($htmlname,'text-main');
        
        # Set author, title, and opffile from manual overrides
        $ebook->set_primary_author(text => $$self{author}) if($$self{author});
        $ebook->set_title(text => $$self{title}) if($$self{title});
        $ebook->set_opffile($$self{opffile}) if($$self{opffile});
        
        # If we still don't have a title, set it from the best extraction we have
        $ebook->set_title(text => $$self{titleauto})
            if(!$ebook->title && $$self{titleauto});
        
        # Automatically clean up any mess
        $ebook->fix_misc;
        $ebook->fix_oeb12;
        $ebook->fix_mobi;
        unlink($opffile);
        $ebook->save;
        
        if($$self{tidy})
        {
            debug(1,"Tidying '",$htmlname,"'");
            system_tidy_xhtml($htmlname);
        }
    }
    return $ebook->opffile;
}


sub unpack_palmdoc :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $filename = $$self{file};

    my $ebook = EBook::Tools->new();
    my $pdb = Palm::Doc->new();
    my ($outfile,$fh_outfile);
    $outfile = $self->filebase . ".txt";

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
        open($fh_outfile,">:utf8",$outfile)
            or croak("Failed to open '",$outfile,"' for writing!");
        print {*$fh_outfile} $pdb->text;
        close($fh_outfile)
            or croak("Failed to close '",$outfile,"'!");

        $ebook->init_blank(opffile => $$self{opffile},
                           title => $$self{title},
                           author => $$self{author});
        $ebook->add_document($outfile,'text-main','text/plain');
        $ebook->save;
    }
    return $$self{opffile};
}


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

=head2 fix_mobi_html(%args)

Takes raw Mobipocket output text and replaces the custom tags and file
position anchors

=head3 Arguments

=over

=item * C<textref>

A reference to the raw document text.  The procedure croaks if this is
not supplied.

=item * C<encoding>

The encoding of the raw document text.  Valid values are '1252'
(Windows-1252) and '65001' (UTF-8).  If not specified, '1252' will be
assumed.

=item * C<filename>

The name of the output HTML file (used in generating hrefs).  The
procedure croaks if this is not supplied.

=item * C<nonewlines>

If this is set to true, the procedure will not attempt to insert
newlines for readability.  This will leave the output in a single
unreadable line, but has the advantage of reducing the processing
time, especially useful if tidy is going to be run on the output
anyway.

=back

=cut

sub fix_mobi_html
{
    my (%args) = @_;

    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");
    my %valid_args = (
        'textref' => 1,
        'encoding' => 1,
        'filename' => 1,
        'nonewlines' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }
    my $html = $args{textref};
    my $filename = $args{filename};
    my $encoding = $args{encoding} || 1252;
    croak($subname,"(): no text supplied")
        unless($$html);
    croak($subname,"(): no filename supplied")
        unless($filename);
    croak($subname,"(): textref must be a reference")
        unless(ref $html);

    my $tree;
    my @elements;
    my $recindex;
    my $link;

    # The very first thing that has to be done is map out all of the
    # filepos references and generate anchors at the referenced
    # positions.  This must be done first because any other
    # modifications to the text will invalidate those positions.
    my @filepos = ($$html =~ /filepos="?([0-9]+)/gix);
    my $length = length($$html);
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
        $atpos = substr($$html,$pos,4);
        
        if($atpos =~ /^<mbp/)
        {
            # Mobipocket-specific element
            # Insert a whole new <a id> here
            debug(2,"DEBUG: filepos ",$pos," points to '<mbp',",
                  " creating new anchor");
            substring($$html,$pos,4,'<a id="' . $pos . '"></a><mbp');
        }
        elsif($atpos =~ /^<(a|p)[ >]/ix)
        {
            # 1-character block-level elements
            debug(2,"DEBUG: filepos ",$pos," points to '",$1,"', updating id");
            substr($$html,$pos,2,"<$1 id=\"fp" . $pos . '"');
        }
        elsif($atpos =~ /^<(h\d)[ >]/)
        {
            # 2-character block-level elements
            debug(2,"DEBUG: filepos ",$pos," points to '",$1,"', updating id");
            substr($$html,$pos,3,"<$1 id=\"fp" . $pos . '"');
        }
        elsif($atpos =~ /^</)
        {
            # All other elements
            debug(2,"DEBUG: filepos ",$pos," points to '",$atpos,
                  "', creating new anchor");
            substr($$html,$pos,1,'<a id="' . $pos . '"></a><');
        }
        else
        {
            # Not an element
            carp("WARNING: filepos ",$pos," pointing to '",$atpos,
                 "' not handled!");
        }
    }


    # Fix the Mobipocket-specific tags
    $$html =~ s#<mbp:pagebreak [\s\n]*
               #<br style="page-break-after: always" #gix;
    $$html =~ s#</mbp:pagebreak>##gix;
    $$html =~ s#</?mbp:nu>##gix;
    $$html =~ s#</?mbp:section>##gix;
    $$html =~ s#</?mbp:frameset##gix;
    $$html =~ s#</?mbp:slave-frame##gix;


    # More complex alterations will require a HTML tree
    $tree = HTML::TreeBuilder->new();
    $tree->ignore_unknown(0);
    # If the encoding is UTF-8, we have to decode it before the parse
    # or the parser will break

    
    if($encoding == 65001)
    {
        debug(1,"DEBUG: decoding utf8 text");
        croak($subname,"(): failed to decode UTF-8 text")
            unless(utf8::decode($$html));
        $tree->parse($$html);
    }
    else { $tree->parse($$html); }
    $tree->eof();

    # Replace img recindex links with img src links 
    debug(2,"DEBUG: converting img recindex attributes");
    @elements = $tree->find('img');
    foreach my $el (@elements)
    {
        $recindex = $el->attr('recindex') + 0;
        debug(3,"DEBUG: converting recindex ",$recindex," to src='",
              $record_links{$recindex},"'");
        $el->attr('recindex',undef);
        $el->attr('hirecindex',undef);
        $el->attr('lorecindex',undef);
        $el->attr('src',$record_links{$recindex});
    }

    # Replace filepos attributes with href attributes
    debug(2,"DEBUG: converting filepos attributes");
    @elements = $tree->look_down('filepos',qr/.*/);
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
    $$html = $tree->as_HTML;

    croak($subname,"(): HTML tree output is empty")
        unless($$html);

    # Strip embedded nulls
    debug(2,"DEBUG: stripping nulls");
    $$html =~ s/\0//gx;

    # HTML::TreeBuilder will remove all of the newlines, so add some
    # back in for readability even if tidy isn't called
    # This is unfortunately quite slow.
    unless($args{nonewlines})
    {
        debug(1,"DEBUG: adding newlines");
        $$html =~ s#<(body|html)> \s* \n?
                   #<$1>\n#gix;
        $$html =~ s#\n? <div
                   #\n<div#gix;
        $$html =~ s#</div> \s* \n?
                   #</div>\n#gix;
        $$html =~ s#</h(\d)> \s* \n?
                   #</h$1>\n#gix;
        $$html =~ s#</head> \s* \n?
                   #</head>\n#gix;
        $$html =~ s#\n? <(br|p)([\s>])
                   #\n<$1$2#gix;
        $$html =~ s#</p>\s*
                   #</p>\n#gix;
    }
    return 1;
}


=head2 unpack_mobi_header

Takes as an argument a scalar containing the variable-length
Mobipocket-specific header data from the first record.  Returns a hash
containing those values keyed to recognizable names.

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

=item C<nontextrecord>

This is thought to be an index to the first PDB record other than the
header record that does not contain the book text.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<titleoffset>

Offset in record 0 (not from start of file) of the full title of the
book.

=item C<titlelength>

Length in bytes of the full title of the book 

=item C<language>

A main language code.  See C<%mobilangcodes> for an exact map of
values.

=item C<region>

The specific region of C<language>.  See C<%mobilangcodes> for an
exact map of values.

The bottom two bits of this value appear to be unused (i.e. all values
are multiples of 4).

=item C<unknown80>

Unsigned long int (32-bit) at offset 80.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<unknown84>

Unsigned long int (32-bit) at offset 84.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<version2>

This is another Mobipocket format version related to DRM.  If no DRM
is present, it should be the same as C<version>.

Use with caution.  This key may be renamed in the future if more
information is found.

=item C<imagerecord>

This is thought to be an index to the first record containing image
data.

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

=back

=cut

sub unpack_mobi_header
{
    my ($headerdata) = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    croak($subname,"(): no header data provided")
        unless($headerdata);

    my $length = length($headerdata);
    my @enckeys = keys(%pdbencoding);
    my $chunk;   # current chunk of headerdata being unpacked
    my @list;    # temporary holding area for unpacked data
    my %retval;  # header hash to return;

    croak($subname,"(): header data is too short! (only ",$length," bytes)")
        unless($length >= 116);

    # The Mobipocket header data is large enough that it's easier to
    # deal with when handled in smaller chunks

    # First chunk is 24 bytes before reserved block
    $chunk = substr($headerdata,0,24);
    @list = unpack("a4NNNNN",$chunk);
    croak($subname,
          "(): Unrecognized Mobipocket header ID '",$list[0],
          "' (expected 'MOBI')")
        unless($list[0] eq 'MOBI');
    croak($subname,
          "(): header specified length ",$list[1]," but found ",
          $length," bytes.")
        unless($list[1] == $length);

    $retval{identifier}   = $list[0];
    $retval{headerlength} = $list[1];
    $retval{type}         = $list[2];
    $retval{encoding}     = $list[3];
    $retval{uniqueid}     = $list[4];
    $retval{version}      = $list[5];

    debug(1,"DEBUG: Found encoding ",$pdbencoding{$retval{encoding}});
    carp($subname,"(): unknown encoding '",$retval{encoding},"'")
        unless($retval{encoding} ~~ @enckeys);

    # Second chunk is 40 bytes of reserved data
    $retval{reserved} = substr($headerdata,24,40);

    # Third chunk is 16 bytes up to the next unknown block
    $chunk = substr($headerdata,64,16);
    @list = unpack("NNNxxcc",$chunk);
    $retval{nontextrecord} = $list[0];
    $retval{titleoffset}   = $list[1];
    $retval{titlelength}   = $list[2];
    $retval{region}        = $list[3];
    $retval{language}      = $list[4];

    # Fourth chunk is 8 bytes of unknown data, often zeros
    $chunk = substr($headerdata,80,8);
    @list = unpack("NN",$chunk);
    $retval{unknown80} = $list[0];
    $retval{unknown84} = $list[1];
    debug(2,"DEBUG: unknown data at offset 80: ",
          sprintf("0x%04x 0x%04x",$retval{unknown80},$retval{unknown84}));

    # Fifth chunk is 8 bytes until next unknown block
    $chunk = substr($headerdata,88,8);
    @list = unpack("NN",$chunk);
    $retval{version2}    = $list[0];
    $retval{imagerecord} = $list[1];

    debug(1,"DEBUG: First image record is ",$retval{imagerecord})
        if($retval{imagerecord});

    # Sixth chunk is 16 bytes of unknown data, often zeros
    $chunk = substr($headerdata,96,16);
    @list = unpack("NNNN",$chunk);
    $retval{unknown96}  = $list[0];
    $retval{unknown100} = $list[1];
    $retval{unknown104} = $list[2];
    $retval{unknown108} = $list[3];
    debug(2,"DEBUG: unknown data at offset 96: ",
          sprintf("0x%04x 0x%04x 0x%04x 0x%04x",
                  $retval{unknown96},$retval{unknown100},
                  $retval{unknown104},$retval{unknown108})
        );

    # Seventh and last chunk guaranteed to be present is the EXTH
    # bitfield
    $chunk = substr($headerdata,112,4);
    $retval{exthflags} = unpack("N",$chunk);

    # Remaining chunks are only parsed if the header is long enough

    # Eighth chunk is 36 bytes of unknown data
    $retval{unknown116} = substr($headerdata,116,36) if($length >= 152);

    # Ninth chunk is 32 bits of DRM-related data
    if($length >= 156)
    {
        $chunk = substr($headerdata,152,4);
        $retval{drmcode} = unpack("N",$chunk);
        debug(1,"DEBUG: found DRM code ",sprintf("0x%08x",$retval{drmcode}));
    }

    # Tenth and last possible chunk is unknown data lasting to the end
    # of the header.
    if($length >= 157)
    {
        $retval{unknown156} = substr($headerdata,156,$length-156);
        debug(2,"DEBUG: found ",$length-156,
              " bytes of unknown final data in Mobipocket header");
    }

    return %retval;
}


=head2 unpack_palmdoc_header

Takes as an argument a scalar containing the 16 bytes of the PalmDoc
header (also used by Mobipocket).  Returns a hash containing those
values keyed to recognizable names.

See:

http://wiki.mobileread.com/wiki/DOC#PalmDOC

and

http://wiki.mobileread.com/wiki/MOBI

=head3 keys

The returned hash will have the following keys:

=over

=item * C<compression>

Possible values:

=over

=item 1 - no compression

=item 2 - PalmDoc compression

=item ?? - HuffDic?

=item 17480 - Mobipocket DRM

=back

A warning will be carped if an unknown value is found.

=item * C<textlength>

Uncompressed length of book text in bytes

=item * C<textrecords>

Number of PDB records used for book text

=item * C<recordsize>

Maximum size of each record containing book text. This should always
be 2048 (for some Mobipocket files) or 4096 (for everything else).  A
warning will be carped if it isn't.

=item * C<unused>

Two bytes that should always be zero.  A warning will be carped if
they aren't.

=back

Note that the current position component of the header is discarded.

=cut

sub unpack_palmdoc_header
{
    my ($headerdata) = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my @list = unpack("nnNnnxxxx",$headerdata);
    my @compression_keys = keys(%pdbcompression);
    my %retval;

    $retval{compression} = $list[0];
    $retval{unused}      = $list[1];
    $retval{textlength}  = $list[2];
    $retval{textrecords} = $list[3];
    $retval{recordsize}  = $list[4];
    carp($subname,"(): value ",$retval{unused},
         " found in unused header segment (expected 0)")
        unless($retval{unused} == 0);
    carp($subname,"(): found text record size ",$retval{recordsize},
         ", expected 2048 or 4096")
        unless($retval{recordsize} ~~ [2048,4096]);
    carp($subname,"(): found unknown compression value ",$retval{compression})
        unless($retval{compression} ~~ @compression_keys);
    debug(1,"DEBUG: PDB compression type is ",
          $pdbcompression{$retval{compression}});
    return %retval;
}

########## END CODE ##########

=head1 BUGS/TODO

=over

=item * The determination of the Mobipocket language codes is a little
haphazard.  Primary languages should be detected, as well as all
supported English region codes, but non-English region codes are
almost entirely missing for languages not starting with A-E.

=item * Bookmarks aren't supported. This is a weakness inherited from
Palm::Doc, and will take a while to fix.

=item * unpack_mobi() could probably use some refactoring

=item * Unit tests are unwritten

=item * Documentation is incomplete

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
