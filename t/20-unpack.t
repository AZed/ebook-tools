use strict; use warnings; use utf8;
use 5.010; # Needed for smart-match operator
use Cwd qw(chdir getcwd);
use EBook::Tools;
use File::Basename qw(basename);
use File::Copy;
use File::Path;    # Exports 'mkpath' and 'rmtree'
use Test::More tests => 23;
BEGIN { use_ok('EBook::Tools::Unpack') };

my $cwd;
my $ebook = EBook::Tools->new();
my $unpacker;
my @list;

my $mobitest_description =
    '<P>Description line 1 — <EM>emphasized</EM> </P> <P>Description line 2 — <STRONG>a bold move </STRONG></P>';

########## TESTS BEGIN ##########

ok( (basename(getcwd()) eq 't') || chdir('t/'), "Working in 't/" ) or die;
$cwd = getcwd();

ok($unpacker = EBook::Tools::Unpack->new(
       'file' => 'mobi/mobitest.prc'),
   'new(file) returns successfully');
ok($unpacker->unpack,'unpack() returns successfully');
chdir($cwd);
ok(-d 'mobitest','unpack() created mobitest/');
ok(-f 'mobitest/mobitest.opf','unpack() created mobitest/mobitest.opf');
ok(-f 'mobitest/mobitest.html','unpack() created mobitest/mobitest.html');

ok($ebook->init('mobitest/mobitest.opf'),'mobitest.opf parses');
is($ebook->title,'A Noncompliant OPF Test Sample',
   'mobitest.opf title is correct');
is($ebook->primary_author,'Zed 1 Pobre',
   'mobitest.opf author is correct');
@list = $ebook->contributor_list;
is_deeply(\@list, ['Me Myself'],
          'mobitest.opf has correct contributors');
@list = $ebook->isbn_list;
is_deeply(\@list, ['0-9999-XXXX-1'],
          'mobitest.opf has correct ISBNs');
@list = $ebook->subject_list;
is_deeply(\@list, ['Computing, Internet','Secondary subject','Education'],
   'mobitest.opf has correct subjects');
is($ebook->description,$mobitest_description,
   'mobitest.opf has correct description');
@list = $ebook->publishers;
is_deeply(\@list, ['CPAN'],
          'mobitest.opf has correct publishers');
is($ebook->date_list(event => 'publication'),'2008-10',
   'mobitest.opf has correct publication date');
is($ebook->languages,'en',
   'mobitest.opf has correct language');
is($ebook->element_list(cond => 'DictionaryInLanguage'),'de-at',
   'mobitest.opf has correct DictionaryInLanguage');
is($ebook->element_list(cond => 'DictionaryOutLanguage'),'es-ar',
   'mobitest.opf has correct DictionaryOutLanguage');
is($ebook->adult,'yes',
   'mobitest.opf is flagged adult');
@list = $ebook->retailprice;
is_deeply(\@list, ['1.23','USD'],
          'mobitest.opf has correct SRP');
@list = $ebook->manifest_hrefs;
is_deeply(\@list, ['mobitest.html'],
          'mobitest.opf has correct manifest');
@list = $ebook->spine_idrefs;
is_deeply(\@list, ['text-main'],
          'mobitest.opf has correct spine');

########## CLEANUP ##########

#rmtree('mobitest');
