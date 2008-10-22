package EBook::Tools::Unpack;
use warnings; use strict; use utf8;
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
    'file'    => $filename,
    'dir'     => $dir,
    'format'  => $format,
    'raw'     => $raw,
    'author'  => $author,
    'title'   => $title,
    'opffile' => $opffile,
    'tidy'    => $tidy,
    );
 $unpacker->unpack;

or, more simply:

 use EBook::Tools::Unpack;
 my $unpacker = EBook::Tools::Unpack->new('file' => 'mybook.prc');
 $unpacker->unpack;

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
    &unpack_ebook
    &unpack_palmdoc
    );

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

=item * C<key>

The decryption key to use if necessary (not yet implemented)

=item * C<keyfile>

The file holding the decryption keys to use if necessary (not yet implemented)

=item * C<opffile>

The name of the file in which the metadata will be stored.  If not
specified, defaults to the value of C<dir> with C<.opf> appended.

=item * C<raw>

This causes a lot of raw, unparsed, unmodified data to be dumped into
the directory along with everything else.  It's useful for debugging
exactly what was in the file being unpacked, but not for much else.

=item * C<author>

Overrides the detected author name.

=item * C<title>

Overrides the detected title.

=item * C<tidy>

Run tidy on any HTML output files to convert them to valid XHTML.  Be
warned that this can occasionally change the formatting, as Tidy isn't
very forgiving on certain common tricks (such as empty <pre> elements
with style elements) that abuse the standard.

=back

=cut

my @fields = (
    'file',
    'dir',
    'format',
    'formatinfo',
    'raw',
    'key',
    'keyfile',
    'opffile',
    'author',
    'title',
    'tidy',
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
        'key' => 1,
        'keyfile' => 1,
        'format' => 1,
        'raw' => 1,
        'author' => 1,
        'title' => 1,
        'opffile' => 1,
        'tidy' => 1,
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
    $self->{key} = $args{key} if($args{key});
    $self->{keyfile} = $args{keyfile} if($args{keyfile});
    $self->{format} = $args{format} if($args{format});
    $self->{author} = $args{author} if($args{author});
    $self->{title} = $args{title} if($args{title});
    $self->{opffile} = $args{opffile} || ($self->{dir} . ".opf");
    $self->{raw} = $args{raw};
    $self->{tidy} = $args{tidy};

    $self->detect_format unless($self->{format});
    return $self;
}


=head1 ACCESSOR METHODS

Methods are available to retrieve all of the values assigned during
construction.  See L</new()> for more details on how each one is used.
Note that some values cannot be autodetected until an unpack method
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

=head2 C<opffile>

=head2 C<raw>

=head2 C<title>

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

sub detect_format
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
        # The info in this case is always the title, so set it if one
        # isn't already set.
        $$self{title} ||= $info;
        return ($ident,$info)
    }
    croak($subname,"(): unable to determine book format");
}

sub unpack
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $filename = $$self{file};
    croak($subname,"(): no input file specified")
        unless($filename);
    my $retval;

    croak($subname,
          "(): don't know how to handle format '",$$self{format},"'")
        if(!$unpack_dispatch{$$self{format}});
    $retval = $unpack_dispatch{$$self{format}}->($self);
    return $retval;
}


sub unpack_mobi
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $pdb = Palm::Doc->new();
    my $ebook = EBook::Tools->new();
    my $data;
    my $opffile;
    my $text;

    # Data from Record 0
    my $type;
    my $encoding;
    my $uniqueid;
    my $version;

    # Used for extracting images
    my $idstring;
    my $imageid = 0;
    my ($imagex,$imagey,$imagetype);
    my $imagename;

    # Used for file output
    my ($fh_html,$fh_image,$fh_raw);
    my $htmlname = $self->filebase . ".html";
    my $rawname;
    my $recindex = 1;

    $pdb->Load($$self{file});
    $self->usedir;

    foreach my $rec (@{$pdb->{records}})
    {
        $data = $rec->{data};
        $idstring = sprintf("%04d",$rec->{id});
        if($rec->{id} == 0)
        {
            # Set additional attributes from information taken from
            # the first record
            #
            # The format is:
            # 4 characters (a4): doctype 
            # unsigned long (N): length
            # unsigned long (N): type
            # unsigned long (N): codepage
            # unsigned long (N): unique ID
            # unsigned long (N): version
            #
            # We're only interested in the last four
            (undef,undef,$type,$encoding,$uniqueid,$version) =
                unpack("a4NNNNN", $data);
        }
        else { ($imagex,$imagey,$imagetype) = imgsize(\$data); }
        if(defined($imagex) && $imagetype)
        {
            $imagename = 
                $self->filebase . '-' . $idstring . '.' . lc($imagetype);
            debug(1,"DEBUG: unpacking image '",$imagename,
                  "' (",$imagex," x ",$imagey,")");
            open($fh_image,">",$imagename)
                or croak("Unable to open '",$imagename,"' to write image!");
            binmode($fh_image);
            print {*$fh_image} $data;
            close($fh_image)
                or croak("Unable to close image file '",$imagename,"'");
            $record_links{$recindex} = $imagename;
            $recindex++;
        }
        elsif($$self{raw})  # Dump non-image records as well
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
        else # Skipping non-image records for this first pass
        {
            debug(2,"  First pass skipping record #",$idstring);
        }
    }

    $text = $pdb->text;
    croak($subname,"(): found no text in '",$$self{file},"'!")
        unless($text);

    fix_mobi_html(\$text);

    open($fh_html,">",$htmlname);
    binmode($fh_html);
    debug(1,"DEBUG: writing corrected text to '",$htmlname,"'");
    print {*$fh_html} $text;
    close($fh_html);
    
    croak($subname,"(): unpack failed to generate any text")
        if(-z $htmlname);


    $opffile = split_metadata($htmlname);
    $ebook->init($opffile);
    $ebook->add_document($htmlname,'text-main');
    $ebook->set_primary_author(text => $$self{author}) if($$self{author});
    $ebook->set_title(text => $$self{title})
        if(!$ebook->title && $$self{title});
    $ebook->set_opffile($$self{opffile}) if($$self{opffile});
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

    return $ebook->opffile;
}


