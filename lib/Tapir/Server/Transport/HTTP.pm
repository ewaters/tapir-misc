package Tapir::Server::Transport::HTTP;

use Moose;
extends 'Tapir::Server::Transport';

# This is a custom modified version of POE::Component::Server::HTTP that supports SSL
use POE qw(Component::Server::HTTPs);
use HTTP::Status qw(:constants);
use JSON::XS;
use Data::UUID;
use Try::Tiny;

my $data_uuid = Data::UUID->new();
my $json_xs = JSON::XS->new->utf8->allow_nonref;

has 'alias' => (is => 'ro', default => 'tapir-http');
has 'port'  => (is => 'ro', default => 3000);
has 'ssl'   => (is => 'ro');

sub setup {
	my $self = shift;

    POE::Session->create(
        object_states => [ $self, [qw(
			_start
			handler
			start_request
			finish_request
		)] ]
    );

	$self->logger->info("Setup called!");
}

sub _start {
    my ($self, $kernel) = @_[OBJECT, KERNEL];

    $kernel->alias_set($self->alias);

    $self->{http_aliases} = POE::Component::Server::HTTPs->new(
        Port => $self->port,
        ContentHandler => {
            '/' => sub {
                $kernel->call($self->alias, 'handler', @_);
            },
        },
		($self->ssl ? (
        SSL => {
            KeyFile  => $self->ssl->{key},
            CertFile => $self->ssl->{cert},
        },
		) : ()),
    );


    $self->logger->info("Connect to the API proxy on HTTP port ".$self->port);
}

sub handler {
    my ($self, $kernel, $request, $response) = @_[OBJECT, KERNEL, ARG0, ARG1];

	my %api_request = (
    	ip       => $request->header('X-Forwarded-For') || $request->{connection}{remote_ip},
		request  => $request,
		response => $response,
	);

    $self->logger->info(sprintf "Request for %s '%s' from %s", uc($request->method), $request->uri->path, $api_request{ip});

    ## Decode the content

	my $error;
	try {
        if (! $request->header('Content-Type') || $request->header('Content-Type') !~ m{^application/json\b}) {
            die "Invalid 'Content-Type' header; must be 'application/json'\n";
        }

        my $payload = $request->content;

        # Decode the payload

        eval { $api_request{data} = $json_xs->decode($payload) };
        if ($@) {
            die "Failed to decode JSON data in request payload: $@\n";
        }
	} catch {
		$error = $_;
	};
    if ($error) {
        $self->logger->error($error);
		_prepare_error_response($response, $error);
		return RC_OK;
    }

    ## Dispatch accordingly

    $api_request{id}            = $data_uuid->create_str;
	$api_request{timing}{start} = Time::HiRes::time;
    
    $response->streaming(1);

	$kernel->yield('start_request', \%api_request);

    return RC_WAIT;
}

sub start_request {
}

sub finish_request {
}

sub _prepare_error_response {
	my ($response, $error) = @_;
	return _prepare_response(
		$response,
		status => HTTP_BAD_REQUEST,
		data   => { message => $error, success => JSON::XS::false },
	);
}

sub _prepare_response {
	my ($response, %args) = @_;
	$response->code($args{status} || HTTP_OK);
	if ($args{data} && ref $args{data}) {
		$response->content_type('application/json; charset=utf8');
		$response->content($json_xs->encode($args{data}));
	}
}

1;
