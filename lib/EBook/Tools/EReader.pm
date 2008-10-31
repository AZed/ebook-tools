package EBook::Tools::EReader;
use warnings; use strict; use utf8;
use 5.010; # Needed for smart-match operator
# $Revision $ $Date $
use version; our $VERSION = qv("0.1.1");

require Exporter;
use base qw(Exporter Palm::Raw);

our @EXPORT_OK;
@EXPORT_OK = qw (
    &cp1252_to_pml
    &pml_to_html
    );

sub import
{
    &Palm::PDB::RegisterPDBHandlers( __PACKAGE__, [ "PPrs", "PNRd" ], );
    &Palm::PDB::RegisterPRCHandlers( __PACKAGE__, [ "PPrs", "PNRd" ], );
    EBook::Tools::EReader->export_to_level(1, @_);
}

=head1 NAME

EBook::Tools::EReader - Components related to the
Fictionwise/PeanutPress eReader format.

=head1 SYNOPSIS

=head1 DEPENDENCIES

=over

=item * C<Compress::Zlib>

=item * C<Image::Size>

=item * C<P5-Palm>

=back

=cut


use Carp;
use Compress::Zlib;
use EBook::Tools qw(debug split_metadata system_tidy_xhtml);
use EBook::Tools::PalmDoc qw(uncompress_palmdoc);
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

our %pdbencoding = (
    '1252' => 'Windows-1252',
    '65001' => 'UTF-8',
    );


#################################
########## CONSTRUCTOR ##########
#################################

=head1 CONSTRUCTOR

=head2 C<new()>

Instantiates a new Ebook::Tools::EReader object.

=cut

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    
    $self->{'creator'} = 'PNRd';
    $self->{'type'} = 'PPrs';
    
    $self->{attributes}{resource} = 0;
    
    $self->{appinfo} = undef;
    $self->{sort} = undef;
    $self->{records} = [];

    $self->{header} = {};
    $self->{text} = '';

    $self->{title}     = '';
    $self->{author}    = '';
    $self->{rights}    = '';
    $self->{publisher} = '';
    $self->{isbn}      = '';

    return $self;
}


=head1 ACCESSOR METHODS

=cut

=head1 MODIFIER METHODS

=cut

