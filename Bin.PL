use warnings; use strict;
use File::Copy;
use File::Path;

mkpath 'bin' or die("Could not create bin/");
copy('ebook.pl','bin/ebook') or die("Could not create bin/ebook");
chmod(0755,'bin/ebook');
