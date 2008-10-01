# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl EBook-Tools.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 13;
use File::Copy;
# Add blib/scripts to the path to find the executables
use Cwd qw(chdir getcwd);
$ENV{'PATH'} .= ":" . getcwd() . "/blib/script";
BEGIN { use_ok('EBook::Tools',qw(system_tidy_xhtml system_tidy_xml)) };

my ($ebook1,$ebook2);
my ($meta1,$meta2);
my @elements;
my @strings;
my $temp;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

ok(chdir('t/'),"Working in 't/");

$ebook1 = EBook::Tools->new();
is(ref $ebook1,'EBook::Tools', 'new() produces an EBook::Tools object');
is($ebook1->opffile,undef, 'new() has undefined opffile');
copy('testopf-emptyuid.xml','emptyuid.opf') or die("Could not copy: $!");
copy('testopf-missingfwid.xml','missingfwid.opf') or die("Could not copy: $!");
is(system_tidy_xml('emptyuid.opf','emptyuid-tidy.opf'),0,
   'system_tidy_xml: emptyuid.opf');
is(system_tidy_xml('missingfwid.opf','missingfwid-tidy.opf'),0,
   'system_tidy_xml: missingfwid.opf');
$ebook2 = EBook::Tools->new('emptyuid.opf');
is($ebook2->twigroot->att('unique-identifier'),'emptyUID', 'new(): emptyuid.opf found');


$ebook1->init('missingfwid.opf');
is($ebook1->twigroot->tag,'package', 'init(): missingfwid.opf found');
is($ebook1->twigroot->att('unique-identifier'),undef, 'missingfwid.opf really missing unique-identifier');

$ebook1->fix_oeb12;
$ebook2->fix_oeb12;

$meta1 = $ebook1->twigroot->first_child('metadata');
$meta2 = $ebook2->twigroot->first_child('metadata');

@elements = $meta1->descendants('dc:Identifier');
is(scalar(@elements),3,'fix_oeb12(): dc:Identifier corrected');
@elements = $meta1->descendants('dc:Title');
is(scalar(@elements),1,'fix_oeb12(): dc:Title corrected');

$ebook1->fix_packageid;
is($ebook1->twigroot->att('unique-identifier'),'FWID', 'fix_packageid[missing]: FWID found');
$ebook2->fix_packageid;
is($ebook2->twigroot->att('unique-identifier'),'GUID', 'fix_packageid[blank]: GUID found');


unlink('emptyuid.opf');
unlink('missingfwid.opf');
#print "DEBUG: ",$ENV{'PATH'},"\n";
# Replace with Test::Critic
#ok(system('perl','-I../blib',`which opffix.pl`,'emptyuid.opf'));
