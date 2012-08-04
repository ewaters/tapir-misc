package Tapir::Server;

=head1 NAME

Tapir::Server - An API server

=head1 DESCRIPTION

Mainly subclassed, this offers a base class for any implementation of the API.

=cut

sub is_valid_request {
	my ($self, %opt) = @_;

	return { };
}

1;
