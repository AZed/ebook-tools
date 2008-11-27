package EBook::Tools::IMP;
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

EBook::Tools::IMP - Components related to the SoftBook/GEB/REB/eBookWise C<.IMP> e-book format 

=head1 SYNOPSIS

 use EBook::Tools::IMP qw(:all)
 my $imp = EBook::Tools::IMP->new();
 $imp->load('myfile.imp');

=cut

require Exporter;
use base qw(Exporter);

our @EXPORT_OK;
@EXPORT_OK = qw (
    &parse_imp_resource_v1
    &parse_imp_resource_v2
    );
our %EXPORT_TAGS = ('all' => [@EXPORT_OK]);

use Carp;
use Cwd qw(getcwd realpath);
use EBook::Tools qw(:all);
use EBook::Tools::LZSS qw(:all);
use Encode;
use File::Basename qw(dirname fileparse);
use File::Path;     # Exports 'mkpath' and 'rmtree'
binmode(STDERR,":utf8");

my $drmsupport = 0;
eval
{
    require EBook::Tools::DRM;
    EBook::Tools::DRM->import();
}; # Trailing semicolon is required here
unless($@){ $drmsupport = 1; }



####################################################
########## CONSTRUCTOR AND INITIALIZATION ##########
####################################################

my %rwfields = (
    'version'       => 'integer',
    'filename'      => 'string',
    'filecount'     => 'integer',
    'resdirlength'  => 'integer',
    'resdiroffset'  => 'integer',
    'compression'   => 'integer',
    'encryption'    => 'integer',
    'type'          => 'integer',
    'zoomstates'     => 'integer',
    'identifier'    => 'string',
    'category'      => 'string',
    'subcategory'   => 'string',
    'title'         => 'string',
    'lastname'      => 'string',
    'middlename'    => 'string',
    'firstname'     => 'string',
    'resdirname'    => 'string',
    'RSRC.INF'      => 'string',
    'resfiles'      => 'array',         # Array of hashrefs
    'toc'           => 'array',         # Table of Contents, array of hashes
    'resources'     => 'hash',          # Hash of hashrefs keyed on 'type'
    'text'          => 'string',        # Uncompressed text
    );
my %rofields = (
    'unknown0x0a'   => 'string',
    'unknown0x18'   => 'integer',
    'unknown0x1c'   => 'integer',
    'unknown0x28'   => 'integer',
    'unknown0x2a'   => 'integer',
    'unknown0x2c'   => 'integer',
    );
my %privatefields = (
);

# A simple 'use fields' will not work here: use takes place inside
# BEGIN {}, so the @...fields variables won't exist.
require fields;
fields->import(
    keys(%rwfields),keys(%rofields),keys(%privatefields)
    );

sub new   ## no critic (Always unpack @_ first)
{
    my $self = shift;
    my $class = ref($self) || $self;
    my ($filename) = @_;
    my $subname = (caller(0))[3];
    debug(2,"DEBUG[",$subname,"]");

    $self = fields::new($class);
    $self->{filename} = $filename if($filename);
    return $self;
}


