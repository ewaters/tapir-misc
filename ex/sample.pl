#!/usr/bin/env perl

package MyAPI::Accounts;

use Moose;
use Tapir::Server::Handler::Signatures;
extends 'Tapir::Server::Handler::Class';

set_service 'Accounts';

method validate : before {
	foreach my $field (@{ $call->arguments->fields }) {
		if ($field->value->isa('Tappy::username')) {
			if (length($field->value) > 8) {
				Tappy::invalidArguments->throw("Username too long");
			}
		}
	}
}

method createAccount ($username, $password) {
	print "createAccount called with $username and $password\n";
	$call->set_result({
		id         => 42,
		allocation => 1000,
	});
}

=cut

method createAccount : version2 ($username, $password) {
	print "createAccount called with $username and $password\n";
	$call->add_action(\&lookup_username);
	$call->add_action(sub {
		my $call = shift;
		my $Username = $call->heap_index('Username');
		return {
			id         => $Username->id,
			allocation => 1000,
		};
	});
}

sub lookup_username {
	my $call = shift;
	$call->heap_set('Username' => Username->new());
}

=cut

package main;

use strict;
use warnings;
use Data::Dumper;

use Tapir::Server;

my $server = Tapir::Server->new(
	thrift_file => 'ex/sample.thrift',
);

# Don't fail a 'require MyAPI::Accounts'
$INC{'MyAPI/Accounts.pm'} = undef;

$server->add_handler(
	class => 'MyAPI::Accounts',
);

$server->add_transport(
	class   => 'Tapir::Server::Transport::HTTP',
	options => {
		port => 8080,
	},
);

$server->add_transport(
	class   => 'Tapir::Server::Transport::AMQP',
	options => {
		username => 'guest',
		password => 'guest',
		hostname => 'localhost',
		port     => 5672,
		ssl      => 0,
		queue_name => '%s', # service name
	},
);

$server->run();
