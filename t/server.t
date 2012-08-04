use strict;
use warnings;
use Test::More tests => 7;

use Thrift::Parser;
use Thrift::IDL;
use Tapir::MethodCall;
use Tapir::Server::ThriftAMQP::Handler::Inline;

## Create a new Thrift IDL to define a new API

my $idl = Thrift::IDL->parse_thrift(<<"ENDTHRIFT");
namespace perl Tappy

typedef i32 account_id
typedef string username
typedef string password

struct account {
	1: account_id id,
	2: i32        allocation
}

exception insufficientResources {
	1: string message
}

service Accounts {
	account createAccount (
		1: username username,
		2: string   password
	)
	throws (
		1: insufficientResources insufficient
	)
}
ENDTHRIFT

## Create a parser for the 'Accounts' service and build the Tappy:: dynamic classes

my $parser = Thrift::Parser->new(
	idl     => $idl,
	service => 'Accounts',
);

## Create a thrift message that tests the server.  This is what the client would send
## Normally the $parser would create this from a Thrift opaque payload (binary or JSON)

my $message = Tappy::Accounts::createAccount->compose_message_call(
	username => 'ewaters',
	password => 'wlkjwoijbe',
);

## Create the method call, an async object carrying state

my $method_call = Tapir::MethodCall->new(
	message => $message,
);

## Let's add some extra business logic to validate the parameters according to some spec
## For example, we have access to the full IDL document above; we could embed validation
## logic inside it in comments. 

$method_call->add_action(sub {
	my $call = shift;

	foreach my $field (@{ $call->arguments->fields }) {
		if ($field->value->isa('Tappy::username')) {
			ok length($field->value) < 8, "1: Tappy::username field meets business logic";
		}
	}
});

## Let's also add some logic to the method call such that, once we have a result, we want
## to serialize the result into the expected return value class

$method_call->add_callback(sub {
	my $call = shift;
	my $result = $call->heap_index('result');

	my $reply = $call->message->compose_reply($result);
	isa_ok $reply, 'Thrift::Parser::Message', "5: The reply is another Thrift message";

	my $return_value = $reply->arguments->field_named('return_value');
	isa_ok $return_value, 'Tappy::account', "6: The return value (inside reply) is an 'account'";

	is $return_value->field_named('allocation'), 1000, "7: The value for 'allocation' has been serialized";
});

## Just in case, let's catch any errors in actions or callbacks

$method_call->add_error_callback(sub {
	my ($call, $error) = @_;
	print STDERR $error . "\n";
});

## Create a handler for method calls.  This is the logic that implements the API server side

my $handler = Tapir::Server::ThriftAMQP::Handler::Inline->new(
	methods => {
		createAccount => sub {
			my $call = shift;
			
			isa_ok $call, 'Tapir::MethodCall', '2: Action is passed a MethodCall';

			## You can now fetch the fields of the Thrift call

			is $call->arguments->field_named('username') . '', 'ewaters', "3: Username seen in arguments";
			isa_ok $call->arguments->field_named('username'), 'Tappy::username', "4: field_named() returns a blessed object";

			## The async method call doesn't finish until we call set_result()

			$call->set_result({
				id         => 42,
				allocation => 1_000,
			});
		},
	},
);

## Use the handler to add actions to the method call

$handler->add_actions($method_call);

## Start the message call, running all actions

$method_call->run();

## Start the kernel.  Any created sessions will be run, and once no further messages are in
## queue on any sessions, the kernel will stop.

POE::Kernel->run();

1;