sub load :method
{
    my $self = shift;
    my ($filename) = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    if(!$self->{filename} and !$filename)
    {
        carp($subname,"(): no filename specified!\n");
        return;
    }

    $self->{filename} = $filename if($filename);
    $filename = $self->{filename} if(!$filename);

    my $fh_imp;
    my $headerdata;
    my $bookpropdata;
    my $retval;
    my $toc_size;
    my $tocdata;
    my $entrydata;
    my $resource;       # Hashref


    open($fh_imp,'<',$filename)
        or croak($subname,"(): unable to open '",$filename,
                 "' for reading!\n");
    sysread($fh_imp,$headerdata,48);
    $retval = $self->parse_imp_header($headerdata);
    if(!$retval)
    {
        carp($subname,"(): '",$filename,"' is not an IMP file!\n");
        return;
    }

    if(!$self->{resdiroffset})
    {
        carp($subname,"(): '",$filename,"' has no res dir offset!\n");
        return;
    }
    my $bookproplength = $self->{resdiroffset} - 24;
    sysread($fh_imp,$bookpropdata,$bookproplength);
    $retval = $self->parse_imp_book_properties($bookpropdata);

    if(!$self->{resdirlength})
    {
        carp($subname,"(): '",$filename,"' has no directory name!\n");
        return;
    }

    sysread($fh_imp,$self->{resdirname},$self->{resdirlength});

    debug(1,"DEBUG: resource directory = '",$self->{resdirname},"'");
    
    $self->{'RSRC.INF'} = $self->pack_imp_rsrc_inf;

    if($self->{version} == 1)
    {
        $toc_size = 10 * $self->{filecount};
        sysread($fh_imp,$tocdata,$toc_size)
            or croak($subname,"(): unable to read TOC data!\n");
        $self->parse_imp_toc_v1($tocdata);

        $self->{resources} = ();
        foreach my $entry (@{$self->{toc}})
        {
            sysread($fh_imp,$entrydata,$entry->{size}+10);
            $resource = parse_imp_resource_v1($entrydata);
            $self->{resources}->{$resource->{type}} = $resource;

            if($entry->{type} eq '    ')
            {
                my $textref = uncompress_lzss(
                    dataref => \$self->{resources}->{'    '}->{data},
                    lengthbits => 3,
                    offsetbits => 14);

                $self->{text} = $$textref;
            }
        }
    }
    elsif($self->{version} == 2)
    {
        $toc_size = 20 * $self->{filecount};
        sysread($fh_imp,$tocdata,$toc_size)
            or croak($subname,"(): unable to read TOC data!\n");
        $self->parse_imp_toc_v2($tocdata);

        $self->{resources} = ();
        foreach my $entry (@{$self->{toc}})
        {
            sysread($fh_imp,$entrydata,$entry->{size}+20);
            $resource = parse_imp_resource_v2($entrydata);
            $self->{resources}->{$resource->{type}} = $resource;
            
            if($entry->{type} eq '    ')
            {
                my $textref = uncompress_lzss(
                    dataref => \$self->{resources}->{'    '}->{data},
                    lengthbits => 3,
                    offsetbits => 14);

                $self->{text} = $$textref;
            }
        }
    }
    else
    {
        carp($subname,"(): IMP version ",$self->{version}," not supported!\n");
        return;
    }

    close($fh_imp)
        or croak($subname,"(): failed to close '",$filename,"'!\n");

    debug(3,$self->{text});
    return 1;
}


######################################
########## ACCESSOR METHODS ##########
######################################

sub text :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{text};
}


sub write_resdir :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    if(!$self->{resdirname})
    {
        carp($subname,"(): .RES directory name not known!\n");
        return;
    }

    my $cwd = getcwd();
    my $fh_resource;

    mkpath($self->{resdirname});
    if(! -d $self->{resdirname})
    {
        croak($subname,"():\n",
              " unable to create .RES directory '",$self->{resdirname},
              "'!\n");
    }
    chdir($self->{resdirname});
    
    if($self->{'RSRC.INF'})
    {
        open($fh_resource,'>','RSRC.INF')
            or croak($subname,"():\n",
                     " unable to open 'RSRC.INF' for writing!\n");

        binmode ($fh_resource);
        print {*$fh_resource} $self->{'RSRC.INF'};
        close($fh_resource)
            or croak($subname,"():\n",
                     " unable to close 'RSRC.INF'!\n");
    }
    else
    {
        carp($subname,"():\n",
             " WARNING: no RSRC.INF data found!\n");
    }

    foreach my $restype (keys %{$self->{resources}})
    {
        my $filename = $self->{resources}->{$restype}->{name};
        $filename = 'DATA.FRK' if($filename eq '    ');

        open($fh_resource,'>:raw',$filename)
            or croak($subname,"():\n",
                     " unable to open '",$filename,"' for writing!\n");

        print {*$fh_resource} $self->{resources}->{$restype}->{data};
        close($fh_resource)
            or croak($subname,"():\n",
                     " unable to close '",$filename,"'!\n");
    }
    
    

    chdir($cwd);
    return 1;
}

######################################
########## MODIFIER METHODS ##########
######################################

=head2 C<pack_imp_rsrc_inf()>

Packs object variables into the data string that would be the content
of the RSRC.INF file.  Returns that string.

Currently does no sanity checking at all on the values it uses.

=cut

