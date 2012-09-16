package Dancer::Plugin::Tapir;

use Dancer ':syntax';
use Dancer::Plugin;
use Carp;
use Data::Dumper;
use Try::Tiny;

use Thrift::IDL;
use Thrift::Parser;
use Tapir::Validator;
use Tapir::MethodCall;

our $VERSION = 0.01;

register setup_thrift_handler => sub {
	my ($self, @args) = plugin_args(@_);
	# $self is undef for Dancer 1
	my $conf = plugin_setting();

	## Validate the plugin settings

	if (my @missing_args = grep { ! defined $conf->{$_} } qw(thrift_idl handler_class)) {
		croak "Missing configuration settings for Tapir plugin: " . join('; ', @missing_args);
	}
	if (! -f $conf->{thrift_idl}) {
		croak "Invalid thrift_idl file '$conf->{thrift_idl}'";
	}
	
	## Audit the IDL

	my $idl = Thrift::IDL->parse_thrift_file($conf->{thrift_idl});

	my $validator = Tapir::Validator->new(
		audit_types => 1,
		docs => {
			# Require all methods be documented
			require => {
				methods => 1,
				rest    => 1,
			},
		},
	);
	
	if (my @errors = $validator->audit_idl_document($idl)) {
		croak "Invalid thrift_idl file '$conf->{thrift_idl}'; the following errors were found:\n"
			. join("\n", map { " - $_" } @errors);
	}

	my %services = map { $_->name => $_ } @{ $idl->services };

	## Use the handler class and test for completeness

	my $handler_class = $conf->{handler_class};
	eval "require $handler_class";
	if ($@) {
		croak "Failed to load $handler_class: $@";
	}
	if (! $handler_class->isa('Tapir::Server::Handler::Class')) {
		croak "$handler_class must be a subclass of Tapir::Server::Handler::Class";
	}

	if (! $handler_class->service) {
		croak "$handler_class didn't call service()";
	}
	my $service = $services{ $handler_class->service };
	if (! $service) {
		croak "$handler_class is for the service ".$handler_class->service.", which is not registered with $conf->{thrift_idl}";
	}

	my %methods = map { $_->name => $_ } @{ $service->methods };
	my %handled_methods = %{ $handler_class->methods };
	foreach my $method_name (keys %methods) {
		if (! $handled_methods{$method_name}) {
			croak "$handler_class doesn't handle method $methods{$method_name}";
		}
	}

	## Setup custom namespaced Thrift classes
	
	my $parser = Thrift::Parser->new(idl => $idl, service => $service->name);

	## Setup routes

	while (my ($method_name, $method_idl) = each %methods) {
		my ($http_method, $dancer_route) = @{ $method_idl->{doc}{rest} }{'method', 'route'};
		my $dancer_method = 'Dancer::' . $http_method;

		my $method_message_class = $parser->{methods}{$method_name}{class};

		my $dancer_sub = sub {
			my $params = request->params;

			my $thrift_message;
			try {
				$thrift_message = $method_message_class->compose_message_call(%$params);
			}
			catch {
				die "Error in composing $method_message_class message: $_\n";
			};

			$validator->validate_parser_message($thrift_message);

			my $call = Tapir::MethodCall->new(
				message => $thrift_message,
			);

			my %args = $call->args('plain');
			return Dumper(\%args);

		};
		
		# Install the route
		{
			no strict 'refs';
			$dancer_method->($dancer_route => $dancer_sub);
		}
	}

};

register_plugin;
true;
