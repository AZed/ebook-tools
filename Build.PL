use Module::Build;
my $build = Module::Build->new
    (
     module_name => 'EBook::Tools',
     license  => 'gpl2',
     requires => {
         'perl'              => '5.10.0',
         'Archive::Zip'      => 1.16,
         'Data::UUID'        => 1,
	 'Date::Manip'       => 5.44,
	 'File::MimeInfo'    => 0.13,
	 'HTML::TreeBuilder' => 3.19,
	 'Image::Size'       => 3.1,
	 'List::MoreUtils'   => 0.21,
	 'Palm::Doc'         => 1.19,
	 'Palm::PDB'         => '1.3.0',
	 'Tie::IxHash'       => 1.21,
	 'Time::Local'       => 1.18,
	 'XML::Twig'         => 3.32,
     },
     PL_files => { 'Bin.PL' => 'bin/ebook' },
     create_makefile_pl => 'small',
    );
$build->create_build_script;
