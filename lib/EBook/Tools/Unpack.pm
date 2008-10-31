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

=cut


use Carp;
use EBook::Tools qw(debug hexstring split_metadata system_tidy_xhtml);
use EBook::Tools::EReader qw(cp1252_to_pml pml_to_html);
use EBook::Tools::Mobipocket;
use EBook::Tools::PalmDoc qw(uncompress_palmdoc);
use Encode;
use Fcntl qw(SEEK_CUR SEEK_SET);
use File::Basename qw(dirname fileparse);
use File::Path;     # Exports 'mkpath' and 'rmtree'

my $drmsupport = 0;
eval
{
    require EBook::Tools::DRM;
    EBook::Tools::DRM->import();
}; # Trailing semicolon is required here
unless($@){ $drmsupport = 1; }


our @EXPORT_OK;
@EXPORT_OK = qw (
    );

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


=head2 C<detect_from_mobi_exth()>

Detects metadata values from the MOBI EXTH headers retrieved via
L</unpack_mobi_exth()> and places them into the C<detected> attribute.

=cut

sub detect_from_mobi_exth :method
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my @mobiexth = @{$$self{datahashes}{mobiexth}};
    my $data;
    my %exthtypes = %EBook::Tools::Mobipocket::exthtypes;
    my %exth_is_int = %EBook::Tools::Mobipocket::exth_is_int;
    my %exth_repeats = %EBook::Tools::Mobipocket::exth_repeats;

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
        
        if($exth_repeats{$$exth{type}})
        {
            debug(2,"DEBUG: Repeating EXTH ",$type," = '",$data,"'");
            my @extharray = ();
            my $oldexth = $$self{detected}{$type};
            if(ref $oldexth eq 'ARRAY') { @extharray = @$oldexth; }
            elsif($oldexth) { push(@extharray,$oldexth); }
            push(@extharray,$data);
            $$self{detected}{$type} = \@extharray;
        }
        else
        {
            debug(2,"DEBUG: Single EXTH ",$type," = '",$data,"'");
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
        debug(2,"Multiple dc:Subject entries");
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
        debug(2,"Single dc:Subject entry");
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
    $$self{encoding}
    = $$self{datahashes}{mobi}{encoding} unless($$self{encoding});
    $$self{detected}{title} = $mobi->{title};
    $$self{detected}{language} = $mobi->{header}{mobi}{language};
    $$self{detected}{dictionaryinlanguage}
    = $mobi->{header}{mobi}{dilanguage};
    $$self{detected}{dictionaryoutlanguage}
    = $mobi->{header}{mobi}{dolanguage};

    $self->detect_from_mobi_exth();
    
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

=item * Unit tests are incomplete

=item * Documentation is incomplete.  Accessors in particular could
use some cleaning up.

=item * Need to implement setter methods for object attributes

=item * Import/extraction/unpacking is currently limited to PalmDoc,
Mobipocket, and eReader.  Extraction from Microsoft Reader (.lit) and
ePub is also eventually planned.  Other formats may follow from there.

=back

=head1 AUTHOR

Zed Pobre <zed@debian.org>

=head1 COPYRIGHT

Copyright 2008 Zed Pobre

Licensed to the public under the terms of the GNU GPL, version 2

=cut

1;
