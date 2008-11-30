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
    &detect_resource_type
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
    'version'        => 'integer',
    'filename'       => 'string',
    'filecount'      => 'integer',
    'resdirlength'   => 'integer',
    'resdiroffset'   => 'integer',
    'compression'    => 'integer',
    'encryption'     => 'integer',
    'device'         => 'integer',
    'zoomstates'     => 'integer',
    'identifier'     => 'string',
    'category'       => 'string',
    'subcategory'    => 'string',
    'title'          => 'string',
    'lastname'       => 'string',
    'middlename'     => 'string',
    'firstname'      => 'string',
    'resdirname'     => 'string',
    'RSRC.INF'       => 'string',
    'resfiles'       => 'array',        # Array of hashrefs
    'toc'            => 'array',        # Table of Contents, array of hashes
    'resources'      => 'hash',         # Hash of hashrefs keyed on 'type'
    'lzsslengthbits' => 'integer',
    'lzssoffsetbits' => 'integer',      
    'text'           => 'string',       # Uncompressed text
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


    open($fh_imp,'<:raw',$filename)
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
            if($resource->{type} ne $entry->{type})
            {
                carp($subname,"():\n",
                     " '",$entry->{type},"' TOC entry pointed to '",
                     $resource->{type},"' resource!\n");
            }
            $self->{resources}->{$resource->{type}} = $resource;

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
        }
    }
    else
    {
        carp($subname,"(): IMP version ",$self->{version}," not supported!\n");
        return;
    }

    $self->parse_imp_resource_cm();
    $self->parse_imp_text();

    close($fh_imp)
        or croak($subname,"(): failed to close '",$filename,"'!\n");

    debug(3,$self->{text});
    return 1;
}


######################################
########## ACCESSOR METHODS ##########
######################################


=head2 C<author()>

Returns the full name of the author of the book.

Author information can either be found entirely in the
C<< $self->{firstname} >> attribute or split up into
C<< $self->{firstname} >>, C<< $self->{middlename} >>, and
C<< $self->{lastname} >>.  If the last name is found separately,
the full name is returned in the format "Last, First Middle".
Otherwise, the full name is returned in the format "First Middle".

=cut

sub author :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my $author;
    if($self->{lastname})
    {
        $author = $self->{lastname};
        if($self->{firstname})
        {
            $author .= ", " . $self->{firstname};
            $author .= " " . $self->{middlename} if($self->{middlename});
        }
    }
    else
    {
        $author = $self->{firstname};
        $author .= " " . $self->{middlename} if($self->{middlename});
    }
        
    return $author;
}


=head2 C<bookproplength()>

Returns the total length in bytes of the book properties data,
including the trailing null used to pack the C-style strings, but
excluding any ETI server data appended to the end of the standard book
properties.

=cut

sub bookproplength :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my $length = 0;
    $length += length($self->{identifier})  + 1;
    $length += length($self->{category})    + 1;
    $length += length($self->{subcategory}) + 1;
    $length += length($self->{title})       + 1;
    $length += length($self->{lastname})    + 1;
    $length += length($self->{middlename})  + 1;
    $length += length($self->{firstname})   + 1;

    return $length;
}


=head2 C<filecount()>

Returns the number of resource files as stored in
C<< $self->{filecount} >>.  Note that this does NOT recompute that value
from the actual number of resources in C<< $self->{resources} >>.  To do
that, use L</create_toc_from_resources()>.

=cut

sub filecount :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{filecount};
}


=head2 C<find_resource_by_name($name)>

Takes as a single argument a resource name and if a resource with that
name exists in C<< $self->{resources} >> returns the resource type
used as the hash key.

Returns undef if no match was found or a name was not specified.

=cut

sub find_resource_by_name :method
{
    my $self = shift;
    my ($name) = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    return unless($name);
    return unless($self->{resources});

    foreach my $type (keys %{$self->{resources}})
    {
        return $type if($self->{resources}->{$type}->{name} eq $name);
    }
    return;
}


=head2 C<pack_imp_book_properties()>

Packs object attributes into the 7 null-terminated strings that
constitute the book properties section of the header.  Returns that
string.

