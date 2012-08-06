#!/usr/bin/env perl

package MyAPI::Accounts;

use strict;
use warnings;
use Tapir::Server::Handler::Signatures;
use base 'Tapir::Server::Handler::Class';

set_service 'Accounts';

method createAccount ($username, $password) {
	print "createAccount called with $username and $password\n";
	$call->set_result({
		id         => 42,
		allocation => 1000,
	});
}

package main;

use strict;
use warnings;

use Tapir::Server;

my $server = Tapir::Server->new(
	idl_file => 'ex/sample.thrift',
);

$server->add_handler(
	class => 'MyAPI::Accounts',
);

$server->add_transport(
	class   => 'Tapir::Server::Transport::HTTP',
	options => {
		port => 8080,
		ssl  => {
			key_file  => 'ex/ssl.key',
			cert_file => 'ex/ssl.cert',
		},
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
