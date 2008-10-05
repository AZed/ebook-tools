# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl EBook-Tools.t'

########## SETUP ##########

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 45;
use Cwd qw(chdir getcwd);
use Data::Dumper;
use File::Basename qw(basename);
use File::Copy;
BEGIN { use_ok('EBook::Tools',qw(system_tidy_xhtml system_tidy_xml)) };

# Set this to 1 or 2 to stress the debugging code, but expect lots of
# output.
$EBook::Tools::debug = 0;

my ($ebook1,$ebook2,$blank);
my @manifest;
my @manifest_hrefs_expected = (
    'part1.html',
    'missingfile.html',
    'cover.jpg'
    );
my @spine_idrefs_expected = (
    'item-text',
    'file-missing'
    );
my %hashtest;


########## TESTS ##########

ok( (basename(getcwd()) eq 't') || chdir('t/'), "Working in 't/" ) or die;

# new()
$ebook1 = EBook::Tools->new() or die;
isa_ok($ebook1,'EBook::Tools', 'EBook::Tools->new()');
is($ebook1->opffile,undef, 'new() has undefined opffile');

# Generate fresh input samples
copy('testopf-emptyuid.xml','emptyuid.opf') or die("Could not copy: $!");
copy('testopf-missingfwid.xml','missingfwid.opf') or die("Could not copy: $!");

is(system_tidy_xml('emptyuid.opf','emptyuid-tidy.opf'),0,
   'system_tidy_xml: emptyuid.opf');
is(system_tidy_xml('missingfwid.opf','missingfwid-tidy.opf'),0,
   'system_tidy_xml: missingfwid.opf');

# new($filename)
$ebook2 = EBook::Tools->new('emptyuid.opf') or die;
is($ebook2->twigroot->att('unique-identifier'),'emptyUID',
   'new(): emptyuid.opf found');

# init($filename)
$ebook1->init('missingfwid.opf') or die;
is($ebook1->twigroot->tag,'package', 'init(): missingfwid.opf found');
is($ebook1->twigroot->att('unique-identifier'),undef,
   'missingfwid.opf really missing unique-identifier');
is($ebook1->opffile,'missingfwid.opf',
   'opffile() found correct value after init()');

# init_blank($filename)
$blank = EBook::Tools->new() or die;
ok($blank->init_blank('test-blank.opf'),'init_blank() returned successfully');
is(ref $blank->twig,'XML::Twig::XPath',
   'init_blank() created a XML::Twig::XPath');
is(ref $blank->twigroot,'XML::Twig::XPath::Elt',
   'init_blank() created a XML::Twig::XPath::Elt root');
is($blank->twigroot
   ->first_child('metadata')
   ->first_child('dc:identifier')
   ->att('scheme'),'UUID',
   'init_blank() has a structure with a UUID');

# spec() and set_spec()
is($ebook1->spec,undef,'spec() undefined after init');
ok($ebook1->set_spec('OPF99'), "set_spec('OPF99')");
is($ebook1->spec,'OPF99','spec() correctly set to invalid OPF99');
ok($ebook1->set_spec('OEB12'), "set_spec('OEB12')");
is($ebook1->spec,'OEB12', "spec() correctly set to OEB12");
ok($ebook1->set_spec('OPF20'), "set_spec('OPF20')");
is($ebook1->spec,'OPF20', "spec() correctly set to OPF20");

# twig(), twigroot()
is(ref($ebook1->twig),'XML::Twig::XPath', "twig() finds 'XML::Twig::XPath'");
is(ref($ebook1->twigroot),'XML::Twig::XPath::Elt',
   "twigroot() finds 'XML::Twig::XPath::Elt'");

# identifier()
$ebook1->fix_opf20() or die;
$ebook1->fix_packageid() or die;
is($ebook1->identifier,'this-is-not-a-fwid',
   "identifier() finds expected value");

# manifest()
is(scalar(@manifest = $ebook1->manifest),3,
   'manifest() finds the correct number of entries');
is(ref($manifest[0]),'HASH','manifest() returns array of hashrefs');
%hashtest = %{$manifest[0]};
is($hashtest{id},'item-text','manifest() hashref seems correct');

# manifest(mtype => ...)
is(scalar(@manifest = $ebook1->manifest(mtype => 'image/jpeg')),
   1,'manifest(mtype => ...) finds the correct number of entries');
%hashtest = %{$manifest[0]};
is($hashtest{id},'coverimage',
   'manifest(mtype => ...) finds the correct entry');

# manifest(mtype,href,logic)
is(scalar(@manifest = $ebook1->manifest(mtype => 'image/jpeg',
                                        href => 'part1.html',
                                        logic => 'or')),
          2,
          'manifest(mtype,href,logic) finds the correct number of entries');
%hashtest = %{$manifest[0]};
is($hashtest{id},'item-text',
   'manifest(mtype,href,logic) finds the correct entries');

# manifest_hrefs()
ok(@manifest = $ebook1->manifest_hrefs,
   'manifest_hrefs() returns successfully');
is_deeply(\@manifest,\@manifest_hrefs_expected,
    'manifest_hrefs() returns expected values');

# primary_author()
is($ebook2->primary_author(),'Zed 1 Pobre',
   'primary_author() finds correct entry');

# print_*
ok($blank->print_errors,'print_errors() returns successfully');
ok($blank->print_warnings,'print_warnings() returns successfully');
ok($blank->print_opf,'print_opf() returns successfully');

# search_*
is($ebook2->search_knownuids(),'UID','search_knownuids() finds UID');
is($ebook1->search_knownuidschemes(),'FWID','search_knownuidschemes() finds FWID');

# spine(), spine_idrefs()
is(scalar(@manifest = $ebook2->spine),2,
   'spine() finds the correct number of entries');
is(ref($manifest[0]),'HASH','spine() returns array of hashrefs');
%hashtest = %{$manifest[0]};
is($hashtest{href},'part1.html','spine() hashref seems correct');
is(scalar(@manifest = $ebook2->spine_idrefs),2,
   'spine_idrefs() finds the correct number of entries');
is_deeply(\@manifest,\@spine_idrefs_expected,
          'spine_idrefs() returns expected values');
is($ebook2->title,'A Noncompliant OPF Test Sample',
   'title() returns the correct value');


########## CLEANUP ##########

#$ebook1->save;
#$ebook2->save;

unlink('emptyuid.opf');
unlink('missingfwid.opf');
