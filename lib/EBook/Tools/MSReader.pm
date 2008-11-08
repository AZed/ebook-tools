package EBook::Tools::MSReader;
use warnings; use strict; use utf8;
use 5.010; # Needed for smart-match operator
use English qw( -no_match_vars );
use version; our $VERSION = qv("0.2.1");
# $Revision$ $Date$
# $Id$

# Perl Critic overrides:
## no critic (Package variable)
# RequireBriefOpen seems to be way too brief to be useful
## no critic (RequireBriefOpen)
# Double-sigils are needed for lexical filehandles in clear print statements
## no critic (Double-sigil dereference)

=head1 NAME

EBook::Tools::MSReader - Helper code for working with Microsoft Reader (.lit) e-books.

=head1 SYNOPSIS

 use EBook::Tools::MSReader qw(find_convertlit find_convertlit_keys 
                               system_convertlit);
 $EBook::Tools::MSReader::convertlit_cmd = '/opt/convertlit/clit';
 $EBook::Tools::MSReader::convertlit_keys = '/opt/convertlit/keys.txt';

 my $convertlit = find_convertlit();
 my $keyfile = find_convertlit_keys();
 system_convertlit(infile => 'myfile.lit',
                   dir => 'myfile-unpacked');

=cut

require Exporter;
use base qw(Exporter);

our @EXPORT_OK;
@EXPORT_OK = qw (
    &find_convertlit
    &find_convertlit_keys
    &system_convertlit
    );

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


our $convertlit_cmd = '';
our $convertlit_keys = '';


################################
########## PROCEDURES ##########
################################

=head1 PROCEDURES

All procedures are exportable, but none are exported by default.


=head2 C<find_convertlit()>

Attempts to locate the convertlit executable by making a test
execution on predicted locations (including just checking PATH) and
looking in the EBook::Tools user configuration directory (see
L<EBook::Tools/userconfigdir()>.

Returns the system command used for a successful invocation, or undef
if nothing worked.

This will use package variable C<$convertlit_cmd> as its first guess,
and set that variable to the return value as well.

=cut

sub find_convertlit
{
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my @convertlit_guesses;
    my $retval;
    my $confdir = userconfigdir();

    if($OSNAME eq 'MSWin32')
    {
        @convertlit_guesses = (
            'clit',
            'C:\Program Files\ConvertLIT\clit',
            );
        if($confdir)
        {
            push(@convertlit_guesses,
                 $confdir . '\clit',
                 $confdir . '\convertlit');
        }
    }
    else
    {
        @convertlit_guesses = (
            'clit',
            'convertlit',
            );
        if($confdir)
        {
            push(@convertlit_guesses,
                 $confdir . "/clit",
                 $confdir . "/convertlit");
        }
        push(@convertlit_guesses,
             '/opt/convertlit/clit',
             '/opt/convertlit/convertlit',
             '/opt/clit/clit',
             '/opt/clit/convertlit'
            );
    }
    unshift(@convertlit_guesses,$convertlit_cmd)
        if($convertlit_cmd);
    undef($convertlit_cmd);

    foreach my $guess (@convertlit_guesses)
    {
        no warnings 'exec';
        `$guess`;
        if($? != -1)
        {
            $convertlit_cmd = $guess;
            last;
        }
    }

    if($convertlit_cmd)
    {
        debug(1,"DEBUG: Found convertlit as '",$convertlit_cmd,"'");
        return $convertlit_cmd;
    }
    else { return; }
}


=head2 C<find_convertlit_keys($filename)>

Attempts to locate the convertlit C<keys.txt> file by checking
predicted filenames, both in the current working directory and in the
EBook::Tools user configuration directory (see
L<EBook::Tools/userconfigdir()>.

If C<$filename> is provided, the file C<basename-keys.txt> will also
be checked in both locations.

Returns the name of the first file found, or undef if nothing was found.

This will use package variable C<$convertlit_keys> as its first guess,
and set that variable to the return value as well.

=cut

sub find_convertlit_keys
{
    my $filename = shift;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my $basename;
    $basename = fileparse($filename,'\.\w+$') if($filename);
    my $confdir = userconfigdir();
    my $keyfile;

    my @guesses = ( 'keys.txt' );
    push(@guesses, $basename . '-keys.txt') if($basename);
    push(@guesses, $confdir . '/keys.txt') if($confdir);
    push(@guesses, $confdir . '/' . $basename . '-keys.txt')
        if($basename && $confdir);
    unshift(@guesses,$convertlit_keys) if($convertlit_keys);

    foreach my $guess (@guesses)
    {
        if(-f $guess)
        {
            $keyfile = $guess;
            debug(1,"DEBUG: found convertlit keys in '",$keyfile,"'");
            last;
        }
    }
    if($keyfile) { return $keyfile; }
    else { return; }
}


sub system_convertlit
{
    my %args = @_;
    my $subname = ( caller(0) )[3];
    debug(2,"DEBUG[",$subname,"]");

    my %valid_args = (
        'infile' => 1,
        'outfile' => 1,
        'keyfile' => 1,
        'dir' => 1,
        );
    foreach my $arg (keys %args)
    {
        croak($subname,"(): invalid argument '",$arg,"'")
            if(!$valid_args{$arg});
    }

    croak($subname,"(): no input file specified!\n")
        unless($args{infile});
    croak($subname,"(): input file '",$args{infile},"' not found!\n")
        unless(-f $args{infile});

    my @convertlit = ($convertlit_cmd);
    my $retval;
    my $keyfile = $args{keyfile};
    my $outfile = $args{outfile};
    my $dir = $args{dir};
    
    if($keyfile)
    {
        push(@convertlit,"-k$keyfile");
    }

    push(@convertlit,$args{infile});

    if($outfile && $dir)
    {
        push(@convertlit,"$dir/$outfile");
    }
    elsif($outfile)
    {
        push(@convertlit,$outfile);
    }
    elsif($dir)
    {
        # Expansion into a directory requires a trailing slash
        unless($dir =~ m{(/ | \\) $}x)
        {
            $dir .= '/';
        }
        push(@convertlit,$dir);
    }
    else
    {
        croak($subname,"(): neither output file nor directory specified!\n");
    }
    
    debug(2,"DEBUG: converting lit with '",join(' ',@convertlit),"'");
    $retval = system(@convertlit);
    return $retval;
}

########## END CODE ##########

=head1 BUGS AND LIMITATIONS

=over

=item * All handling happens through ConvertLIT as an external helper.
Native Perl code may eventually be written to handle non-DRMed
extraction.

=item * Unit tests are unwritten

=back

=head1 AUTHOR

Zed Pobre <zed@debian.org>

=head1 LICENSE AND COPYRIGHT

Copyright 2008 Zed Pobre

Licensed to the public under the terms of the GNU GPL, version 2.

ConvertLIT (not included) is copyright 2002, 2003 Dan A. Jackson, and
licensed under the terms of the GNU GPL, version 2 or later.

=cut

1;
__END__
