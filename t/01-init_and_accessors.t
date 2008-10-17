use warnings; use strict;
use utf8;
binmode(STDOUT,':utf8');
binmode(STDERR,':utf8');

########## SETUP ##########

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 58;
binmode(Test::More->builder->failure_output,':utf8');
use Cwd qw(chdir getcwd);
use Data::Dumper;
use File::Basename qw(basename);
use File::Copy;
BEGIN { use_ok('EBook::Tools',qw(system_tidy_xhtml system_tidy_xml)) };

# Set this to 1 or 2 to stress the debugging code, but expect lots of
# output.
$EBook::Tools::debug = 0;

my ($ebook1,$ebook2,$blank);
my $meta;
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
my @rights;


########## TESTS ##########

ok( (basename(getcwd()) eq 't') || chdir('t/'), "Working in 't/" ) or die;

# new()
$ebook1 = EBook::Tools->new() or die;
isa_ok($ebook1,'EBook::Tools', 'EBook::Tools->new()');
is($ebook1->opffile,undef, 'new() has undefined opffile');

# Generate fresh input samples
copy('testopf-emptyuid.xml','emptyuid.opf') or die("Could not copy: $!");
copy('testopf-missingfwid.xml','missingfwid.opf') or die("Could not copy: $!");

# new($filename)
$ebook2 = EBook::Tools->new('emptyuid.opf') or die;
is($ebook2->twigroot->att('unique-identifier'),'emptyUID',
   'new(): emptyuid.opf parsed');
@rights = $ebook2->rights;
is($rights[0],"Copyright \x{00A9} 2008 by Zed Pobre",
   'emptyuid.opf HTML entity handled properly by new()');

# save() and init($filename) 
ok($ebook2->save,'emptyuid.opf saved');
ok($ebook1->init('emptyuid.opf'),'emptyuid.opf saved output re-parsed');
@rights = $ebook1->rights;
is($rights[0],"Copyright \x{00A9} 2008 by Zed Pobre",
   'emptyuid.opf HTML entity handled properly after save()');

$ebook1->init('missingfwid.opf') or die;
is($ebook1->twigroot->tag,'package', 'init(): missingfwid.opf found');
is($ebook1->twigroot->att('unique-identifier'),undef,
   'missingfwid.opf really missing unique-identifier');
is($ebook1->opffile,'missingfwid.opf',
   'opffile() found correct value after init()');

# init_blank()
$blank = EBook::Tools->new() or die;
ok(!eval { $blank->init_blank() },'init_blank() fails with no argument');

# init_blank(opffile => $filename)
ok($blank->init_blank(opffile => 'test-blank.opf'),
   'init_blank(opffile => $filename) returned successfully');
is(ref $blank->twig,'XML::Twig',
   'init_blank(opffile => $filename) created a XML::Twig');
is(ref $blank->twigroot,'XML::Twig::Elt',
   'init_blank(opffile => $filename) created a XML::Twig::Elt root');
is($blank->twigroot->att('unique-identifier'),'UUID',
   'init_blank(opffile => $filename) correctly set unique-identifier');
$meta = $blank->twigroot->first_child('metadata') or die;
is($meta
   ->first_child('dc:identifier')
   ->att('opf:scheme'),'UUID',
   'init_blank(opffile => $filename) has a structure with a UUID');
is($meta->first_child('dc:title')->text,'Unknown Title',
   'init_blank(opffile => $filename) generates the default title');
is($meta->first_child('dc:creator')->text,'Unknown Author',
   'init_blank(opffile => $filename) generates the default creator');
is($meta->first_child('dc:creator')->att('opf:role'),'aut',
   'init_blank(opffile => $filename) creator has role "aut"');

# init_blank(all args)
ok($blank->init_blank(opffile => 'test-blank.opf',
                      author => 'New Author',
                      title => 'New Title'),
   'init_blank(all args) returned successfully');
is($blank->twigroot->att('unique-identifier'),'UUID',
   'init_blank(all args) correctly set unique-identifier');
$meta = $blank->twigroot->first_child('metadata') or die;
is($meta
   ->first_child('dc:identifier')
   ->att('opf:scheme'),'UUID',
   'init_blank(all args) has a structure with a UUID');
is($meta->first_child('dc:title')->text,'New Title',
   'init_blank(all args) generates the assigned title');
is($meta->first_child('dc:creator')->text,'New Author',
   'init_blank(all args) generates the assigned creator');
is($meta->first_child('dc:creator')->att('opf:role'),'aut',
   'init_blank(all args) creator has role "aut"');

# spec() and set_spec()
is($ebook1->spec,undef,'spec() undefined after init');
ok($ebook1->set_spec('OPF99'), "set_spec('OPF99')");
is($ebook1->spec,'OPF99','spec() correctly set to invalid OPF99');
ok($ebook1->set_spec('OEB12'), "set_spec('OEB12')");
is($ebook1->spec,'OEB12', "spec() correctly set to OEB12");
ok($ebook1->set_spec('OPF20'), "set_spec('OPF20')");
is($ebook1->spec,'OPF20', "spec() correctly set to OPF20");

# twig(), twigroot()
is(ref($ebook1->twig),'XML::Twig', "twig() finds 'XML::Twig'");
is(ref($ebook1->twigroot),'XML::Twig::Elt',
   "twigroot() finds 'XML::Twig::Elt'");

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
