package test::handler;

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

method getAccount ($username) {
	print "getAccount called with $username\n";
	$call->set_result({
		id         => 42,
		error      => "this will fail",
		allocation => 1000,
	});
}

1;
