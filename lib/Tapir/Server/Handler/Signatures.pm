package Tapir::Server::Handler::Signatures;

use strict;
use warnings;
use base qw(Devel::Declare::MethodInstaller::Simple Exporter);
use Carp;

our @EXPORT = qw(set_service);

sub import {
	my $class = shift;
	$class->install_methodhandler(
		name => 'method',
		into => caller,
	);
	$class->export_to_level(1, @_);
}

sub parse_proto {
	my $self = shift;
	my ($proto) = @_;
	$proto ||= '';

	my $inject = "my \$call = shift;";

	foreach my $part (split /\s* , \s*/x, $proto) {
		# scalar '$var'
		if ($part =~ m{\$(\S+)}) {
			$inject .= "my $part = \$call->arguments->field_named('$1')->value_plain();";
		}
		else {
			croak "Unrecognized handler signature '$proto' (failed at '$part')";
		}
	}

	return $inject;
}

sub set_service ($) {
	my $class = caller;
	$class->service(@_);
}

1;
