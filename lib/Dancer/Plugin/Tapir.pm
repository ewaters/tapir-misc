package Dancer::Plugin::Tapir;

use Dancer ':syntax';
use Dancer::Plugin;
use Carp;
use Data::Dumper;
use Try::Tiny;
use IO::Capture::Stdout;

# POE sessions will be created by Tapir::MethodCall; let's not see an error about POE never running
use POE;
POE::Kernel->run();

use Thrift::IDL;
use Thrift::Parser;
use Tapir::Validator;
use Tapir::MethodCall;

our $VERSION = 0.01;

register setup_thrift_handler => sub {
	my ($self, @args) = plugin_args(@_);
	# $self is undef for Dancer 1
	my $conf = plugin_setting();
	my %conf = ( %$conf, @args );

	## Validate the plugin settings

	if (my @missing_args = grep { ! defined $conf{$_} } qw(thrift_idl handler_class)) {
		croak "Missing configuration settings for Tapir plugin: " . join('; ', @missing_args);
	}
	if (! -f $conf{thrift_idl}) {
		croak "Invalid thrift_idl file '$conf{thrift_idl}'";
	}
	
	## Audit the IDL

	my $idl = Thrift::IDL->parse_thrift_file($conf{thrift_idl});

	# Conduct an audit of the thrift document to ensure that all the methods are
	# documented, have a @rest declaration, and all custom types are defined before
	# being used.  Further, this will fill in the $object->{doc} hash for each
	# Thrfit::IDL object, which is necessary for validate_parser_message as well as
	# extracting the @rest values later.

	my $validator = Tapir::Validator->new(
		audit_types => 1,
		docs => {
			require => {
				methods => 1,
				rest    => 1,
			},
		},
	);
	if (my @errors = $validator->audit_idl_document($idl)) {
		croak "Invalid thrift_idl file '$conf{thrift_idl}'; the following errors were found:\n"
			. join("\n", map { " - $_" } @errors);
	}

	my %services = map { $_->name => $_ } @{ $idl->services };

	## Use the handler class and test for completeness

	my $handler_class = $conf{handler_class};
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
		croak "$handler_class is for the service ".$handler_class->service.", which is not registered with $conf{thrift_idl}";
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
	
	my $logger = Dancer::LoggerMockObject->new();

	while (my ($method_name, $method_idl) = each %methods) {
		my ($http_method, $dancer_route) = @{ $method_idl->{doc}{rest} }{'method', 'route'};
		my $dancer_method = 'Dancer::' . $http_method;

		my $method_message_class = $parser->{methods}{$method_name}{class};

		my $dancer_sub = sub {
			my $request = request;
			my $params = $request->params;

			my $thrift_message;
			try {
				$thrift_message = $method_message_class->compose_message_call(%$params);
			}
			catch {
				die "Error in composing $method_message_class message: $_\n";
			};

			$validator->validate_parser_message($thrift_message);

			my $call = Tapir::MethodCall->new(
				service   => $service,
				message   => $thrift_message,
				transport => $request,
				logger    => $logger,
			);

			$handler_class->add_call_actions($call);

			# We can't check is_finished since that's only set via a POE post; check instead to see
			# if the action called set_result, set_exception or set_error
			my $call_is_finished_sub = sub {
				my @set = grep { $call->heap_isset($_) } qw(result exception error);
				return $set[0];
			};

			my $capture_stdout = IO::Capture::Stdout->new();
			$capture_stdout->start();

			# Execute the actions
			while (my $action = $call->get_next_action) {
				$action->($call);
				last if $call_is_finished_sub->();
			}

			$capture_stdout->stop();
			foreach my $line ($capture_stdout->read()) {
				$logger->info($handler_class.' in handling '.$call->method->name.' emitted: '.$line);
			}

			my $result_key = $call_is_finished_sub->();
			if (! $result_key) {
				die $handler_class.' in handling '.$call->method->name." never called set_result, set_exception or set_error\n";
			}
			my $result_value = $call->heap_index($result_key);

			if ($result_key eq 'result') {
				# Validate the result value against the Thrift specification
				try {
					$thrift_message->compose_reply($result_value);
				}
				catch {
					die "Error in composing $method_message_class result: $_\n";
				};
				return $result_value;
			}
			else {
				die $result_value;
			}
		};
		
		# Install the route
		{
			no strict 'refs';
			$dancer_method->($dancer_route => $dancer_sub);
		}
	}

	# FIXME: This each call should auto-detect which serializer to use, contextually
	set serializer => 'JSON';
};

register_plugin;

{
	package Dancer::LoggerMockObject;

	use strict;
	use warnings;

	sub new {
		my $class = shift;
		return bless {}, $class;
	}

	sub core    { shift; Dancer::Logger::core(@_); }
	sub debug   { shift; Dancer::Logger::debug(@_); }
	sub warning { shift; Dancer::Logger::warning(@_); }
	sub error   { shift; Dancer::Logger::error(@_); }
	sub info    { shift; Dancer::Logger::info(@_); }
}

true;