sub ParseRecord :method
{
    my $self = shift;
    my %record = @_;
    my $subname = ( caller(0) )[3];
    debug(3,"DEBUG[",$subname,"]");

    my $currentrecord = scalar @{$$self{records}};
    my $version = $self->{header}->{version};
    my $recordtext;

    my $uncompress;  # Coderef to decompression sub

    if($currentrecord == 0)
    {
        $self->ParseRecord0($record{data});
        return \%record;
    }

    # Determine how to handle the remaining records
    if($version == 2)
    { 
        $uncompress = \&uncompress_palmdoc; 
    }
    elsif($version == 10)
    { 
        $uncompress = \&uncompress; 
    }
    elsif($version > 255)
    {
        croak($subname,"(): eReader DRM not supported [version ",
              $version,"]\n");
    }
    else
    {
        croak($subname,"(): unknown eReader version: ",$version,"\n");
    }


    # Start handling non-header records
    if($currentrecord < $self->{header}->{nontextrec})
    {
        $recordtext = $uncompress->($record{data});
        $recordtext =~ s/\0//;
#        $recordtext = decode('windows-1252',$recordtext);
        if($recordtext)
        {
            $self->{text} .= $recordtext;
            debug(3,"DEBUG: record ",$currentrecord," is text");
        }
        else
        {
            debug(1,"DEBUG: record ",$currentrecord,
                  " could not be decompressed (",
                  length($record{data})," bytes)");
            $$self{unknowndata}{$currentrecord} = $record{data};
        }
    }
    elsif($currentrecord >= $self->{header}->{nontextrec}
          && $currentrecord < $self->{header}->{bookmarkrec})
    {
        $recordtext = $uncompress->($record{data});
        debug(1,"DEBUG: record ",$currentrecord," contains ",
              length($record{data})," bytes of unknown data");

        if($recordtext)
        {
            $$self{unknowndata}{$currentrecord} = $recordtext;
        }
        else
        {
            $$self{unknowndata}{$currentrecord} = $record{data};
        }
    }
    elsif($currentrecord >= $self->{header}->{bookmarkrec}
          && $currentrecord < $self->{header}->{metadatarec})
    {
        my @list = unpack('nn',$record{data});
        $recordtext = substr($record{data},4);
        $recordtext =~ s/\0//gx;

        debug(3,"DEBUG: record ",$currentrecord," is bookmark '",
              $recordtext,
              "' [",sprintf("unk=0x%04x offset=0x%04x",@list),"]");
    }
    elsif($currentrecord == $self->{header}->{metadatarec})
    {
        # The metadata record consists of five null-terminated
        # strings
        my @list = $record{data} =~ m/(.*?)\0/gx;
        $self->{title}     = $list[0];
        $self->{author}    = $list[1];
        $self->{rights}    = $list[2];
        $self->{publisher} = $list[3];
        $self->{isbn}      = $list[4];
    }
    elsif($currentrecord == $self->{header}->{footnoterec})
    {
        my @footnoteids = $record{data} =~ m/(\w+)\0/gx;
        $self->{footnoteids} = \@footnoteids;
        debug(2,"DEBUG: record ",$currentrecord," has footnote ids: '",
              join("' '",@footnoteids),"'");
    }
    elsif($currentrecord > $self->{header}->{footnoterec}
          && $currentrecord < $self->{header}->{lastdatarec})
    {
        my @footnotes;
        my @footnoteids;

        if(ref $self->{footnoteids} eq 'ARRAY' and @{$self->{footnoteids}})
        {
            @footnoteids = @{$self->{footnoteids}};
        }
        else
        {
            carp($subname,
                 "(): adding a footnote, but no footnote IDs found\n");
            @footnoteids = [];
        }

        if(ref $self->{footnotes} eq 'ARRAY' and @{$self->{footnotes}})
        {
            @footnotes = @{$self->{footnotes}};
        }

        $recordtext = $uncompress->($record{data});
        if($recordtext)
        {
            $recordtext =~ s/\0//x;
            push(@footnotes,$recordtext);
        }

        if( scalar(@footnotes) > scalar(@footnoteids) )
        {
            carp($subname,
                 "(): footnote ",scalar(@footnotes),
                 " has no associated ID\n");
        }
        else
        {
            debug(2,"DEBUG: record ",$currentrecord," is footnote '",
                  $footnoteids[$#footnotes],"'");
        }

        $self->{footnotes} = \@footnotes;
    }
    else
    {
        my ($imagex,$imagey,$imagetype) = imgsize(\$record{data});
        $recordtext = $uncompress->($record{data});
        if(defined($imagex) && $imagetype)
        {
            debug(1,"DEBUG: record ",$currentrecord," is image");
            $$self{unknowndata}{$currentrecord} = $record{data};
        }
        elsif($recordtext)
        {
            debug(1,"DEBUG: record ",$currentrecord," has extra text:");
            debug(1,"       '",$recordtext,"'");
            $$self{unknowndata}{$currentrecord} = $recordtext;
        }
        else
        {
            debug(1,"DEBUG: record ",$currentrecord," is unknown (",
                  length($record{data})," bytes)");
            $$self{unknowndata}{$currentrecord} = $record{data};
        }
    }
    return \%record;
}


sub ParseRecord0 :method
{
    my $self = shift;
    my $data = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $version;     # EReader version
                     # Expected values are:
                     # 02 - PalmDoc Compression
                     # 10 - Inflate Compression
                     # >255 - data is in Record 1
    my $headerdata;  # used for holding temporary data segments
    my $headersize;  # size of variable-length header data
    my $offset;
    my %header;
    my @list;

    debug(1,"DEBUG: EReader Record 0 is ",length($data)," bytes");
    $headerdata = substr($data,0,16);
    @list = unpack('nnNnnnn',$headerdata);
    $header{version}        = $list[0]; # Bytes 0-1
    $header{unknown2}       = $list[1]; # Bytes 2-3
    $header{unknown4}       = $list[2]; # Bytes 4-7
    $header{unknown8}       = $list[3]; # Bytes 8-9
    $header{unknown10}      = $list[4]; # Bytes 10-11
    $header{nontextrec}     = $list[5]; # Bytes 12-13
    $header{nontextrec2}    = $list[5]; # Bytes 14-15

    $headerdata = substr($data,16,16);
    @list = unpack('nnNnnnn',$headerdata);
    $header{unknown16} = $list[0];
    $header{unknown18} = $list[1];
    $header{unknown20} = $list[2];
    $header{unknown22} = $list[3];
    $header{unknown24} = $list[4];
    $header{unknown28} = $list[5];
    $header{unknown30} = $list[6];

    $headerdata = substr($data,32,24);
    @list = unpack('nnnnnnnnnnnn',$headerdata);
    $header{bookmarkrec}   = $list[0];
    $header{unknown34}     = $list[1];
    $header{nontextrec3}   = $list[2];
    $header{unknown38}     = $list[3];
    $header{metadatarec}   = $list[4];
    $header{metadatarec2}  = $list[5];
    $header{metadatarec3}  = $list[6];
    $header{metadatarec4}  = $list[7];
    $header{footnoterec}   = $list[8];
    $header{unknown50}     = $list[9];
    $header{lastdatarec}   = $list[10];
    $header{unknown54}     = $list[11];

    $offset = 60;
    while($headerdata = substr($data,$offset,4))
    {
        @list = unpack('nn',$headerdata);
        debug(2,"DEBUG: offset ",$offset,"=",sprintf("0x%04x",$list[0]),
            " offset ",$offset+2,"=",sprintf("0x%04x",$list[1]))
            if($list[0] || $list[1]);
        $offset += 4;
    }

    foreach my $key (sort keys %header)
    {
        debug(2,'DEBUG: ereader{',$key,'}=0x',sprintf("%04x",$header{$key}));
#            if($header{$key});
    }

    $$self{header} = \%header;
    return %header;
}    


sub footnotes
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my %footnotehash;
    my @footnoteids = ();
    my @footnotes = ();
    my $lastindex;

    if(ref $self->{footnoteids} eq 'ARRAY' and @{$self->{footnoteids}})
    {
        @footnoteids = @{$self->{footnoteids}};
    }

    if(ref $self->{footnotes} eq 'ARRAY' and @{$self->{footnotes}})
    {
        @footnotes = @{$self->{footnotes}};
    }
    
    if($#footnotes != $#footnoteids)
    {
        carp($subname,"(): found ",scalar(@footnotes)," footnotes but ",
             scalar(@footnoteids)," footnote ids\n");
    }
    $lastindex = min($#footnotes, $#footnoteids);

    foreach my $idx (0 .. $lastindex)
    {
        $footnotehash{$footnoteids[$idx]} = $footnotes[$idx];
    }

    return %footnotehash;
}


sub footnotes_pml
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my %footnotehash = $self->footnotes;
    my $text;

    foreach my $footnoteid (sort keys %footnotehash)
    {
        $text .= '<footnote id="' . $footnoteid . '">';
        $text .= $footnotehash{$footnoteid};
        $text .= "</footnote>\n\n";
    }
    return $text;
}

sub pml
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");
    debug(2,"DEBUG: returning ",length($self->{text})," bytes of PML text");
    return $self->{text} . "\n" . $self->footnotes_pml;
}


sub html
{
    my $self = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    return pml_to_html($self->{text});
}


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

sub cp1252_to_pml
{
    my $text = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");
    
    return unless(defined $text);

    my %cppml = (
        "\x{92}" => '\a146',
        );

    foreach my $char (keys %cppml)
    {
        $text =~ s/$char/$cppml{$char}/gx;
    }
    return $text;
}


sub pml_to_html
{
    my $text = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");
    
    return unless(defined $text);
    my %pmlcodes = (
        '\p' => '<br style="page-break-after: always" />',
        '\x' => [ '<h1>','</h1>' ],
        '\X0' => [ '<h1>','</h1>' ],
        '\X1' => [ '<h2>','</h2>' ],
        '\X2' => [ '<h3>','</h3>' ],
        '\X3' => [ '<h4>','</h4>' ],
        '\X4' => [ '<h5>','</h5>' ],
        '\C0=' => '<div class="C0" id="$1"></div>',
        '\C0=' => '<div class="C1" id="$1"></div>',
        '\C0=' => '<div class="C2" id="$1"></div>',
        '\C0=' => '<div class="C3" id="$1"></div>',
        '\C0=' => '<div class="C4" id="$1"></div>',
        '\c' => [ '<div style="text-align: center">','</div>' ],
        '\r' => [ '<div style="text-align: right">','</div>' ],
        '\i' => [ '<em>','</em>' ],
        '\u' => [ '<ul>','</ul>' ],
        '\o' => [ '<strike>','</strike>' ],
        '\v' => [ '<!-- ',' -->' ],
        '\t' => [ '<ul>','</ul>' ],
        '\T=' => undef,
        '\w=' => '<hr />',
        '\n' => undef,
        '\s' => undef,
        '\b' => [ '<b>','</b>' ],
        '\B' => [ '<strong>','</strong>' ],
        '\l' => [ '<font size="+2">','</font>' ],
        '\Sb' => [ '<sub>','</sub>' ],
        '\Sp' => [ '<sup>','</sup>' ],
        # font-variant: small-caps is very badly supported on most
        # browsers, so using a workaround.
        # '\k' => [ '<div style="font-variant: small-caps">','</div>' ],
        '\k' => [ '<div style="font-size: smaller; text-transform: uppercase;">',
                  '</div>' ],
        "\\\\" => "\\",
        '\m=' => undef,
        '\q=' => [ '<a href="$1">','</a>' ],
        '\Q=' => [ '<div id="$1">','</div>' ],
        '\-' => '',
        '\Fn=' => [ undef, undef ],
        '\Sd=' => [ undef, undef ],
        '\I' => [ '<div class="refindex">','</div>' ],
        );

    while(my ($pmlcode,$replacement) = each(%pmlcodes) )
    {
        if(ref $replacement eq 'ARRAY')
        {
            if($pmlcode =~ / = $/x)
            {
                $pmlcode =~ s/= $//x;
                $text =~ s/$pmlcode="(.*?)" (.*?) $pmlcode
                          /$replacement->[0]$2$replacement->[1]/gx;
            }
            else
            {
                $text =~ s/$pmlcode (.*?) $pmlcode
                          /$replacement->[0]$1$replacement->[1]/gx;
            }
        }
        else
        {
            if($pmlcode =~ / = $/x)
            {
                $text =~ s/$pmlcode"(.*?)"/$replacement/gx;
            }
            else
            {
                $text =~ s/$pmlcode/$replacement/gx;
            }
            
        }
    } # while(my ($pmlcode,$replacement) = each(%pmlcodes) )
    return $text;
}

########## END CODE ##########

=head1 BUGS/TODO

=over

=item * Footnotes are extracted, but sidebars aren't.

=item * HTML conversion is very poor

=item * Documentation is very incomplete

=back

=head1 AUTHOR

Zed Pobre <zed@debian.org>

=head1 COPYRIGHT

Copyright 2008 Zed Pobre

Licensed to the public under the terms of the GNU GPL, version 2

=cut

1;