sub pack_imp_rsrc_inf :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my $rsrc;
    my $length;
    my $pad;

    $rsrc = pack('na[8]n',$self->{version},'BOOKDOUG',$self->{resdiroffset});
    $rsrc .= pack('NNNNnCCN',
                  $self->{unknown0x18},$self->{unknown0x1c},
                  $self->{compression},$self->{encryption},
                  $self->{unknown0x28},$self->{unknown0x2a},
                  ($self->{type} * 16) + $self->{zoomstates},
                  $self->{unknown0x2c});
    $rsrc .= pack('Z*','3:B:' . $self->{identifier});
    $rsrc .= pack('Z*Z*Z*',
                  $self->{category},$self->{subcategory},$self->{title});
    $rsrc .= pack('Z*Z*Z*',
                  $self->{lastname},$self->{middlename},$self->{firstname});
    
    # Make sure next record is 4-byte aligned (omit; breaks existing tools)
    #$length = length($rsrc);
    #$pad = $length % 4;
    #if($pad)
    #{
    #    $pad = 4 - $pad;
    #    $rsrc .= pack("a[$pad]","\0");
    #}
    #
    # Use ISSUE_NUMBER here for periodicals, but periodicals not yet handled
    #$rsrc .= pack('NN',2,0xffffffff);
    # CONTENT_FEED periodical data not used
    #$rsrc .= pack('Z*','');
    # SOURCE_ID:SOURCE_TYPE:None
    #$rsrc .= pack('Z*','3:B:None');
    # Unknown 4 bytes
    #$rsrc .= pack('N',0);

    return $rsrc;
}


=head2 C<parse_imp_book_properties($propdata)>

Takes as a single argument a string containing the book properties
data.  Sets the object variables from its contents, which should be
seven null-terminated strings in the following order:

=over

=item * Identifier

=item * Category

=item * Subcategory

=item * Title

=item * Last Name

=item * Middle Name

=item * First Name

=back

Note that the entire name is frequently placed into the "First Name"
component, and the "Last Name" and "Middle Name" components are left
blank.

A warning will be carped if the length of the parsed properties
(including the C null string terminators) is not equal to the length
of the data passed.

=cut

sub parse_imp_book_properties :method
{
    my $self = shift;
    my ($propdata) = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my @properties = unpack("Z*Z*Z*Z*Z*Z*Z*",$propdata);
    if(scalar(@properties) != 7)
    {
        carp($subname,"(): WARNING: expected 7 book properties, but found ",
             scalar(@properties),"!\n");
    }

    $self->{identifier}  = $properties[0];
    $self->{category}    = $properties[1];
    $self->{subcategory} = $properties[2];
    $self->{title}       = $properties[3];
    $self->{lastname}    = $properties[4];
    $self->{middlename}  = $properties[5];
    $self->{firstname}   = $properties[6];

    debug(2,"DEBUG: found ",scalar(@properties)," properties: ");
    debug(2,"  Identifier:   ",$self->{identifier});
    debug(2,"  Category:     ",$self->{category});
    debug(2,"  Subcategory:  ",$self->{subcategory});
    debug(2,"  Title:        ",$self->{title});
    debug(2,"  Last Name:    ",$self->{lastname});
    debug(2,"  Middle Name:  ",$self->{middlename});
    debug(2,"  First Name:   ",$self->{firstname});

    # Check for leftover data
    my $length = 0;
    $length += (length($properties[0]) + 1) if(defined $properties[0]);
    $length += (length($properties[1]) + 1) if(defined $properties[1]);
    $length += (length($properties[2]) + 1) if(defined $properties[2]);
    $length += (length($properties[3]) + 1) if(defined $properties[3]);
    $length += (length($properties[4]) + 1) if(defined $properties[4]);
    $length += (length($properties[5]) + 1) if(defined $properties[5]);
    $length += (length($properties[6]) + 1) if(defined $properties[6]);
    
    if($length != length($propdata))
    {
        carp($subname,"():\n parsed ",$length,
             " bytes of book properties, but was passed ",length($propdata),
             " bytes of data!\n");
    }
    return 1;
}


=head2 C<parse_imp_header()>

Parses the first 48 bytes of a .IMP file, setting object variables.
The method croaks if it receives any more or less than 48 bytes.

=head3 Header Format

=over

=item * Offset 0x00 [2 bytes, big-endian unsigned short int]

Version.  Expected values are 1 or 2; the version affects the format
of the table of contents header.  If this isn't 1 or 2, the method
carps a warning and returns undef.

