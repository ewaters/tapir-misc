package Tapir::Server::Handler;

use strict;
use warnings;
use base 'Class::Accessor::Grouped';

__PACKAGE__->mk_group_accessors(inherited => qw(service methods));

sub add_method {
	my ($class, $method, $modifier) = @_;
	$modifier ||= 'normal';
	if (my $methods = $class->methods) {
		$methods->{$method} = $modifier;
	}
	else {
		$class->methods({ $method => $modifier });
	}
}

1;
