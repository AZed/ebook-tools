use strict; use warnings; use utf8;
use Cwd qw(chdir getcwd);
use Digest::MD5 qw(md5);
use File::Basename qw(basename);
use File::Path;    # Exports 'mkpath' and 'rmtree'
use Test::More tests => 38;
BEGIN { use_ok('EBook::Tools::IMP') };

my $cwd;
my $imp = EBook::Tools::IMP->new();
my $filename;
my $fh_res;
my $fh_res_eti;
my $md5 = Digest::MD5->new();
my $md5eti = Digest::MD5->new();
my @list;

########## TESTS BEGIN ##########

ok( (basename(getcwd()) eq 't') || chdir('t/'), "Working in 't/" ) or die;
$cwd = getcwd();

ok($imp->load('imp/REBTestDocument.imp'),
   "load('imp/REBTestDocument.imp') returns succesfully");
ok($imp->write_resdir,
   "write_resdir() returns successfully");
ok(-d 'REBtestdoc.RES',
   'write_resdir() creates the correct directory');

while(<imp/REBtestdoc-ETI.RES/*>)
{
    open($fh_res_eti,'<:raw',$_)
        or die("Unable to open '",$_,"' for reading! [@!]\n");
    $md5eti->addfile($fh_res_eti);
    close($fh_res_eti);

    $filename = 'REBtestdoc.RES/' . basename($_);
    open($fh_res,'<:raw',$filename)
        or die("Unable to open '",$filename,"' for reading! [@!]\n");
    $md5->addfile($fh_res);
    close($fh_res);

    ok($md5->digest eq $md5eti->digest,
       "write_resdir correctly unpacks '$filename'");
}

########## CLEANUP ##########

rmtree('REBtestdoc.RES');
