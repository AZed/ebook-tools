use 5.010000;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'EBook::Tools',
    VERSION_FROM      => 'EBook/Tools.pm', # finds $VERSION
    PREREQ_PM         => {
	Archive::Zip => 1.16,
	Class::Meta => 0.53,
	Class::Meta::Express,
	Date::Manip,
	File::Basename,
	File::Copy,
	File::MimeInfo::Magic,
	Time::Local,
	XML::Twig,
    },
    EXE_FILES => [ qw(
	epubgen.pl
	metasplit.pl
	opffix.pl
	tidyxhtml.pl
	tidyxml.pl)
	],
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'EBook/Tools.pm', # retrieve abstract from module
       AUTHOR         => 'Zed Pobre <zed@debian.org>') : ()),
);