Note that this does NOT pack the ETI server data appended to this
section in encrypted books downloaded directly from the ETI servers,
even if that data was found when the .imp file was loaded.  This is
because the extra data can confuse the GEBLibrarian application, and
is not needed to read the book.  The L</bookproplength()> and
L</pack_imp_header()> methods also assume that this data will not be
present.

=cut

sub pack_imp_book_properties :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my $bookpropdata = pack("Z*Z*Z*Z*Z*Z*Z*",
                            $self->{identifier},
                            $self->{category},
                            $self->{subcategory},
                            $self->{title},
                            $self->{lastname},
                            $self->{middlename},
                            $self->{firstname});

    return $bookpropdata;
}


=head2 C<pack_imp_header()>

Packs object attributes into the 48-byte string representing the IMP
header.  Returns that string on success, carps a warning and returns
undef if a required attribute did not contain valid data.

Note that in the case of an encrypted e-book with ETI server data in
it, this header will not be identical to the original -- the
resdiroffset value is recalculated for the position with the ETI
server data stripped.  See L</bookproplength()> and
L</pack_imp_book_properties()>.

=cut

sub pack_imp_header :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my $header;
    my $filecount = scalar(keys %{$self->{resources}});
    my $resdir = $self->{resdirname};

    if(!$filecount)
    {
        carp($subname,"():\n",
             " No resources found (has a file been loaded?)\n");
        return;
    }

    if(!$resdir)
    {
        carp($subname,"():\n",
             " No resource directory name specified!\n");
        return;
    }

    if(!$self->{version})
    {
        carp($subname,"():\n",
             " No version specified (has a file been loaded?)\n");
        return;
    }
    if($self->{version} > 2)
    {
        carp($subname,"():\n",
             " invalid version ",$self->{version},"\n");
        return;
    }

    $header = pack('n',$self->{version});
    $header .= 'BOOKDOUG';
    if(length($self->{unknown0x0a}) != 8)
    {
        carp($subname,"():\n",
             " unknown data at 0x0a has incorrect length",
             " - substituting nulls");
        $self->{unknown0x0a} = "\x00\x00\x00\x00\x00\x00\x00\x00";
    }
    $header .= $self->{unknown0x0a};
    $header .= pack('nn',$filecount,length($resdir));
    $header .= pack('n',$self->bookproplength + 24);
    $header .= pack('NN',$self->{unknown0x18},$self->{unknown0x1c});
    $header .= pack('NN',$self->{compression},$self->{encryption});
    $header .= pack('nC',$self->{unknown0x28},$self->{unknown0x2a});
    $header .= pack('C',$self->{device} * 16 + $self->{zoomstates});
    $header .= pack('N',$self->{unknown0x2c});

    if(length($header) != 48)
    {
        croak($subname,"():\n",
              " total header length not 48 bytes (found ",
              length($header),")\n");
    }
    return $header;
}


=head2 C<pack_imp_resource(%args)>

Packs the specified resource stored in C<< $self->{resources} >> into
a a data string suitable for writing into a .imp file, with a header
format determined by C<< $self->{version} >>.

Returns a reference to that string if the resource was found, or undef
it was not.

=head3 Arguments

=over

=item * C<name>

Select the resource by resource name.

If both this and C<type> are specified, the type is checked first and
the name is only used if the type lookup fails.

=item * C<type>

Select the resource by resource type.  This is faster than selecting
by name (since resources are stored in a hash keyed by type) and is
recommended for most use.

If both this and C<name> are specified, the type is checked first and
the name is only used if the type lookup fails.

=back

=cut

