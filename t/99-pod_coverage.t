use Test::More;
eval "use Test::Pod::Coverage 1.00";
plan skip_all => "Test::Pod::Coverage 1.00 required for testing POD coverage"
    if $@;
plan tests => 1;
pod_coverage_ok('EBook::Tools','EBook::Tools POD coverage');
# all_pod_coverage doesn't work?
#all_pod_coverage_ok();
#print "DEBUG: looking for modules\n";
#foreach my $module (all_modules('blib'))
#{
#    print "DEBUG: testing $module\n";
#    pod_coverage_ok($module,$module);
#}
