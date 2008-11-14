use strict; use warnings;
use Cwd qw(chdir getcwd);
use File::Basename qw(basename);
use File::Copy;
use Test::More tests => 10;
BEGIN { use_ok('EBook::Tools',qw(:all)); };

my $result;
my $longline = 'We think ourselves possessed, or, at least, we boast that we are so, of liberty of conscience on all subjects, and of the right of free inquiry and private judgment in all cases, and yet how far are we from these exalted privileges in fact! -- John Adams';
my $hexable = "\x{d0}\x{be}\x{d0}\x{be}\x{da}";

########## TESTS BEGIN ##########

ok( (basename(getcwd()) eq 't') || chdir('t/'), "Working in 't/" ) or die;

ok(find_in_path('perl'),'find_in_path() finds perl');
is(excerpt_line($longline),
   'We think ourselves possessed,  [...] vileges in fact! -- John Adams',
   'excerpt_line() excerpts correctly');

# Generate fresh input samples, test finding them
copy('testopf-emptyuid.xml','emptyuid.opf') or die("Could not copy: $!");
is(find_opffile(),'emptyuid.opf',
   'find_opffile() finds a single OPF');
copy('testopf-missingfwid.xml','missingfwid.opf') or die("Could not copy: $!");
is(find_opffile(),undef,
   'find_opffile() returns undef with multiple OPF files');

is(hexstring($hexable),'d0bed0beda',
   'hexstring() returns correct string');

# Tidy may not be available to test
SKIP:
{
    skip('Tidy not available',2) unless(-x '/usr/bin/tidy');
    is(system_tidy_xml('emptyuid.opf','emptyuid-tidy.opf'),0,
       'system_tidy_xml: emptyuid.opf');
    is(system_tidy_xml('missingfwid.opf','missingfwid-tidy.opf'),0,
       'system_tidy_xml: missingfwid.opf');
}

SKIP: 
{
    skip('No /proc/PID/statm',1) unless(-f "/proc/$$/statm");
    ok(print_memory('15-misc_procedures.t'),'print_memory returns sucessfully');
}

########## CLEANUP ##########

unlink('emptyuid.opf');
unlink('missingfwid.opf');
