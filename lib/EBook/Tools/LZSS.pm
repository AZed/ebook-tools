package EBook::Tools::LZSS;
use warnings; use strict; use utf8;
use English qw( -no_match_vars );
use version; our $VERSION = qv("0.4.0");
# $Revision$ $Date$
# $Id$

# Perl Critic overrides:
## no critic (Package variable)
# RequireBriefOpen seems to be way too brief to be useful
## no critic (RequireBriefOpen)
# Double-sigils are needed for lexical filehandles in clear print statements
## no critic (Double-sigil dereference)

=head1 NAME

EBook::Tools::LZSS - Lempel-Ziv-Storer-Szymanski compression and decompression

=head1 SYNOPSIS

 use EBook::Tools::LZSS;
 my $lzss = EBook::Tools::LZSS->new(lengthbits => 3,
                                    offsetbits => 14,
                                    windowinit => 'the man');
 my $textref = $lzss->uncompress(\$data);

=cut

require Exporter;
use base qw(Exporter);

our @EXPORT_OK;
@EXPORT_OK = qw (
    );
our %EXPORT_TAGS = ('all' => [@EXPORT_OK]);


use Bit::Vector;
use Carp;
use EBook::Tools qw(:all);
use Encode;
use File::Basename qw(dirname fileparse);
use File::Path;     # Exports 'mkpath' and 'rmtree'
binmode(STDERR,":utf8");


use constant ENCODED => 0;
use constant UNCODED => 1;



####################################################
########## CONSTRUCTOR AND INITIALIZATION ##########
####################################################

my %rwfields = (
    'lengthbits' => 'integer',
    'offsetbits' => 'integer',
    'windowinit' => 'string',
    'windowsize' => 'integer',
    'verbose'    => 'boolean',
    );
my %rofields = (
    );
my %privatefields = (
);

# A simple 'use fields' will not work here: use takes place inside
# BEGIN {}, so the @...fields variables won't exist.
require fields;
fields->import(
    keys(%rwfields),keys(%rofields),keys(%privatefields)
    );


=head1 CONSTRUCTOR AND INITIALIZATION

=head2 C<new(%args)>

Instantiates a new EBook::Tools::LZSS object.

=head3 Arguments

All arguments are optional, but must be identical between compression
and decompression for the result to be valid.

=over

=item * C<lengthbits>

The number of bits used to encode the length of a LZSS reference.  If
not specified defaults to 4 bits (a maximum reference length of 18
bytes, as the actual length is always 3 bytes more than specified).

The eBookwise .IMP format typically compresses with 3 length bits
(maximum reference length of 10 bytes).

=item * C<offsetbits>

The number of bits used to encode the offset to a LZSS reference.
This also determines the size of the sliding window of reference data.
If not specified, it defaults to 12 bits (4096-byte window).

The eBookwise .IMP format typically compresses with 14 offset bits
(16384-byte window).

=item * C<windowinit>

A string used to initalize the sliding window.  If specified, this
string MUST be the same length as the window size, or the subroutine
will croak.  If not specified, the window will be initialized with
spaces.

=item * C<verbose>

If set to true, compression and uncompression will provide additional
status feedback on STDOUT.

=back

=cut

sub new   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my $class = ref($self) || $self;
    my %args = @_;
    my $subname = (caller(0))[3];
    debug(2,"DEBUG[",$subname,"]");

    my %valid_args = (
        'lengthbits' => 1,
        'offsetbits' => 1,
        'windowinit' => 1,
        'verbose' => 1,
        );

    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    $self = fields::new($class);
    $self->{lengthbits} = $args{lengthbits} || 4;
    $self->{offsetbits} = $args{offsetbits} || 12;
    $self->{windowsize} = 1 << $self->{offsetbits};
    $self->{windowinit} = $args{windowinit} || ' ' x $self->{windowsize};
    $self->{verbose} = $args{verbose};

    if($self->{windowinit}
       and length($self->{windowinit}) != $self->{windowsize})
    {
        croak($subname,"(): \n window initialization string size (",
              length($self->{windowinit}),
              " does not match specified number of offset bits (",
              $self->{windowsize},")\n")
    }

    return $self;
}


#############################
########## METHODS ##########
#############################

=head1 METHODS

=head2 C<uncompress(\$dataref)>

Takes a reference to a compressed data string, uncompresses the data
string and returns a reference to the uncompressed string.

=cut

