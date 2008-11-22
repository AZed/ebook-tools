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
    );
our %EXPORT_TAGS = ('all' => [@EXPORT_OK]);

use Carp;
use EBook::Tools qw(debug userconfigdir);
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



#################################
########## CONSTRUCTOR ##########
#################################

my %rwfields = (
    'filename'      => 'string',
    'filecount'     => 'integer',
    'resdirlength'  => 'integer',
    'resdiroffset'  => 'integer',
    'version'       => 'integer',
    'compression'   => 'integer',
    'encryption'    => 'integer',
    'zoomstate'     => 'integer',
    'identifier'    => 'string',
    'category'      => 'string',
    'subcategory'   => 'string',
    'title'         => 'string',
    'lastname'      => 'string',
    'middlename'    => 'string',
    'firstname'     => 'string',
    'resdirname'    => 'string',
    );
my %rofields = (
    'unknown0x0a'   => 'string',
    'unknown0x18'   => 'integer',
    'unknown0x1c'   => 'integer',
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


######################################
########## MODIFIER METHODS ##########
######################################

sub load
{
    my $self = shift;
    my ($filename) = @_;
    my $subname = (caller(0))[3];
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

    return 1;
}


sub parse_imp_book_properties
{
    my $self = shift;
    my ($propdata) = @_;
    my $subname = (caller(0))[3];
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

=item * Offset 0x28 [4 bytes, big-endian unsigned long int]

Zoom state, stored in C<< $self->{zoomstate} >>.  Expected values are
0 (both zooms), 1 (small zoom), and 2 (large zoom)

=item * Offset 0x2C [4 bytes, big-endian unsigned long int]

Unknown value, stored in C<< $self->{unknown0x2c} >>.  Use with
caution -- this value may be renamed if more information is obtained.

=back

=cut

sub parse_imp_header
{
    my $self = shift;
    my ($headerdata) = @_;
    my $subname = (caller(0))[3];
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

    my $version = unpack('n',$headerdata);
    if($version < 1 or $version > 2)
    {
        carp($subname,"(): Version ",$version," is not supported!\n");
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

    # Unsigned long int values
    @list = unpack('NNNNNN',substr($headerdata,0x18,24));
    $self->{unknown0x18} = $list[0];
    $self->{unknown0x1c} = $list[1];
    $self->{compression} = $list[2];
    $self->{encryption}  = $list[3];
    $self->{zoomstate}   = $list[4];
    $self->{unknown0x2c} = $list[5];
    debug(2,"DEBUG: IMP compression = ",$self->{compression});
    debug(2,"DEBUG: IMP encryption = ",$self->{encryption});
    debug(2,"DEBUG: IMP zoom state = ",$self->{zoomstate});
    debug(2,"DEBUG: Unknown value at offset 0x18 = ",$self->{unknown0x18});
    debug(2,"DEBUG: Unknown value at offset 0x1c = ",$self->{unknown0x1c});
    debug(2,"DEBUG: Unknown value at offset 0x2c = ",$self->{unknown0x2c});

    return 1;
}


################################
########## PROCEDURES ##########
################################

=head1 PROCEDURES

All procedures are exportable, but none are exported by default.

=cut



########## END CODE ##########

=head1 BUGS AND LIMITATIONS

=over

=item * Not finished.  Do not try to use yet.

=back

=head1 AUTHOR

Zed Pobre <zed@debian.org>

=head1 LICENSE AND COPYRIGHT

Copyright 2008 Zed Pobre

Licensed to the public under the terms of the GNU GPL, version 2.

=cut

1;
__END__

