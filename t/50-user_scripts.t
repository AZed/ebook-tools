# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl EBook-Tools.t'

########## SETUP ##########

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 9;
use Cwd qw(chdir getcwd);
use File::Basename qw(basename);
use File::Copy;
use utf8;
binmode STDOUT,":utf8";
binmode STDERR,":utf8";


BEGIN { use_ok('EBook::Tools') };

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

my $ebook;
my @rights;

########## TESTS ##########

$exitval = system('perl','-I../lib','../ebook.pl','fix','emptyuid.opf');
$exitval >>= 8;
is($exitval,0,'ebook fix exits successfully');

unlink('containsmetadata.opf');
$exitval = system('perl','-I../lib',
                  '../ebook.pl','metasplit','containsmetadata.html');
$exitval >>= 8;
is($exitval,0,'ebook metasplit generates right return value');
ok(-f 'containsmetadata.opf','ebook metasplit created containsmetadata.opf');

ok($ebook = EBook::Tools->new('containsmetadata.opf'),
   'split metadata parsed successfully');
is($ebook->title,'A Noncompliant OPF Test Sample',
   'split metadata has correct title');
is(@rights = $ebook->rights,1,'split metadata contains dc:rights');
is(@rights[0],"Copyright \x{00A9} 2008 by Zed Pobre",
   'split metadata has correct rights (HTML entity handled)');

########## CLEANUP ##########

unlink('containsmetadata.html');
unlink('containsmetadata.opf');
unlink('emptyuid.opf');
unlink('missingfwid.opf');
unlink('part1.html');
unlink('part2.html');