sub pack_imp_resource :method
{
    my $self = shift;
    my %args = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my %valid_args = (
        'name' => 1,
        'type' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }
    if(!$args{name} and !$args{type})
    {
        carp($subname,"():\n",
             " at least one of name or type must be specified!\n");
        return;
    }

    my $type = $args{type};
    my $resource;
    my $resdata;

    if(!($type and $self->{resources}->{$type}) and $args{name})
    {
        $type = $self->find_resource_by_name($args{name});
        if(!$type or !$self->{resources}->{$type})
        {
            carp($subname,"():\n",
                 " no resource with name '",$args{name},"' found!\n");
            return;
        }
    }
    if(!$self->{resources}->{$type})
    {
        carp($subname,"()\n",
             " no resource with type '",$args{type},"' found!\n");
        return;
    }

    $resource = $self->{resources}->{$type};
    if($self->{version} == 1)
    {
        $resdata = pack('a[4]nN',
                        $resource->{name},
                        $resource->{unknown1},
                        $resource->{size});
        $resdata .= $resource->{data};
    }
    elsif($self->{version} == 2)
    {
        $resdata = pack('a[4]NNa[4]N',
                        $resource->{name},
                        $resource->{unknown1},
                        $resource->{size},
                        $resource->{type},
                        $resource->{unknown2});
        $resdata .= $resource->{data};
    }
    else
    {
        carp($subname,"(): invalid version ",$self->{version},"!\n");
        return;
    }

    if(!$resdata)
    {
        carp($subname,"(): no resource data packed!\n");
        return;
    }

    return \$resdata;
}


=head2 C<pack_imp_rsrc_inf()>

Packs object attributes into the data string that would be the content
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

    $rsrc = pack('na[8]n',1,'BOOKDOUG',$self->{resdiroffset});
    $rsrc .= pack('NNNNnCCN',
                  $self->{unknown0x18},$self->{unknown0x1c},
                  $self->{compression},$self->{encryption},
                  $self->{unknown0x28},$self->{unknown0x2a},
                  ($self->{device} * 16) + $self->{zoomstates},
                  $self->{unknown0x2c});
    $rsrc .= pack('Z*',$self->{identifier});
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


=head2 C<pack_imp_toc()>

Packs the C<< $self->{toc} >> object attribute into a data string
suitable for writing into a .imp file.  The format is determined by 
C<< $self->{version} >>.

Returns that string, or undef if valid version or TOC data is not
found.

=cut

sub pack_imp_toc
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    
    my $tocdata;

    if(!$self->{version})
    {
        carp($subname,"():\n",
             " no version information found (did you load a file first?)\n");
        return;
    }
    if($self->{version} > 2)
    {
        carp($subname,"():\n",
             " invalid version ",$self->{version},"!\n");
        return;
    }

    if(!@{$self->{toc}})
    {
        carp($subname,"(): no TOC data found!\n");
        return;
    }
    
    foreach my $entry (@{$self->{toc}})
    {
        if($self->{version} == 1)
        {
            $tocdata .= pack('a[4]nN',
                             $entry->{name},
                             $entry->{unknown1},
                             $entry->{size});
        }
        elsif($self->{version} == 2)
        {
            $tocdata .= pack('a[4]NNa[4]N',
                             $entry->{name},
                             $entry->{unknown1},
                             $entry->{size},
                             $entry->{type},
                             $entry->{unknown2});
        }
    }

    if(!length($tocdata))
    {
        carp($subname,"(): no valid TOC data produced!\n");
        return;
    }

    return $tocdata;
}


=head2 C<resdirbase()>

In scalar context, this returns the basename of C<< $self->{resdirname} >>.
In list context, it actually returns the basename, directory, and
extension as per C<fileparse> from L<File::Basename>.

=cut

sub resdirbase :method
{
    my $self = shift;
    return fileparse($self->{resdirname},'\.\w+$');
}


=head2 C<resdirlength()>

Returns the length of the .RES directory name as stored in
C<< $self->{resdirlength} >>.  Note that this does NOT recompute the 
length from the actual name stored in C<< $self->{resdirname} >> --
for that, use L</set_resdirlength()>.

=cut

sub resdirlength
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{resdirlength};
}


=head2 C<resdirname()>

Returns the .RES directory name stored in C<< $self->{resdirname} >>.

=cut

sub resdirname :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{resdirname};
}


=head2 C<resource($type)>

Returns a hashref containing the resource data for the specified
resource type, as stored in C<< $self->{resources}->{$type} >>.

Returns undef if C<$type> is not specified, or if the specified type
is not found.

=cut

sub resource
{
    my $self = shift;
    my ($type) = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return unless($type);
    return $self->{resources}->{$type};
}


=head2 C<resources()>

Returns a hashref of hashrefs containing all of the resource data
keyed by type, as stored in C<< $self->{resources} >>.

=cut

sub resources :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{resources};
}


=head2 C<text()>

Returns the uncompressed text originally stored in the DATA.FRK
(C<'    '>) resource.  This will only work if the text was unencrypted.   

