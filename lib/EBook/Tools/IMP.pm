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
    'dirnamelength' => 'integer',
    'bookpropsize'  => 'integer',
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

    if(!$self->{bookpropsize})
    {
        carp($subname,"(): '",$filename,"' has no book properties!\n");
        return;
    }
    sysread($fh_imp,$bookpropdata,$self->{bookpropsize});
    $retval = $self->parse_imp_book_properties($bookpropdata);

    return 1;
}


sub parse_imp_book_properties
{
    my $self = shift;
    my ($propdata) = @_;
    my $subname = (caller(0))[3];
    debug(2,"DEBUG[",$subname,"]");

    my $length = length($propdata);
    if($length != $self->{bookpropsize})
    {
        croak($subname,"(): expected ",$self->{bookpropsize},
              " bytes, was passed ",$length,"!\n");
    }

    my @properties;
    (@properties) = ($propdata =~ m/(.*?)\0/gx);

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
    $self->{dirnamelength} = $list[1];
    $self->{bookpropsize}    = $list[2];
    debug(2,"DEBUG: IMP file count = ",$self->{filecount});
    debug(2,"DEBUG: IMP dirnamelength = ",$self->{dirnamelength});
    debug(2,"DEBUG: IMP book properties size = ",$self->{bookpropsize});

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

