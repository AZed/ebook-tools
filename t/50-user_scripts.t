# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl EBook-Tools.t'

########## SETUP ##########

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 4;
use Cwd qw(chdir getcwd);
use File::Basename qw(basename);
use File::Copy;

ok( (basename(getcwd()) eq 't') || chdir('t/'), "Working in 't/" ) or die;

copy('test-containsmetadata.html','containsmetadata.html')
    or die("Could not copy containsmetadata.html: $!");
copy('test-part1.html','part1.html')
    or die("Could not copy part1.html: $!");
copy('test-part2.html','part2.html')
    or die("Could not copy part2.html: $!");
copy('testopf-emptyuid.xml','emptyuid.opf')
    or die("Could not copy emptyuid.opf: $!");
copy('testopf-missingfwid.xml','missingfwid.opf')
    or die("Could not copy missingfwid.opf: $!");


########## TESTS ##########

$exitval = system('perl','-I../lib','../ebook.pl','fix','emptyuid.opf');
$exitval >>= 8;
is($exitval,0,'ebook fix exits successfully');

unlink('containsmetadata.opf');
$exitval = system('perl','-I../lib',
                  '../ebook.pl','metasplit','containsmetadata.html');
$exitval >>= 8;
is($exitval,0,'metasplit.pl generates right return value');
ok(-f 'containsmetadata.opf','metasplit.pl created containsmetadata.opf');


########## CLEANUP ##########

unlink('containsmetadata.html');
unlink('containsmetadata.opf');
unlink('emptyuid.opf');
unlink('missingfwid.opf');
unlink('part1.html');
unlink('part2.html');
