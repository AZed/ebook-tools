use strict; use warnings;
use Cwd qw(chdir getcwd);
use File::Basename qw(basename);
use File::Copy;
use Test::More tests => 5;
BEGIN { use_ok('EBook::Tools',
               qw(print_memory system_tidy_xhtml system_tidy_xml)) };

########## TESTS BEGIN ##########

ok( (basename(getcwd()) eq 't') || chdir('t/'), "Working in 't/" ) or die;

# Generate fresh input samples
copy('testopf-emptyuid.xml','emptyuid.opf') or die("Could not copy: $!");
copy('testopf-missingfwid.xml','missingfwid.opf') or die("Could not copy: $!");

is(system_tidy_xml('emptyuid.opf','emptyuid-tidy.opf'),0,
   'system_tidy_xml: emptyuid.opf');
is(system_tidy_xml('missingfwid.opf','missingfwid-tidy.opf'),0,
   'system_tidy_xml: missingfwid.opf');

SKIP: 
{
    skip('No /proc/PID/statm',1) unless(-f "/proc/$$/statm");
    ok(print_memory('15-misc_procedures.t'),'print_memory returns sucessfully');
}

########## CLEANUP ##########

unlink('emptyuid.opf');
unlink('missingfwid.opf');
