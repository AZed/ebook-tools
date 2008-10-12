package EBook::Tools::Unpack;
use warnings; use strict; use utf8;
require Exporter;
use base qw(Exporter);
use version; our $VERSION = qv("0.1.0");
# $Revision $ $Date $

use Carp;
use EBook::Tools qw(debug);
use Fcntl qw(SEEK_CUR SEEK_SET);
use File::Basename qw(dirname fileparse);
use File::Path;     # Exports 'mkpath' and 'rmtree'
use Palm::PDB;
use Palm::Doc;
#use Palm::Raw;

our @EXPORT_OK;
@EXPORT_OK = qw (
    &detect_ebook
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
    );


sub detect_ebook
{
    my ($filename) = @_;
    my $fh;
    my $subname = ( caller(0) )[3];
    my $ident;
    my $info;
    my $index;
    debug(2,"DEBUG[",$subname,"]");

    croak($subname,"(): no filename specified")
        unless($filename);
    croak($subname,"(): '",$filename,"' not found")
        unless(-f $filename);

    open($fh,"<",$filename)
        or croak($subname,"(): failed to open '",$filename,"' for reading");
 
    # Check for PalmDB identifiers
    sysseek($fh,60,SEEK_SET);
    sysread($fh,$ident,8);

    if($palmdbcodes{$ident})
    {
        $ident = $palmdbcodes{$ident};
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
        debug(1,"DEBUG: Autodetected book format '",$ident,
              "', info '",$info,"'");
        return ($ident,$info);
    }
    return (undef,undef);
}

sub unpack_ebook
{
    my (%args) = @_;
    my %valid_args = (
        'file' => 1,
        'dir' => 1,
        'format' => 1,
        'author' => 1,
        'title' => 1,
        'opffile' => 1,
        );
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $filename = $args{file};
    croak($subname,"(): no input file specified")
        if(!$filename);
    my ($format,$info);

    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    if($args{format})
    {
        $format = $args{format};
    }
    else
    {
        ($format,$info) = detect_ebook($filename);
        croak($subname,"(): Format autodetection failed!")
            if(!$format);
    }
    croak($subname,
          "(): don't know how to handle format '",$format,"'")
        if(!$unpack_dispatch{$format});
    delete($args{format});
    $unpack_dispatch{$format}->(%args);
    return 1;
}


sub unpack_palmdoc
{
    my (%args) = @_;
    my %valid_args = (
        'file' => 1,
        'dir' => 1,
        'author' => 1,
        'title' => 1,
        'opffile' => 1,
        );
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $filename = $args{file};
    croak($subname,"(): no input file specified")
        if(!$filename);

    my ($filebase,$filedir,$fileext) = fileparse($filename,'\.\w+$');
    my $ebook = EBook::Tools->new();
    my $pdb = Palm::PDB->new();
    my $author = $args{author};
    my $title = $args{title};
    my $dir = $args{dir} || $filebase;
    my $opffile = $args{opffile};
    my ($outfile,$fh_outfile);
    $outfile = "$filebase.txt";

    $pdb->Load($filename);

    unless(-d $dir)
    {
        mkpath($dir)
            or croak("Unable to create output directory '",$dir,"'!");
    }
    chdir($dir)
        or croak("Unable to change working directory to '",$dir,"'!");

    open($fh_outfile,">:utf8",$outfile)
        or croak("Failed to open '",$outfile,"' for writing!");
    print {*$fh_outfile} $pdb->text;
    close($fh_outfile)
        or croak("Failed to close '",$outfile,"'!");

    $title = $title || $pdb->{'name'};
    $author = $author || 'Unknown Author';
    $opffile = $opffile || $title . ".opf";

    debug(2,"DEBUG: PalmDoc Name: ",$pdb->{'name'});
    debug(2,"DEBUG: PalmDoc Version: ",$pdb->{'version'});
    debug(2,"DEBUG: PalmDoc Type: ",$pdb->{'type'});
    debug(2,"DEBUG: PalmDoc Creator: ",$pdb->{'creator'});

    $ebook->init_blank(opffile => $opffile,
                       title => $title,
                       author => $author);
    $ebook->add_document($outfile,'text-main','text/plain');
    $ebook->save;
    return $opffile;
}