sub uncompress :method
{
    my $self = shift;
    my ($dataref) = @_;
    my $subname = (caller(0))[3];
    debug(2,"DEBUG[",$subname,"]");

    croak($subname,"(): no data provided!\n")
        unless($dataref);
    croak($subname,"(): data is not a reference!\n")
        unless(ref $dataref);

    my $lengthbits = $self->{lengthbits} || 4;
    my $offsetbits = $self->{offsetbits} || 12;
    my $windowsize = $self->{windowsize};
    my $window = $self->{windowinit};
    my $max_uncoded = 2;
    my $max_encoded = (1 << $lengthbits) + $max_uncoded;

    if(length($window) != $windowsize)
    {
        croak($subname,"(): \n window initialization string size (",
              length($window),
              " does not match specified number of offset bits (",
              $windowsize,")\n")
    }

    my $bitsize = length($$dataref) * 8;
    my $bitvector = Bit::Vector->new($bitsize);
    my $bitoffset;
    my $bitpos = 0;
    my $byte;

    my $windowpos = 1;
    my $encflag;
    my $dataoffset = 0;
    my $lzss_offset;
    my $lzss_length;
    my $lzss_text;
    my $uncompressed;

    # Unfortunately, the bitstream needs to be processed from left to
    # right, and Bit::Vector really likes to process from right to
    # left, so we have to process by chunk instead of using
    # Block_Store
    while($bitpos < $bitsize)
    {
        $bitoffset = $bitsize-$bitpos;
        $byte = unpack('C',substr($$dataref,$dataoffset,1));
        $bitvector->Chunk_Store(8,$bitoffset-8,$byte);
        $dataoffset++;
        $bitpos += 8;
    }

    $bitpos = 0;
    while($bitpos < $bitsize - 8)
    {
        # If there are less than 8 bits left, there's nothing to
        # decode and we can stop.  Otherwise, uncompress.

        if($self->{verbose} or $EBook::Tools::debug > 0)
        {
            my $percent = int( ($bitpos / $bitsize) * 100);
            
            print("Uncompressing text... [",$percent,"%]\r")
                if($percent % 5 == 0);
        }
        $bitoffset = $bitsize - $bitpos;
        $encflag = $bitvector->Chunk_Read(1,$bitoffset-1);
        $bitpos++;
        $bitoffset--;
        
        if($encflag == UNCODED)
        {
            if($bitoffset - 8 < 0)
            {
                debug(1,"DEBUG: ran out of bits at bit position ",
                      $bitpos,"!");
                last;
            }

            $bitoffset -= 8;
            $bitpos += 8;
            $byte = $bitvector->Chunk_Read(8,$bitoffset);
            $uncompressed .= chr($byte);
            substr($window,$windowpos,1,chr($byte));
            $windowpos++;
            $windowpos %= $windowsize;
        }
        else
        {
            if($bitoffset - ($offsetbits + $lengthbits) < 0)
            {
                debug(1,"DEBUG: ran out of bits at bit position ",
                      $bitpos," [",$bitoffset," bits remaining]!");
                last;
            }
            $bitoffset -= $offsetbits;
            $lzss_offset = $bitvector->Chunk_Read($offsetbits,$bitoffset);
            $bitoffset -= $lengthbits;
            $lzss_length = $bitvector->Chunk_Read($lengthbits,$bitoffset);
            if($lzss_length == 0
               and $lzss_offset == 0)
            {
                if($bitoffset >= 8)
                {
                    carp($subname,"(): invalid LZSS code at bit position ",
                         $bitpos," [",$bitoffset," bits remaining]!\n");
                }
                last;
            }
            $bitpos += ($offsetbits + $lengthbits);
            $lzss_length += 3;

            $lzss_text = substr($window,$lzss_offset,$lzss_length);
            substr($window,$windowpos,$lzss_length,$lzss_text);
            $windowpos += $lzss_length;
            $windowpos %= $windowsize;
            $uncompressed .= $lzss_text;
        }
    }

    if($self->{verbose} or $EBook::Tools::debug > 0)
    {
        print("Finished uncompressing text.\n");
    }
    return \$uncompressed;
}


################################
########## PROCEDURES ##########
################################


########## END CODE ##########

=head1 BUGS AND LIMITATIONS

=over

=item * Compression not yet implemented.

=item * The LZSS algorithm isn't documented in the POD.

=back


=head1 AUTHOR

Zed Pobre <zed@debian.org>

The design of this module was based on the C LZSS library by Michael
Dipperstein, version 0.5.2, at http://michael.dipperstein.com/lzss/


=head1 LICENSE AND COPYRIGHT

Copyright 2008 Zed Pobre

Licensed to the public under the terms of the GNU GPL, version 2.

=cut

1;
__END__