=item * Offset 0x02 [8 bytes]

Identifier.  This is always 'BOOKDOUG', and the method carps a warning
and returns undef if it isn't.

=item * Offset 0x0A [8 bytes]

Unknown data, stored in C<< $self->{unknown0x0a} >>.  Use with caution
-- this value may be renamed if more information is obtained.

=item * Offset 0x12 [2 bytes, big-endian unsigned short int]

Number of included files, stored in C<< $self->{filecount} >>.

=item * Offset 0x14 [2 bytes, big-endian unsigned short int]

Length in bytes of the .RES directory name, stored in
C<< $self->{resdirlength} >>.

=item * Offset 0x16 [2 bytes, big-endian unsigned short int]

Offset from the point after this value to the .RES directory name,
which also marks the end of the book properties.  Note that this is
NOT the length of the book properties.  To get the length of the book
properties, subtract 24 from this value (the number of bytes remaining
in the header after this point).

=item * Offset 0x18 [4 bytes, big-endian unsigned long int?]

Unknown value, stored in C<< $self->{unknown0x18} >>.  Use with
caution -- this value may be renamed if more information is obtained.

=item * Offset 0x1C [4 bytes, big-endian unsigned long int?]

Unknown value, stored in C<< $self->{unknown0x1c} >>.  Use with
caution -- this value may be renamed if more information is obtained.

=item * Offset 0x20 [4 bytes, big-endian unsigned long int]

Compression type, stored in C<< $self->{compression} >>.  Expected
values are 0 (no compression) and 1 (LZSS compression).

=item * Offset 0x24 [4 bytes, big-endian unsigned long int]

Encryption type, stored in C<< $self->{encryption} >>.  Expected
values are 0 (no encryption) and 2 (DES encryption).

=item * Offset 0x28 [2 bytes, big-ending unsigned short int]

Unknown value, stored in C<< $self->{unknown0x28} >>.  Use with
caution -- this value may be renamed if more information is obtained.

=item * Offset 0x2A [1 byte]

Unknown value, stored in C<< $self->{unknown0x2A} >>.  Use with
caution -- this value may be renamed if more information is obtained.

=item * Offset 0x2B [2 nybbles (1 byte)]

The upper nybble at this position is the IMP reader type for which the
e-book was designed, stored in C<< $self->{type} >>.  Expected values
are 0 (Softbook 200/250e), 1 (REB 1200/GEB 2150), and 2 (EBW
1150/GEB1150).

The lower nybble marks the possible zoom states, stored in
C<< $self->{zoomstates} >>.  Expected values are 0 (both zooms), 1
(small zoom), and 2 (large zoom)

=item * Offset 0x2C [4 bytes, big-endian unsigned long int]

Unknown value, stored in C<< $self->{unknown0x2c} >>.  Use with
caution -- this value may be renamed if more information is obtained.

=back

=cut

