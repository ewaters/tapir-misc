package Tapir::Server::Handler;

use strict;
use warnings;
use base 'Class::Accessor::Grouped';

__PACKAGE__->mk_group_accessors(inherited => qw(service methods));

sub add_method {
	my ($class, $method) = @_;
	if (my $methods = $class->methods) {
		push @$methods, $method;
	}
	else {
		$class->methods([ $method ]);
	}
}

1;