=cut

sub text :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{text};
}


=head2 C<title()>

Returns the book title as stored in C<< $self->{title} >>.

=cut

sub title :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{title};
}


=head2 C<tocentry($index)>

Takes as a single argument an integer index to the table of contents
data stored in C<< $self->{toc} >>.  Returns the hashref corresponding
to that TOC entry, if it exists, or undef otherwise.

=cut

sub tocentry :method
{
    my $self = shift;
    my ($index) = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{toc}->[$index];
}


=head2 C<version()>

Returns the version of the IMP format used to determine TOC and
resource metadata size as stored in C<< $self->{version} >>.  Expected
values are 1 (10-byte metadata) and 2 (20-byte metadata).

=cut

sub version
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    return $self->{version};
}


=head2 C<write_imp($filename)>

Takes as a sole argument the name of a file to write to, and writes a
.imp file to that filename using the object attribute data.

Returns 1 on success, or undef if required data (including the
filename) was invalid or missing, or the file could not be written.

=cut

sub write_imp :method
{
    my $self = shift;
    my ($filename) = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");
    
    return unless($filename);

    my $fh_imp;
    if(!open($fh_imp,'>:raw',$filename))
    {
        carp($subname,"():\n",
             " unable to open '",$filename,"' for writing!\n");
        return;
    }

    my $headerdata = $self->pack_imp_header();
    my $bookpropdata = $self->pack_imp_book_properties();
    my $tocdata = $self->pack_imp_toc;

    if(!$headerdata or length($headerdata) != 48)
    {
        carp($subname,"(): invalid header data!\n");
        return;
    }
    if(!$bookpropdata)
    {
        carp($subname,"(): invalid book properties data!\n");
        return;
    }
    if(!$tocdata)
    {
        carp($subname,"(): invalid table of contents data!\n");
        return;
    }
    if(!$self->{resdirname})
    {
        carp($subname,"(): invalid .RES directory name!\n");
        return;
    }
    if(!scalar(keys %{$self->{resources}}))
    {
        carp($subname,"(): no resources found!\n");
        return;
    }

    print {*$fh_imp} $headerdata;
    print {*$fh_imp} $bookpropdata;
    print {*$fh_imp} $self->{resdirname};
    print {*$fh_imp} $tocdata;

    foreach my $tocentry (@{$self->{toc}})
    {
        print {*$fh_imp} ${$self->pack_imp_resource(type => $tocentry->{type})};
    }

    return 1;
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
    
    $self->{'RSRC.INF'} = $self->pack_imp_rsrc_inf;

    if($self->{'RSRC.INF'})
    {
        open($fh_resource,'>:raw','RSRC.INF')
            or croak($subname,"():\n",
                     " unable to open 'RSRC.INF' for writing!\n");

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


sub write_text :method
{
    my $self = shift;
    my %args = @_;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    my %valid_args = (
        'dir' => 1,
        'textfile' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    my $dirname = $args{dir} || $self->resdirbase;
    my $textfile = $args{textfile} || $self->resdirbase . '.txt';
    $textfile = $dirname . '/' . $textfile;
    my $fh_text;

    mkpath($dirname) if(! -d $dirname);

    if(! -d $dirname)
    {
        warn($subname,"(): unable to create directory '",$dirname,"'!\n");
        return;
    }

    if(!open($fh_text,'>:raw',$textfile))
    {
        warn($subname,"(): unable to open '",$textfile,"' for writing!\n");
        return;
    }
    print {*$fh_text} $self->text;
    if(!close($fh_text))
    {
        warn($subname,"(): unable to close '",$textfile,"'!\n");
        return;
    }

    return 1;
}


######################################
########## MODIFIER METHODS ##########
######################################

=head2 C<create_toc_from_resources()>

Creates appropriate table of contents data from the metadata in
C<< $self->{resources} >>, in the format specified by
C<< $self->{version} >>.  This will also set C<< $self->{filecount} >> to
match the actual number of resources.

=cut

sub create_toc_from_resources
{
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
    my $length = $self->bookproplength;
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
which also marks the end of the book properties, stored in 
C<< $self->{resdiroffset} >>.  Note that this is NOT the length of the
book properties.  To get the length of the book properties, subtract
24 from this value (the number of bytes remaining in the header after
this point).  It is also NOT the offset from the beginning of the file
to the .RES directory name -- to find that, add 24 to this value (the 
number of bytes already parsed).

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

The upper nybble at this position is the IMP reader device for which the
e-book was designed, stored in C<< $self->{device} >>.  Expected values
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
    $self->{device}        = $list[0] >> 4;
    $self->{zoomstates}   = $list[0] & 0x0f;
    $self->{unknown0x2c} = $list[1];

    debug(2,"DEBUG: IMP device = ",$self->{device});
    debug(2,"DEBUG: IMP zoom state = ",$self->{zoomstates});
    debug(2,"DEBUG: Unknown long int at offset 0x2c = ",$self->{unknown0x2c});

    return 1;
}


=head2 C<parse_imp_resource_cm()>

Parses the C<!!cm> resource loaded into C<< $self->{resources} >>,
if present, extracting the LZSS uncompression parameters into
C<< $self->{lzssoffsetbits} >> and C<< $self->{lzsslengthbits} >>.

Returns 1 on success, or undef if no C<!!cm> resource has been loaded
yet or the resource data is invalid.

=cut

sub parse_imp_resource_cm :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    return unless($self->{resources}->{'!!cm'});

    my @list;
    my $version;
    my $ident;          # Must be constant string '!!cm'
    my $unknown1;
    my $indexoffset;
    my $lzssdata;

    @list = unpack('na[4]NN',$self->{resources}->{'!!cm'}->{data});
    $version     = $list[0];
    $ident       = $list[1];
    $unknown1    = $list[2];
    $indexoffset = $list[3];

    if($ident ne '!!cm')
    {
        carp($subname,"():\n",
             " Invalid '!!cm' record!\n");
        return;
    }
    debug(2,"DEBUG: parsing !!cm v",$version,", index offset ",$indexoffset);
    $lzssdata = substr($self->{resources}->{'!!cm'}->{data},$indexoffset-4,4);
    @list = unpack('nn',$lzssdata);

    if($list[0] + $list[1] > 32
       or $list[0] < 2
       or $list[1] < 1)
    {
        carp($subname,"():\n",
             " invalid LZSS compression bit lengths!\n",
             "[",$list[0]," offset bits, ",
             $list[1]," length bits]\n");
        return;
    }

    $self->{lzssoffsetbits} = $list[0];
    $self->{lzsslengthbits} = $list[1];
    debug(2,"DEBUG: !!cm specifies ",$list[0]," offset bits, ",
          $list[1]," length bits");
    return 1;
}


=head2 C<parse_imp_text()>

Parses the C<'    '> (DATA.FRK) resource loaded into
C<< $self->{resources} >>, if present, extracting the text into 
C<< $self->{text} >>, uncompressing it if necessary.  LZSS uncompression
will use the C<< $self->{lzsslengthbits} >> and
C<< $self->{lzssoffsetbits} >> attributes if present, and default to 3
length bits and 14 offset bits otherwise.

Returns the length of the uncompressed text, or undef if no text
resource was found.

=cut

sub parse_imp_text :method
{
    my $self = shift;
    my $subname = (caller(0))[3];
    croak($subname . "() called as a procedure!\n") unless(ref $self);
    debug(2,"DEBUG[",$subname,"]");

    return unless($self->{resources}->{'    '});
    
    my $lengthbits = $self->{lzsslengthbits} || 3;
    my $offsetbits = $self->{lzssoffsetbits} || 14;
    my $lzss = EBook::Tools::LZSS->new(lengthbits => $lengthbits,
                                       offsetbits => $offsetbits);
    my $textref = $lzss->uncompress(\$self->{resources}->{'    '}->{data});
        
    $self->{text} = $$textref;

    return length($self->{text});
}


=head2 C<parse_imp_toc_v1($tocdata)>

Takes as a single argument a string containing the table of contents
data, and parses it into object attributes following the version 1
format (10 bytes per entry).

=head3 Format

=over

=item * Offset 0x00 [4 bytes, text]

Resource name.  Stored in hash key C<name>.  In the case of the
'DATA.FRK' text resource, this will be four spaces (C<'    '>).

=item * Offset 0x04 [2 bytes, big-endian unsigned short int]

Unknown, but always zero or one.  Stored in hash key C<unknown1>.

=item * Offset 0x08 [4 bytes, big-endian unsigned long int]

Size of the resource data in bytes.  Stored in hash key C<size>.

=back

=cut

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
        $tocentry{unknown1} = $list[1];
        $tocentry{size}     = $list[2];

        debug(3,"DEBUG: found toc entry '",$tocentry{name},
              "', type '",$tocentry{type},"' [",$tocentry{size}," bytes]");
        push(@{$self->{toc}}, \%tocentry);
        $offset += 10;
    }

    return 1;
}


