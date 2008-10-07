use Module::Build;
my $build = Module::Build->new
    (
     module_name => 'EBook::Tools',
     license  => 'gpl2',
     requires => {
         'perl'          => '5.8.0',
         'Archive::Zip'  => 1.16,
         'Class::Meta'   => 0.53,
	 'Class::Meta::Express' => 0.10,
	 'Date::Manip'   => 5.44,,
	 'Time::Local'   => 1.18,
	 'XML::Twig'     => 3.32,
     },
    );
$build->create_build_script;
