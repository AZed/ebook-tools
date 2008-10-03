# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl EBook-Tools.t'

########## SETUP ##########

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 4;
use Cwd qw(chdir);
use File::Copy;

ok(chdir('t/'),"Working in 't/");

copy('testopf-emptyuid.xml','emptyuid.opf') or die("Could not copy: $!");
copy('testopf-missingfwid.xml','missingfwid.opf') or die("Could not copy: $!");

$exitval = system('perl','-I..','../opffix.pl','emptyuid.opf');
$exitval >>= 8;
is($exitval,5,'opffix.pl generates right return value');

unlink('emptyuid.opf');
unlink('missingfwid.opf');


copy('test-containsmetadata.html','containsmetadata.html')
    or die("Could not copy: $!");
unlink('containsmetadata.opf');
$exitval = system('perl','-I..','../metasplit.pl','containsmetadata.html');
$exitval >>= 8;
is($exitval,0,'metasplit.pl generates right return value');
ok(-f 'containsmetadata.opf','metasplit.pl created containsmetadata.opf');

unlink('containsmetadata.html');
unlink('containsmetadata.opf');