=head2 C<parse_imp_toc_v2($tocdata)>

Takes as a single argument a string containing the table of contents
data, and parses it into object attributes following the version 2
format (20 bytes per entry).

=head3 Format

=over

=item * Offset 0x00 [4 bytes, text]

Resource name.  Stored in C<name>.  In the case of the 'DATA.FRK' text
resource, this will be four spaces (C<'   '>).

=item * Offset 0x04 [4 bytes, big-endian unsigned long int]

Unknown, but always zero.  Stored in C<unknown1>.

=item * Offset 0x08 [4 bytes, big-endian unsigned long int]

Size of the resource data in bytes.  Stored in C<size>.

=item * Offset 0x0C [4 bytes, text]

Resource type.  Stored in C<type>, and used as the key for the stored
resource hash.

=item * Offset 0x10 [4 bytes, big-endian unsigned long int]

Unknown, but always either zero or one.  Stored in C<unknown2>.

=back

=cut

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

        debug(3,"DEBUG: found toc entry '",$tocentry{name},
              "', type '",$tocentry{type},"' [",$tocentry{size}," bytes,",
              " unk1=",$tocentry{unknown1}," unk2=",$tocentry{unknown2},"]");
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


=head2 C<detect_resource_type(\$data)

Takes as a sole argument a reference to the data component of a
resource.  Returns a 4-byte string containing the resource type if
detected successfully, or undef otherwise.

