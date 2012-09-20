use Module::Build;

my $build = Module::Build->new(
	module_name => 'Tapir',
	license     => 'perl',
	sign        => 1,
	create_readme => 1,
	configure_requires => {
		'Module::Build' => 0.4,
	},
	build_requires => {
		'Test::More' => 0,
		'Test::Deep' => 0,
	},
	requires => {
		'Thrift::Parser' => 0,
		'POE::Component::Sequence' => '0.02',
		'Moose' => 0,

		# AMQP Server
		'POE::Component::Client::AMQP' => 0,
		'Net::IP' => 0,
		'YAML::XS' => 0,

		# Signatures
		'Devel::Declare' => 0,

		# JSON Proxy
		'IO::Socket::SSL' => 0,
		'POE::Component::Server::HTTP' => 0,
		'Data::UUID' => 0,
	},
	create_makefile_pl => 'small',
	meta_merge => {
		resources => {
			repository => "http://github.com/ewaters/tapir",
			bugtracker => "http://github.com/ewaters/tapir/issues?labels=bug",
		},
	},
);

$build->create_build_script;

