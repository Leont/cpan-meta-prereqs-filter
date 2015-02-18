package CPAN::Meta::Prereqs::Filter;

use strict;
use warnings;

use Exporter 5.57;
our @EXPORT = qw/filter_prereqs/;

use Carp 'croak';

my @phases = qw/configure build test runtime develop/;
my @relationships = qw/requires recommends suggests/;

my %dependents_for = (
	runtime => [ qw/build test develop/ ],
	configure => [ qw/build test/ ],
	build => [ 'test' ],
);

sub _normalize_version {
	my $raw = shift;
	if ($raw =~ /v5\.[\d.]+/) {
		require version;
		$raw = version->new($raw)->numify;
		my $pattern = $raw >= 5.010 ? '%7.6f' : '%4.3f';
		return sprintf $pattern, $raw;
	}
	elsif ($raw eq 'latest') {
		require Module::CoreList;
		return (reverse sort keys %Module::CoreList::version)[0];
	}
	return $raw >= 5.010 ? sprintf '%7.6f', $raw : $raw;
}

sub filter_prereqs {
	my ($prereqs, %args) = @_;
	return $prereqs if not grep { $_ } values %args;
	$prereqs = $prereqs->clone;
	my $core_version = defined $args{omit_core} ? _normalize_version($args{omit_core}) : undef;
	if ($core_version) {
		require Module::CoreList;
		croak "$core_version is not a known perl version" if not exists $Module::CoreList::version{$core_version};
		for my $phase (@phases) {
			for my $relation (@relationships) {
				my $req = $prereqs->requirements_for($phase, $relation);

				$req->clear_requirement('perl') if $req->accepts_module('perl', $core_version);
				for my $module ($req->required_modules) {
					next if not exists $Module::CoreList::version{$core_version}{$module};
					next if not $req->accepts_module($module, $Module::CoreList::version{$core_version}{$module});
					next if Module::CoreList->is_deprecated($module, $core_version);
					$req->clear_requirement($module);
				}
			}
		}
	}
	if ($args{sanatize}) {
		for my $parent (qw/runtime configure build/) {
			for my $child ( @{ $dependents_for{$parent} } ) {
				for my $relationship (@relationships) {
					my $source = $prereqs->requirements_for($parent, $relationship);
					my $sink = $prereqs->requirements_for($child, $relationship);
					for my $module ($source->required_modules) {
						next if not defined(my $right = $sink->requirements_for_module($module));
						my $left = $source->requirements_for_module($module);
						$sink->clear_requirement($module) if $left eq $right || $right eq '0';
					}
				}
			}
		}
	}
	if ($args{only_missing}) {
		require Module::Metadata;
		for my $phase (@phases) {
			for my $relation (@relationships) {
				my $req = $prereqs->requirements_for($phase, $relation);
				$req->clear_requirement('perl') if $req->accepts_module('perl', $]);
				for my $module ($req->required_modules) {
					if ($req->requirements_for_module($module)) {
						my $metadata = Module::Metadata->new_from_module($module);
						if ($metadata && $req->accepts_module($module, $metadata->version($module) || 0)) {
							$req->clear_requirement($module);
						}
					}
					else {
						$req->clear_requirement($module) if Module::Metadata->find_module_by_name($module);
					}
				}
			}
		}
	}
	return $prereqs;
}

1;

# ABSTRACT: Filtering various things out of CPAN::Meta::Prereqs