Detection will not work on the C<DATA.FRK> (C<'   '>) resource.  That
one must be detected separately by name/type.

=cut

sub detect_resource_type
{
    my ($dataref) = @_;
    my $subname = (caller(0))[3];
    debug(3,"DEBUG[",$subname,"]");

    if(!$dataref)
    {
        carp($subname,"(): no resource data provided!\n");
        return;
    }
    if(ref $dataref ne 'SCALAR')
    {
        carp($subname,"(): argument is not a scalar reference!\n");
        return;
    }

    my $id = substr($$dataref,2,4);
    if($id =~ m/^[\w! ]{4}$/)
    {
        return $id;
    }
    carp($subname,"(): resource not recognized!\n");
    return;
}


=head2 C<parse_imp_resource_v1()>

Takes as a sole argument a string containing the data (including the
10-byte header) of a version 1 IMP resource.

Returns a hashref containing that data separated into the following
keys:

=over

=item * C<name>

The four-letter name of the resource.

=item * C<type>

The four-letter type of the resource.  This is detected from the data,
and is not part of the v1 header.

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
    $resource{unknown1} = $list[1];
    $resource{size}     = $list[2];
    $resource{data}     = substr($data,10);
    if($resource{name} eq '    ')
    {
        $resource{type} = '    ';
    }
    else
    {
        $resource{type} = detect_resource_type(\$resource{data});
    }

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
          "', type '",$resource{type},"' [",$resource{size}," bytes,",
          " unk1=",$resource{unknown1}," unk2=",$resource{unknown2},"]");

    return \%resource;
}


########## END CODE ##########

=head1 BUGS AND LIMITATIONS

=over

=item * Not finished.  Do not try to use yet.

=item * Support for v1 files is completely untested and implemented
with some guesswork.  Bug reports welcome.

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

Thanks are also due to Jeffrey Kraus-yao <krausyaoj@ameritech.net> for
his work reverse-engineering the .IMP format to begin with, and the
documentation at L<http://krausyaoj.tripod.com/reb1200.htm>.

=head1 LICENSE AND COPYRIGHT

Copyright 2008 Zed Pobre

Licensed to the public under the terms of the GNU GPL, version 2.

=cut

1;
__END__

