# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl EBook-Tools.t'

########## SETUP ##########

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 27;
use Cwd qw(chdir getcwd);
use File::Basename qw(basename);
use File::Copy;
BEGIN { use_ok('EBook::Tools',qw(system_tidy_xhtml system_tidy_xml)) };

my ($ebook1,$ebook2);
my ($meta1,$meta2,$dcmeta1,$dcmeta2);
my @elementnames;
my @elements;
my @strings;
my $exitval;
my $temp;

my @dcexpected1 = (
    "dc:Identifier",
    "dc:Identifier",
    "dc:Identifier",
    "dc:Title",
    "dc:Creator",
    "dc:Creator",
    "dc:Publisher",
    "dc:Date",
    "dc:Date",
    "dc:Date",
    "dc:Date",
    "dc:Type",
    "dc:Format",
    "dc:Language",
    "dc:Language",
    "dc:Rights"
    );

my @metastruct_expected1 = (
    "dc-metadata",
    "dc:Identifier",
    "dc:title",
    "dc:creator",
    "dc:Creator",
    "dc:creator",
    "dc:publisher",
    "dc:date",
    "dc:Date",
    "dc:date",
    "dc:Date",
    "dc:Type",
    "dc:format",
    "dc:identifier",
    "dc:identifier",
    "dc:language",
    "dc:Language",
    "dc:rights",
    "dc:identifier"
    );

my @metastruct_expected2 = (
    "dc-metadata",
    "dc:Identifier",
    "dc:Title",
    "dc:Creator",
    "dc:Creator",
    "dc:Creator",
    "dc:Publisher",
    "dc:Date",
    "dc:Date",
    "dc:Date",
    "dc:Date",
    "dc:Type",
    "dc:Format",
    "dc:Identifier",
    "dc:Identifier",
    "dc:Language",
    "dc:Language",
    "dc:Rights",
    "dc:Identifier"
    );

########## TESTS ##########

ok( (basename(getcwd()) eq 't') || chdir('t/'), "Working in 't/" ) or die;

copy('testopf-emptyuid.xml','emptyuid.opf') or die("Could not copy: $!");
copy('testopf-missingfwid.xml','missingfwid.opf') or die("Could not copy: $!");
is(system_tidy_xml('emptyuid.opf','emptyuid-tidy.opf'),0,
   'system_tidy_xml: emptyuid.opf');
is(system_tidy_xml('missingfwid.opf','missingfwid-tidy.opf'),0,
   'system_tidy_xml: missingfwid.opf');

$ebook1 = EBook::Tools->new('missingfwid.opf') or die;
is($ebook1->twigroot->att('unique-identifier'),undef,
   'missingfwid.opf really missing unique-identifier') or die;
$ebook2 = EBook::Tools->new('emptyuid.opf') or die;
is($ebook2->twigroot->att('unique-identifier'),'emptyUID',
   'new(): emptyuid.opf found') or die;

ok($ebook1->fix_oeb12,'fix_oeb12(): successful call');
ok($meta1 = $ebook1->twigroot->first_child('metadata'),'fix_oeb12(): metadata found');
ok($dcmeta1 = $meta1->first_child('dc-metadata'),'fix_oeb12(): dc-metadata found');
ok(@elements = $dcmeta1->children,'fix_oeb12(): DC elements found');
undef @elementnames;
foreach my $el (@elements)
{
    push(@elementnames,$el->gi);
}
is_deeply(\@elementnames,\@dcexpected1,'fix_oeb12(): DC elements found in expected order');


ok($ebook2->fix_oeb12_metastructure,'fix_oeb12_metastructure(): successful call');
ok($meta2 = $ebook2->twigroot->first_child('metadata'),'fix_oeb12_metastructure(): metadata found');
ok(@elements = $meta2->children,'fix_oeb12_metastructure(): metadata subelements found');
undef @elementnames;
foreach my $el (@elements)
{
    push(@elementnames,$el->gi);
}
is_deeply(\@elementnames,\@metastruct_expected1,'fix_oeb12_metastructure(): subelements found in expected order');

ok($ebook2->fix_oeb12_dcmetatags,'fix_oeb12_dcmetatags(): successful call');
ok(@elements = $meta2->children,'fix_oeb12_dcmetatags(): DC elements found');
undef @elementnames;
foreach my $el (@elements)
{
    push(@elementnames,$el->gi);
}
is_deeply(\@elementnames,\@metastruct_expected2,'fix_oeb12_dcmetatags(): DC elements found in expected order');

ok($ebook1->fix_packageid,'fix_packageid[missing]: successful call');
is($ebook1->twigroot->att('unique-identifier'),'FWID', 'fix_packageid[missing]: FWID found');
ok($ebook2->fix_packageid,'fix_packageid[blank]: successful call');
is($ebook2->twigroot->att('unique-identifier'),'UID', 'fix_packageid[blank]: UID found');

# Not a comprehensive date test.  See 10-fix_datestring.t
ok($ebook1->fix_dates,'fix_dates(): successful call');
is($ebook1->twigroot->first_descendant('dc:Date[@event="creation"]')->text,'2008-01-01',
   'fixdate(): YYYY-01-01 not clobbered');
is($ebook1->twigroot->first_descendant('dc:Date[@event="publication"]')->text,'2008-03',
   'fixdate(): MM/01/YYYY properly handled');
is($ebook1->twigroot->first_descendant('dc:Date[@event="badfebday"]')->text,'2/31/2004',
   'fixdate(): invalid day not touched');
is($ebook1->twigroot->first_descendant('dc:Date[@event="YYYY-xx-DD"]')->text,'2009-xx-01',
   'fixdate(): invalid datestring not touched');


########## CLEANUP ##########

#$ebook1->save;
#$ebook2->save;

unlink('emptyuid.opf');
unlink('missingfwid.opf');