sub parse_imp_header :method
{
    my $self = shift;
    my ($headerdata) = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my $length = length($headerdata);
    if($length != 48)
    {
        croak($subname,"(): expected 48 bytes, was passed ",$length,"!\n");
    }

    my $identstring = substr($headerdata,2,8);
    if($identstring ne 'BOOKDOUG')
    {
        carp($subname,"(): invalid IMP header!\n");
        return;
    }

    $self->{version} = unpack('n',$headerdata);
    if($self->{version} < 1 or $self->{version} > 2)
    {
        carp($subname,"(): Version ",$self->{version}," is not supported!\n");
        return;
    }

    $self->{unknown0x0a} = substr($headerdata,10,8);
    
    # Unsigned short int values
    my @list = unpack('nnn',substr($headerdata,0x12,6));
    $self->{filecount}     = $list[0];
    $self->{resdirlength}  = $list[1];
    $self->{resdiroffset}  = $list[2];
    debug(2,"DEBUG: IMP file count = ",$self->{filecount});
    debug(2,"DEBUG: IMP resdirlength = ",$self->{resdirlength});
    debug(2,"DEBUG: IMP resdir offset = ",$self->{resdiroffset});

    # Unknown long ints
    @list = unpack('NN',substr($headerdata,0x18,8));
    $self->{unknown0x18} = $list[0];
    $self->{unknown0x1c} = $list[1];
    debug(2,"DEBUG: Unknown long int at offset 0x18 = ",$self->{unknown0x18});
    debug(2,"DEBUG: Unknown long int at offset 0x1c = ",$self->{unknown0x1c});

    # Compression/Encryption/Unknown
    @list = unpack('NNnC',substr($headerdata,0x20,11));
    $self->{compression} = $list[0];
    $self->{encryption}  = $list[1];
    $self->{unknown0x28} = $list[2];
    $self->{unknown0x2a} = $list[3];
    debug(2,"DEBUG: IMP compression = ",$self->{compression});
    debug(2,"DEBUG: IMP encryption = ",$self->{encryption});
    debug(2,"DEBUG: Unknown short int at offset 0x28 = ",$self->{unknown0x28});
    debug(2,"DEBUG: Unknown byte at offset 0x2A = ",$self->{unknown0x2a});

    # Zoom State, and Unknown
    @list = unpack('CN',substr($headerdata,0x2B,5));
    $self->{type}        = $list[0] >> 4;
    $self->{zoomstates}   = $list[0] & 0x0f;
    $self->{unknown0x2c} = $list[1];

    debug(2,"DEBUG: IMP type = ",$self->{type});
    debug(2,"DEBUG: IMP zoom state = ",$self->{zoomstates});
    debug(2,"DEBUG: Unknown long int at offset 0x2c = ",$self->{unknown0x2c});

    return 1;
}


sub parse_imp_toc_v1 :method
{
    my $self = shift;
    my ($tocdata) = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my $length = length($tocdata);
    my $lengthexpected = 10 * $self->{filecount};
    my $tocentrydata;
    my $offset = 0;

    if($self->{version} != 1)
    {
        carp($subname,"(): attempting to parse a version 1 TOC,",
             " but the file appears to be version ",$self->{version},"!\n");
    }

    if($length != $lengthexpected)
    {
        carp($subname,"(): expected ",$lengthexpected," bytes, but received ",
             $length," -- aborting!\n");
        return;
    }
    
    $self->{toc} = ();
    foreach my $index (0 .. $self->{filecount} - 1)
    {
        my %tocentry;
        my @list;
        $tocentrydata = substr($tocdata,$offset,10);
        @list = unpack('a[4]nN',$tocentrydata);

        $tocentry{name}     = $list[0];
        $tocentry{type}     = $list[0];
        $tocentry{unknown1} = $list[1];
        $tocentry{size}     = $list[2];

        debug(2,"DEBUG: found toc entry '",$tocentry{name},
              "', type '",$tocentry{type},"' [",$tocentry{size}," bytes]");
        push(@{$self->{toc}}, \%tocentry);
        $offset += 10;
    }

    return 1;
}


sub parse_imp_toc_v2 :method
{
    my $self = shift;
    my ($tocdata) = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my $length = length($tocdata);
    my $lengthexpected = 20 * $self->{filecount};
    my $template;
    my $tocentrydata;
    my $offset = 0;

    if($self->{version} != 2)
    {
        carp($subname,"(): attempting to parse a version 2 TOC,",
             " but the file appears to be version ",$self->{version},"!\n");
    }

    if($length != $lengthexpected)
    {
        carp($subname,"(): expected ",$lengthexpected," bytes, but received ",
             $length," -- aborting!\n");
        return;
    }
    
    $self->{toc} = ();
    foreach my $index (0 .. $self->{filecount} - 1)
    {
        my %tocentry;
        my @list;
        $tocentrydata = substr($tocdata,$offset,20);
        @list = unpack('a[4]NNa[4]N',$tocentrydata);

        $tocentry{name}     = $list[0];
        $tocentry{unknown1} = $list[1];
        $tocentry{size}     = $list[2];
        $tocentry{type}     = $list[3];
        $tocentry{unknown2} = $list[4];

        debug(2,"DEBUG: found toc entry '",$tocentry{name},
              "', type '",$tocentry{type},"' [",$tocentry{size}," bytes]");
        push(@{$self->{toc}}, \%tocentry);
        $offset += 20;
    }

    return 1;
}


################################
########## PROCEDURES ##########
################################

=head1 PROCEDURES

All procedures are exportable, but none are exported by default.


=head2 C<parse_imp_resource_v1()>