sub unpack_palmdoc
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

    $self->usedir;
    open($fh_outfile,">:utf8",$outfile)
        or croak("Failed to open '",$outfile,"' for writing!");
    print {*$fh_outfile} $pdb->text;
    close($fh_outfile)
        or croak("Failed to close '",$outfile,"'!");

    $$self{title}   ||= $pdb->{'name'};
    $$self{author}  ||= 'Unknown Author';
    $$self{opffile} ||= $$self{title} . ".opf";

    debug(2,"DEBUG: PalmDoc Name: ",$pdb->{'name'});
    debug(2,"DEBUG: PalmDoc Version: ",$pdb->{'version'});
    debug(2,"DEBUG: PalmDoc Type: ",$pdb->{'type'});
    debug(2,"DEBUG: PalmDoc Creator: ",$pdb->{'creator'});

    $ebook->init_blank(opffile => $$self{opffile},
                       title => $$self{title},
                       author => $$self{author});
    $ebook->add_document($outfile,'text-main','text/plain');
    $ebook->save;
    return $$self{opffile};
}


sub usedir
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");
    unless(-d $$self{dir})
    {
        debug(2,"  Creating directory '",$$self{dir},"'");
        mkpath($$self{dir})
            or croak("Unable to create output directory '",$$self{dir},"'!");
    }
    chdir($$self{dir})
        or croak("Unable to change working directory to '",$$self{dir},"'!");
    return 1;
}


########## PROCEDURES ##########

sub fix_mobi_html
{
    my ($html) = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");
    croak($subname,"(): argument must be a reference")
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
            substring($$html,$pos,1,'<a id="' . $pos . '"></a><');
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
    $tree->parse($$html);
    $tree->eof();

    # Replace img recindex links with img src links 
    @elements = $tree->find('img');
    foreach my $el (@elements)
    {
        $recindex = $el->attr('recindex') + 0;
        debug(2,"DEBUG: converting recindex ",$recindex," to src='",
              $record_links{$recindex},"'");
        $el->attr('recindex',undef);
        $el->attr('hirecindex',undef);
        $el->attr('lorecindex',undef);
        $el->attr('src',$record_links{$recindex});
    }

    # Replace filepos attributes with href attributes
    @elements = $tree->look_down('filepos',qr/.*/);
    foreach my $el (@elements)
    {
        $link = $el->attr('filepos');
        if($link)
        {
            debug(2,"DEBUG: converting filepos ",$link," to href");
            $link = '#fp' . $link;
            $el->attr('href',$link);
            $el->attr('filepos',undef);
        }
    }

    $$html = $tree->as_HTML;

    # HTML::TreeBuilder will remove all of the newlines, so add some
    # back in for readability even if tidy isn't called
    # This is unfortunately quite slow.  Make it optional?
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

    return 1;
}

########## END CODE ##########

=head1 BUGS/TODO

=over

=item * Unit tests are unwritten

=item * The process of adding newlines to output HTML can be quite
slow on larger documents.  It may be made optional in later versions.

=item * Import/extraction/unpacking is currently limited to PalmDoc
and Mobipocket.  Extraction from eReader, and Microsoft Reader (.lit)
is also eventually planned.

=back

=head1 AUTHOR

Zed Pobre <zed@debian.org>

=head1 COPYRIGHT

Copyright 2008 Zed Pobre

Licensed to the public under the terms of the GNU GPL, version 2

=cut

1;
