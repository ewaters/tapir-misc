package Dancer::Plugin::Tapir;

use Dancer ':syntax';
use Dancer::Plugin;

our $VERSION = 0.01;

register setup_thrift_handler => sub {
	my ($self, @args) = plugin_args(@_);
	# $self is undef for Dancer 1
	my $conf = plugin_setting();

	get '/tapir' => sub {
		print STDERR "Here in " . __PACKAGE__ . ": " . $conf->{thrift_idl} . "\n";
	};
};

register_plugin;
true;