Takes as a sole argument a string containing the data (including the
10-byte header) of a version 1 IMP resource.

Returns a hashref containing that data separated into the following
keys:

=over

=item * C<name>

The four-letter name of the resource.

=item * C<type>

The four-letter type of the resource.  For a version 1 resource, this
is the same as C<name>

=item * C<unknown1>

A 16-bit unsigned int of unknown purpose.  Expected values are 0 or 1.

Use with caution.  This key may be renamed later if more information
is found.

=item * C<size>

The expected size in bytes of the actual resource data.  A warning
will be carped if this does not match the actual size of the data
following the header.

=item * C<data>

The actual resource data.

=back

=cut

sub parse_imp_resource_v1
{
    my ($data) = @_;
    my $subname = (caller(0))[3];
    debug(3,"DEBUG[",$subname,"]");

    my @list;           # Temporary list
    my %resource;       # Hash containing resource data and metadata
    my $size;           # Actual size of resource data

    @list = unpack('a[4]nN',$data);
    $resource{name}     = $list[0];
    $resource{type}     = $list[0];
    $resource{unknown1} = $list[1];
    $resource{size}     = $list[2];
    $resource{data}     = substr($data,10);

    $size = length($resource{data});
    if($size != $resource{size})
    {
        carp($subname,"(): resource '",$resource{name},"' has ",
             $size," bytes (expected ",$resource{size},")!\n");
    }
    
    debug(2,"DEBUG: found resource '",$resource{name},
          "', type '",$resource{type},"' [",$resource{size}," bytes]");

    return \%resource;
}


=head2 C<parse_imp_resource_v2()>

Takes as a sole argument a string containing the data (including the
20-byte header) of a version 2 IMP resource.

Returns a hashref containing that data separated into the following
keys:

=over

=item * C<name>

The four-letter name of the resource.

=item * C<unknown1>

A 32-bit unsigned int of unknown purpose.  Expected values are 0 or 1.

Use with caution.  This key may be renamed later if more information
is found.

=item * C<size>

The expected size in bytes of the actual resource data.  A warning
will be carped if this does not match the actual size of the data
following the header.

=item * C<type>

The four-letter type of the resource.

=item * C<unknown2>

A 32-bit unsigned int of unknown purpose.  Expected values are 0 or 1.

Use with caution.  This key may be renamed later if more information
is found.

=item * C<data>

The actual resource data.

=back

=cut

sub parse_imp_resource_v2
{
    my ($data) = @_;
    my $subname = (caller(0))[3];
    debug(3,"DEBUG[",$subname,"]");

    my @list;           # Temporary list
    my %resource;       # Hash containing resource data and metadata
    my $size;           # Actual size of resource data

    @list = unpack('a[4]NNa[4]N',$data);
    $resource{name}     = $list[0];
    $resource{unknown1} = $list[1];
    $resource{size}     = $list[2];
    $resource{type}     = $list[3];
    $resource{unknown2} = $list[4];
    $resource{data}     = substr($data,20);

    $size = length($resource{data});
    if($size != $resource{size})
    {
        carp($subname,"(): resource '",$resource{name},"' has ",
             $size," bytes (expected ",$resource{size},")!\n");
    }
    
    debug(2,"DEBUG: found resource '",$resource{name},
          "', type '",$resource{type},"' [",$resource{size}," bytes]");

    return \%resource;
}


########## END CODE ##########

=head1 BUGS AND LIMITATIONS

=over

=item * Not finished.  Do not try to use yet.

=item * Encrypted .IMP files provided by the eBookwise servers may
have additional data inside the book properties header area,
corresponding to the data from the padding bytes through the
SOURCE_ID:SOURCE_TYPE:None string in the RSRC.INF file.  Currently,
this information is completely ignored (preset values will be used
when writing the RSRC.INF in all cases), and a warning will be carped
if it exists.  This should only happen inside encrypted books,
however.

=back

=head1 AUTHOR

Zed Pobre <zed@debian.org>

=head1 THANKS

Thanks are due to Nick Rapallo <nrapallo@yahoo.ca> for invaluable
assistance in understanding the .IMP format and testing this code.

=head1 LICENSE AND COPYRIGHT

Copyright 2008 Zed Pobre

Licensed to the public under the terms of the GNU GPL, version 2.

=cut

1;
__END__

