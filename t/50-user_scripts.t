# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl EBook-Tools.t'

########## SETUP ##########

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 2;
use Cwd qw(chdir);
use File::Copy;

ok(chdir('t/'),"Working in 't/");

copy('testopf-emptyuid.xml','emptyuid.opf') or die("Could not copy: $!");
copy('testopf-missingfwid.xml','missingfwid.opf') or die("Could not copy: $!");

$exitval = system('perl','-I..','../opffix.pl','emptyuid.opf');
$exitval >>= 8;
is($exitval,3,'opffix.pl generates right return value');

#unlink('emptyuid.opf');
#unlink('missingfwid.opf');
